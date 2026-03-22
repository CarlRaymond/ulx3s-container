# launch.ps1 — Launch the ULX3S development container from Windows
# Run from a normal (non-admin) PowerShell prompt.
#
# If the device has never been bound, or if the driver is in an error state,
# this script will invoke setup-usb.ps1 which triggers a UAC prompt only for
# the steps that require it. Normal launches after setup need no UAC.

$VID    = "0403"
$PID_ID = "6015"
$WSL_LAUNCH = "cd /mnt/c/sandbox/ulx3s-container && bash launch.sh"

# Helper: query usbipd list for the ULX3S device line
function Get-ULX3SDevice {
    usbipd list | Select-String "${VID}:${PID_ID}" | Select-Object -First 1
}

# Helper: extract busid from a device line
function Get-BusId ($deviceLine) {
    ($deviceLine.Line.Trim() -split '\s+')[0]
}

# Helper: attempt attach, retrying a few times to ride out transient errors
function Invoke-Attach ($busid) {
    for ($i = 1; $i -le 3; $i++) {
        Write-Host "Attaching $busid to WSL (attempt $i/3)..."
        usbipd attach --wsl --busid $busid
        if ($LASTEXITCODE -eq 0) { return $true }
        if ($i -lt 3) { Start-Sleep -Milliseconds 2000 }
    }
    return $false
}

# 1. Check usbipd is available
if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    Write-Host "usbipd not found — running setup-usb.ps1 to install it..."
    & "$PSScriptRoot\setup-usb.ps1"
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# 2. Find the ULX3S device
$device = Get-ULX3SDevice
if (-not $device) {
    Write-Error "ULX3S not found (VID $VID / PID $PID_ID). Is the board plugged in?"
    exit 1
}

$busid = Get-BusId $device
Write-Host "Found ULX3S at bus ID: $busid"

# 3. Bind if needed (setup-usb.ps1 self-elevates via UAC; skipped after first run)
$isBound = $device.Line -match "Shared|Attached"
if (-not $isBound) {
    Write-Host "Device not bound — running setup-usb.ps1..."
    & "$PSScriptRoot\setup-usb.ps1"
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

# 4. Detach any stale WSL session, then wait for the stub driver to settle
#    before re-querying — detach triggers reenumeration which takes a moment.
usbipd detach --busid $busid 2>$null
Start-Sleep -Milliseconds 4000

$device = Get-ULX3SDevice
if (-not $device) {
    Write-Error "ULX3S disappeared after detach. Try unplugging and replugging the board."
    exit 1
}
$busid = Get-BusId $device

# 5. Attach to WSL2; retry a few times, then fall back to an elevated rebind
if (-not (Invoke-Attach $busid)) {
    Write-Host "Attach failed — resetting driver state via rebind (will prompt for admin)..."
    & "$PSScriptRoot\setup-usb.ps1" -Rebind
    if ($LASTEXITCODE -ne 0) { exit 1 }

    $device = Get-ULX3SDevice
    if (-not $device) { Write-Error "ULX3S not found after rebind."; exit 1 }
    $busid = Get-BusId $device

    if (-not (Invoke-Attach $busid)) {
        Write-Error "Failed to attach device to WSL even after rebind. Try unplugging and replugging the board."
        exit 1
    }
}

Write-Host "Device attached. Launching container..."

# 6. Launch via WSL
wsl -- bash -c $WSL_LAUNCH
