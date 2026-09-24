@echo off
REM Builds The Thief of London for Windows and packs the installer.
REM
REM Usage (from anywhere):  tools\build_windows.bat "C:\Godot\Godot_v4.7.2-stable_win64.exe"
REM   - The Godot editor's export templates must be installed (Editor > Manage Export
REM     Templates > Download and Install).
REM   - Inno Setup 6 (https://jrsoftware.org/isdl.php) makes the installer; without it you
REM     still get the game in builds\windows\ (zip that folder for itch.io or Steam).
setlocal
set "GODOT=%~1"
if "%GODOT%"=="" set "GODOT=godot"
cd /d "%~dp0\.."

echo === Importing assets...
"%GODOT%" --headless --path . --import
if errorlevel 1 goto :fail

echo === Exporting builds\windows\TheThiefOfLondon.exe ...
if not exist builds\windows mkdir builds\windows
"%GODOT%" --headless --path . --export-release "Windows Desktop" builds\windows\TheThiefOfLondon.exe
if errorlevel 1 goto :fail
if not exist builds\windows\TheThiefOfLondon.pck goto :fail

copy /y installer\README.txt "builds\windows\Read Me.txt" >nul
copy /y installer\LICENSE.txt "builds\windows\Licence.txt" >nul
copy /y installer\THIRD_PARTY_NOTICES.txt "builds\windows\Third-party notices.txt" >nul

set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (
  echo Inno Setup 6 not found: skipping the installer. The game is in builds\windows\
  goto :done
)
echo === Building the installer...
"%ISCC%" installer\thief_of_london.iss
if errorlevel 1 goto :fail
echo Installer: installer\Output\

:done
echo === Done.
exit /b 0

:fail
echo === BUILD FAILED (see the messages above).
exit /b 1
