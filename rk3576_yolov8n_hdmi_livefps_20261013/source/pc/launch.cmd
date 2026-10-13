@echo off
cd /d "%~dp0"
if exist "dist\RKVisionHost\RKVisionHost.exe" (
    start "" "dist\RKVisionHost\RKVisionHost.exe"
) else (
    ".venv\Scripts\python.exe" app.py
)
