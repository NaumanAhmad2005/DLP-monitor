#requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"

$ServiceName = "Chrome Upload Detector"
$ServiceDisplayName = "Chrome Upload Detector"

$HistoryTaskName = "Chrome History Monitor"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$ServiceExe = Join-Path $ScriptRoot "ChromeUploadDetectorService.exe"
$Receiver = Join-Path $ScriptRoot "receiver.ps1"
$CollectorSource = Join-Path $ScriptRoot "collector.ps1"

$InstalledExe = Join-Path $BaseDir "ChromeUploadDetectorService.exe"
$InstalledReceiver = Join-Path $BaseDir "receiver.ps1"
$InstalledCollector = Join-Path $BaseDir "collector.ps1"

Write-Host ""
Write-Host "========================================="
Write-Host " Chrome History & Upload Monitor"
Write-Host " Installation"
Write-Host "========================================="
Write-Host ""

# =========================================================
# [1] CHECK INSTALLATION FILES
# =========================================================

Write-Host "[1/8] Checking installation files..."

if (-not (Test-Path $ServiceExe)) {
    throw "Missing: $ServiceExe"
}

if (-not (Test-Path $Receiver)) {
    throw "Missing: $Receiver"
}

if (-not (Test-Path $CollectorSource)) {
    throw "Missing: $CollectorSource"
}

Write-Host "      Required files found."

# =========================================================
# [2] CREATE PROGRAM DIRECTORY
# =========================================================

Write-Host "[2/8] Creating program directory..."

New-Item `
    -ItemType Directory `
    -Path $BaseDir `
    -Force |
    Out-Null

Write-Host "      $BaseDir"

# =========================================================
# [3] COPY RUNTIME FILES
# =========================================================

Write-Host "[3/8] Installing runtime files..."

Copy-Item `
    $Receiver `
    $InstalledReceiver `
    -Force

Copy-Item `
    $ServiceExe `
    $InstalledExe `
    -Force

Copy-Item `
    $CollectorSource `
    $InstalledCollector `
    -Force

Write-Host "      Files installed."

# =========================================================
# [4] REMOVE OLD UPLOAD SERVICE
# =========================================================

Write-Host "[4/8] Configuring upload detector service..."

$existingService = Get-Service `
    -Name $ServiceName `
    -ErrorAction SilentlyContinue

if ($existingService) {

    if ($existingService.Status -ne "Stopped") {

        Write-Host "      Stopping existing service..."

        Stop-Service `
            -Name $ServiceName `
            -Force `
            -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2

    & sc.exe delete $ServiceName | Out-Null

    Start-Sleep -Seconds 2
}

& sc.exe create $ServiceName `
    binPath= "`"$InstalledExe`"" `
    start= auto `
    DisplayName= "`"$ServiceDisplayName`"" `
    obj= LocalSystem

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create Chrome Upload Detector service."
}

Write-Host "      Service created."

# Automatic recovery

& sc.exe failure $ServiceName `
    reset= 86400 `
    actions= restart/5000/restart/5000/restart/10000 |
    Out-Null

& sc.exe failureflag $ServiceName 1 |
    Out-Null


# =========================================================
# [5] CREATE HIDDEN CHROME HISTORY TASK
# =========================================================

Write-Host "[5/8] Configuring Chrome History Monitor..."

# Remove previous task if present

$existingTask = Get-ScheduledTask `
    -TaskName $HistoryTaskName `
    -ErrorAction SilentlyContinue

if ($existingTask) {

    Write-Host "      Removing previous history task..."

    Unregister-ScheduledTask `
        -TaskName $HistoryTaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 1
}

# ---------------------------------------------------------
# Create task using SCHTASKS
#
# /SC ONLOGON       = run when a user logs on
# /RU "SYSTEM"      = task owner
# /RL HIGHEST       = highest privileges
# /F                = replace existing task
#
# The collector itself determines the active Chrome profile.
# ---------------------------------------------------------

$TaskCommand = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstalledCollector`""

& schtasks.exe /Create `
    /TN $HistoryTaskName `
    /TR $TaskCommand `
    /SC ONLOGON `
    /RU SYSTEM `
    /RL HIGHEST `
    /F

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create Chrome History Monitor scheduled task."
}

Write-Host "      Chrome History Monitor task created."

# ---------------------------------------------------------
# Hide the task from normal Task Scheduler view
# ---------------------------------------------------------

try {

    $task = Get-ScheduledTask `
        -TaskName $HistoryTaskName `
        -ErrorAction Stop

    # Mark task hidden through task XML
    [xml]$xml = Export-ScheduledTask `
        -TaskName $HistoryTaskName

    $xml.Task.Settings.Hidden = "true"

    Register-ScheduledTask `
        -TaskName $HistoryTaskName `
        -Xml $xml.OuterXml `
        -Force |
        Out-Null

    Write-Host "      Task configured as hidden."

}
catch {

    Write-Warning "Could not mark task hidden. Task will still run in background."
}



# =========================================================
# [6] START UPLOAD SERVICE
# =========================================================

Write-Host "[6/8] Starting upload detector service..."

Start-Service `
    -Name $ServiceName

Start-Sleep -Seconds 3

$service = Get-Service `
    -Name $ServiceName

Write-Host "      Service status: $($service.Status)"

if ($service.Status -ne "Running") {

    Write-Host ""
    Write-Host "ERROR: Upload detector service did not start."
    Write-Host ""

    Write-Host "Check:"
    Write-Host "  $BaseDir\service-host.log"
    Write-Host "  $BaseDir\receiver.log"

    exit 1
}

# =========================================================
# [7] START HISTORY TASK FOR CURRENT USER
# =========================================================

Write-Host "[7/8] Starting Chrome History Monitor..."

try {

    Start-ScheduledTask `
        -TaskName $HistoryTaskName

    Start-Sleep -Seconds 2

    $taskInfo = Get-ScheduledTaskInfo `
        -TaskName $HistoryTaskName

    Write-Host "      History task started."
    Write-Host "      Last run: $($taskInfo.LastRunTime)"

}
catch {

    Write-Warning "History task could not be started immediately."
    Write-Warning "It will automatically start at the next user logon."
}

# =========================================================
# [8] VERIFY INSTALLATION
# =========================================================

Write-Host "[8/8] Verifying installation..."

$listener = Get-NetTCPConnection `
    -LocalPort 8765 `
    -ErrorAction SilentlyContinue

$task = Get-ScheduledTask `
    -TaskName $HistoryTaskName `
    -ErrorAction SilentlyContinue

$service = Get-Service `
    -Name $ServiceName `
    -ErrorAction SilentlyContinue

Write-Host ""

if ($service -and $service.Status -eq "Running") {

    Write-Host "  [OK] Upload detector service: Running"

}
else {

    Write-Warning "Upload detector service is not running."
}

if ($task) {

    Write-Host "  [OK] Chrome history task: Installed"

}
else {

    Write-Warning "Chrome history task was not installed."
}

if ($listener) {

    Write-Host "  [OK] Upload listener: Port 8765"

}
else {

    Write-Warning "Upload listener is not currently detected."
}

Write-Host ""
Write-Host "========================================="
Write-Host " Installation complete"
Write-Host "========================================="
Write-Host ""
Write-Host "Service : $ServiceName"
Write-Host "History : $HistoryTaskName"
Write-Host "Port    : 8765"
Write-Host "Folder  : $BaseDir"
Write-Host ""
Write-Host "The history collector runs silently at user logon."
Write-Host "The upload detector runs as a Windows service."
Write-Host ""