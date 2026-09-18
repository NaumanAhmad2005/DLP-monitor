$ErrorActionPreference = "Stop"

# ============================================================
# Chrome History Monitor - Multi-user / SYSTEM version
#
# Runs from the Windows Scheduled Task as SYSTEM.
# Enumerates local Windows profiles and Chrome profiles, so the
# installation is not tied to Administrator or any installer user.
#
# Writes only new visits to:
#   C:\ProgramData\ChromeHistoryMonitor\chrome_history.log
#
# The archive key is (username, chrome_profile, chrome_visit_id).
# ============================================================

$BaseDir       = "C:\ProgramData\ChromeHistoryMonitor"
$ArchiveDb     = Join-Path $BaseDir "chrome_history_archive.db"
$WazuhLog      = Join-Path $BaseDir "chrome_history.log"
$CollectorLog  = Join-Path $BaseDir "collector.log"
$SQLite        = Join-Path $BaseDir "sqlite3.exe"

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

function Write-CollectorLog {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp $Message" | Out-File -FilePath $CollectorLog -Append -Encoding UTF8
}

if (-not (Test-Path $SQLite)) {
    Write-CollectorLog "ERROR sqlite3.exe not found at $SQLite"
    exit 1
}

# ------------------------------------------------------------
# Initialize archive
# ------------------------------------------------------------

if (-not (Test-Path $ArchiveDb)) {
    $CreateDb = @"
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    chrome_profile TEXT NOT NULL,
    chrome_visit_id INTEGER NOT NULL,
    visit_time TEXT NOT NULL,
    url TEXT NOT NULL,
    title TEXT,
    UNIQUE(username, chrome_profile, chrome_visit_id)
);

CREATE INDEX IF NOT EXISTS idx_history_user
ON history(username, chrome_profile);

CREATE INDEX IF NOT EXISTS idx_history_time
ON history(visit_time);

