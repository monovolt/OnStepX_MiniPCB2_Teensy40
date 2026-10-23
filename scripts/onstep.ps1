param(
  [Parameter(Mandatory=$true, Position=0)][string]$Command,
  [string]$Port = "COM5",
  [int]$Baud = 115200,
  [int]$WaitSeconds = 15,   # hard cap, for catching a full boot log after a reset
  [int]$IdleMs = 700        # once a reply starts, stop this long after it goes quiet
)

$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$sp.ReadTimeout = 500
$sp.Open()
Start-Sleep -Milliseconds 200   # let the port/driver settle before writing

$cmd = ":$Command#"
Write-Host "-> $cmd"
$sp.Write($cmd)

$deadline = (Get-Date).AddSeconds($WaitSeconds)
$lastData = Get-Date
$got = $false
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 50
  if ($sp.BytesToRead -gt 0) {
    $resp = $sp.ReadExisting()
    if ($resp) { Write-Host "<- $resp" -NoNewline; $got = $true; $lastData = Get-Date }
  } elseif ($got -and (((Get-Date) - $lastData).TotalMilliseconds -gt $IdleMs)) {
    break
  }
}
if (-not $got) { Write-Host "<- (no reply/log in $WaitSeconds s)" }

$sp.Close()
