param(
    [Parameter(Mandatory = $true)][string]$RemotePath,
    [Parameter(Mandatory = $true)][string]$LocalPath,
    [string]$Port = 'COM12',
    [int]$Baud = 1500000
)

$ErrorActionPreference = 'Stop'
if ($RemotePath -notmatch '^/[A-Za-z0-9_./-]+$') {
    throw 'RemotePath may contain only letters, digits, /, ., _ and -'
}
$serial = [IO.Ports.SerialPort]::new($Port, $Baud, [IO.Ports.Parity]::None,
                                     8, [IO.Ports.StopBits]::One)
$serial.ReadTimeout = 100
$serial.WriteTimeout = 5000
$serial.DtrEnable = $false
$serial.RtsEnable = $false
try {
    $serial.Open()
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()
    $serial.Write("stty -echo`r")
    Start-Sleep -Milliseconds 100
    $serial.DiscardInBuffer()
    $serial.Write("printf __CODEX_B64_BEGIN__; base64 -w 0 '$RemotePath'; printf __CODEX_B64_END__`r")
    $received = [Text.StringBuilder]::new()
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($serial.BytesToRead -gt 0) {
            [void]$received.Append($serial.ReadExisting())
            if ($received.ToString().Contains('__CODEX_B64_END__')) { break }
        } else {
            Start-Sleep -Milliseconds 5
        }
    }
    $output = $received.ToString()
    $begin = $output.IndexOf('__CODEX_B64_BEGIN__')
    $end = $output.IndexOf('__CODEX_B64_END__')
    if ($begin -lt 0 -or $end -le $begin) {
        throw "Serial download incomplete ($($output.Length) characters)"
    }
    $encoded = $output.Substring($begin + '__CODEX_B64_BEGIN__'.Length,
                                 $end - $begin - '__CODEX_B64_BEGIN__'.Length)
    $data = [Convert]::FromBase64String($encoded)
    [IO.File]::WriteAllBytes($LocalPath, $data)
    Write-Output "downloaded $($data.Length) bytes to $LocalPath"
} finally {
    if ($serial.IsOpen) {
        $serial.Write("stty echo`r")
        $serial.Close()
    }
    $serial.Dispose()
}
