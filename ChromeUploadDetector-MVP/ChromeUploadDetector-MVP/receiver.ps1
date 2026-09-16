$BaseDir = "C:\ProgramData\ChromeHistoryMonitor"
$Port = 8765
$LogFile = Join-Path $BaseDir "chrome_upload.log"

New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()

Write-Host "Chrome Upload Detector listening on http://127.0.0.1:$Port/"
Write-Host "Log: $LogFile"

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()

        if ($ctx.Request.HttpMethod -ne "POST" -or
            $ctx.Request.Url.AbsolutePath -ne "/event") {
            $ctx.Response.StatusCode = 404
            $ctx.Response.Close()
            continue
        }

        $reader = [System.IO.StreamReader]::new($ctx.Request.InputStream)
        $body = $reader.ReadToEnd()
        $reader.Dispose()

        try {
            $obj = $body | ConvertFrom-Json
            $obj | Add-Member NoteProperty received_at `
                ([DateTime]::UtcNow.ToString("o")) -Force

            $line = "CHROME_UPLOAD " +
                (($obj | ConvertTo-Json -Compress) -replace "`r|`n","")

            Add-Content -Path $LogFile -Value $line -Encoding UTF8

            $response = '{"ok":true}'
            $ctx.Response.StatusCode = 200
        }
        catch {
            $response = '{"ok":false}'
            $ctx.Response.StatusCode = 400
        }

        $bytes = [Text.Encoding]::UTF8.GetBytes($response)
        $ctx.Response.ContentType = "application/json"
        $ctx.Response.OutputStream.Write($bytes,0,$bytes.Length)
        $ctx.Response.Close()
    }
    catch {
        Add-Content -Path $LogFile `
            -Value ("RECEIVER_ERROR " + $_.Exception.Message) `
            -Encoding UTF8
    }
}