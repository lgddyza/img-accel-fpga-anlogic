param(
    [Parameter(Mandatory = $true)][string]$RemotePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$Port = 'COM12',
    [int]$Baud = 1500000,
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
if ($RemotePath -notmatch '^/[A-Za-z0-9_./-]+$') {
    throw 'RemotePath must be an absolute path with simple safe characters.'
}
$begin = '__CODEX_BINARY_BEGIN__'
$end = '__CODEX_BINARY_END__'
$serial = [System.IO.Ports.SerialPort]::new(
    $Port, $Baud, [System.IO.Ports.Parity]::None, 8,
    [System.IO.Ports.StopBits]::One)
$serial.ReadTimeout = 100
$serial.WriteTimeout = 5000
$serial.DtrEnable = $false
$serial.RtsEnable = $false
try {
    $serial.Open()
    Start-Sleep -Milliseconds 150
    $serial.DiscardInBuffer()
    $serial.Write("`r")
    Start-Sleep -Milliseconds 200
    if ($serial.BytesToRead -gt 0) { [void]$serial.ReadExisting() }
    # The complete delimiters are composed on RK, so terminal command echo
    # cannot masquerade as the actual payload boundaries.
    $command = "printf '\n__CODEX_BINARY_%s__\n' 'BEGIN'; base64 -w0 '$RemotePath'; printf '\n__CODEX_BINARY_%s__\n' 'END'`r"
    $serial.Write($command)
    $buffer = [System.Text.StringBuilder]::new()
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($serial.BytesToRead -gt 0) {
            [void]$buffer.Append($serial.ReadExisting())
            if ($buffer.ToString().Contains($end)) { break }
        } else {
            Start-Sleep -Milliseconds 20
        }
    }
    $response = $buffer.ToString()
    $start = $response.IndexOf($begin, [StringComparison]::Ordinal)
    $stop = $response.IndexOf($end, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $stop -lt $start) {
        throw "Timed out or did not receive complete base64 for $RemotePath"
    }
    $payload = $response.Substring($start + $begin.Length,
                                    $stop - $start - $begin.Length)
    $encoded = [regex]::Replace($payload, '\s+', '')
    $bytes = [Convert]::FromBase64String($encoded)
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [IO.File]::WriteAllBytes($OutputPath, $bytes)
    Write-Output "Saved $($bytes.Length) bytes to $OutputPath"
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
