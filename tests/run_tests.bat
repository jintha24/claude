@echo off
REM Runs every automated gameplay test headless.
REM Usage: tests\run_tests.bat "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
set GODOT=%~1
if "%GODOT%"=="" set GODOT=godot
cd /d "%~dp0.."
set STATUS=0
for %%T in (tests\test_*.gd) do (
  if /I not "%%~nxT"=="test_base.gd" (
    echo === %%T
    "%GODOT%" --headless --path . --script "res://tests/%%~nxT"
    if errorlevel 1 set STATUS=1
  )
)
exit /b %STATUS%
