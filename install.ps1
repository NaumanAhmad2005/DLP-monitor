#requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"
$ServiceName = "Chrome Upload Detector"
$ServiceDisplayName = "Chrome Upload Detector"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$ServiceExe = Join-Path $ScriptRoot "ChromeUploadDetectorService.exe"
$Receiver = Join-Path $ScriptRoot "receiver.ps1"

Write-Host ""
Write-Host "========================================="
Write-Host " Chrome Upload Detector Installation"
Write-Host "========================================="
Write-Host ""

# ---------------------------------------------------------
# Verify required files
# ---------------------------------------------------------

Write-Host "[1/7] Checking installation files..."

if (-not (Test-Path $ServiceExe)) {
    throw "Missing: $ServiceExe"
}

if (-not (Test-Path $Receiver)) {
    throw "Missing: $Receiver"
}

Write-Host "      Required files found."

# ---------------------------------------------------------
# Create program directory
# ---------------------------------------------------------

Write-Host "[2/7] Creating program directory..."

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

Write-Host "      $BaseDir"

# ---------------------------------------------------------
# Copy runtime files
# ---------------------------------------------------------

Write-Host "[3/7] Copying detector files..."

Copy-Item $Receiver `
    (Join-Path $BaseDir "receiver.ps1") `
    -Force

Copy-Item $ServiceExe `
    (Join-Path $BaseDir "ChromeUploadDetectorService.exe") `
    -Force

# Copy collector if present
$CollectorSource = Join-Path $ScriptRoot "collector.ps1"

if (Test-Path $CollectorSource) {
    Copy-Item $CollectorSource `
        (Join-Path $BaseDir "collector.ps1") `
        -Force
}

Write-Host "      Files installed."

# ---------------------------------------------------------
# Remove old service if present
# ---------------------------------------------------------

Write-Host "[4/7] Removing previous service..."

$existing = Get-Service $ServiceName -ErrorAction SilentlyContinue

if ($existing) {

    if ($existing.Status -ne "Stopped") {
        Write-Host "      Stopping existing service..."
        Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 2

    & sc.exe delete $ServiceName | Out-Null

    Start-Sleep -Seconds 2
}

# ---------------------------------------------------------
# Create service
# ---------------------------------------------------------

Write-Host "[5/7] Creating Windows service..."

$InstalledExe = Join-Path $BaseDir "ChromeUploadDetectorService.exe"

& sc.exe create $ServiceName `
    binPath= "`"$InstalledExe`"" `
    start= auto `
    DisplayName= "`"$ServiceDisplayName`"" `
    obj= LocalSystem

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create Windows service."
}

# ---------------------------------------------------------
# Configure service recovery
# ---------------------------------------------------------

Write-Host "      Configuring automatic recovery..."

& sc.exe failure $ServiceName `
    reset= 86400 `
    actions= restart/5000/restart/5000/restart/10000 | Out-Null

& sc.exe failureflag $ServiceName 1 | Out-Null

# ---------------------------------------------------------
# Start service
# ---------------------------------------------------------

Write-Host "[6/7] Starting service..."

Start-Service $ServiceName

Start-Sleep -Seconds 3

$service = Get-Service $ServiceName

Write-Host ""
Write-Host "Service status: $($service.Status)"

if ($service.Status -ne "Running") {
    Write-Host ""
    Write-Host "ERROR: Service did not start."
    Write-Host ""
    Write-Host "Check:"
    Write-Host "  $BaseDir\service-host.log"
    Write-Host "  $BaseDir\receiver.log"
    exit 1
}

# ---------------------------------------------------------
# Verify listener
# ---------------------------------------------------------

Write-Host "[7/7] Checking upload detector listener..."

$listener = Get-NetTCPConnection `
    -LocalPort 8765 `
    -ErrorAction SilentlyContinue

if ($listener) {

    Write-Host ""
    Write-Host "========================================="
    Write-Host " Installation successful"
    Write-Host "========================================="
    Write-Host ""
    Write-Host "Service : $ServiceName"
    Write-Host "Status  : Running"
    Write-Host "Port    : 8765"
    Write-Host "Folder  : $BaseDir"
    Write-Host ""

}
else {

    Write-Warning "Service is running but port 8765 is not listening yet."
    Write-Warning "Check receiver.log."
}