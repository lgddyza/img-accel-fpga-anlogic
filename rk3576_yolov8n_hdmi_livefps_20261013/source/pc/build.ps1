$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
& .\.venv\Scripts\python.exe -m PyInstaller --noconfirm --clean --onedir --windowed --name RKVisionHost --add-data 'board_agent.py;.' app.py
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller failed' }
# Python's bundled ICU 78 DLL has the same unversioned filename as Windows ICU.
# Qt6Core imports Windows ICU entry points; the bundled copy shadows them.
$shadow = Join-Path $PSScriptRoot 'dist/RKVisionHost/_internal/icuuc.dll'
if (Test-Path -LiteralPath $shadow) { Remove-Item -LiteralPath $shadow }
