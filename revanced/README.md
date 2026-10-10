# ReVanced patches build scripts

Builds the ReVanced patches file (`.rvp`) from the `dev` branch of [revanced-patches](https://gitlab.com/revanced/revanced-patches).

## Requirements

- A GitHub account and a **classic** Personal Access Token with the `read:packages` scope: https://github.com/settings/tokens/new. Fine-grained tokens do not work, because the dependencies come from GitHub Packages.
- About 2 GB of free space and a stable connection. The Android SDK download is about 200 MB.

## Computer (Linux, macOS, Windows)

`build-revanced.sh` (Linux, macOS) and `build-revanced.ps1` (Windows) build the patches on a computer. Install git and JDK 17 or newer first:

- Linux: `sudo apt install openjdk-17-jdk git`
- macOS: `brew install openjdk@17 git`
- Windows: [JDK 17](https://adoptium.net/temurin/releases/?version=17) and [Git for Windows](https://git-scm.com/download/win)

Run on Linux or macOS:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Avonae/Scripts/main/revanced/build-revanced.sh)
```

Run on Windows in PowerShell:

```powershell
irm https://raw.githubusercontent.com/Avonae/Scripts/main/revanced/build-revanced.ps1 | iex
```

What it does:

- Checks that git and JDK 17+ are installed. On macOS it also finds the Homebrew `openjdk@17`, which is not on `PATH` by default.
- Asks for the GitHub username and token and saves them to `~/.gradle/gradle.properties`. On the next run, press Enter to keep the saved values.
- Clones the `dev` branch to `~/revanced-patches`, or updates it on the next run. Set `REPO_DIR` to use another folder.
- Accepts the [Android SDK License](https://developer.android.com/studio/terms) by writing the license file to `~/android-sdk/licenses`. Gradle downloads the SDK parts it needs.
- Raises `minSdk` from 26 to 33 in `extensions/twitter/build.gradle.kts`. Without it the build fails with `Call requires API level 33`.
- Builds the patches.

The result is `~/revanced-patches/patches/build/libs/patches-<version>.rvp`. Ignore the `-sources.rvp` file.

The Gradle heap is 4 GB by default. Set `JVM_XMX` to change it, e.g. `JVM_XMX=2g`.

## Termux (Android, aarch64)

`build-revanced-termux.sh` builds the patches on the phone. Install Termux from F-Droid, not from Google Play.

Run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Avonae/Scripts/main/revanced/build-revanced-termux.sh)
```

Do not pipe the script into `bash` (`curl ... | bash`): it reads the username and token from the keyboard.

What it does:

- Asks for the GitHub username and token and saves them to `~/.gradle/gradle.properties`. On the next run, press Enter to keep the saved values.
- Installs `git`, `openjdk-17`, `aapt2`, `aidl` and `protobuf`.
- Clones the `dev` branch to `~/revanced-patches`, or updates it on the next run.
- Accepts the [Android SDK License](https://developer.android.com/studio/terms) by writing the license file to `~/android-sdk/licenses`.
- Replaces the x86 `protoc`, `aidl` and `aapt2` binaries with the native Termux ones.
- Raises `minSdk` from 26 to 33 in `extensions/twitter/build.gradle.kts`, same as the computer scripts.
- Builds the patches.

The result is `~/revanced-patches/patches/build/libs/patches-<version>.rvp`. If `termux-setup-storage` was run, the file is also copied to `Download`.

If Termux closes during the build, it is out of memory. Lower the Gradle heap and disable battery optimization for Termux:

```bash
JVM_XMX=1536m bash <(curl -fsSL https://raw.githubusercontent.com/Avonae/Scripts/main/revanced/build-revanced-termux.sh)
```
