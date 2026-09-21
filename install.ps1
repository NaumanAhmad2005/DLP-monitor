#requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# =========================================================
# CONFIGURATION
# =========================================================

$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"

# Chrome Upload Detector
$UploadServiceName        = "Chrome Upload Detector"
$UploadServiceDisplayName = "Chrome Upload Detector"

# Chrome History Monitor
$HistoryServiceName        = "ChromeHistoryMonitor"
$HistoryServiceDisplayName = "Chrome History Monitor"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------
# Installer source files
# ---------------------------------------------------------

$UploadServiceExe = Join-Path $ScriptRoot "ChromeUploadDetectorService.exe"
$HistoryServiceExe = Join-Path $ScriptRoot "ChromeHistoryService.exe"
$Receiver         = Join-Path $ScriptRoot "receiver.ps1"
$CollectorSource  = Join-Path $ScriptRoot "collector.ps1"
$MvpSource        = Join-Path $ScriptRoot "ChromeUploadDetector-MVP"

# Try the normal tools location first
$SqliteSource = Join-Path $ScriptRoot "tools\sqlite3.exe"

if (-not (Test-Path $SqliteSource)) {
    $SqliteSource = Join-Path $ScriptRoot "sqlite3.exe"
}

# ---------------------------------------------------------
# Installed files
# ---------------------------------------------------------

$InstalledUploadExe         = Join-Path $BaseDir "ChromeUploadDetectorService.exe"
$InstalledHistoryServiceExe = Join-Path $BaseDir "ChromeHistoryService.exe"
$InstalledReceiver          = Join-Path $BaseDir "receiver.ps1"
$InstalledCollector         = Join-Path $BaseDir "collector.ps1"
$InstalledSqlite            = Join-Path $BaseDir "sqlite3.exe"
$InstalledMvp               = Join-Path $BaseDir "ChromeUploadDetector-MVP"

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

if (-not (Test-Path $UploadServiceExe)) {
    throw "Missing: $UploadServiceExe"
}

if (-not (Test-Path $HistoryServiceExe)) {
    throw "Missing: $HistoryServiceExe"
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
    throw "Missing sqlite3.exe. Expected $ScriptRoot\tools\sqlite3.exe or $ScriptRoot\sqlite3.exe"
}

Write-Host "      Required files found."
Write-Host "      History service: $HistoryServiceExe"
Write-Host "      Upload service : $UploadServiceExe"

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
# Stop/remove old Scheduled Task if it exists
# ---------------------------------------------------------

$HistoryTaskName = "Chrome History Monitor"

$existingTask = Get-ScheduledTask `
    -TaskName $HistoryTaskName `
    -ErrorAction SilentlyContinue

if ($existingTask) {

    Write-Host "      Found old history Scheduled Task."

    Stop-ScheduledTask `
        -TaskName $HistoryTaskName `
        -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2

    Unregister-ScheduledTask `
        -TaskName $HistoryTaskName `
        -Confirm:$false `
        -ErrorAction SilentlyContinue

    Write-Host "      Old history Scheduled Task removed."
}

# ---------------------------------------------------------
# Stop history Windows Service if it already exists
# ---------------------------------------------------------

$existingHistoryService = Get-Service `
    -Name $HistoryServiceName `
    -ErrorAction SilentlyContinue

if ($existingHistoryService) {

    Write-Host "      Found existing history service."

    if ($existingHistoryService.Status -ne "Stopped") {
        Write-Host "      Stopping history service..."

        Stop-Service `
            -Name $HistoryServiceName `
            -Force `
            -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 2
    }
}

# ---------------------------------------------------------
# Stop upload service if it already exists
# ---------------------------------------------------------

$existingUploadService = Get-Service `
    -Name $UploadServiceName `
    -ErrorAction SilentlyContinue

if ($existingUploadService) {

    Write-Host "      Found existing upload detector service."

    if ($existingUploadService.Status -ne "Stopped") {
        Write-Host "      Stopping upload detector service..."

        Stop-Service `
            -Name $UploadServiceName `
            -Force `
            -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 2
    }
}

# ---------------------------------------------------------
# Stop any remaining collector processes
# ---------------------------------------------------------

Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.CommandLine -like "*collector.ps1*"
    } |
    ForEach-Object {

        Write-Host "      Stopping collector PID $($_.ProcessId)..."

        Stop-Process `
            -Id $_.ProcessId `
            -Force `
            -ErrorAction SilentlyContinue
    }

Start-Sleep -Seconds 2

# ---------------------------------------------------------
# Stop remaining service executable processes
# ---------------------------------------------------------

Get-Process -Name "ChromeHistoryService" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Get-Process -Name "ChromeUploadDetectorService" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 2

Write-Host "      Previous components stopped."

# =========================================================
# [4] REMOVE OLD SERVICE REGISTRATIONS
# =========================================================

Write-Host "[4/9] Removing previous service registrations..."

# ---------------------------------------------------------
# Remove history service
# ---------------------------------------------------------

$existingHistoryService = Get-Service `
    -Name $HistoryServiceName `
    -ErrorAction SilentlyContinue

if ($existingHistoryService) {

    & sc.exe delete $HistoryServiceName | Out-Null

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500

        $serviceCheck = Get-Service `
            -Name $HistoryServiceName `
            -ErrorAction SilentlyContinue

        if (-not $serviceCheck) {
            break
        }
    }

    Write-Host "      Previous history service removed."
}
else {
    Write-Host "      No previous history service found."
}

