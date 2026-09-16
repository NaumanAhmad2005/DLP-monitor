#requires -RunAsAdministrator

$ErrorActionPreference = "Continue"

$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"
$Collector = Join-Path $BaseDir "collector.ps1"
$RunnerLog = Join-Path $BaseDir "collector-runner.log"

$IntervalSeconds = 10

function Write-RunnerLog {
    param([string]$Message)

    try {
        Add-Content -Path $RunnerLog -Value (
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
        )
    }
    catch {}
}

Write-RunnerLog "Chrome History collector runner started. PID=$PID"

if (-not (Test-Path $Collector)) {
    Write-RunnerLog "ERROR: Collector not found: $Collector"
    exit 1
}

while ($true) {

    try {

        & powershell.exe `
            -NoProfile `
            -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $Collector

        $ExitCode = $LASTEXITCODE

        if ($ExitCode -ne 0) {
            Write-RunnerLog "Collector exited with code $ExitCode."
        }

    }
    catch {

        Write-RunnerLog "ERROR running collector: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $IntervalSeconds
}