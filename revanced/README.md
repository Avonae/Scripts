# ReVanced patches build scripts

Builds the ReVanced patches file (`.rvp`) from the `dev` branch of [revanced-patches](https://gitlab.com/revanced/revanced-patches).

## Requirements

- A GitHub account and a **classic** Personal Access Token with the `read:packages` scope: https://github.com/settings/tokens/new. Fine-grained tokens do not work, because the dependencies come from GitHub Packages.
- About 2 GB of free space and a stable connection. The Android SDK download is about 200 MB.

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
- Builds the patches.

The result is `~/revanced-patches/patches/build/libs/patches-<version>.rvp`. If `termux-setup-storage` was run, the file is also copied to `Download`.

If Termux closes during the build, it is out of memory. Lower the Gradle heap and disable battery optimization for Termux:

```bash
JVM_XMX=1536m bash <(curl -fsSL https://raw.githubusercontent.com/Avonae/Scripts/main/revanced/build-revanced-termux.sh)
```
