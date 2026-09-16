#requires -RunAsAdministrator

$ErrorActionPreference = "SilentlyContinue"

$ServiceName = "Chrome Upload Detector"

Write-Host ""
Write-Host "========================================="
Write-Host " Chrome Upload Detector Uninstallation"
Write-Host "========================================="
Write-Host ""

Write-Host "Stopping service..."

Stop-Service $ServiceName -Force

Start-Sleep -Seconds 2

Write-Host "Removing service..."

& sc.exe delete $ServiceName

Start-Sleep -Seconds 2

Write-Host ""
Write-Host "Service removed."
Write-Host ""

$remaining = Get-Service $ServiceName -ErrorAction SilentlyContinue

if ($remaining) {
    Write-Warning "Service still appears to exist. A reboot may be required."
}
else {
    Write-Host "Chrome Upload Detector successfully uninstalled."
}

Write-Host ""
Write-Host "The data directory was NOT deleted:"
Write-Host "C:\ProgramData\ChromeHistoryMonitor"
Write-Host ""
Write-Host "Logs and database have been preserved."
Write-Host ""