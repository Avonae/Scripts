#!/usr/bin/env bash
# Build ReVanced Patches (.rvp) from the dev branch on Linux or macOS.
# Asks for a GitHub username and a classic PAT (scope: read:packages), does the rest.
# Needs git and JDK 17+ installed.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Avonae/Scripts/main/revanced/build-revanced.sh)
# Optional env vars:
#   REPO_DIR=~/revanced-patches   - where to clone the sources
#   JVM_XMX=4g                    - Gradle heap size (default 4g)
set -euo pipefail

REPO_URL="https://gitlab.com/revanced/revanced-patches"
REPO_BRANCH="dev"
REPO_DIR="${REPO_DIR:-$HOME/revanced-patches}"
SDK_DIR="$HOME/android-sdk"
GRADLE_PROPS="$HOME/.gradle/gradle.properties"
TWITTER_GRADLE="extensions/twitter/build.gradle.kts"
JVM_XMX="${JVM_XMX:-4g}"

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
# In-place sed that works with both GNU and BSD (macOS) sed
sed_i() { sed -i.bak "$@" && rm -f "${@: -1}.bak"; }

# --- 1. Tools ----------------------------------------------------------------
log "Checking tools"
command -v git >/dev/null || die "git not found. Linux: sudo apt install git. macOS: brew install git."

# Homebrew's openjdk@17 is keg-only, so it is not on PATH by default
if [ -z "${JAVA_HOME:-}" ] && [ "$(uname)" = "Darwin" ]; then
  for jdk in /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@17; do
    if [ -x "$jdk/bin/java" ]; then
      export JAVA_HOME="$jdk/libexec/openjdk.jdk/Contents/Home"
      export PATH="$jdk/bin:$PATH"
      break
    fi
  done
fi
command -v java >/dev/null \
  || die "Java not found. Linux: sudo apt install openjdk-17-jdk. macOS: brew install openjdk@17."
java_ver=$(java -version 2>&1 | awk -F'"' '/version/ {print $2}' | cut -d. -f1)
[ "${java_ver:-0}" -ge 17 ] 2>/dev/null || die "JDK 17 or newer is required, found: ${java_ver:-unknown}."
echo "git: $(git --version), java: $java_ver"

# --- 2. GitHub credentials (dependencies come from GitHub Packages) ---------
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

# --- 3. Repository -----------------------------------------------------------
if [ -d "$REPO_DIR/.git" ]; then
  log "Updating repository"
  # Revert our local patch first so the pull is clean; it is re-applied below
  git -C "$REPO_DIR" checkout -- "$TWITTER_GRADLE" 2>/dev/null || true
  git -C "$REPO_DIR" pull --ff-only origin "$REPO_BRANCH"
else
  log "Cloning repository"
  git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"
chmod +x gradlew

# --- 4. Android SDK location + accepted licenses -----------------------------
# Gradle downloads the needed SDK parts itself once the license is accepted
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

# --- 5. Global Gradle properties ---------------------------------------------
log "Writing $GRADLE_PROPS"
mkdir -p "$(dirname "$GRADLE_PROPS")"
touch "$GRADLE_PROPS"
sed_i \
  -e '/^githubPackagesUsername=/d' \
  -e '/^githubPackagesPassword=/d' \
  -e '/^org\.gradle\.jvmargs=/d' \
  -e '/^gpr\./d' \
  "$GRADLE_PROPS"
cat >> "$GRADLE_PROPS" <<EOF
githubPackagesUsername=$GH_USER
githubPackagesPassword=$GH_PAT
org.gradle.jvmargs=-Xmx$JVM_XMX
EOF
chmod 600 "$GRADLE_PROPS"

# --- 6. Twitter extension: readAllBytes needs API 33 -------------------------
# Without it the build fails with "Call requires API level 33 (current min is 26)"
if [ -f "$TWITTER_GRADLE" ] && grep -q 'minSdk = 26' "$TWITTER_GRADLE"; then
  log "Raising minSdk to 33 in $TWITTER_GRADLE"
  sed_i 's/minSdk = 26/minSdk = 33/' "$TWITTER_GRADLE"
fi

# --- 7. Build ----------------------------------------------------------------
log "Building (first run downloads the SDK and takes a while)"
./gradlew build --no-daemon || die "Build failed. Check the log above."

# --- 8. Result ---------------------------------------------------------------
rvp=$(ls -t patches/build/libs/*.rvp 2>/dev/null | grep -v -- '-sources\.rvp$' | head -n1 || true)
[ -n "$rvp" ] || die "Build finished but no .rvp file was found."
log "Done: $REPO_DIR/$rvp"
