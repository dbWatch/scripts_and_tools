# dbWatch CC → Slack (Bash & PowerShell)

This package posts a concise, rolling status from dbWatch Control Center (dbWatch CC) to a Slack channel. It deletes the previous message each run and posts a fresh one.

## Contents

- `scripts/CustomerOp.sh` (Ubuntu)
- `scripts/CustomerOp.ps1` (Windows)
- `scripts/SetupStatus.sh` / `scripts/SetupStatus.ps1`
- `scripts/fdl4ini.txt`
- `config/customers.ini` (sample)
- `config/slack.xml` (optional resource)
- `guides/Slack_App_Setup_and_Install_Guide.docx`
- `assets/Slack_Screenshot_01.jpg`

> Minimal Slack scopes: `chat:write`; `channels:read` is optional (only if you resolve `#channel` to ID at runtime). Invite the bot to your target channel.

## Quickstart

### 1) Slack app (one-time)
- Create the app → Add `chat:write` (optionally `channels:read`) → Install to workspace → copy Bot token (`xoxb-…`).
- Invite the bot to the target channel: `/invite @YourBot`.

### 2) dbWatch CC (one-time)
- Optional: upload `config/slack.xml` via **Server → Upload resource**.
- First execution may require CCC approval; run once, approve, then rerun.
- You can use `SetupStatus.sh` / `SetupStatus.ps1` to apply minimal read permissions (All Instances/All Servers).

### 3) Configure monitored domains
Edit `config/customers.ini` (one per line):
```
<ACCESSPOINT>,<TARGET>,<DOMAINNAME>,<TOKEN>
```
- `ACCESSPOINT`: e.g. `192.168.7.30:7100`
- `TARGET`: Node ID under *Server → Domain Configuration → Nodes*
- `DOMAINNAME`: As in Domain Configuration/license
- `TOKEN`: Cloud Router token

### 4) Set Slack env vars
Prefer a **channel ID** (e.g., `C123…`) to avoid needing `channels:read`.

**Ubuntu**
```bash
export SLACK_TOKEN="xoxb-xxxxxxxx"
export SLACK_CHANNEL="C1234567890"
```

**Windows**
```powershell
$env:SLACK_TOKEN   = "xoxb-xxxxxxxx"
$env:SLACK_CHANNEL = "C1234567890"
```

### 5) Run

**Ubuntu**
```bash
chmod +x scripts/CustomerOp.sh scripts/SetupStatus.sh
./scripts/SetupStatus.sh   # first-time CCC approval only
./scripts/CustomerOp.sh
```

**Windows**
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\SetupStatus.ps1  # first-time CCC approval only
.\scripts\CustomerOp.ps1
```

## How it works
dbWatch CC → **CCC** (`fdl4ini.txt`) → `CustomerOp.*` → Slack Web API (`chat.delete` then `chat.postMessage`) → a single rolling message in your channel.

## Scheduling
- Ubuntu: cron or systemd timer
- Windows: Task Scheduler

## Troubleshooting
- **Bot can’t post:** Bot must be invited to the channel (or add `chat:write.public` to post to public channels without invite).
- **Delete fails:** You can delete only your app’s own messages (under `chat:write`). Persist and reuse the previous `ts`.
- **Channel name vs ID:** Resolve once and switch to the ID to drop `channels:read`.
