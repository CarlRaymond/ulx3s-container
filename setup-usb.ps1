# setup-usb.ps1 — USB setup for the ULX3S board
#
# Run from a normal user account — it will self-elevate via UAC only
# for the steps that require admin rights (installing usbipd, binding
# the device). Safe to re-run; skips steps that are already done.
#
# Flags:
#   -Rebind   Force unbind + rebind even if already bound (fixes driver
#             error state; used automatically by launch.ps1 on attach failure)

param([switch]$Rebind)

$VID    = "0403"
$PID_ID = "6015"

# ---------------------------------------------------------------------------
# Helper: re-launch this script elevated, capturing output back to this
# terminal, and wait for it to finish.
# ---------------------------------------------------------------------------
function Invoke-Elevated ([string]$ExtraArgs = "") {
    # Capture elevated output via a wrapper script — redirection (*>) only
    # works inside a .ps1 file, not when passed as a -File argument.
    $log     = [System.IO.Path]::GetTempFileName()
    $wrapper = [System.IO.Path]::GetTempFileName() + ".ps1"
    Set-Content $wrapper "& `"$PSCommandPath`" $ExtraArgs *> `"$log`"; exit `$LASTEXITCODE"

    try {
        $proc = Start-Process powershell.exe -Verb RunAs -Wait -PassThru `
                    -WindowStyle Hidden `
                    -ArgumentList "-ExecutionPolicy Bypass -File `"$wrapper`""
    } catch {
        Write-Error "Elevation was cancelled or denied."
        Remove-Item $wrapper, $log -ErrorAction SilentlyContinue
        exit 1
    }

    Remove-Item $wrapper -ErrorAction SilentlyContinue
    if (Test-Path $log) {
        Get-Content $log | Write-Host
        Remove-Item $log -ErrorAction SilentlyContinue
    }
    exit $proc.ExitCode
}

$isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------------------------------------------------------------------
# Step 1 — Install usbipd if missing (requires admin)
# ---------------------------------------------------------------------------
if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    Write-Host "usbipd not found — will install via winget (requires admin)."
    if (-not $isAdmin) {
        $extra = if ($Rebind) { "-Rebind" } else { "" }
        Invoke-Elevated $extra
    }

    winget install --exact --id "dorssel.usbipd-win" --silent
    if ($LASTEXITCODE -ne 0) { Write-Error "winget install failed."; exit 1 }

    # Reload PATH so usbipd is visible without reopening the shell
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH","User")
}

# ---------------------------------------------------------------------------
# Step 2 — Find the ULX3S device (retry — device may be briefly invisible
#           after a failed attach or while Windows reenumerates it)
# ---------------------------------------------------------------------------
$device = $null
for ($i = 1; $i -le 6; $i++) {
    $device = usbipd list | Select-String "${VID}:${PID_ID}" | Select-Object -First 1
    if ($device) { break }
    Write-Host "Waiting for device... ($i/6)"
    Start-Sleep -Milliseconds 1000
}
if (-not $device) {
    Write-Error "ULX3S not found (VID $VID / PID $PID_ID). Is the board plugged in?"
    exit 1
}

$busid = ($device.Line.Trim() -split '\s+')[0]
Write-Host "Found ULX3S at bus ID: $busid"

# ---------------------------------------------------------------------------
# Step 3 — Bind (or rebind) the device (requires admin)
# ---------------------------------------------------------------------------
$isBound = $device.Line -match "Shared|Attached"

if ($isBound -and -not $Rebind) {
    Write-Host "Device $busid is already bound — nothing to do."
    exit 0
}

if ($Rebind) {
    Write-Host "Rebinding device $busid to reset driver state (requires admin)..."
} else {
    Write-Host "Device is not bound — binding requires admin privileges."
}

if (-not $isAdmin) {
    $extra = if ($Rebind) { "-Rebind" } else { "" }
    Invoke-Elevated $extra
}

# Running as admin — unbind first if rebinding, then bind
if ($Rebind -and $isBound) {
    usbipd unbind --busid $busid 2>$null
    Start-Sleep -Milliseconds 1500   # wait for FTDI driver to reload
}

usbipd bind --busid $busid
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to bind device $busid."; exit 1 }

Start-Sleep -Milliseconds 2000  # let stub driver settle
Write-Host "Device $busid bound successfully."