# ---------------------------------------------------------
# Remove upload service
# ---------------------------------------------------------

$existingUploadService = Get-Service `
    -Name $UploadServiceName `
    -ErrorAction SilentlyContinue

if ($existingUploadService) {

    & sc.exe delete $UploadServiceName | Out-Null

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500

        $serviceCheck = Get-Service `
            -Name $UploadServiceName `
            -ErrorAction SilentlyContinue

        if (-not $serviceCheck) {
            break
        }
    }

    Write-Host "      Previous upload service removed."
}
else {
    Write-Host "      No previous upload service found."
}

# ---------------------------------------------------------
# Verify service executables are no longer locked
# ---------------------------------------------------------

foreach ($Executable in @(
    $InstalledHistoryServiceExe,
    $InstalledUploadExe
)) {

    if (Test-Path $Executable) {

        $lockReleased = $false

        for ($i = 0; $i -lt 10; $i++) {

            try {

                $stream = [System.IO.File]::Open(
                    $Executable,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::ReadWrite,
                    [System.IO.FileShare]::None
                )

                $stream.Close()
                $stream.Dispose()

                $lockReleased = $true
                break
            }
            catch {
                Start-Sleep -Milliseconds 500
            }
        }

        if (-not $lockReleased) {
            throw "$Executable is still in use. Installation cannot safely replace it."
        }
    }
}

Write-Host "      Service executable locks released."

# =========================================================
# [5] INSTALL RUNTIME FILES
# =========================================================

Write-Host "[5/9] Installing runtime files..."

Copy-Item `
    $HistoryServiceExe `
    $InstalledHistoryServiceExe `
    -Force

Copy-Item `
    $UploadServiceExe `
    $InstalledUploadExe `
    -Force

Copy-Item `
    $CollectorSource `
    $InstalledCollector `
    -Force

Copy-Item `
    $Receiver `
    $InstalledReceiver `
    -Force

Copy-Item `
    $SqliteSource `
    $InstalledSqlite `
    -Force

# Copy extension/configuration package
if (Test-Path $InstalledMvp) {
    Remove-Item `
        $InstalledMvp `
        -Recurse `
        -Force
}

Copy-Item `
    $MvpSource `
    $InstalledMvp `
    -Recurse `
    -Force

Write-Host "      History service installed."
Write-Host "      Upload service installed."
Write-Host "      Collector installed."
Write-Host "      Receiver installed."
Write-Host "      SQLite installed."
Write-Host "      ChromeUploadDetector-MVP installed."

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

    if (-not (Test-Path $InstalledSqlite)) {
        throw "Installed sqlite3.exe was not found."
    }

    $ColumnNames = @(
        & $InstalledSqlite `
            $ArchiveDb `
            "SELECT name FROM pragma_table_info('history');" `
            2>$null |
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
        Write-Host "      Old archive detected."
        Write-Host "      Backing it up before creating the new archive."
        Write-Host "      Backup: $BackupDb"

        Move-Item `
            $ArchiveDb `
            $BackupDb `
            -Force

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
# [7] CREATE WINDOWS SERVICES
# =========================================================

Write-Host "[7/9] Configuring Windows services..."

# ---------------------------------------------------------
# Chrome History Monitor
# ---------------------------------------------------------

& sc.exe create $HistoryServiceName `
    binPath= "`"$InstalledHistoryServiceExe`"" `
    start= auto `
    DisplayName= "`"$HistoryServiceDisplayName`"" `
    obj= LocalSystem

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create Chrome History Monitor service."
}

& sc.exe failure $HistoryServiceName `
    reset= 86400 `
    actions= restart/5000/restart/5000/restart/10000 |
    Out-Null

& sc.exe failureflag $HistoryServiceName 1 |
    Out-Null

Write-Host "      Chrome History service created."
Write-Host "      Startup: Automatic"
Write-Host "      Account: LocalSystem"

# ---------------------------------------------------------
# Chrome Upload Detector
# ---------------------------------------------------------

& sc.exe create $UploadServiceName `
    binPath= "`"$InstalledUploadExe`"" `
    start= auto `
    DisplayName= "`"$UploadServiceDisplayName`"" `
    obj= LocalSystem

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create Chrome Upload Detector service."
}

& sc.exe failure $UploadServiceName `
    reset= 86400 `
    actions= restart/5000/restart/5000/restart/10000 |
    Out-Null

& sc.exe failureflag $UploadServiceName 1 |
    Out-Null

