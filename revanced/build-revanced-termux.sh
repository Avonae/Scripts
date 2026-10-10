#!/data/data/com.termux/files/usr/bin/bash
# Build ReVanced Patches (.rvp) from the dev branch in Termux on ARM (aarch64) devices.
# Asks for a GitHub username and a classic PAT (scope: read:packages), does the rest.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Avonae/Scripts/main/revanced/build-revanced-termux.sh)
# Optional env vars:
#   JVM_XMX=1536m   - Gradle heap size (default 2g), lower it if Termux gets killed
set -euo pipefail

REPO_URL="https://gitlab.com/revanced/revanced-patches"
REPO_BRANCH="dev"
REPO_DIR="$HOME/revanced-patches"
SDK_DIR="$HOME/android-sdk"
GRADLE_PROPS="$HOME/.gradle/gradle.properties"
PROTO_GRADLE="extensions/shared/protobuf/build.gradle.kts"
VERSIONS_TOML="gradle/libs.versions.toml"
JVM_XMX="${JVM_XMX:-2g}"

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ] || die "Run this script inside Termux."

# --- 1. GitHub credentials (dependencies come from GitHub Packages) ---------
log "GitHub credentials"
saved_user=$(sed -n 's/^githubPackagesUsername=//p' "$GRADLE_PROPS" 2>/dev/null | head -n1 || true)
saved_pat=$(sed -n 's/^githubPackagesPassword=//p' "$GRADLE_PROPS" 2>/dev/null | head -n1 || true)

if [ -n "$saved_user" ]; then
  read -rp "GitHub username [$saved_user]: " GH_USER
  GH_USER="${GH_USER:-$saved_user}"
else
  read -rp "GitHub username: " GH_USER
fi
[ -n "$GH_USER" ] || die "Username is empty."

if [ -n "$saved_pat" ]; then
  read -rsp "GitHub PAT (Enter = keep saved one): " GH_PAT; echo
  GH_PAT="${GH_PAT:-$saved_pat}"
else
  read -rsp "GitHub PAT (classic, scope read:packages): " GH_PAT; echo
fi
[ -n "$GH_PAT" ] || die "PAT is empty."

# --- 2. Packages: JDK + native ARM replacements for x86 SDK binaries --------
log "Installing packages"
pkg upgrade -y
pkg install -y git openjdk-17 aapt2 aidl protobuf

# --- 3. Repository -----------------------------------------------------------
if [ -d "$REPO_DIR/.git" ]; then
  log "Updating repository"
  # Revert our local patches first so the pull is clean; they are re-applied below
  git -C "$REPO_DIR" checkout -- "$PROTO_GRADLE" "$VERSIONS_TOML" 2>/dev/null || true
  git -C "$REPO_DIR" pull --ff-only origin "$REPO_BRANCH"
else
  log "Cloning repository"
  git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"
chmod +x gradlew

# --- 4. Android SDK location + accepted licenses -----------------------------
log "Preparing Android SDK"
mkdir -p "$SDK_DIR/licenses"
# Standard hashes of the Android SDK License text (same as `sdkmanager --licenses`).
# Writing this file means you accept https://developer.android.com/studio/terms
cat > "$SDK_DIR/licenses/android-sdk-license" <<'EOF'

24333f8a63b6825ea9c5514f83c2829b004d1fee
d56f5187479451eabf01fb78af6dfcb131a6481e
84831b9409646a918e30573bab4c9c91346d8abd
EOF
echo "sdk.dir=$SDK_DIR" > local.properties
export ANDROID_HOME="$SDK_DIR"
grep -q '^export ANDROID_HOME=' "$HOME/.bashrc" 2>/dev/null \
  || echo "export ANDROID_HOME=$SDK_DIR" >> "$HOME/.bashrc"

# --- 5. Global Gradle properties ---------------------------------------------
log "Writing $GRADLE_PROPS"
mkdir -p "$(dirname "$GRADLE_PROPS")"
touch "$GRADLE_PROPS"
sed -i \
  -e '/^githubPackagesUsername=/d' \
  -e '/^githubPackagesPassword=/d' \
  -e '/^android\.aapt2FromMavenOverride=/d' \
  -e '/^org\.gradle\.jvmargs=/d' \
  -e '/^gpr\./d' \
  "$GRADLE_PROPS"
cat >> "$GRADLE_PROPS" <<EOF
githubPackagesUsername=$GH_USER
githubPackagesPassword=$GH_PAT
android.aapt2FromMavenOverride=$PREFIX/bin/aapt2
org.gradle.jvmargs=-Xmx$JVM_XMX
EOF
chmod 600 "$GRADLE_PROPS"

# --- 6. protobuf: use Termux protoc and a matching javalite runtime ----------
log "Patching protobuf setup"
if grep -q 'artifact = .*protoc' "$PROTO_GRADLE"; then
  sed -i "s|artifact = .*protoc.*|path = \"$PREFIX/bin/protoc\"|" "$PROTO_GRADLE"
fi
grep -q "path = \"$PREFIX/bin/protoc\"" "$PROTO_GRADLE" \
  || die "Could not patch protoc in $PROTO_GRADLE (project layout changed?)"

proto_ver=$(protoc --version | awk '{print $2}')   # e.g. "35.1"
case "$proto_ver" in
  3.*) runtime_ver="$proto_ver" ;;                  # legacy numbering
  *)   runtime_ver="4.$proto_ver" ;;                # protoc 35.1 -> runtime 4.35.1
esac
grep -q '^protoc = ' "$VERSIONS_TOML" || die "No 'protoc' key in $VERSIONS_TOML"
sed -i "s|^protoc = \".*\"|protoc = \"$runtime_ver\"|" "$VERSIONS_TOML"
echo "protoc $proto_ver -> protobuf-javalite $runtime_ver"

# --- 7. Replace x86 build-tools binaries with Termux ones --------------------
# Returns 0 if something was replaced
fix_build_tools() {
  local changed=1 bt tool
  for bt in "$SDK_DIR"/build-tools/*/; do
    [ -d "$bt" ] || continue
    for tool in aidl aapt2; do
      if [ -e "$bt$tool" ] && [ ! -L "$bt$tool" ]; then
        mv "$bt$tool" "$bt$tool.x86"
        ln -s "$PREFIX/bin/$tool" "$bt$tool"
        echo "Linked $bt$tool -> $PREFIX/bin/$tool"
        changed=0
      fi
    done
  done
  return $changed
}

# --- 8. Build ----------------------------------------------------------------
log "Building (first run downloads the SDK and takes a while)"
fix_build_tools || true
if ! ./gradlew build --no-daemon; then
  # build-tools are downloaded during the first build, so fix them and retry once
  if fix_build_tools; then
    log "Replaced x86 build-tools binaries, retrying"
    ./gradlew build --no-daemon
  else
    die "Build failed. Check the log above."
  fi
fi

# --- 9. Result ---------------------------------------------------------------
rvp=$(ls -t patches/build/libs/*.rvp 2>/dev/null | head -n1 || true)
[ -n "$rvp" ] || die "Build finished but no .rvp file was found."
log "Done: $REPO_DIR/$rvp"
if [ -d "$HOME/storage/downloads" ]; then
  cp "$rvp" "$HOME/storage/downloads/"
  echo "Copied to Downloads."
else
  echo "Tip: run termux-setup-storage once to get the .rvp copied to Downloads."
fi
