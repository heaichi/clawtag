@echo off
REM Pet Diary - APK build script (ASCII-only to stay cmd/GBK safe)
REM
REM Version scheme: pubspec keeps "versionName+versionCode", e.g. version: 1.0.66+4066
REM   versionName = x.y.z (what users see): patch +1, at patch 99 -> minor +1 / patch 0
REM   versionCode = 4000 + minor*100 + patch   (monotonic, NEVER decrease)
REM   These builds are deliberately NOT split per ABI, so the APK versionCode always
REM   equals that number. Split APKs would get an extra ABI offset (+2000 for arm64),
REM   which makes debug/acceptance installs look like downgrades - avoid on the phone.
REM
REM Usage:
REM   scripts\build.bat          arm64 only, single APK   -> acceptance / install on phone (fastest)
REM   scripts\build.bat full     arm64 + armeabi-v7a       -> distribution
REM
REM Steps: guard JAVA_HOME -> bump version -> regenerate version.dart -> build release
REM        -> friendly-named APK copy -> archive APK to build\apk_history (keep newest 5)

setlocal
cd /d "%~dp0.."

REM --- JAVA_HOME guard -------------------------------------------------------
REM Gradle needs a JDK 17+. If JAVA_HOME is unset or stale, set it before running
REM this script (e.g. set JAVA_HOME=C:\path\to\jdk-17) — the error below tells you.
if not exist "%JAVA_HOME%\bin\java.exe" (
  echo ERROR: no usable JDK found. Point JAVA_HOME at a JDK 17+ directory.
  exit /b 1
)
echo JAVA_HOME = %JAVA_HOME%

REM --- options ---------------------------------------------------------------
if /I "%~1"=="full" (set "BUILD_MODE=full") else (set "BUILD_MODE=arm64")
if "%BUILD_MODE%"=="full" (
  set "TARGET_ARGS=--target-platform android-arm,android-arm64"
  set "APK_TAG=armv7-arm64"
) else (
  set "TARGET_ARGS=--target-platform android-arm64"
  set "APK_TAG=arm64"
)
echo Mode: %BUILD_MODE%  (%TARGET_ARGS%)

REM --- bump version ----------------------------------------------------------
REM Read "version: X.Y.Z(+N)", bump patch (carry at 99), recompute versionCode,
REM write pubspec back as UTF-8 without BOM, emit "x.y.z|buildno".
REM Get-Content needs -Encoding UTF8; Set-Content would corrupt the Chinese description.
powershell -NoProfile -Command "$c = Get-Content pubspec.yaml -Raw -Encoding UTF8; if ($c -match '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?') { $maj = [int]$matches[1]; $min = [int]$matches[2]; $pat = [int]$matches[3]; if ($pat -ge 99) { $min = $min + 1; $pat = 0 } else { $pat = $pat + 1 }; $bn = 4000 + $min * 100 + $pat; $name = '{0}.{1}.{2}' -f $maj, $min, $pat; $full = $name + '+' + $bn; $c = [regex]::Replace($c, '(?m)^version:\s*\d+\.\d+\.\d+(?:\+\d+)?', 'version: ' + $full); [System.IO.File]::WriteAllText('pubspec.yaml', $c, (New-Object System.Text.UTF8Encoding($false))); $name + '|' + $bn } else { 'ERROR|0' }" > "%TEMP%\petdiary_ver.tmp"
for /f "usebackq tokens=1,2 delims=|" %%a in ("%TEMP%\petdiary_ver.tmp") do set NEW_VERSION=%%a&set BUILD_NUMBER=%%b
del "%TEMP%\petdiary_ver.tmp"
if "%BUILD_NUMBER%"=="0" (
  echo ERROR: could not parse "version:" from pubspec.yaml
  exit /b 1
)
echo New version: %NEW_VERSION%   versionCode: %BUILD_NUMBER%

REM --- regenerate version.dart (single source of truth = pubspec) -------------
REM Use `dart <file>` (not `dart run`) to avoid pub build-hooks hanging in cmd.
call dart scripts/update_version.dart release
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

REM --- build -----------------------------------------------------------------
call flutter build apk --release %TARGET_ARGS% --build-number %BUILD_NUMBER%
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

REM --- friendly-named copy: pet_diary_<version>_<arch>_release.apk -------------
set OUTPUT_DIR=build\app\outputs\flutter-apk
copy /Y "%OUTPUT_DIR%\app-release.apk" "%OUTPUT_DIR%\pet_diary_%NEW_VERSION%_%APK_TAG%_release.apk" >nul
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
set APK_PATH=%OUTPUT_DIR%\pet_diary_%NEW_VERSION%_%APK_TAG%_release.apk

REM --- archive history + keep only the newest 5 -------------------------------
REM Locale-independent timestamp (PowerShell, never %DATE%).
powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmm'" > "%TEMP%\petdiary_ts.tmp"
for /f "usebackq delims=" %%t in ("%TEMP%\petdiary_ts.tmp") do set TIMESTAMP=%%t
del "%TEMP%\petdiary_ts.tmp"
if not exist "build\apk_history" mkdir "build\apk_history"
set HISTORY_PATH=build\apk_history\pet_diary_%NEW_VERSION%_%APK_TAG%_release_%TIMESTAMP%.apk
copy /Y "%APK_PATH%" "%HISTORY_PATH%" >nul
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
for /f "skip=5 delims=" %%f in ('dir /b /o-d "build\apk_history\*.apk" 2^>nul') do del "build\apk_history\%%f" >nul 2>nul

echo.
echo ================================
echo  Build complete!
echo  Mode:    %BUILD_MODE% (%APK_TAG%)
echo  Version: %NEW_VERSION%   versionCode: %BUILD_NUMBER%
echo  APK:     %APK_PATH%
echo  Saved:   %HISTORY_PATH%
echo ================================
endlocal
