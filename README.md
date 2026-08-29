# MT5 Trade Copier

[![MetaTrader 5](https://img.shields.io/badge/Platform-MetaTrader%205-blue)](https://www.metatrader5.com/)
[![MQL5](https://img.shields.io/badge/Language-MQL5-green)](https://www.mql5.com/)
[![Version](https://img.shields.io/badge/Version-1.01-orange)](Experts/MT5TradeCopier/MT5TradeCopier.mq5)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A MetaTrader 5 Expert Advisor that copies **all open positions** from a **Provider** account to one or more **Receiver** accounts — on the same PC (local file sync) or across machines (FTP + HTTP).

Works with manual trades, signals, or **any other EA** (e.g. TBR Executor, Firebase bots) running on the provider account.

---

## Table of contents

- [Features](#features)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start (local copy)](#quick-start-local-copy)
- [Copy trades from another EA](#copy-trades-from-another-ea)
- [Remote copy (different PCs)](#remote-copy-different-pcs)
- [Input parameters](#input-parameters)
- [Polling interval](#polling-interval)
- [Troubleshooting](#troubleshooting)
- [Project structure](#project-structure)
- [Known limitations](#known-limitations)
- [License](#license)

---

## Features

| Feature | Description |
|---------|-------------|
| **Dual mode** | Single EA — choose `PROVIDER` or `RECEIVER` at attach time |
| **All symbols** | One chart attachment copies **every** open position on the account |
| **Local sync** | Shared `Common\Files` snapshot (same machine) |
| **Remote sync** | Optional FTP upload (provider) + HTTP download (receiver) |
| **Multi-provider** | Receiver can subscribe to multiple provider account numbers |
| **Ticket mapping** | Persisted provider→receiver ticket map survives restarts |
| **Lot sizing** | Same, proportional to balance, or proportional to free margin |
| **Risk controls** | Deviation filter, age filter, direction filter, equity reserve |
| **Symbol remap** | Map broker-specific symbol names between accounts |
| **Partial close** | Proportional volume sync when provider partially closes |
| **Safe coexistence** | Only touches trades with the copier magic + comment tag |

---

## How it works

```
┌─────────────────────┐         ┌──────────────────────────┐         ┌─────────────────────┐
│  PROVIDER terminal  │         │   Common\Files (local)   │         │ RECEIVER terminal   │
│                     │         │   or HTTP (remote)       │         │                     │
│  Any open positions │ ──────► │ MT5Copier-{acct}.csv     │ ──────► │ Mirror positions    │
│  (manual / any EA)  │  write  │ + checksum / row count   │  read   │ (magic + MCP tag)   │
└─────────────────────┘         └──────────────────────────┘         └─────────────────────┘
```

1. **Provider** polls all open positions on a timer and writes an atomic CSV snapshot.
2. **Receiver** reads the snapshot, diffs against a persisted mapping file, and opens/closes/modifies tagged trades only.
3. Timer-driven sync (`OnTimer`) — the chart symbol does **not** matter.

---

## Requirements

- MetaTrader 5 (hedging account **strongly recommended**)
- MetaEditor to compile the EA
- **Same PC (local):** both terminals installed; `Common\Files` is shared automatically
- **Remote:** FTP server (provider) + HTTP URL (receiver) whitelisted in terminal settings

---

## Installation

### From GitHub

```bash
git clone https://github.com/bpareshgit/MT5TradeCopier.git
```

### Into MetaTrader 5

1. In MT5: **File → Open Data Folder**
2. Copy the folder:

   ```
   Experts/MT5TradeCopier/  →  MQL5/Experts/MT5TradeCopier/
   ```

3. Open `MT5TradeCopier.mq5` in MetaEditor
4. Press **Compile** (F7) — expect **0 errors**, version **1.01**

All `.mqh` headers live **next to** the `.mq5` file in the same folder.

---

## Quick start (local copy)

Use two MT5 terminals on the **same computer** (or two accounts in portable instances sharing `Common\Files`).

### Provider terminal

| Input | Value |
|-------|-------|
| Operating mode | `PROVIDER` |
| Poll interval | `1000` ms |
| Remote upload FTP | `false` |

Attach to **any chart** (symbol does not matter). Open a small manual trade.

Verify snapshot file exists:

```
Terminal\Common\Files\MT5Copier-{yourLogin}-positions.csv
```

### Receiver terminal

| Input | Value |
|-------|-------|
| Operating mode | `RECEIVER` |
| Provider account numbers | provider login, e.g. `12345678` |
| Lot sizing mode | `SAME_AS_PROVIDER` |
| Remote download HTTP | `false` |
| Symbol remap | only if symbols differ between brokers |

Attach to any chart. Matching trade should appear within ~1 second.

State file (survives restarts):

```
Terminal\Common\Files\MT5Copier_state_{receiverLogin}_{providerLogin}.csv
```

---

## Copy trades from another EA

You can run **MT5TradeCopier** alongside another EA (e.g. TBR Executor, signal copiers, Firebase bots) on the **provider** account.

| Question | Answer |
|----------|--------|
| Separate chart per symbol? | **No** — one copier on any chart copies all account positions |
| Match the other EA's poll rate? | **No** — use **1000–2000 ms** on the copier for fast sync |
| Which trades are copied? | **All** open positions on the provider account |
| Which trades does receiver touch? | Only copies with copier magic + `MCP\|{account}\|{ticket}` comment |

**Example:** TBR Executor scans Firebase every ~15 s. Set copier poll to **1000 ms** on both provider and receiver — the copier mirrors positions as soon as TBR opens them, without waiting 15 s.

---

## Remote copy (different PCs)

### Provider

1. **Tools → Options → FTP** — configure server, login, password
2. Set **Remote upload FTP** = `true`
3. Expose the uploaded CSV via HTTP for receivers

### Receiver

1. **Tools → Options → Expert Advisors** — add HTTP download URL to allowed list
2. Set **Remote download HTTP** = `true`
3. Set URL, e.g. `https://example.com/copier/MT5Copier-{account}-positions.csv`
4. Set HTTP username/password if needed

---

## Input parameters

### General

| Input | Default | Description |
|-------|---------|-------------|
| Operating mode | `RECEIVER` | `PROVIDER` or `RECEIVER` |
| Poll interval (ms) | `1000` | Sync timer (min 200 ms) |
| Magic number | `56001501` | Tags copied receiver trades |
| Log level | `INFO` | NONE / ERROR / WARN / INFO / DEBUG |
| Log to file | `true` | Rotating log in Common\Files |

### Receiver

| Input | Description |
|-------|-------------|
| Provider account numbers | Comma-separated, e.g. `12345,67890` |
| Lot sizing mode | Same / balance / free margin proportional |
| Factor leverage | Scale lots by leverage ratio |
| Symbol remap | `EURUSD=EURUSD.micro;XAUUSD=XAUUSDm` |
| Slippage points | Max slippage for orders |

### Risk

| Input | Description |
|-------|-------------|
| Max price deviation | Skip if price moved too far (points) |
| Max trade age | Skip old provider positions (minutes) |
| Ignore profitable | Skip trades already in profit on provider |
| Direction filter | Both / buy only / sell only |
| Excluded tickets | Comma-separated provider tickets to skip |
| Equity reserve % | Stop copying when margin usage too high |
| Mass close mode | Auto-close or alert when many losers close at once |

Full list is in the EA inputs panel under grouped sections.

---

## Polling interval

| Component | Recommended | Notes |
|-----------|-------------|-------|
| Provider copier | **1000–2000 ms** | Writes position snapshot |
| Receiver copier | **Same as provider** | Reads and syncs |
| Other EA on provider (e.g. TBR) | Independent | Copier does not need to match this rate |

Faster polling = lower copy latency. Values below 200 ms are raised automatically.

---

## Troubleshooting

### `CopierTypes.mqh not found`

Copy the **entire** `MT5TradeCopier` folder (all 8 files) into `MQL5/Experts/MT5TradeCopier/`. Do not copy only the `.mq5` file.

### `SYMBOL_VOLUME_DIGITS` compile error

You have an old `CopierTrade.mqh`. Delete the folder and reinstall from this repo (version **1.01**).

### Receiver does not copy

1. Confirm provider CSV exists in `Terminal\Common\Files\`
2. Check **Provider account numbers** matches provider login exactly
3. Enable **INFO** logging and check Experts tab
4. Verify symbol exists on receiver broker (use **Symbol remap**)
5. Confirm both accounts are **hedging** mode

### Receiver skips new trades

- **Max price deviation** — price moved too far from provider entry
- **Max trade age** — position too old when first seen
- **Equity reserve** — receiver margin limit reached
- **Direction filter** — buy/sell filter active

---

## Project structure

```
MT5TradeCopier/
├── README.md
├── .gitignore
└── Experts/
    └── MT5TradeCopier/
        ├── MT5TradeCopier.mq5      # Main EA — compile this
        ├── CopierTypes.mqh          # Enums and structs
        ├── CopierLogger.mqh         # Logging
        ├── CopierCsv.mqh            # CSV helpers
        ├── CopierFileSync.mqh       # Atomic file read/write
        ├── CopierRemote.mqh         # HTTP / FTP / heartbeat
        ├── CopierState.mqh          # Ticket mapping persistence
        └── CopierTrade.mqh          # Lot sizing and execution
```

---

## Known limitations

- **Hedging accounts** are required for reliable ticket-level copy (netting is warned/blocked by default).
- **WebRequest URLs** must be whitelisted manually in terminal settings.
- **FTP** uses terminal-wide FTP settings (`SendFTP`); no per-EA FTP credentials in MQL5.
- **Async execution** — brief delay possible before receiver ticket appears in mapping.
- **Checksum guard** — receiver skips a poll cycle if provider file is mid-write.

---

## License

MIT License — see [LICENSE](LICENSE).

Use, modify, and distribute freely. Attribution appreciated.

Architecture inspired by the community file-sync copier pattern ([sharing-is-caring](https://github.com/wait4signal/sharing-is-caring)); this codebase is **not** a port of that GPL project.

---

## Author

Maintained by [bpareshgit](https://github.com/bpareshgit).
