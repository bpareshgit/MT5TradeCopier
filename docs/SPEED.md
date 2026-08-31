# Speed optimization plan

How to make **MT5 Trade Copier** as fast as possible **without interfering** with your existing EA (signal bots, manual trading, etc.).

---

## Golden rules (protect your main EA)

| Rule | Why |
|------|-----|
| Run copier in **PROVIDER** mode on provider account — **never place orders** there | Provider only **reads** open positions and writes a small CSV file |
| Run **your signal EA + copier provider** on the **same** provider account | Copier mirrors whatever is open — no conflict |
| Use a **different chart** for each EA (optional but tidy) | MT5 allows multiple EAs per account; separate charts keep inputs clear |
| Use **different magic number** on receiver (default `56001501`) | Receiver only closes/modifies trades **it** opened |
| **Do not** attach receiver copier on the same account as your signal EA | Receiver **executes** trades — that would fight your bot |
| Keep copier **log level** at `WARN` or `ERROR` on provider | Less disk I/O while your main EA runs |

**Your signal EA is untouched:** it keeps opening trades as usual. The copier only watches the resulting positions.

---

## Target latency (realistic)

| Setup | Typical delay after provider opens |
|-------|-----------------------------------|
| Default (1000 ms poll, local) | ~0.5–1.5 seconds |
| Optimized (200 ms poll, local) | ~0.2–0.5 seconds |
| Remote HTTP/FTP | +network time (often 1–5+ seconds) |

For **lightning-fast** copy, use **local `Common\Files` sync** on the **same PC** with **200 ms** polling on both terminals.

---

## Phase 1 — Settings only (do this now)

### Provider terminal (where your EA runs)

| Input | Recommended | Notes |
|-------|---------------|-------|
| Operating mode | `PROVIDER` | Read-only |
| Poll interval (ms) | **`200`** | Minimum safe value in EA |
| Remote upload FTP | `false` | Local copy only |
| Log level | `WARN` or `ERROR` | Quieter, less I/O |
| Log to file | `false` on provider | Optional — reduces disk writes |
| Heartbeat URL | empty | Disable unless you need monitoring |

Attach copier to **any** chart (XAUUSD, BTCUSD, etc. — symbol does not matter).

### Receiver terminal

| Input | Recommended | Notes |
|-------|---------------|-------|
| Operating mode | `RECEIVER` |
| Poll interval (ms) | **`200`** | Match provider |
| Provider account numbers | exact provider login |
| Remote download HTTP | **`false`** | Must be off for local copy |
| Lot sizing mode | `SAME_AS_PROVIDER` | Fastest — no extra calc |
| Log level | `INFO` while testing, then `WARN` |
| Slippage points | `30–50` on XAUUSD | Helps fill speed (broker-dependent) |
| Max price deviation | `100–200` on volatile symbols | Too low = skipped copies |
| Max trade age (minutes) | `0` | Do not delay new copies |
| Symbol remap | set **before** first trade | e.g. `XAUUSD=XAUUSDm` |

### Terminal / system

- [ ] **Algo Trading** enabled on both terminals
- [ ] Add all copied symbols to **Market Watch** on receiver (one-time)
- [ ] Use **hedging** accounts (faster ticket mapping)
- [ ] Same PC, SSD, avoid heavy CPU load during news
- [ ] **VPS** near broker if you must run 24/7 (both terminals on same VPS = local copy)

### What NOT to do

| Avoid | Reason |
|-------|--------|
| HTTP/FTP for local copy | Adds network delay |
| Poll interval below 200 ms | EA enforces 200 ms minimum |
| Matching your EA's slow scan interval | Irrelevant — copier should be **faster** than your EA |
| `DEBUG` log on provider 24/7 | Extra file writes every 200 ms |

---

## Phase 2 — Verify speed (5-minute test)

1. Provider: your EA (or manual) opens **one small XAUUSD** trade.
2. Note time in provider **Toolbox → History**.
3. Note time receiver copy appears in **Toolbox → Trade**.
4. Check provider file updates:
   ```text
   File → Open Data Folder → Common\Files\MT5Copier-{login}-positions.csv
   ```
5. Target: receiver copy within **under 1 second** with 200 ms local setup.

If slow, check:
- Remote HTTP still `true`? → set `false`
- Wrong provider account number?
- Receiver log: `Skipped … by risk filters`?
- Symbol not in Market Watch?

---

## Phase 3 — Architecture diagram

```
┌─────────────────────────────────────────────────────────────┐
│  PROVIDER TERMINAL (same PC)                                │
│                                                             │
│  ┌──────────────┐     ┌─────────────────────┐              │
│  │ Your EA      │     │ MT5TradeCopier      │              │
│  │ (your EA)    │     │ mode = PROVIDER     │              │
│  │ Opens trades │     │ READ ONLY           │              │
│  └──────┬───────┘     │ poll 200ms          │              │
│         │             │ writes CSV only     │              │
│         ▼             └──────────┬──────────┘              │
│    Open positions                │                          │
│         │                        ▼                          │
│         └────────────► Common\Files\MT5Copier-*.csv        │
└─────────────────────────────────────────────────────────────┘
                                    │
                                    │ (same disk, ~instant)
                                    ▼
┌─────────────────────────────────────────────────────────────┐
│  RECEIVER TERMINAL (same PC)                                │
│                                                             │
│  ┌─────────────────────┐                                   │
│  │ MT5TradeCopier      │  poll 200ms → read CSV → OPEN     │
│  │ mode = RECEIVER     │  magic + MCP comment only         │
│  └─────────────────────┘                                   │
└─────────────────────────────────────────────────────────────┘
```

**No line connects copier to your EA** — they only share the account’s position list.

---

## Why this does not affect your ongoing EA

| Copier action | Provider (your EA account) | Receiver account |
|---------------|------------------------|------------------|
| Open trade | ❌ Never | ✅ Only copied trades |
| Close trade | ❌ Never | ✅ Only its own copies |
| Modify SL/TP | ❌ Never | ✅ Only its copies |
| Read positions | ✅ Every 200 ms | ✅ From CSV |
| CPU on OnTick | ❌ Empty OnTick | ❌ Empty OnTick |
| Uses timer | ✅ Lightweight | ✅ Lightweight |

Your EA keeps full control of **when** to open. Copier only **reflects** what already exists.

---

## Phase 4 — Optional upgrades (future)

If you need **sub-200 ms** reaction, the EA would need a code change:

- **`OnTradeTransaction`** on provider → write snapshot immediately when a position opens/closes (event-driven + optional 200 ms backup poll)
- **Reduce `Sleep(50)`** wait in receiver open logic (currently up to ~1 s ticket lookup)

These are not in v1.01. Open a [GitHub issue](https://github.com/bpareshgit/MT5TradeCopier/issues) if you want event-driven mode added.

---

## Quick copy-paste settings

### Provider (with your EA running)
```
Mode = PROVIDER
Poll = 200
Remote FTP = false
Remote HTTP = false
Log = WARN
```

### Receiver
```
Mode = RECEIVER
Poll = 200
Provider accounts = YOUR_PROVIDER_LOGIN
Remote HTTP = false
Remote FTP = false
Lot = SAME_AS_PROVIDER
Max trade age = 0
Log = INFO (testing) → WARN (live)
```

---

[← Setup guide](SETUP.md) · [← README](../README.md)
