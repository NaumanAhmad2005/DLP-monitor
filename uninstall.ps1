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

$Service = Get-Service $ServiceName
if ($Service) {
    Write-Host "Stopping upload service..."
    Stop-Service $ServiceName -Force
    Start-Sleep -Seconds 2
    & sc.exe delete $ServiceName | Out-Null
}

$Task = Get-ScheduledTask $HistoryTaskName
if ($Task) {
    Write-Host "Removing history task..."
    Stop-ScheduledTask $HistoryTaskName
    Unregister-ScheduledTask $HistoryTaskName -Confirm:$false
}

Write-Host ""
Write-Host "Services and tasks removed."
Write-Host ""
Write-Host "The data directory was NOT deleted:"
Write-Host $BaseDir
Write-Host ""
Write-Host "Logs and databases have been preserved."
Write-Host ""
