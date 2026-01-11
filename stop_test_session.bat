@echo off
echo ========================================
echo Stopping all Godot instances...
echo ========================================
echo.

REM Kill all Godot processes
taskkill /F /IM Godot_v4.4.1-stable_win64_console.exe >nul 2>&1

if %errorlevel% equ 0 (
    echo All Godot instances terminated successfully.
) else (
    echo No Godot instances found running.
)

echo.
echo ========================================
echo Test session stopped.
echo ========================================
