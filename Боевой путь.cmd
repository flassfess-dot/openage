@echo off
setlocal
set "GODOT=%~dp0.tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=godot"
start "" "%GODOT%" --path "%~dp0prototype" -- --match=expedition_outpost
