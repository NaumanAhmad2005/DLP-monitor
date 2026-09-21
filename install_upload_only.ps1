#requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

# Chrome Upload Detector - UPLOAD ONLY installer
# Common directory:
# C:\ProgramData\ChromeHistoryMonitor
# This installer does NOT install, modify, stop, or remove history detection.

$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$ServiceScmName = "ChromeUploadDetector"
$ServiceDisplayName = "Chrome Upload Detector"

$ServiceSource = Join-Path $ScriptRoot "ChromeUploadDetectorService.exe"
$ReceiverSource = Join-Path $ScriptRoot "receiver.ps1"
$MvpSource = Join-Path $ScriptRoot "ChromeUploadDetector-MVP"

$ServiceDest = Join-Path $BaseDir "ChromeUploadDetectorService.exe"
$ReceiverDest = Join-Path $BaseDir "receiver.ps1"
$MvpDest = Join-Path $BaseDir "ChromeUploadDetector-MVP"

Write-Host ""
Write-Host "=============================================="
Write-Host " Chrome Upload Detector - Upload Only"
Write-Host "=============================================="
Write-Host ""

Write-Host "[1/6] Checking source files..."
if (-not (Test-Path $ServiceSource -PathType Leaf)) { throw "Missing: $ServiceSource" }
if (-not (Test-Path $ReceiverSource -PathType Leaf)) { throw "Missing: $ReceiverSource" }
if (-not (Test-Path $MvpSource -PathType Container)) { throw "Missing: $MvpSource" }
Write-Host "      All upload files found."

Write-Host "[2/6] Preparing common directory..."
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

Write-Host "[3/6] Stopping ONLY upload service..."
$svc = Get-Service $ServiceScmName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne "Stopped") {
        Stop-Service $ServiceScmName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    & sc.exe delete $ServiceScmName | Out-Null
    for ($i=0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Get-Service $ServiceScmName -ErrorAction SilentlyContinue)) { break }
    }
}
Get-Process -Name "ChromeUploadDetectorService" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "[4/6] Installing upload files..."
Copy-Item $ServiceSource $ServiceDest -Force
Copy-Item $ReceiverSource $ReceiverDest -Force
if (Test-Path $MvpDest) { Remove-Item $MvpDest -Recurse -Force }
Copy-Item $MvpSource $MvpDest -Recurse -Force

Write-Host "[5/6] Creating upload service..."
& sc.exe create $ServiceScmName `
    binPath= "`"$ServiceDest`"" `
    start= auto `
    DisplayName= "`"$ServiceDisplayName`"" `
    obj= LocalSystem
if ($LASTEXITCODE -ne 0) { throw "Failed to create ChromeUploadDetector service." }

& sc.exe description $ServiceScmName "Chrome browser upload and clipboard-paste telemetry detector." | Out-Null
& sc.exe failure $ServiceScmName reset= 86400 actions= restart/5000/restart/5000/restart/10000 | Out-Null
& sc.exe failureflag $ServiceScmName 1 | Out-Null

Start-Service $ServiceScmName
Start-Sleep -Seconds 3

$svc = Get-Service $ServiceScmName -ErrorAction Stop
if ($svc.Status -ne "Running") { throw "Upload detector service did not start." }

Write-Host "[6/6] Verification..."
Write-Host ""
Write-Host "[OK] Upload service : $($svc.Status)"
Write-Host "[OK] Startup         : $($svc.StartType)"
Write-Host "[OK] Service EXE     : $ServiceDest"
Write-Host "[OK] Receiver        : $ReceiverDest"
Write-Host "[OK] Extension       : $MvpDest"
Write-Host ""

$historyService = Get-Service "ChromeHistoryMonitor" -ErrorAction SilentlyContinue
$historyTask = Get-ScheduledTask "Chrome History Monitor" -ErrorAction SilentlyContinue

if ($historyService) {
    Write-Host "[PRESERVED] ChromeHistoryMonitor service was not modified."
} else {
    Write-Host "[INFO] ChromeHistoryMonitor service is not installed."
}
if ($historyTask) {
    Write-Host "[PRESERVED] Chrome History Monitor task was not modified."
} else {
    Write-Host "[INFO] Chrome History Monitor task is not installed."
}

Write-Host ""
Write-Host "Upload-only installation finished."
Write-Host "No history files or history components were installed/changed."
