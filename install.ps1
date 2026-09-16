#requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# =========================================================
# CONFIGURATION
# =========================================================

$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"

$ServiceName        = "Chrome Upload Detector"
$ServiceDisplayName = "Chrome Upload Detector"

$HistoryTaskName = "Chrome History Monitor"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Installer source files
$ServiceExe       = Join-Path $ScriptRoot "ChromeUploadDetectorService.exe"
$Receiver         = Join-Path $ScriptRoot "receiver.ps1"
$CollectorSource  = Join-Path $ScriptRoot "collector.ps1"
$MvpSource        = Join-Path $ScriptRoot "ChromeUploadDetector-MVP"

# Try the normal tools location first
$SqliteSource = Join-Path $ScriptRoot "tools\sqlite3.exe"

if (-not (Test-Path $SqliteSource)) {
    $SqliteSource = Join-Path $ScriptRoot "sqlite3.exe"
}

# Installed files
$InstalledExe       = Join-Path $BaseDir "ChromeUploadDetectorService.exe"
$InstalledReceiver  = Join-Path $BaseDir "receiver.ps1"
$InstalledCollector = Join-Path $BaseDir "collector.ps1"
$InstalledSqlite    = Join-Path $BaseDir "sqlite3.exe"
$InstalledMvp        = Join-Path $BaseDir "ChromeUploadDetector-MVP"

$ArchiveDb = Join-Path $BaseDir "chrome_history_archive.db"

# =========================================================
# HEADER
# =========================================================

Write-Host ""
Write-Host "========================================="
Write-Host " Chrome History & Upload Monitor"
Write-Host " Installation"
Write-Host "========================================="
Write-Host ""

# =========================================================
# [1] CHECK INSTALLATION FILES
# =========================================================

Write-Host "[1/9] Checking installation files..."

if (-not (Test-Path $ServiceExe)) {
    throw "Missing: $ServiceExe"
}

if (-not (Test-Path $Receiver)) {
    throw "Missing: $Receiver"
}

if (-not (Test-Path $CollectorSource)) {
    throw "Missing: $CollectorSource"
}

if (-not (Test-Path $MvpSource -PathType Container)) {
    throw "Missing ChromeUploadDetector-MVP folder: $MvpSource"
}

if (-not (Test-Path $SqliteSource)) {
    throw "Missing sqlite3.exe."
    Write-Host "Expected:"
    Write-Host "  $ScriptRoot\tools\sqlite3.exe"
    Write-Host "or"
    Write-Host "  $ScriptRoot\sqlite3.exe"
}

Write-Host "      Required files found."

# =========================================================
# [2] CREATE PROGRAM DIRECTORY
# =========================================================

Write-Host "[2/9] Creating program directory..."

New-Item `
    -ItemType Directory `
    -Path $BaseDir `
    -Force |
    Out-Null

Write-Host "      $BaseDir"

# =========================================================
# [3] STOP OLD COMPONENTS BEFORE COPYING
# =========================================================

Write-Host "[3/9] Stopping previous components..."

# ---------------------------------------------------------
# Stop upload service
# ---------------------------------------------------------

$existingService = Get-Service `
    -Name $ServiceName `
    -ErrorAction SilentlyContinue

if ($existingService) {

    if ($existingService.Status -ne "Stopped") {

        Write-Host "      Stopping upload detector service..."

        Stop-Service `
            -Name $ServiceName `
            -Force `
            -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 2
    }
}

# ---------------------------------------------------------
# Stop/remove history task
# ---------------------------------------------------------

$existingTask = Get-ScheduledTask `
    -TaskName $HistoryTaskName `
    -ErrorAction SilentlyContinue

