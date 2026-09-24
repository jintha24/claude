@echo off
REM Uploads builds\windows to Steam with steamcmd (from the Steamworks SDK).
REM Usage: tools\steam\upload.bat C:\steamworks_sdk\tools\ContentBuilder\builder\steamcmd.exe
REM Fill in tools\steam\steam_ids.txt first. The build appears in Steamworks > SteamPipe >
REM Builds, where you choose which branch to set it live on.
setlocal EnableDelayedExpansion
set "STEAMCMD=%~1"
if "%STEAMCMD%"=="" set "STEAMCMD=steamcmd"
cd /d "%~dp0"
for /f "usebackq tokens=1,* delims==" %%a in ("steam_ids.txt") do (
  set "line=%%a"
  if not "!line:~0,1!"=="#" set "%%a=%%b"
)
if "%APP_ID%"=="" ( echo Fill in APP_ID in tools\steam\steam_ids.txt & exit /b 1 )
if "%DEPOT_ID%"=="" ( echo Fill in DEPOT_ID in tools\steam\steam_ids.txt & exit /b 1 )
if "%STEAM_USER%"=="" ( echo Fill in STEAM_USER in tools\steam\steam_ids.txt & exit /b 1 )
for /f "tokens=2 delims==" %%v in ('findstr /b "config/version=" ..\..\project.godot') do set "VERSION=%%~v"
if not exist ..\..\builds\steam_output mkdir ..\..\builds\steam_output
powershell -NoProfile -Command "(Get-Content app_build.vdf) -replace '__APP_ID__','%APP_ID%' -replace '__DEPOT_ID__','%DEPOT_ID%' -replace '__VERSION__','%VERSION%' | Set-Content ..\..\builds\steam_output\app_build.vdf"
powershell -NoProfile -Command "(Get-Content depot_windows.vdf) -replace '__DEPOT_ID__','%DEPOT_ID%' | Set-Content ..\..\builds\steam_output\depot_windows.vdf"
"%STEAMCMD%" +login %STEAM_USER% +run_app_build "%CD%\..\..\builds\steam_output\app_build.vdf" +quit
