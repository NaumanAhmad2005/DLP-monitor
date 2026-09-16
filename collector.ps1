$ErrorActionPreference = "Stop"

# ============================================================
# Chrome History Monitor
#
# Reads Chrome visits, archives them in SQLite and writes
# only new events to the Wazuh log.
#
# Important:
#   - Chrome DB is copied before reading.
#   - Archive DB is opened only once per collection cycle.
#   - All database inserts happen inside ONE transaction.
#   - Chrome visits.id is used as the persistent event ID.
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"

$ArchiveDb = Join-Path $BaseDir "chrome_history_archive.db"

$WazuhLog = Join-Path $BaseDir "chrome_history.log"

$CollectorLog = Join-Path $BaseDir "collector.log"


# ------------------------------------------------------------
# Create directory
# ------------------------------------------------------------

New-Item `
    -ItemType Directory `
    -Path $BaseDir `
    -Force |
    Out-Null


# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

function Write-CollectorLog {

    param(
        [string]$Message
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    "$Timestamp $Message" |
        Out-File `
            -FilePath $CollectorLog `
            -Append `
            -Encoding UTF8
}


# ------------------------------------------------------------
# Chrome profile
# ------------------------------------------------------------

$ChromeUserProfile = $env:CHROME_USER_PROFILE

# If CHROME_USER_PROFILE is not set, use the current Windows
# user's profile directory.
if ([string]::IsNullOrWhiteSpace($ChromeUserProfile)) {
    $ChromeUserProfile = $env:USERPROFILE
}