CREATE INDEX IF NOT EXISTS idx_history_url
ON history(url);
"@

    try {
        $CreateDb | & $SQLite $ArchiveDb
        if ($LASTEXITCODE -ne 0) {
            throw "SQLite database creation failed with exit code $LASTEXITCODE"
        }
    }
    catch {
        Write-CollectorLog "ERROR failed to create archive database: $($_.Exception.Message)"
        exit 1
    }
}
else {
    # Upgrade an older archive that used only chrome_visit_id.
    $SchemaCheck = & $SQLite $ArchiveDb "SELECT name FROM sqlite_master WHERE type='table' AND name='history';" 2>$null
    if (-not $SchemaCheck) {
        Write-CollectorLog "ERROR archive database has no history table"
        exit 1
    }

    # Read the actual column names.
    # Do NOT use -notmatch directly on the full PRAGMA output here:
    # that can evaluate true because unrelated columns do not match.
    $ColumnNames = @(
        & $SQLite $ArchiveDb "SELECT name FROM pragma_table_info('history');" 2>$null |
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

    if ($MissingColumns.Count -gt 0) {
        Write-CollectorLog "ERROR existing archive uses an incompatible/old schema. Missing columns: $($MissingColumns -join ', '). Backup/delete chrome_history_archive.db before first multi-user run."
        exit 1
    }
}

# ------------------------------------------------------------
# Collection function
#
# The Scheduled Task starts this collector once as SYSTEM.
# The collector then stays alive and polls every 10 seconds.
# This avoids launching a new PowerShell process every 10 seconds.
# ------------------------------------------------------------

function Invoke-ChromeHistoryCollection {
    # ------------------------------------------------------------
    # Find all local Windows profiles
    # ------------------------------------------------------------

    $Profiles = Get-CimInstance Win32_UserProfile |
        Where-Object {
            -not $_.Special -and
            $_.LocalPath -and
            (Test-Path $_.LocalPath)
        } |
        Select-Object LocalPath,SID

    if (-not $Profiles) {
        Write-CollectorLog "Collection completed. No local user profiles found."
        exit 0
    }

    $TotalEvents = 0
    $TotalProfiles = 0

    foreach ($Profile in $Profiles) {

        $UserProfile = $Profile.LocalPath
        $Username = Split-Path $UserProfile -Leaf

        # Search all Chrome profiles: Default, Profile 1, Profile 2, etc.
        $ChromeUserData = Join-Path $UserProfile "AppData\Local\Google\Chrome\User Data"

        if (-not (Test-Path $ChromeUserData)) {
            continue
        }

        $ChromeProfiles = Get-ChildItem $ChromeUserData -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                Test-Path (Join-Path $_.FullName "History")
            }

        foreach ($ChromeProfile in $ChromeProfiles) {

            $ProfileName = $ChromeProfile.Name
            $ChromeHistory = Join-Path $ChromeProfile.FullName "History"

            $TotalProfiles++

            # Per-user/per-Chrome-profile state.
            $SafeUser = $Username -replace '[^\w.-]', '_'
            $SafeProfile = $ProfileName -replace '[^\w.-]', '_'
            $StateFile = Join-Path $BaseDir "state_${SafeUser}_${SafeProfile}.txt"

            $LastProcessedId = 0

            if (Test-Path $StateFile) {
                $StateText = (Get-Content $StateFile -Raw -ErrorAction SilentlyContinue).Trim()
                if ($StateText -match '^\d+$') {
                    $LastProcessedId = [Int64]$StateText
                }
            }

            $TempDb = Join-Path $env:TEMP "chrome_history_${SafeUser}_${SafeProfile}_$PID.db"
            Remove-Item $TempDb -Force -ErrorAction SilentlyContinue

            try {
                Copy-Item -Path $ChromeHistory -Destination $TempDb -Force -ErrorAction Stop
            }
            catch {
                Write-CollectorLog "WARNING unable to copy History for $Username/$ProfileName : $($_.Exception.Message)"
                continue
            }

            $Query = @"
    SELECT
        visits.id,
        visits.visit_time,
        urls.url,
        urls.title
    FROM visits
    JOIN urls ON visits.url = urls.id
    WHERE visits.id > $LastProcessedId
    ORDER BY visits.id ASC;
"@

            $Rows = @(
                & $SQLite -separator "|" $TempDb $Query 2>$null
            )

            if ($LASTEXITCODE -ne 0) {
                Write-CollectorLog "WARNING SQLite query failed for $Username/$ProfileName"
                Remove-Item $TempDb -Force -ErrorAction SilentlyContinue
                continue
            }

            $Events = New-Object System.Collections.Generic.List[object]
            $MaxVisitId = $LastProcessedId

            foreach ($Row in $Rows) {

                if ([string]::IsNullOrWhiteSpace($Row)) { continue }

                $Parts = $Row -split '\|', 4
                if ($Parts.Count -lt 3) { continue }

                try {
                    $ChromeVisitId = [Int64]$Parts[0]
                    $ChromeTime = [Int64]$Parts[1]
                }
                catch {
                    continue
                }

                $Url = $Parts[2]
                $Title = if ($Parts.Count -eq 4) { $Parts[3] } else { "" }

                if ($ChromeVisitId -gt $MaxVisitId) {
                    $MaxVisitId = $ChromeVisitId
                }

                try {
                    $FileTime = [Int64]($ChromeTime * 10)
                    $VisitDate = [DateTime]::FromFileTimeUtc($FileTime).ToLocalTime()
                    $VisitTime = $VisitDate.ToString("yyyy-MM-dd HH:mm:ss")
                }
                catch {
                    continue
                }

                $SafeUrl = $Url -replace '[\r\n]', ''
                $SafeTitle = $Title -replace '[\r\n]', ''

                $Events.Add([PSCustomObject]@{
                    ChromeVisitId = $ChromeVisitId
                    VisitTime     = $VisitTime
                    Username      = ($Username -replace '[\r\n]', '')
                    ChromeProfile = ($ProfileName -replace '[\r\n]', '')
                    Url           = $SafeUrl
                    Title         = $SafeTitle
                })
            }

            if ($Events.Count -eq 0) {
                Remove-Item $TempDb -Force -ErrorAction SilentlyContinue
                continue
            }

            # One SQLite transaction for this profile.
            $Sql = New-Object System.Text.StringBuilder
            [void]$Sql.AppendLine("PRAGMA busy_timeout=10000;")
            [void]$Sql.AppendLine("PRAGMA journal_mode=WAL;")
            [void]$Sql.AppendLine("BEGIN IMMEDIATE TRANSACTION;")

            foreach ($Event in $Events) {

                $DbUser = $Event.Username.Replace("'", "''")
                $DbProfile = $Event.ChromeProfile.Replace("'", "''")
                $DbTime = $Event.VisitTime.Replace("'", "''")
                $DbUrl = $Event.Url.Replace("'", "''")
                $DbTitle = $Event.Title.Replace("'", "''")

                [void]$Sql.AppendLine(@"
    INSERT OR IGNORE INTO history
    (username, chrome_profile, chrome_visit_id, visit_time, url, title)
    VALUES
    ('$DbUser', '$DbProfile', $($Event.ChromeVisitId), '$DbTime', '$DbUrl', '$DbTitle');
"@)
            }

            [void]$Sql.AppendLine("COMMIT;")

            try {
                $Sql.ToString() | & $SQLite $ArchiveDb
                if ($LASTEXITCODE -ne 0) {
                    throw "SQLite transaction failed with exit code $LASTEXITCODE"
                }
            }
            catch {
                Write-CollectorLog "ERROR archive transaction failed for $Username/$ProfileName : $($_.Exception.Message)"
                Remove-Item $TempDb -Force -ErrorAction SilentlyContinue
                continue
            }

            # Only after successful archive commit, emit Wazuh events.
            foreach ($Event in $Events) {
                $WazuhEvent = "CHROME_HISTORY user=$($Event.Username) profile=$($Event.ChromeProfile) visit_id=$($Event.ChromeVisitId) time=$($Event.VisitTime) url=$($Event.Url) title=$($Event.Title)"
                try {
                    $WazuhEvent | Out-File -FilePath $WazuhLog -Append -Encoding UTF8
                }
                catch {
                    Write-CollectorLog "ERROR failed writing Wazuh event for $Username/$ProfileName/$($Event.ChromeVisitId): $($_.Exception.Message)"
                }
            }

            # Persist state separately for each user/profile.
            $MaxVisitId.ToString() | Set-Content -Path $StateFile -Encoding ASCII

            $TotalEvents += $Events.Count

            Remove-Item $TempDb -Force -ErrorAction SilentlyContinue
        }
    }

    Write-CollectorLog "Collection completed. Profiles checked: $TotalProfiles. New events: $TotalEvents"
}

# ------------------------------------------------------------
# Continuous monitoring loop
# ------------------------------------------------------------

$CollectionIntervalSeconds = 5

Write-CollectorLog "Chrome History Monitor started. Polling interval: $CollectionIntervalSeconds seconds."

while ($true) {

    try {
        Invoke-ChromeHistoryCollection
    }
    catch {
        Write-CollectorLog "ERROR collection cycle failed: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $CollectionIntervalSeconds
}
