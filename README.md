# Chrome History & Upload Monitor for Wazuh

## Overview

Windows endpoint telemetry project integrating Chrome browsing-history and upload-activity signals with Wazuh.

## Features

- Multi-user Chrome profile monitoring
- Chrome browsing history collection
- SQLite archival and per-user/profile state
- Chrome upload activity detection
- Windows background service
- Hidden SYSTEM history task
- Wazuh Agent/Manager integration
- Custom Wazuh rules

## Technology Stack

| Technology | Role |
|---|---|
| PowerShell | Collector, receiver, installer |
| SQLite | Archive/state |
| C# / Windows Service | Upload detector host |
| JavaScript / Chrome Extension | Browser upload activity |
| Windows Task Scheduler | History collector execution |
| Windows Services | Persistent upload detection |
| Wazuh Agent | Telemetry transport and endpoint identity |
| Wazuh Manager | Rules/alerts |
| Wazuh Dashboard | SOC visualization |
| Sysmon | Supporting endpoint telemetry |
| TCP 8765 | Extension-to-receiver communication |

## Architecture

```text
Chrome
 ├── History DB → collector.ps1 → SQLite → chrome_history.log ─┐
 └── Upload Extension → Windows Service → receiver.ps1 → chrome_upload.log
                                                               │
                                                               ▼
                                                          Wazuh Agent
                                                               │
                                                               ▼
                                                         Wazuh Manager
                                                               │
                                                         Custom Rules
                                                               │
                                                               ▼
                                                          Dashboard
```

## Directory

```text
C:\ProgramData\ChromeHistoryMonitor\
├── collector.ps1
├── receiver.ps1
├── ChromeUploadDetectorService.exe
├── sqlite3.exe
├── ChromeUploadDetector-MVP\
├── chrome_history_archive.db
├── chrome_history.log
├── chrome_upload.log
├── collector.log
├── receiver.log
├── service-host.log
└── state_<user>_<profile>.txt
```

## Event Formats

```text
CHROME_HISTORY user=<WindowsUser> profile=<ChromeProfile> visit_id=<ID> time=<TIME> url=<URL> title=<TITLE>
UPLOAD_ACTIVITY ...
```

## Wazuh Rules

```text
100200  Chrome browsing history
100201  Narrow collector PowerShell suppression
100202  Chrome upload activity
```

## Installation

See the endpoint and SOC installation documents.

The Chrome MVP can currently be loaded unpacked from:

```text
C:\ProgramData\ChromeHistoryMonitor\ChromeUploadDetector-MVP\ChromeUploadDetector-MVP
```

## Monitoring Model

The collector runs continuously and polls Chrome history at a 10-second target interval. The scheduled task launches it in SYSTEM context for multi-user coverage. Upload monitoring runs as an Automatic LocalSystem Windows service.

## Security & Privacy

- Browsing history is sensitive telemetry; collect only with appropriate authorization.
- Restrict access to ProgramData logs/databases.
- URLs may contain sensitive query parameters.
- Keep Wazuh suppressions narrow.
- Correlate upload telemetry with other endpoint evidence when needed.
- Use approved enterprise Chrome management for production extension deployment.

## Future Development

- Structured upload decoding
- File hashes and richer metadata
- Centralized extension deployment
- Sysmon correlation
- Additional Wazuh dashboards

## License

Add the organization's approved license before publishing the repository.