if ([string]::IsNullOrWhiteSpace($ChromeUserProfile)) {

    Write-CollectorLog `
        "ERROR Chrome user profile could not be determined"

    exit 1
}

Write-CollectorLog `
    "Using Chrome user profile: $ChromeUserProfile"


$ChromeHistory = Join-Path `
    $ChromeUserProfile `
    "AppData\Local\Google\Chrome\User Data\Default\History"


$TempDb = Join-Path `
    $env:TEMP `
    "chrome_history_copy_$($env:USERNAME).db"


# ------------------------------------------------------------
# SQLite availability
# ------------------------------------------------------------

$SqliteExe = "C:\Users\Nauman Ahmad\AppData\Local\Microsoft\WinGet\Links\sqlite3.exe"

if (-not (Test-Path $SqliteExe)) {

    Write-CollectorLog `
        "ERROR sqlite3.exe not found at $SqliteExe"

    exit 1
}

Write-CollectorLog `
    "Using SQLite: $SqliteExe"


# ------------------------------------------------------------
# Chrome history availability
# ------------------------------------------------------------

if (-not (Test-Path $ChromeHistory)) {

    Write-CollectorLog `
        "Chrome history database not found: $ChromeHistory"

    exit 0
}


# ------------------------------------------------------------
# Initialize archive database
# ------------------------------------------------------------

if (-not (Test-Path $ArchiveDb)) {

    Write-CollectorLog `
        "Creating archive database"

    $CreateDb = @"
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chrome_visit_id INTEGER NOT NULL UNIQUE,
    visit_time TEXT NOT NULL,
    username TEXT,
    url TEXT NOT NULL,
    title TEXT
);

CREATE INDEX IF NOT EXISTS idx_chrome_visit_id
ON history(chrome_visit_id);

CREATE INDEX IF NOT EXISTS idx_visit_time
ON history(visit_time);

CREATE INDEX IF NOT EXISTS idx_url
ON history(url);
"@

    try {

        $CreateDb |
            & $SqliteExe $ArchiveDb

        if ($LASTEXITCODE -ne 0) {

            throw `
                "SQLite database creation failed with exit code $LASTEXITCODE"
        }

    }
    catch {

        Write-CollectorLog `
            "ERROR failed to create archive database: $($_.Exception.Message)"

        exit 1
    }
}


# ------------------------------------------------------------
# Make sure WAL mode is enabled
# ------------------------------------------------------------

try {

    "PRAGMA busy_timeout=10000; PRAGMA journal_mode=WAL;" |
        & $SqliteExe $ArchiveDb |
        Out-Null

    if ($LASTEXITCODE -ne 0) {

        throw `
            "SQLite WAL initialization failed with exit code $LASTEXITCODE"
    }

}
catch {

    Write-CollectorLog `
        "ERROR unable to initialize archive database: $($_.Exception.Message)"

    exit 1
}


# ------------------------------------------------------------
# Read last processed Chrome visit ID
# ------------------------------------------------------------

$StateQuery = @"
SELECT COALESCE(MAX(chrome_visit_id), 0)
FROM history;
"@

$StateOutput = & $SqliteExe `
    $ArchiveDb `
    $StateQuery `
    2>$null

$LastProcessedId = 0

if ($StateOutput -match '^\d+$') {

    $LastProcessedId = [Int64]$StateOutput.Trim()
}


Write-CollectorLog `
    "Last processed Chrome visit ID: $LastProcessedId"


# ------------------------------------------------------------
# Copy Chrome database
# ------------------------------------------------------------

Remove-Item `
    $TempDb `
    -Force `
    -ErrorAction SilentlyContinue


try {

    Copy-Item `
        -Path $ChromeHistory `
        -Destination $TempDb `
        -Force

}
catch {

    Write-CollectorLog `
        "ERROR unable to copy Chrome History database: $($_.Exception.Message)"

    exit 1
}


# ------------------------------------------------------------
# Query new Chrome visits
# ------------------------------------------------------------

$Query = @"
SELECT
    visits.id,
    visits.visit_time,
    urls.url,
    urls.title
FROM visits
JOIN urls
    ON visits.url = urls.id
WHERE visits.id > $LastProcessedId
ORDER BY visits.id ASC;
"@


$Rows = @(
    & $SqliteExe `
        -separator "|" `
        $TempDb `
        $Query `
        2>$null
)


# ------------------------------------------------------------
# Nothing new
# ------------------------------------------------------------

if ($Rows.Count -eq 0) {

    Remove-Item `
        $TempDb `
        -Force `
        -ErrorAction SilentlyContinue

    Write-CollectorLog `
        "Collection completed. New events: 0. Last visit ID: $LastProcessedId"

    exit 0
}


# ------------------------------------------------------------
# Prepare events
# ------------------------------------------------------------

$Events = New-Object System.Collections.Generic.List[object]

$MaxVisitId = $LastProcessedId


foreach ($Row in $Rows) {

    if ([string]::IsNullOrWhiteSpace($Row)) {
        continue
    }


    # --------------------------------------------------------
    # Split SQLite output
    #
    # Expected:
    #
    # visit_id|visit_time|url|title
    # --------------------------------------------------------

    $Parts = $Row -split '\|', 4


    if ($Parts.Count -lt 3) {

        Write-CollectorLog `
            "WARNING malformed SQLite row skipped"

        continue
    }


    try {

        $ChromeVisitId = [Int64]$Parts[0]

        $ChromeTime = [Int64]$Parts[1]

    }
    catch {

        Write-CollectorLog `
            "WARNING invalid Chrome visit row skipped"

        continue
    }


    $Url = $Parts[2]

    $Title = ""

    if ($Parts.Count -eq 4) {

        $Title = $Parts[3]
    }


    # --------------------------------------------------------
    # Track highest visit ID
    # --------------------------------------------------------

    if ($ChromeVisitId -gt $MaxVisitId) {

        $MaxVisitId = $ChromeVisitId
    }


    # --------------------------------------------------------
    # Chrome timestamp conversion
    #
    # Chrome:
    # microseconds since 1601-01-01 UTC
    #
    # FILETIME:
    # 100-nanosecond intervals since 1601-01-01 UTC
    #
    # Therefore:
    # Chrome microseconds * 10 = FILETIME
    # --------------------------------------------------------

    try {

        $FileTime = [Int64]($ChromeTime * 10)

        $VisitDate = `
            [DateTime]::FromFileTimeUtc($FileTime).ToLocalTime()

        $VisitTime = `
            $VisitDate.ToString("yyyy-MM-dd HH:mm:ss")

    }
    catch {

        Write-CollectorLog `
            "WARNING unable to convert Chrome timestamp: $ChromeTime"

        continue
    }


    # --------------------------------------------------------
    # Remove line breaks
    # --------------------------------------------------------

    $SafeUrl = `
        $Url -replace '[\r\n]', ''

    $SafeTitle = `
        $Title -replace '[\r\n]', ''

    $SafeUser = `
        $env:USERNAME -replace '[\r\n]', ''


    # --------------------------------------------------------
    # Store event in memory
    # --------------------------------------------------------

    $Event = [PSCustomObject]@{

        ChromeVisitId = $ChromeVisitId

        VisitTime = $VisitTime

        Username = $SafeUser

        Url = $SafeUrl

        Title = $SafeTitle
    }


    $Events.Add($Event)
}


# ------------------------------------------------------------
# If no valid events remain
# ------------------------------------------------------------

if ($Events.Count -eq 0) {

    Remove-Item `
        $TempDb `
        -Force `
        -ErrorAction SilentlyContinue

    Write-CollectorLog `
        "Collection completed. New events: 0. Last visit ID: $LastProcessedId"

    exit 0
}


# ------------------------------------------------------------
# Build ONE SQLite transaction
#
# This is the important fix for:
#
#     database is locked
#
# Instead of starting sqlite3.exe for every INSERT,
# we send all INSERT statements in ONE SQLite session.
# ------------------------------------------------------------

$SqlCommands = New-Object System.Text.StringBuilder

[void]$SqlCommands.AppendLine("PRAGMA busy_timeout=10000;")

[void]$SqlCommands.AppendLine("PRAGMA journal_mode=WAL;")

[void]$SqlCommands.AppendLine("BEGIN IMMEDIATE TRANSACTION;")


foreach ($Event in $Events) {

    $DbUser = $Event.Username.Replace("'", "''")

    $DbUrl = $Event.Url.Replace("'", "''")

    $DbTitle = $Event.Title.Replace("'", "''")

    $DbVisitTime = $Event.VisitTime.Replace("'", "''")


    $Insert = @"
INSERT OR IGNORE INTO history
(
    chrome_visit_id,
    visit_time,
    username,
    url,
    title
)
VALUES
(
    $($Event.ChromeVisitId),
    '$DbVisitTime',
    '$DbUser',
    '$DbUrl',
    '$DbTitle'
);
"@


    [void]$SqlCommands.AppendLine($Insert)
}


[void]$SqlCommands.AppendLine("COMMIT;")


# ------------------------------------------------------------
# Execute ONE SQLite process
# ------------------------------------------------------------

try {

    $SqlCommands.ToString() |
        & $SqliteExe $ArchiveDb

    if ($LASTEXITCODE -ne 0) {

        throw `
            "SQLite transaction failed with exit code $LASTEXITCODE"
    }

}
catch {

    Write-CollectorLog `
        "ERROR archive transaction failed: $($_.Exception.Message)"

    Remove-Item `
        $TempDb `
        -Force `
        -ErrorAction SilentlyContinue

    exit 1
}


# ------------------------------------------------------------
# Write events to Wazuh log
#
# Only write after the SQLite transaction succeeds.
# ------------------------------------------------------------

foreach ($Event in $Events) {

    $WazuhEvent = `
        "CHROME_HISTORY user=$($Event.Username) visit_id=$($Event.ChromeVisitId) time=$($Event.VisitTime) url=$($Event.Url) title=$($Event.Title)"


    try {

        $WazuhEvent |
            Out-File `
                -FilePath $WazuhLog `
                -Append `
                -Encoding UTF8

    }
    catch {

        Write-CollectorLog `
            "ERROR failed writing Wazuh event for visit ID $($Event.ChromeVisitId): $($_.Exception.Message)"
    }
}


# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

Remove-Item `
    $TempDb `
    -Force `
    -ErrorAction SilentlyContinue


# ------------------------------------------------------------
# Final status
# ------------------------------------------------------------

Write-CollectorLog `
    "Collection completed. New events: $($Events.Count). Last visit ID: $MaxVisitId"