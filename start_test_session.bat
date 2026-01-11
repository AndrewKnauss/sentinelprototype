@echo off
setlocal

set "GODOT_EXE=C:\Users\andre\OneDrive\Desktop\files\Godot_v4.4.1-stable_win64\Godot_v4.4.1-stable_win64_console.exe"
set "PROJECT_DIR=%~dp0."

set "HOST=127.0.0.1"
set "PORT=24567"

echo ========================================
echo Starting Test Session:
echo   1 Server (visible)
echo   3 Clients (auto-connect)
echo ========================================
echo.

REM Start server (top-left quadrant)
echo Starting SERVER (top-left)...
start "Sentinel Server" "%GODOT_EXE%" --path "%PROJECT_DIR%" --position 50,50 --screen 0 -- --server
timeout /t 2 /nobreak >nul

REM Start client 1 (top-right quadrant) - auto-connect
echo Starting CLIENT 1 (top-right)...
start "Sentinel Client 1" "%GODOT_EXE%" --path "%PROJECT_DIR%" --position 1350,50 --screen 0 -- --client --host=%HOST% --port=%PORT% --auto-connect
timeout /t 1 /nobreak >nul

REM Start client 2 (bottom-left quadrant) - auto-connect
echo Starting CLIENT 2 (bottom-left)...
start "Sentinel Client 2" "%GODOT_EXE%" --path "%PROJECT_DIR%" --position 50,750 --screen 0 -- --client --host=%HOST% --port=%PORT% --auto-connect
timeout /t 1 /nobreak >nul

REM Start client 3 (bottom-right quadrant) - auto-connect
echo Starting CLIENT 3 (bottom-right)...
start "Sentinel Client 3" "%GODOT_EXE%" --path "%PROJECT_DIR%" --position 1350,750 --screen 0 -- --client --host=%HOST% --port=%PORT% --auto-connect

echo.
echo ========================================
echo Test session started!
echo   - Server: Top-left
echo   - Client 1: Top-right (auto-connected)
echo   - Client 2: Bottom-left (auto-connected)
echo   - Client 3: Bottom-right (auto-connected)
echo.
echo To stop all instances, run: stop_test_session.bat
echo ========================================
