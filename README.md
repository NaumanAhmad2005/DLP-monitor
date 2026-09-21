# DLP-Based Web Activity Monitor and Upload Detector

## Overview

This Windows-based DLP monitoring solution collects Chrome browsing history and detects Chrome file-upload and clipboard-paste activity. It processes telemetry locally and forwards structured events to Wazuh for centralized monitoring, custom rule-based detection, and alerts in the Wazuh Dashboard.

The project supports two deployment types:

- Complete installation for critical systems
- Upload-detection-only installation for normal systems

## Features

- Multi-user Windows and multi-profile Chrome history monitoring
- Per-user and per-profile state tracking
- SQLite-based Chrome history archival
- Chrome file-upload detection
- Chrome clipboard-paste detection
- Persistent Windows services
- Wazuh Agent, Manager, and Dashboard integration
- Custom Wazuh decoders and detection rules
- Optional Sysmon-based supporting telemetry

## Technology Stack

| Technology | Purpose |
|---|---|
| PowerShell | Collector, receiver, installers, and management scripts |
| SQLite | Local Chrome history archive |
| C# / Windows Services | Persistent monitoring service hosts |
| JavaScript / Chrome Extension | Chrome upload and paste detection |
| Wazuh Agent | Log collection and transport |
| Wazuh Manager | Decoding, rule processing, and alert generation |
| Wazuh Dashboard | Centralized monitoring and visualization |
| Sysmon | Supporting endpoint telemetry |
| TCP port 8765 | Extension-to-receiver communication |

## Architecture

### Complete Installation – Critical Systems

```text
Chrome History Database
        |
        v
collector.ps1
        |
        v
SQLite Archive
        |
        v
chrome_history.log
        |
        v
Wazuh Agent
        |
        v
Wazuh Manager
        |
        v
Wazuh Dashboard


Chrome Extension
        |
        v
ChromeUploadDetectorService
        |
        v
receiver.ps1
        |
        v
chrome_upload.log
        |
        v
Wazuh Agent
        |
        v
Wazuh Manager
        |
        v
Wazuh Dashboard
```

### Upload Detection Only – Normal Systems

```text
Chrome Extension
        |
        v
ChromeUploadDetectorService
        |
        v
receiver.ps1
        |
        v
chrome_upload.log
        |
        v
Wazuh Agent
        |
        v
Wazuh Manager
        |
        v
Wazuh Dashboard
```

The complete installation uses the ChromeHistoryMonitor service to start and supervise the history collector. The upload-only installation does not install or modify the history-monitoring components.

## Project Directory

```text
ChromeHistory&UploadMonitor│
├── install.ps1
├── install-upload-only.ps1
├── uninstall.ps1
├── collector.ps1
├── receiver.ps1
├── ChromeHistoryService.exe
├── ChromeUploadDetectorService.exe
├── sqlite3.exe
│
└── ChromeUploadDetector-MVP    ├── manifest.json
    ├── background.js
    └── content.js
```

## Runtime Directory

```text
C:\ProgramData\ChromeHistoryMonitor\
│
├── collector.ps1
├── receiver.ps1
├── ChromeHistoryService.exe
├── ChromeUploadDetectorService.exe
├── sqlite3.exe
├── ChromeUploadDetector-MVP\
├── chrome_history_archive.db
├── chrome_history.log
├── chrome_upload.log
├── collector.log
├── receiver.log
├── service.log
├── service-host.log
└── state_<user>_<profile>.txt
```

## Multi-User and Multi-Profile Monitoring

The history collector discovers Windows user profiles and Chrome profiles independently. Each user/profile combination has its own state file:

```text
state_<user>_<profile>.txt
```

This prevents activity from different users or Chrome profiles from being processed as the same session.

The collector runs through the ChromeHistoryMonitor Windows service under SYSTEM context and continuously checks for new Chrome history records.

## Event Formats

### Chrome History

```text
CHROME_HISTORY user=<WindowsUser> profile=<ChromeProfile> visit_id=<ID> time=<TIME> url=<URL> title=<TITLE>
```

### Chrome Upload Activity

```text
UPLOAD_ACTIVITY {"type":"file_dropped", ...}
```

Possible upload event types include:

- file_selected
- file_dropped
- upload_submit

### Chrome Paste Activity

```text
CHROME_PASTE {"type":"chrome_paste", ...}
```

Paste events may contain page information, input details, paste type, clipboard types, text size, timestamp, and tab information. The extension records metadata and does not transmit the actual clipboard text or image content.

## Wazuh Rules

```text
100200  Chrome browsing history
100201  Collector PowerShell suppression
100202  Chrome upload activity
100210  Chrome clipboard paste activity
```

Custom decoders identify the CHROME_PASTE and UPLOAD_ACTIVITY event prefixes before the corresponding rules process them.

## Monitor Installation

### 1. Complete Installation – Critical Systems

Purpose: Installs Chrome history monitoring and Chrome upload/paste detection.

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\install.ps1
```

### 2. Upload Detection Only – Normal Systems

Purpose: Installs only Chrome upload and paste detection.

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\install-upload-only.ps1
```

Run both scripts from an elevated PowerShell window.

## Monitoring Model

The ChromeHistoryMonitor service starts and supervises collector.ps1. The collector archives new Chrome history records in SQLite and writes events to chrome_history.log.

The Chrome Upload Detector service runs receiver.ps1. The Chrome extension sends upload and paste metadata to the receiver through TCP port 8765. The receiver writes events to chrome_upload.log.

The Wazuh Agent monitors both logs and forwards them to the Wazuh Manager. Custom decoders and rules generate alerts that are displayed in the Wazuh Dashboard.

The current architecture does not use Windows Task Scheduler for history monitoring.

## Troubleshooting

Check the history service:

```powershell
Get-Service "ChromeHistoryMonitor"
```

Check the upload service:

```powershell
Get-Service "Chrome Upload Detector"
```

Check upload and paste logs:

```powershell
Get-Content "C:\ProgramData\ChromeHistoryMonitor\chrome_upload.log" -Tail 20
```

Check history logs:

```powershell
Get-Content "C:\ProgramData\ChromeHistoryMonitor\chrome_history.log" -Tail 20
```

## Security and Privacy

- Collect telemetry only with proper authorization.
- Restrict access to the monitoring directory and logs.
- Treat URLs, page titles, and upload metadata as sensitive.
- Keep Wazuh suppression rules narrow and specific.
- Protect logs and databases from unauthorized modification.
- Use approved enterprise Chrome management for extension deployment.
- Avoid collecting actual clipboard contents unless explicitly required and authorized.

## Future Development

- Structured Wazuh JSON decoding
- File hashes and richer upload metadata
- Centralized extension deployment
- Improved profile discovery
- Sysmon correlation
- Additional Wazuh rules and dashboard visualizations
- Correlation between browsing and upload activity