if ($existingTask) {

    Write-Host "      Stopping history monitor task..."

    Stop-ScheduledTask `
        -TaskName $HistoryTaskName `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 1

    Write-Host "      Removing previous history task..."

    Unregister-ScheduledTask `
        -TaskName $HistoryTaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2
}

Write-Host "      Previous components stopped."

# =========================================================
# [4] REMOVE OLD SERVICE
# =========================================================

Write-Host "[4/9] Removing previous upload service..."

$existingService = Get-Service `
    -Name $ServiceName `
    -ErrorAction SilentlyContinue

if ($existingService) {

    & sc.exe delete $ServiceName | Out-Null

    Start-Sleep -Seconds 2

    Write-Host "      Previous service removed."
}
else {

    Write-Host "      No previous service found."
}

# =========================================================
# [5] INSTALL RUNTIME FILES
# =========================================================

Write-Host "[5/9] Installing runtime files..."

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

Copy-Item `
    $SqliteSource `
    $InstalledSqlite `
    -Force

# Copy the manual Chrome extension/configuration package so all
# deployment components remain under the same ProgramData folder.
if (Test-Path $InstalledMvp) {
    Remove-Item $InstalledMvp -Recurse -Force
}

Copy-Item `
    $MvpSource `
    $InstalledMvp `
    -Recurse `
    -Force

Write-Host "      Collector installed."
Write-Host "      Receiver installed."
Write-Host "      Upload service installed."
Write-Host "      SQLite installed."

# =========================================================
# VERIFY COLLECTOR SYNTAX BEFORE CONTINUING
# =========================================================

Write-Host "      Checking collector PowerShell syntax..."

$tokens = $null
$parseErrors = $null

[System.Management.Automation.Language.Parser]::ParseFile(
    $InstalledCollector,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

if ($parseErrors -and $parseErrors.Count -gt 0) {

    Write-Host ""
    Write-Host "ERROR: collector.ps1 contains PowerShell syntax errors."
    Write-Host ""

    $parseErrors |
        Select-Object Message,Extent,ErrorId |
        Format-List

    throw "Collector syntax validation failed."
}

Write-Host "      Collector syntax: OK"

# =========================================================
# [6] HANDLE OLD ARCHIVE DATABASE
# =========================================================

Write-Host "[6/9] Checking Chrome history archive..."

if (Test-Path $ArchiveDb) {

    Write-Host "      Existing archive found."

    # Make sure sqlite can be executed
    if (-not (Test-Path $InstalledSqlite)) {
        throw "Installed sqlite3.exe was not found."
    }

    # Read the actual history-table column names.
    # Checking exact column names avoids false schema failures.
    $ColumnNames = @(
        & $InstalledSqlite $ArchiveDb "SELECT name FROM pragma_table_info('history');" 2>$null |
        ForEach-Object { $_.ToString().Trim() } |
        Where-Object { $_ }
    )

    $RequiredColumns = @(
        'username',
        'chrome_profile',
        'chrome_visit_id',
        'visit_time',
        'url'
    )

    $MissingColumns = @(
        $RequiredColumns |
        Where-Object { $ColumnNames -notcontains $_ }
    )

    $LooksOld = ($MissingColumns.Count -gt 0)

    if ($LooksOld) {

        $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"

        $BackupDb = "$ArchiveDb.old_$Stamp"

        Write-Host ""
        Write-Host "      Old single-user archive detected."
        Write-Host "      Backing it up before creating the new archive."
        Write-Host ""
        Write-Host "      Backup: $BackupDb"

        Move-Item `
            $ArchiveDb `
            $BackupDb `
            -Force

        # Also remove possible WAL/SHM files associated with
        # the old database.
        Remove-Item `
            "$ArchiveDb-wal" `
            -Force `
            -ErrorAction SilentlyContinue

        Remove-Item `
            "$ArchiveDb-shm" `
            -Force `
            -ErrorAction SilentlyContinue

        Write-Host "      Old archive preserved."
        Write-Host "      New multi-user archive will be created."
    }
    else {

        Write-Host "      Existing archive appears compatible."
        Write-Host "      Existing history will be preserved."
    }

}
else {

    Write-Host "      No existing archive found."
    Write-Host "      Fresh multi-user archive will be created."
}

# =========================================================
# [7] CREATE UPLOAD DETECTOR WINDOWS SERVICE
# =========================================================

Write-Host "[7/9] Configuring upload detector service..."

& sc.exe create $ServiceName `
    binPath= "`"$InstalledExe`"" `
    start= auto `
    DisplayName= "`"$ServiceDisplayName`"" `
    obj= LocalSystem

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create Chrome Upload Detector service."
}

# Automatic service recovery

& sc.exe failure $ServiceName `
    reset= 86400 `
    actions= restart/5000/restart/5000/restart/10000 |
    Out-Null

& sc.exe failureflag $ServiceName 1 |
    Out-Null

Write-Host "      Upload service created."
Write-Host "      Startup: Automatic"
Write-Host "      Account: LocalSystem"

# =========================================================
# CREATE HISTORY MONITOR TASK
# =========================================================

Write-Host "      Creating multi-user Chrome history task..."

# ---------------------------------------------------------
# Action
# ---------------------------------------------------------

$Action = New-ScheduledTaskAction `
    -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstalledCollector`"" `
    -WorkingDirectory $BaseDir

# ---------------------------------------------------------
# Trigger
#
# Start at system startup and repeat every 10 seconds.
# SYSTEM can access all normal user profile directories.
# ---------------------------------------------------------

$StartTime = (Get-Date).AddMinutes(1)

$Trigger = New-ScheduledTaskTrigger `
    -Once `
    -At $StartTime `
    -RepetitionInterval (New-TimeSpan -Seconds 10) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

# ---------------------------------------------------------
# SYSTEM principal
# ---------------------------------------------------------

$Principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

# ---------------------------------------------------------
# Settings
# ---------------------------------------------------------

$Settings = New-ScheduledTaskSettingsSet `
    -Hidden `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew

# ---------------------------------------------------------
# Register
# ---------------------------------------------------------

Register-ScheduledTask `
    -TaskName $HistoryTaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Multi-user Chrome History Monitor" `
    -Force

Write-Host "      History task created."
Write-Host "      Account: SYSTEM"
Write-Host "      Interval: 10 seconds"
Write-Host "      Mode: Hidden"

# =========================================================
# [8] START COMPONENTS
# =========================================================

Write-Host "[8/9] Starting monitoring components..."

# ---------------------------------------------------------
# Start upload service
# ---------------------------------------------------------

Start-Service `
    -Name $ServiceName

Start-Sleep -Seconds 3

$service = Get-Service `
    -Name $ServiceName

if ($service.Status -ne "Running") {

    Write-Host ""
    Write-Host "ERROR: Upload detector service failed to start."
    Write-Host ""

    Write-Host "Check:"
    Write-Host "  $BaseDir\service-host.log"
    Write-Host "  $BaseDir\receiver.log"

    exit 1
}

Write-Host "      Upload detector: Running"

# ---------------------------------------------------------
# Start history task immediately
# ---------------------------------------------------------

try {

    Start-ScheduledTask `
        -TaskName $HistoryTaskName

    Start-Sleep -Seconds 5

    $TaskInfo = Get-ScheduledTaskInfo `
        -TaskName $HistoryTaskName

    Write-Host "      History monitor started."
    Write-Host "      Last run: $($TaskInfo.LastRunTime)"
    Write-Host "      Result: $($TaskInfo.LastTaskResult)"

}
catch {

    Write-Warning "History task could not be started immediately."
    Write-Warning "It will start automatically from its trigger."
}

# =========================================================
# [9] FINAL VERIFICATION
# =========================================================

Write-Host "[9/9] Verifying installation..."

$service = Get-Service `
    -Name $ServiceName `
    -ErrorAction SilentlyContinue

$task = Get-ScheduledTask `
    -TaskName $HistoryTaskName `
    -ErrorAction SilentlyContinue

$listener = Get-NetTCPConnection `
    -LocalPort 8765 `
    -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================="
Write-Host " Installation complete"
Write-Host "========================================="
Write-Host ""

if ($service -and $service.Status -eq "Running") {
    Write-Host "  [OK] Upload detector service : Running"
}
else {
    Write-Warning "Upload detector service is not running."
}

if ($task) {

    $PrincipalInfo = $task.Principal

    Write-Host "  [OK] Chrome history task     : Installed"
    Write-Host "  [OK] History task account    : $($PrincipalInfo.UserId)"
}
else {
    Write-Warning "Chrome history task was not installed."
}

if ($listener) {
    Write-Host "  [OK] Upload listener         : Port 8765"
}
else {
    Write-Warning "Upload listener is not currently detected."
}

if (Test-Path $InstalledSqlite) {
    Write-Host "  [OK] SQLite                  : Installed"
}
else {
    Write-Warning "SQLite executable is missing."
}

if (Test-Path $InstalledCollector) {
    Write-Host "  [OK] Collector               : Installed"
}
else {
    Write-Warning "Collector is missing."
}

if (Test-Path $InstalledMvp -PathType Container) {
    Write-Host "  [OK] ChromeUploadDetector-MVP : Installed"
}
else {
    Write-Warning "ChromeUploadDetector-MVP folder is missing."
}

Write-Host ""
Write-Host "PC identity is provided by the Wazuh agent."
Write-Host "History monitoring covers Windows user Chrome profiles."
Write-Host "Upload monitoring runs as a Windows service."
Write-Host ""
Write-Host "========================================="
Write-Host ""