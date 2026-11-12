# MT5 Trade Copier

[![MetaTrader 5](https://img.shields.io/badge/Platform-MetaTrader%205-blue)](https://www.metatrader5.com/)
[![MQL5](https://img.shields.io/badge/Language-MQL5-green)](https://www.mql5.com/)
[![Version](https://img.shields.io/badge/Version-1.08-orange)](Experts/MT5TradeCopier/MT5TradeCopier.mq5)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Free, open-source MetaTrader 5 Expert Advisor** that mirrors trades from a **Master (Provider)** account to one or more **Slave (Receiver)** accounts.

- Open, change **SL/TP**, and **close** on the master → same happens on the slave  
- Works with **manual trades** or **any other EA** on the master  
- Same PC (fast local file sync) or different PCs (FTP + HTTP)

> **Hit an error?** Start with **[docs/SETUP.md](docs/SETUP.md)**  
> **Want lower delay?** See **[docs/SPEED.md](docs/SPEED.md)**

---

## Words used in this project

| Word | Meaning |
|------|---------|
| **Master / Provider** | Account where **you** trade (opens / edits / closes) |
| **Slave / Receiver** | Account that **copies** those trades |
| **Master account number** | MT5 login of the master (e.g. `128862787`) — **required on the receiver** |

One EA file, two roles: attach as `PROVIDER` on master, as `RECEIVER` on slave.

---

## Features

| Feature | What it does |
|---------|----------------|
| **Full mirror** (default ON) | Copies opens, SL/TP changes, and closes |
| **Respect local close** (default ON) | If you close on the slave, it will **not** reopen while that master trade is still open |
| **All symbols** | One chart attachment copies **every** open position |
| **Local sync** | Same PC via shared `Common\Files` |
| **Remote sync** | Optional FTP (master) + HTTP (slave) |
| **Multi-master** | One slave can follow several master logins |
| **Lot sizing** | Same lots, or proportional to balance / free margin |
| **Symbol remap** | Map names like `XAUUSD` → `XAUUSDm` |
| **On-chart status** | Live panel: linked / failed, position count, paths |

---

## How it works

```
Master terminal                    Shared folder / HTTP                 Slave terminal
(PROVIDER mode)                    Common\Files                         (RECEIVER mode)
─────────────────                  ──────────────────                   ────────────────
Reads all open trades   ──────►   MT5Copier-{login}-positions.csv  ──►  Opens / edits / closes
Writes CSV on timer +                                                       matching copies
on every trade event
```

1. Master writes a small CSV of open positions.  
2. Slave reads it, keeps a ticket map, and mirrors changes.  
3. Chart symbol does **not** matter — attach once per terminal.

---

## Requirements

- MetaTrader 5  
- **Hedging** accounts strongly recommended (default setting)  
- MetaEditor (to compile once)  
- **Same PC:** two terminals sharing `Common\Files` (normal install)  
- **Different PCs:** FTP + HTTP URL allowed in Expert Advisor settings  

---

## Installation

### 1. Download

```bash
git clone https://github.com/bpareshgit/MT5TradeCopier.git
```

Or download ZIP from GitHub → **Code → Download ZIP**.

### 2. Copy into MetaTrader 5

1. MT5 → **File → Open Data Folder**  
2. Copy the whole folder:

   ```
   Experts/MT5TradeCopier/   →   MQL5/Experts/MT5TradeCopier/
   ```

   You need **all** files (`.mq5` + `.mqh`), not only the main EA.

### 3. Compile

1. Open `MQL5/Experts/MT5TradeCopier/MT5TradeCopier.mq5` in MetaEditor  
2. Press **Compile (F7)**  
3. Expect **0 errors**, version **1.08**

---

## Quick start (same PC — recommended)

You need **two** MT5 terminals (two accounts).

### A) Master terminal

| Input | Value |
|-------|-------|
| Operating mode | `PROVIDER` |
| Poll interval | `1000` ms (or `200` for faster copy) |
| Remote upload FTP | `false` |

1. Attach EA to **any** chart.  
2. Enable **Algo Trading** (toolbar green).  
3. Open a small test trade.  
4. Confirm this file exists:

   ```
   File → Open Data Folder → Common\Files\MT5Copier-{YOUR_MASTER_LOGIN}-positions.csv
   ```

   Note your master login from the Experts log (e.g. `128862787`).

### B) Slave terminal

| Input | Value |
|-------|-------|
| **1. Master account number** | **REQUIRED** — paste the **master** login (e.g. `128862787`) |
| Operating mode | `RECEIVER` |
| Poll interval | same as master |
| Full mirror | `true` |
| Respect local close | `true` |
| Remote download HTTP | `false` |
| Lot sizing | `SAME_AS_PROVIDER` |

1. Attach EA to any chart.  
2. Experts log should show handshake **linked** and then a copied trade.  
3. Test: change SL/TP on master → slave updates; close on master → slave closes.

**Several masters on one slave:**  
`128862787,7004348`

---

## What gets mirrored

| You do on master | Slave does |
|------------------|------------|
| Open trade | Opens matching trade |
| Change SL / TP later | Updates SL / TP |
| Partial close | Partial close |
| Full close | Full close |
| Close only on **slave** | Stays closed (will not reopen) while master trade is still open |

---

## Copy trades from another EA

Run your signal EA **and** this copier as **PROVIDER** on the **same** master account.

| Question | Answer |
|----------|--------|
| Need one chart per symbol? | **No** — one copier copies all positions |
| Match the other EA’s slow timer? | **No** — set copier poll to **200–1000 ms** |
| What is copied? | All open positions on the master |
| What can the slave change? | Only its own copies (copier magic + `MCP|…` comment) |

---

## Remote copy (different PCs)

### Master

1. **Tools → Options → FTP** — server, login, password  
2. **Remote upload FTP** = `true`  
3. Host the uploaded CSV over HTTP for the slave  

### Slave

1. **Tools → Options → Expert Advisors** → allow WebRequest for your URL  
2. **Remote download HTTP** = `true`  
3. **HTTP download URL**, e.g.  
   `https://example.com/copier/MT5Copier-{account}-positions.csv`  
4. Still set **Master account number** to the real master login  

---

## Input parameters (overview)

Inputs are grouped. **#1 is always Master account number.**

### 1. Master account (required for Receiver)

| Input | Description |
|-------|-------------|
| **Master account number** | MT5 login of the account you copy **FROM**. Example: `128862787`. Several: `128862787,7004348`. Leave empty → receiver will not start. |

### 2. General

| Input | Default | Description |
|-------|---------|-------------|
| Operating mode | `RECEIVER` | `PROVIDER` (master) or `RECEIVER` (slave) |
| Poll interval (ms) | `1000` | How often to sync (minimum `200`) |
| Magic number | `56001501` | Tags copied trades on the slave |
| Log level | `INFO` | NONE / ERROR / WARN / INFO / DEBUG |
| Show chart status | `true` | On-chart status panel |

### 4. Receiver (slave)

| Input | Description |
|-------|-------------|
| Lot sizing | Same as master / by balance / by free margin |
| Symbol remap | e.g. `XAUUSD=XAUUSDm;EURUSD=EURUSD.micro` |
| Slippage points | Max slippage for slave orders |
| **Full mirror** | ON = open + SL/TP + close |
| **Respect local close** | ON = manual slave close will not reopen |

### 7. Risk (usually leave defaults)

With **Full mirror ON**, price-deviation / age / “ignore profitable” filters are ignored.  
Equity reserve and direction filter still apply if you set them.

---

## Polling interval

| Setup | Suggested poll |
|-------|----------------|
| Comfortable | `1000` ms on both |
| Fast local | `200` ms on both |
| Remote HTTP/FTP | often keep `1000+` (network limited) |

Faster poll = lower copy delay. Values under 200 ms are raised to 200 automatically.

---

## Troubleshooting (short)

Full guide: **[docs/SETUP.md](docs/SETUP.md)**

| Problem | Fix |
|---------|-----|
| `Master account number is REQUIRED` | Fill input **#1** with the real master login |
| `HANDSHAKE FAILED` / snapshot missing | Start **PROVIDER** on master; check Common\Files CSV name matches that login |
| `Receiver requires a hedging account` | Use hedging account, or set require-hedging = false for testing |
| `CopierTypes.mqh not found` | Copy the **entire** `MT5TradeCopier` folder |
| Slave closes then reopens | Use **v1.08+**, keep **Respect local close = true** |
| No copy at all | Algo Trading ON; HTTP = false for local; symbol remap if names differ |

Log file: `Common\Files\MT5Copier-log.txt`

---

## Project structure

```
MT5TradeCopier/
├── README.md                 ← you are here
├── LICENSE                   ← MIT
├── docs/
│   ├── SETUP.md              ← setup & errors
│   └── SPEED.md              ← low-latency tips
└── Experts/
    └── MT5TradeCopier/
        ├── MT5TradeCopier.mq5   ← compile this
        ├── CopierTypes.mqh
        ├── CopierLogger.mqh
        ├── CopierCsv.mqh
        ├── CopierFileSync.mqh
        ├── CopierRemote.mqh
        ├── CopierState.mqh
        └── CopierTrade.mqh
```

---

## Known limitations

- Hedging accounts are best for ticket-level copy.  
- WebRequest URLs must be allowed manually for remote HTTP.  
- FTP uses the terminal’s global FTP settings.  
- Mid-write CSV is skipped safely (checksum); brief “refreshing” is normal.  

---

## License

**MIT** — free to use, modify, and share. See [LICENSE](LICENSE).

Public repo: [github.com/bpareshgit/MT5TradeCopier](https://github.com/bpareshgit/MT5TradeCopier)

---

## Author

Maintained by [bpareshgit](https://github.com/bpareshgit).

Issues and ideas: [GitHub Issues](https://github.com/bpareshgit/MT5TradeCopier/issues)
