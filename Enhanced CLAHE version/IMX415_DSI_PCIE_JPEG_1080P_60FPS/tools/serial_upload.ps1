param(
    [Parameter(Mandatory = $true)][string]$LocalPath,
    [string]$RemotePath = '/root/jpeg_rk_bundle.zip',
    [string]$Port = 'COM12',
    [int]$Baud = 1500000
)

$ErrorActionPreference = 'Stop'
$data = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $LocalPath).Path)
$encoded = [Convert]::ToBase64String($data)
$expected = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($data)).ToLowerInvariant()
$serial = [IO.Ports.SerialPort]::new($Port, $Baud, [IO.Ports.Parity]::None, 8,
                                     [IO.Ports.StopBits]::One)
$serial.ReadTimeout = 100
$serial.WriteTimeout = 5000
$serial.DtrEnable = $false
$serial.RtsEnable = $false

function Invoke-SerialLine([string]$line, [string]$marker) {
    $serial.Write("$line; printf '\n$marker\n'`r")
    $received = [Text.StringBuilder]::new()
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($serial.BytesToRead -gt 0) {
            [void]$received.Append($serial.ReadExisting())
            if ($received.ToString().Contains($marker)) {
                return $received.ToString()
            }
        } else {
            Start-Sleep -Milliseconds 10
        }
    }
    throw "Serial upload timed out at $marker`: $received"
}

try {
    $serial.Open()
    Start-Sleep -Milliseconds 150
    $serial.DiscardInBuffer()
    $serial.Write("stty -echo`r")
    Start-Sleep -Milliseconds 150
    $serial.DiscardInBuffer()
    [void](Invoke-SerialLine ': > /tmp/codex_jpeg_bundle.b64' '__JPEG_UPLOAD_INIT__')
    $chunkSize = 512
    $total = [int][Math]::Ceiling($encoded.Length / $chunkSize)
    for ($i = 0; $i -lt $total; $i++) {
        $start = $i * $chunkSize
        $chunk = $encoded.Substring($start, [Math]::Min($chunkSize, $encoded.Length - $start))
        [void](Invoke-SerialLine "printf '%s' '$chunk' >> /tmp/codex_jpeg_bundle.b64" "__JPEG_UPLOAD_${i}__")
        if ((($i + 1) % 10) -eq 0 -or ($i + 1) -eq $total) {
            Write-Output "uploaded $($i + 1)/$total chunks"
        }
    }
    $result = Invoke-SerialLine "base64 -d /tmp/codex_jpeg_bundle.b64 > $RemotePath && sha256sum $RemotePath" '__JPEG_UPLOAD_DONE__'
    if ($result -notmatch [regex]::Escape($expected)) {
        throw "RK SHA-256 mismatch: $result"
    }
    Write-Output "RK verified $RemotePath sha256=$expected"
} finally {
    if ($serial.IsOpen) {
        $serial.Write("stty echo`r")
        $serial.Close()
    }
    $serial.Dispose()
}
