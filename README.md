# DLP Based Web Activity Monitor and Upload Detector 

## Overview

It is a Windows-based DLP monitoring solution designed to monitor **multiple Windows users and Chrome profiles** on an endpoint. It collects Chrome browsing history and detects file upload activity through a Chrome Extension, processes the telemetry locally, and forwards structured events to **Wazuh** for centralized monitoring, custom rule-based detection, and security alerting through the Wazuh Dashboard.

The system maintains **separate state for each Windows user and Chrome profile**, allowing browsing activity from multiple users on the same Windows machine to be collected without mixing their records.

## Features

* Multi-user Windows endpoint monitoring
* Multi-profile Chrome monitoring
* Chrome browsing history collection
* Per-user and per-profile state tracking
* SQLite-based local archival
* Chrome upload activity detection
* Windows background service for persistent upload monitoring
* SYSTEM-based scheduled task for history collection
* Wazuh Agent/Manager integration
* Custom Wazuh detection and suppression rules
* Centralized security alerts and visualization through Wazuh Dashboard

## Technology Stack

| Technology                    | Role                                                                 |
| ----------------------------- | -------------------------------------------------------------------- |
| PowerShell                    | History collector, upload receiver, installer and management scripts |
| SQLite                        | Local history archive and state management                           |
| C# / Windows Service          | Persistent upload detector host                                      |
| JavaScript / Chrome Extension | Browser upload activity detection                                    |
| Windows Task Scheduler        | Launches the history collector in SYSTEM context                     |
| Windows Services              | Provides persistent upload monitoring                                |
| Wazuh Agent                   | Endpoint telemetry transport and identity                            |
| Wazuh Manager                 | Event processing, rules and alerts                                   |
| Wazuh Dashboard               | SOC monitoring and visualization                                     |
| Sysmon                        | Supporting endpoint telemetry                                        |
| TCP 8765                      | Extension-to-receiver communication                                  |

## Architecture

```text
                         Windows Endpoint
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│   User 1 ──► Chrome Profile ──┐                              │
│   User 2 ──► Chrome Profile ──┤                              │
│   User 3 ──► Chrome Profile ──┤                              │
│                               │                              │
│                               ▼                              │
│                        Chrome History DB                     │
│                               │                              │
│                               ▼                              │
│                        collector.ps1                         │
│                               │                              │
│                               ▼                              │
│                            SQLite                            │
│                               │                              │
│                               ▼                              │
│                       chrome_history.log                     │
│                                                              │
│   Chrome Upload Extension                                    │
│          │                                                   │
│          ▼                                                   │
│   Windows Service ──► receiver.ps1 ──► chrome_upload.log     │
│                                                              │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
                         Wazuh Agent
                               │
                               ▼
                        Wazuh Manager
                               │
                               ▼
                         Custom Rules
                               │
                               ▼
                       Wazuh Dashboard
```

## Multi-User Monitoring

The system is designed for Windows endpoints where **multiple users may have separate Chrome profiles**.

The history collector identifies the Windows user and associated Chrome profile and maintains separate state files using the following concept:

```text
state_<user>_<profile>.txt
```

This prevents events from different users or profiles from being treated as the same browsing session.

For example:

```text
User A
 ├── Chrome Profile: Default
 └── Chrome Profile: Profile 1

User B
 ├── Chrome Profile: Default
 └── Chrome Profile: Profile 2
```

Each user's Chrome activity is collected independently while the resulting telemetry is forwarded through the same Wazuh Agent installed on the endpoint.

The history collector runs under **SYSTEM context**, allowing the scheduled task to provide coverage across Windows user profiles rather than depending on a single interactive PowerShell session.

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

### Chrome History

```text
CHROME_HISTORY user=<WindowsUser> profile=<ChromeProfile> visit_id=<ID> time=<TIME> url=<URL> title=<TITLE>
```

### Upload Activity

```text
UPLOAD_ACTIVITY ...
```

Including the Windows user and Chrome profile in telemetry allows Wazuh events to be associated with the appropriate endpoint user/profile.

## Wazuh Rules

```text
100200  Chrome browsing history
100201  Narrow collector PowerShell suppression
100202  Chrome upload activity
```

## Installation

See the endpoint and SOC installation documents for complete deployment instructions.

The Chrome MVP can currently be loaded unpacked from:

```text
C:\ProgramData\ChromeHistoryMonitor\ChromeUploadDetector-MVP\ChromeUploadDetector-MVP
```

## Monitoring Model

The history collector continuously polls Chrome history at a **10-second target interval**. A Windows Task Scheduler task launches the collector in **SYSTEM context**, providing multi-user coverage across the endpoint.

The collector maintains separate state for each Windows user and Chrome profile so that previously processed events are not repeatedly collected.

Upload monitoring runs independently as an **Automatic LocalSystem Windows service**. The Chrome Extension communicates with the receiver through TCP port `8765`, allowing upload activity to be captured and written to the upload telemetry log.

Both telemetry streams are monitored by the Wazuh Agent and forwarded to the Wazuh Manager, where custom rules generate security alerts that can be viewed in the Wazuh Dashboard.

## Security & Privacy

* Browsing history is sensitive telemetry; collect only with appropriate authorization.
* Restrict access to ProgramData logs and databases.
* URLs may contain sensitive query parameters.
* Keep Wazuh suppressions narrow and specific.
* Correlate upload telemetry with other endpoint evidence when needed.
* Use approved enterprise Chrome management for production extension deployment.
* Protect collected telemetry from unauthorized access or modification.

## Future Development

* Structured upload decoding
* File hashes and richer upload metadata
* Centralized extension deployment
* Improved multi-user/profile discovery
* Sysmon correlation
* Additional Wazuh detection rules
* Additional Wazuh dashboards and visualizations
* Enhanced event correlation between browsing and upload activity
