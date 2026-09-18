# ============================================================
# Chrome History & Upload Monitor - Uninstaller
# ============================================================

$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"

$HistoryServiceName = "ChromeHistoryMonitor"
$HistoryTaskName = "Chrome History Monitor"

$UploadServiceName = "Chrome Upload Detector"

Write-Host ""
Write-Host "============================================"
Write-Host " Chrome History & Upload Monitor Uninstaller"
Write-Host "============================================"
Write-Host ""

# ------------------------------------------------------------
# 1. Stop Chrome History Windows Service
# ------------------------------------------------------------

Write-Host "[1/7] Checking Chrome History service..."

$HistoryService = Get-Service $HistoryServiceName -ErrorAction SilentlyContinue

if ($HistoryService) {

    Write-Host "      Found service: $HistoryServiceName"

    if ($HistoryService.Status -ne "Stopped") {
        Write-Host "      Stopping service..."
        Stop-Service $HistoryServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Write-Host "      Deleting service registration..."
    sc.exe delete $HistoryServiceName | Out-Null

    Start-Sleep -Seconds 2

    Write-Host "      Chrome History service removed."
}
else {
    Write-Host "      Service not installed."
}

# ------------------------------------------------------------
# 2. Stop Chrome Upload Detector service
# ------------------------------------------------------------

Write-Host ""
Write-Host "[2/7] Checking Chrome Upload Detector service..."

$UploadService = Get-Service $UploadServiceName -ErrorAction SilentlyContinue

if ($UploadService) {

    Write-Host "      Found service: $UploadServiceName"

    if ($UploadService.Status -ne "Stopped") {
        Write-Host "      Stopping service..."
        Stop-Service $UploadServiceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    Write-Host "      Deleting service registration..."
    sc.exe delete $UploadServiceName | Out-Null

    Start-Sleep -Seconds 2

    Write-Host "      Chrome Upload Detector service removed."
}
else {
    Write-Host "      Upload service not installed."
}

# ------------------------------------------------------------
# 3. Remove old Chrome History Scheduled Task
# ------------------------------------------------------------

Write-Host ""
Write-Host "[3/7] Checking old Chrome History Scheduled Task..."

$HistoryTask = Get-ScheduledTask `
    -TaskName $HistoryTaskName `
    -ErrorAction SilentlyContinue

if ($HistoryTask) {

    Write-Host "      Found task: $HistoryTaskName"

    Write-Host "      Stopping task..."
    Stop-ScheduledTask `
        -TaskName $HistoryTaskName `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    Write-Host "      Removing scheduled task..."
    Unregister-ScheduledTask `
        -TaskName $HistoryTaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    Write-Host "      Scheduled Task removed."
}
else {
    Write-Host "      Scheduled Task not installed."
}

# ------------------------------------------------------------
# 4. Stop remaining collector processes
# ------------------------------------------------------------

Write-Host ""
Write-Host "[4/7] Checking for remaining collector processes..."

$CollectorProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.CommandLine -like "*collector.ps1*"
    }

if ($CollectorProcesses) {

    foreach ($Process in $CollectorProcesses) {

        Write-Host "      Stopping collector PID $($Process.ProcessId)..."

        Stop-Process `
            -Id $Process.ProcessId `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
}
else {
    Write-Host "      No collector processes found."
}

# ------------------------------------------------------------
# 5. Stop remaining service processes
# ------------------------------------------------------------

Write-Host ""
Write-Host "[5/7] Checking for remaining service processes..."

$ServiceProcess = Get-Process `
    -Name "ChromeHistoryService" `
    -ErrorAction SilentlyContinue

if ($ServiceProcess) {

    foreach ($Process in $ServiceProcess) {

        Write-Host "      Stopping ChromeHistoryService PID $($Process.Id)..."

        Stop-Process `
            -Id $Process.Id `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2
}
else {
    Write-Host "      No ChromeHistoryService process found."
}

# ------------------------------------------------------------
# 6. Remove project directory
# ------------------------------------------------------------

Write-Host ""
Write-Host "[6/7] Removing project files..."

if (Test-Path $BaseDir) {

    Remove-Item `
        -Path $BaseDir `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    if (Test-Path $BaseDir) {
        Write-Host "      WARNING: Some files could not be removed."
        Write-Host "      Directory: $BaseDir"
    }
    else {
        Write-Host "      Project directory removed."
    }
}
else {
    Write-Host "      Project directory not found."
}

# ------------------------------------------------------------
# 7. Final verification
# ------------------------------------------------------------

Write-Host ""
Write-Host "[7/7] Final verification..."

$RemainingHistoryService = Get-Service `
    $HistoryServiceName `
    -ErrorAction SilentlyContinue

$RemainingUploadService = Get-Service `
    $UploadServiceName `
    -ErrorAction SilentlyContinue

$RemainingTask = Get-ScheduledTask `
    -TaskName $HistoryTaskName `
    -ErrorAction SilentlyContinue

if (-not $RemainingHistoryService) {
    Write-Host "      [OK] ChromeHistoryMonitor service removed."
}
else {
    Write-Host "      [WARNING] ChromeHistoryMonitor service still exists."
}

if (-not $RemainingUploadService) {
    Write-Host "      [OK] Chrome Upload Detector service removed."
}
else {
    Write-Host "      [WARNING] Chrome Upload Detector service still exists."
}

if (-not $RemainingTask) {
    Write-Host "      [OK] Chrome History Monitor Scheduled Task removed."
}
else {
    Write-Host "      [WARNING] Scheduled Task still exists."
}

if (-not (Test-Path $BaseDir)) {
    Write-Host "      [OK] Project directory removed."
}
else {
    Write-Host "      [WARNING] Project directory still exists."
}

Write-Host ""
Write-Host "============================================"
Write-Host " Uninstallation completed."
Write-Host "============================================"
Write-Host ""