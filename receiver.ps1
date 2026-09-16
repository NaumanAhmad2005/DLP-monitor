$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"
$Port = 8765

$LogFile = Join-Path $BaseDir "chrome_upload.log"
$ServiceLog = Join-Path $BaseDir "receiver.log"

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

function Write-ReceiverLog {
    param(
        [string]$Message
    )

    $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")

    try {
        Add-Content -Path $ServiceLog `
            -Value "$timestamp $Message" `
            -Encoding UTF8
    }
    catch {
        # Do not allow logging failure to kill the receiver.
    }
}

function Write-UploadLog {
    param(
        [string]$Line
    )

    $fs = $null
    $sw = $null

    try {
        $fs = [System.IO.FileStream]::new(
            $LogFile,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )

        $sw = [System.IO.StreamWriter]::new($fs)
        $sw.WriteLine($Line)
        $sw.Flush()
    }
    finally {
        if ($sw) {
            $sw.Dispose()
        }
        elseif ($fs) {
            $fs.Dispose()
        }
    }
}

$listener = [System.Net.HttpListener]::new()

try {

    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Start()

    Write-ReceiverLog "Chrome Upload Detector started."
    Write-ReceiverLog "Listening on http://127.0.0.1:$Port/"
    Write-ReceiverLog "Upload log: $LogFile"

    while ($listener.IsListening) {

        try {

            $ctx = $listener.GetContext()

            if ($ctx.Request.HttpMethod -ne "POST" -or
                $ctx.Request.Url.AbsolutePath -ne "/event") {

                $ctx.Response.StatusCode = 404
                $ctx.Response.Close()
                continue
            }

            $reader = [System.IO.StreamReader]::new(
                $ctx.Request.InputStream
            )

            $body = $reader.ReadToEnd()
            $reader.Dispose()

            try {

                $obj = $body | ConvertFrom-Json

                $obj | Add-Member NoteProperty received_at `
                    ([DateTime]::UtcNow.ToString("o")) -Force

                $json = $obj | ConvertTo-Json -Compress

                $line = "CHROME_UPLOAD $json"

                Write-UploadLog -Line $line

                $response = '{"ok":true}'
                $ctx.Response.StatusCode = 200

            }
            catch {

                Write-ReceiverLog "Invalid JSON received: $($_.Exception.Message)"

                $response = '{"ok":false}'
                $ctx.Response.StatusCode = 400
            }

            $bytes = [Text.Encoding]::UTF8.GetBytes($response)

            $ctx.Response.ContentType = "application/json"
            $ctx.Response.ContentLength64 = $bytes.Length

            $ctx.Response.OutputStream.Write(
                $bytes,
                0,
                $bytes.Length
            )

            $ctx.Response.Close()

        }
        catch {

            Write-ReceiverLog "Receiver loop error: $($_.Exception.Message)"
        }
    }
}
catch {

    Write-ReceiverLog "Receiver failed to start: $($_.Exception.Message)"
    exit 1
}
finally {

    if ($listener) {
        $listener.Stop()
        $listener.Close()
    }

    Write-ReceiverLog "Chrome Upload Detector stopped."
}