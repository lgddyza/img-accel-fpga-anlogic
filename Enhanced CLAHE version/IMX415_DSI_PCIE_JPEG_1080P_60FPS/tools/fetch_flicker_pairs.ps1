$ErrorActionPreference = 'Stop'
$captureDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'captures\flicker'
New-Item -ItemType Directory -Path $captureDir -Force | Out-Null
$remote = 'python3 -c ''import base64,zlib; f=open("/dev/shm/flicker_60.gray","rb"); n=2073600; ids=(0,1,10,11,14,15); pairs=[(i,(f.seek(i*n),f.read(n))[1]) for i in ids]; [print("FRAME"+str(i)+":"+base64.b64encode(zlib.compress(bytes(b[y*1920+x] for y in range(0,1080,3) for x in range(0,1920,3)),6)).decode()) for i,b in pairs]; print("__END_FLICKER__")'''
$port = [System.IO.Ports.SerialPort]::new('COM12',1500000,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$port.ReadBufferSize = 1048576
$text = [System.Text.StringBuilder]::new()
try {
    $port.Open()
    $port.DiscardInBuffer()
    $port.WriteLine($remote)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($watch.Elapsed.TotalSeconds -lt 90) {
        $chunk = $port.ReadExisting()
        if ($chunk.Length) { [void]$text.Append($chunk) }
        if ($text.ToString().Contains("`n__END_FLICKER__`r")) { break }
        Start-Sleep -Milliseconds 20
    }
} finally {
    if ($port.IsOpen) { $port.Close() }
    $port.Dispose()
}
$output = $text.ToString()
$matches = [regex]::Matches($output,'FRAME([0-9]+):([A-Za-z0-9+/=]+)')
if ($matches.Count -ne 6) { throw "Expected 6 frames, found $($matches.Count); received $($output.Length) characters" }
foreach ($match in $matches) {
    $index = [int]::Parse($match.Groups[1].Value)
    $bytes = [Convert]::FromBase64String($match.Groups[2].Value)
    $path = Join-Path $captureDir ("frame_{0}.zlib" -f $index)
    [System.IO.File]::WriteAllBytes($path,$bytes)
    Write-Output ("frame {0}: {1} bytes" -f $index,$bytes.Length)
}
