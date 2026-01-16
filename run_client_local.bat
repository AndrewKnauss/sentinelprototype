@echo off
setlocal

set "GODOT_EXE=C:\Users\andre\OneDrive\Desktop\files\Godot_v4.4.1-stable_win64\Godot_v4.4.1-stable_win64_console.exe"
set "PROJECT_DIR=%~dp0."

set "HOST=127.0.0.1"
set "PORT=24567"
set "USERNAME=%1"

if "%USERNAME%"=="" (
	echo Starting CLIENT with auto-connect to localhost...
	echo Username will be prompted in-game.
	"%GODOT_EXE%" --path "%PROJECT_DIR%" -- --client --host=%HOST% --port=%PORT% --auto-connect
) else (
	echo Starting CLIENT with auto-connect to localhost as %USERNAME%...
	"%GODOT_EXE%" --path "%PROJECT_DIR%" -- --client --host=%HOST% --port=%PORT% --auto-connect --username=%USERNAME%
)
