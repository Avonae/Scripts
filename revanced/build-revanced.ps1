# Build ReVanced Patches (.rvp) from the dev branch on Windows.
# Asks for a GitHub username and a classic PAT (scope: read:packages), does the rest.
# Needs Git for Windows and JDK 17+ installed.
#
# Usage (PowerShell):
#   irm https://raw.githubusercontent.com/Avonae/Scripts/main/revanced/build-revanced.ps1 | iex
# Optional env vars:
#   $env:REPO_DIR = "$HOME\revanced-patches"   - where to clone the sources
#   $env:JVM_XMX  = "4g"                       - Gradle heap size (default 4g)

# Wrapped in a function: the script runs through iex, and `exit` would close the window
function Build-ReVancedPatches {
  $ErrorActionPreference = 'Stop'

  $RepoUrl     = 'https://gitlab.com/revanced/revanced-patches'
  $RepoBranch  = 'dev'
  $RepoDir     = if ($env:REPO_DIR) { $env:REPO_DIR } else { Join-Path $HOME 'revanced-patches' }
  $SdkDir      = Join-Path $HOME 'android-sdk'
  $GradleProps = Join-Path $HOME '.gradle\gradle.properties'
  $TwitterGradle = 'extensions/twitter/build.gradle.kts'
  $JvmXmx      = if ($env:JVM_XMX) { $env:JVM_XMX } else { '4g' }
  $Utf8NoBom   = New-Object System.Text.UTF8Encoding $false

  function Log($msg) { Write-Host "`n==> $msg" -ForegroundColor Green }
  function Die($msg) { throw "ERROR: $msg" }
  function Run($exe, [string[]]$argv) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) { Die "$exe $($argv -join ' ') failed with exit code $LASTEXITCODE." }
  }

  # --- 1. Tools --------------------------------------------------------------
  Log 'Checking tools'
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Die 'git not found. Install Git for Windows: https://git-scm.com/download/win'
  }
  if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Die 'Java not found. Install JDK 17: https://adoptium.net/temurin/releases/?version=17'
  }
  # java -version prints to stderr; cmd keeps PowerShell from turning it into an error
  $javaOut = cmd /c 'java -version 2>&1' | Out-String
  if ($javaOut -notmatch 'version "(\d+)') { Die "Cannot read Java version: $javaOut" }
  $javaVer = [int]$Matches[1]
  if ($javaVer -lt 17) { Die "JDK 17 or newer is required, found: $javaVer." }
  Write-Host "java: $javaVer"

  # --- 2. GitHub credentials (dependencies come from GitHub Packages) -------
  Log 'GitHub credentials'
  $props = @()
  if (Test-Path $GradleProps) { $props = @(Get-Content $GradleProps) }
  $savedUser = ($props | Where-Object { $_ -like 'githubPackagesUsername=*' } | Select-Object -First 1)
  $savedPat  = ($props | Where-Object { $_ -like 'githubPackagesPassword=*' } | Select-Object -First 1)
  if ($savedUser) { $savedUser = $savedUser.Substring('githubPackagesUsername='.Length) }
  if ($savedPat)  { $savedPat  = $savedPat.Substring('githubPackagesPassword='.Length) }

  if ($savedUser) {
    $ghUser = Read-Host "GitHub username [$savedUser]"
    if (-not $ghUser) { $ghUser = $savedUser }
  } else {
    $ghUser = Read-Host 'GitHub username'
  }
  if (-not $ghUser) { Die 'Username is empty.' }

  $prompt = if ($savedPat) { 'GitHub PAT (Enter = keep saved one)' } else { 'GitHub PAT (classic, scope read:packages)' }
  $secure = Read-Host $prompt -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $ghPat = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  if (-not $ghPat) { $ghPat = $savedPat }
  if (-not $ghPat) { Die 'PAT is empty.' }

  # --- 3. Repository ---------------------------------------------------------
  if (Test-Path (Join-Path $RepoDir '.git')) {
    Log 'Updating repository'
    # Revert our local patch first so the pull is clean; it is re-applied below
    try { & git -C $RepoDir checkout -- $TwitterGradle 2>$null } catch { }
    Run git @('-C', $RepoDir, 'pull', '--ff-only', 'origin', $RepoBranch)
  } else {
    Log 'Cloning repository'
    Run git @('clone', '--depth', '1', '-b', $RepoBranch, $RepoUrl, $RepoDir)
  }
  Set-Location $RepoDir

  # --- 4. Android SDK location + accepted licenses ---------------------------
  # Gradle downloads the needed SDK parts itself once the license is accepted
  Log 'Preparing Android SDK'
  $licDir = Join-Path $SdkDir 'licenses'
  New-Item -ItemType Directory -Force -Path $licDir | Out-Null
  # Standard hashes of the Android SDK License text (same as `sdkmanager --licenses`).
  # Writing this file means you accept https://developer.android.com/studio/terms
  [IO.File]::WriteAllText((Join-Path $licDir 'android-sdk-license'),
    "`n24333f8a63b6825ea9c5514f83c2829b004d1fee`nd56f5187479451eabf01fb78af6dfcb131a6481e`n84831b9409646a918e30573bab4c9c91346d8abd`n",
    $Utf8NoBom)
  # local.properties is a Java properties file: ':' and '\' must be escaped
  $sdkEscaped = $SdkDir.Replace('\', '\\').Replace(':', '\:')
  [IO.File]::WriteAllText((Join-Path $RepoDir 'local.properties'), "sdk.dir=$sdkEscaped`n", $Utf8NoBom)
  $env:ANDROID_HOME = $SdkDir

  # --- 5. Global Gradle properties -------------------------------------------
  Log "Writing $GradleProps"
  New-Item -ItemType Directory -Force -Path (Split-Path $GradleProps) | Out-Null
  $keep = @($props | Where-Object {
    $_ -notmatch '^(githubPackagesUsername|githubPackagesPassword|org\.gradle\.jvmargs)=' -and $_ -notmatch '^gpr\.'
  })
  $new = $keep + @(
    "githubPackagesUsername=$ghUser",
    "githubPackagesPassword=$ghPat",
    "org.gradle.jvmargs=-Xmx$JvmXmx"
  )
  [IO.File]::WriteAllLines($GradleProps, [string[]]$new, $Utf8NoBom)

  # --- 6. Twitter extension: readAllBytes needs API 33 -----------------------
  # Without it the build fails with "Call requires API level 33 (current min is 26)"
  $twitterPath = Join-Path $RepoDir $TwitterGradle
  if ((Test-Path $twitterPath) -and (Select-String -Path $twitterPath -SimpleMatch 'minSdk = 26' -Quiet)) {
    Log "Raising minSdk to 33 in $TwitterGradle"
    $text = [IO.File]::ReadAllText($twitterPath).Replace('minSdk = 26', 'minSdk = 33')
    [IO.File]::WriteAllText($twitterPath, $text, $Utf8NoBom)
  }

  # --- 7. Build --------------------------------------------------------------
  Log 'Building (first run downloads the SDK and takes a while)'
  Run (Join-Path $RepoDir 'gradlew.bat') @('build', '--no-daemon')

  # --- 8. Result -------------------------------------------------------------
  $rvp = Get-ChildItem (Join-Path $RepoDir 'patches\build\libs') -Filter '*.rvp' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike '*-sources.rvp' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $rvp) { Die 'Build finished but no .rvp file was found.' }
  Log "Done: $($rvp.FullName)"
}

Build-ReVancedPatches
