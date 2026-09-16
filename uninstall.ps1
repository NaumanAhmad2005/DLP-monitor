#requires -RunAsAdministrator

$ErrorActionPreference = "SilentlyContinue"

$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"
$ServiceName = "Chrome Upload Detector"
$HistoryTaskName = "Chrome History Monitor"

Write-Host ""
Write-Host "========================================="
Write-Host " Chrome History & Upload Monitor"
Write-Host " Uninstallation"
Write-Host "========================================="
Write-Host ""

# =========================================================
# Stop/remove history monitor task
# =========================================================

$Task = Get-ScheduledTask `
    -TaskName $HistoryTaskName `
    -ErrorAction SilentlyContinue

if ($Task) {

    Write-Host "Stopping history monitor..."

    Stop-ScheduledTask `
        -TaskName $HistoryTaskName `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    Write-Host "Removing history monitor task..."

    Unregister-ScheduledTask `
        -TaskName $HistoryTaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    Write-Host "History monitor task removed."

}
else {

    Write-Host "History monitor task not found. Nothing to remove."
}

# =========================================================
# Stop/remove upload detector service
# =========================================================

$Service = Get-Service `
    -Name $ServiceName `
    -ErrorAction SilentlyContinue

if ($Service) {

    Write-Host "Stopping upload service..."

    Stop-Service `
        -Name $ServiceName `
        -Force `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    Write-Host "Removing upload service..."

    & sc.exe delete $ServiceName | Out-Null

    Start-Sleep -Seconds 2

    Get-Process `
        -Name "ChromeUploadDetectorService" `
        -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host "Upload service removed."

}
else {

    Write-Host "Upload service not found. Nothing to remove."
}

Write-Host ""
Write-Host "Services and tasks removed."
Write-Host ""
Write-Host "The data directory was NOT deleted:"
Write-Host $BaseDir
Write-Host ""
Write-Host "Logs and databases have been preserved."
Write-Host ""