Write-Host "      Chrome Upload Detector service created."
Write-Host "      Startup: Automatic"
Write-Host "      Account: LocalSystem"

# =========================================================
# [8] START COMPONENTS
# =========================================================

Write-Host "[8/9] Starting monitoring components..."

# ---------------------------------------------------------
# Start Chrome History Monitor
# ---------------------------------------------------------

Start-Service `
    -Name $HistoryServiceName

Start-Sleep -Seconds 3

$HistoryService = Get-Service `
    -Name $HistoryServiceName `
    -ErrorAction Stop

if ($HistoryService.Status -ne "Running") {

    Write-Host ""
    Write-Host "ERROR: Chrome History Monitor service failed to start."
    Write-Host ""
    Write-Host "Check:"
    Write-Host "  $BaseDir\service.log"
    Write-Host "  $BaseDir\collector.log"

    throw "Chrome History Monitor service is not running."
}

Write-Host "      Chrome History Monitor: Running"

# ---------------------------------------------------------
# Start Chrome Upload Detector
# ---------------------------------------------------------

Start-Service `
    -Name $UploadServiceName

Start-Sleep -Seconds 3

$UploadService = Get-Service `
    -Name $UploadServiceName `
    -ErrorAction Stop

if ($UploadService.Status -ne "Running") {

    Write-Host ""
    Write-Host "ERROR: Chrome Upload Detector service failed to start."
    Write-Host ""
    Write-Host "Check:"
    Write-Host "  $BaseDir\service-host.log"
    Write-Host "  $BaseDir\receiver.log"

    throw "Chrome Upload Detector service is not running."
}

Write-Host "      Chrome Upload Detector: Running"

# =========================================================
# [9] FINAL VERIFICATION
# =========================================================

Write-Host "[9/9] Verifying installation..."

$HistoryService = Get-Service `
    -Name $HistoryServiceName `
    -ErrorAction SilentlyContinue

$UploadService = Get-Service `
    -Name $UploadServiceName `
    -ErrorAction SilentlyContinue

$listener = Get-NetTCPConnection `
    -LocalPort 8765 `
    -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================="
Write-Host " Installation complete"
Write-Host "========================================="
Write-Host ""

if ($HistoryService -and $HistoryService.Status -eq "Running") {
    Write-Host "  [OK] Chrome history service   : Running"
}
else {
    throw "Chrome History Monitor service verification failed."
}

if ($UploadService -and $UploadService.Status -eq "Running") {
    Write-Host "  [OK] Upload detector service  : Running"
}
else {
    throw "Chrome Upload Detector service verification failed."
}

if ($listener) {
    Write-Host "  [OK] Upload listener          : Port 8765"
}
else {
    Write-Warning "Upload listener is not currently detected."
}

if (Test-Path $InstalledHistoryServiceExe) {
    Write-Host "  [OK] History service EXE      : Installed"
}
else {
    throw "ChromeHistoryService.exe is missing."
}

if (Test-Path $InstalledUploadExe) {
    Write-Host "  [OK] Upload service EXE       : Installed"
}
else {
    throw "ChromeUploadDetectorService.exe is missing."
}

if (Test-Path $InstalledSqlite) {
    Write-Host "  [OK] SQLite                   : Installed"
}
else {
    throw "SQLite executable is missing."
}

if (Test-Path $InstalledCollector) {
    Write-Host "  [OK] Collector                : Installed"
}
else {
    throw "Collector is missing."
}

if ((Test-Path $InstalledMvp -PathType Container) -and
    (Get-ChildItem $InstalledMvp -Force -ErrorAction SilentlyContinue)) {

    Write-Host "  [OK] ChromeUploadDetector-MVP : Installed"
}
else {
    throw "ChromeUploadDetector-MVP folder verification failed."
}

# ---------------------------------------------------------
# Verify collector process
# ---------------------------------------------------------

Start-Sleep -Seconds 2

$CollectorProcesses = @(
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.CommandLine -like "*collector.ps1*"
    }
)

if ($CollectorProcesses.Count -eq 1) {
    Write-Host "  [OK] Collector process        : 1 running instance"
}
elseif ($CollectorProcesses.Count -eq 0) {
    Write-Warning "No collector.ps1 process detected yet. Check service.log and collector.log."
}
else {
    Write-Warning "Multiple collector.ps1 processes detected: $($CollectorProcesses.Count)"
    $CollectorProcesses |
        Select-Object ProcessId,ParentProcessId,CommandLine |
        Format-Table -AutoSize
}

Write-Host ""
Write-Host "PC identity is provided by the Wazuh agent."
Write-Host "History monitoring covers Windows user Chrome profiles."
Write-Host "History collector polling is controlled by collector.ps1."
Write-Host "Upload monitoring runs as a Windows service."
Write-Host ""
Write-Host "Installed directory:"
Write-Host "  $BaseDir"
Write-Host ""
Write-Host "========================================="
Write-Host ""
