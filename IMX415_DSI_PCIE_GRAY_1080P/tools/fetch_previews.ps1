$paramFull = $false
if ($args.Count -gt 0 -and $args[0] -eq '-Full') { $paramFull = $true }
$paramBalance = $false
if ($args.Count -gt 0 -and $args[0] -eq '-Balance') { $paramBalance = $true }
$ErrorActionPreference = 'Stop'
$captureDir = 'E:\FPGA\workspace\IMX415_DSI_PCIE_GRAY_1080P\captures'
if ($paramFull) { $captureDir = Join-Path $captureDir 'full' }
if ($paramBalance) { $captureDir = Join-Path $captureDir 'hdmi' }
New-Item -ItemType Directory -Path $captureDir -Force | Out-Null
$remote = 'python3 -c ''import base64,zlib; f=open("/root/imx415_pcie_gray_1080p/capture_3frames.gray","rb"); frames=[f.read(2073600) for _ in range(3)]; [print("FRAME"+str(i)+":"+base64.b64encode(zlib.compress(bytes(b[y*1920+x] for y in range(0,1080,3) for x in range(0,1920,3)),6)).decode()) for i,b in enumerate(frames)]; print("__END_FRAMES__")'''
if ($paramFull) {
    $remote = 'python3 -c ''import base64,zlib; f=open("/root/imx415_pcie_gray_1080p/capture_3frames.gray","rb"); frames=[f.read(2073600) for _ in range(3)]; [print("FRAME"+str(i)+":"+base64.b64encode(zlib.compress(b,6)).decode()) for i,b in enumerate(frames)]; print("__END_FRAMES__")'''
}
if ($paramBalance) {
    $remote = 'python3 -c ''import base64,zlib; b=open("/root/imx415_pcie_gray_1080p/balance_test.gray","rb").read(); print("FRAME0:"+base64.b64encode(zlib.compress(b,6)).decode()); print("__END_FRAMES__")'''
}
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
        if ($text.ToString().Contains("`n__END_FRAMES__`r")) { break }
        Start-Sleep -Milliseconds 20
    }
} finally {
    if ($port.IsOpen) { $port.Close() }
    $port.Dispose()
}
$output = $text.ToString()
$matches = [regex]::Matches($output,'FRAME([0-2]):([A-Za-z0-9+/=]+)')
$expectedCount = if ($paramBalance) { 1 } else { 3 }
if ($matches.Count -ne $expectedCount) {
    throw "Expected $expectedCount compressed frames, found $($matches.Count); received $($output.Length) characters"
}
foreach ($match in $matches) {
    $index = [int]::Parse($match.Groups[1].Value)
    $bytes = [Convert]::FromBase64String($match.Groups[2].Value)
    $path = Join-Path $captureDir ("frame_{0}.zlib" -f $index)
    [System.IO.File]::WriteAllBytes($path,$bytes)
    Write-Output ("frame {0}: {1} compressed bytes -> {2}" -f $index,$bytes.Length,$path)
}
