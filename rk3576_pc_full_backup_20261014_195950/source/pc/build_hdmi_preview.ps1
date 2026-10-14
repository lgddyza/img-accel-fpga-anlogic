$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$agentAsset = (Join-Path $PSScriptRoot 'board_agent.py') + ';.'
& .\.venv\Scripts\python.exe -m PyInstaller --noconfirm --clean --onedir --windowed --name RKVisionHost --distpath dist_hdmi_preview --workpath build_hdmi_preview --specpath build_hdmi_preview --add-data $agentAsset app.py
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller failed' }
$shadow = Join-Path $PSScriptRoot 'dist_hdmi_preview/RKVisionHost/_internal/icuuc.dll'
if (Test-Path -LiteralPath $shadow) { Remove-Item -LiteralPath $shadow }
