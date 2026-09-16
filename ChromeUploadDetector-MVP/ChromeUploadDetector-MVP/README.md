# Chrome Upload Detector MVP

This is the actual browser-side upload detector for the Wazuh project.

It detects:
1. A file selected through an HTML file input.
2. A form containing that selected file being submitted.

It sends JSON to a localhost PowerShell receiver.

Log:
C:\ProgramData\ChromeHistoryMonitor\chrome_upload.log

Important:
Chrome does not expose the original full local path to normal web content. The detector records filename, size, MIME type, page URL/title and event type.

This is intentionally separate from Sysmon. Sysmon Event 3 can show Chrome network connections, but it cannot reliably tell us that a particular HTTPS connection was a file upload.
