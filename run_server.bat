@echo off
setlocal

set "GODOT_EXE=C:\Users\andre\OneDrive\Desktop\files\Godot_v4.4.1-stable_win64\Godot_v4.4.1-stable_win64_console.exe"
set "PROJECT_DIR=%~dp0."

echo Starting SERVER...
echo Godot: "%GODOT_EXE%"
echo Project: "%PROJECT_DIR%"
echo.

if not exist "%GODOT_EXE%" (
  echo ERROR: Godot EXE not found:
  echo   %GODOT_EXE%
  pause
  exit /b 1
)

if not exist "%PROJECT_DIR%\project.godot" (
  echo ERROR: project.godot not found in:
  echo   %PROJECT_DIR%
  pause
  exit /b 1
)

"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" -- --server

echo.
echo Server exited. Press any key to close.
pause >nul
