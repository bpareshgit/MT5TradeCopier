# Setup & troubleshooting guide

Step-by-step setup for **MT5 Trade Copier**, plus fixes for the most common errors seen in the Experts log.

Use this guide if the EA fails on init, spams warnings, or does not copy trades.

---

## Before you start (checklist)

- [ ] MetaTrader 5 installed and **Algo Trading** enabled (toolbar button green)
- [ ] EA compiled with **0 errors** in MetaEditor (version **1.01**)
- [ ] All 8 files copied to `MQL5/Experts/MT5TradeCopier/`
- [ ] You know whether you copy **local** (same PC) or **remote** (different PCs)
- [ ] Provider and receiver account **login numbers** noted
- [ ] **Hedging** accounts preferred (see [Error 1](#error-1-receiver-requires-a-hedging-account) below)

---

## Choose your setup path

```
Same computer, two MT5 terminals?
├── YES → Use LOCAL COPY (Remote HTTP = false, FTP = false)
└── NO  → Use REMOTE COPY (FTP on provider + HTTP on receiver)
```

---

## Local copy setup (same PC) — recommended for first test

### Provider terminal

1. Attach **MT5TradeCopier** to any chart (symbol does not matter).
2. Set inputs:

| Input | Value |
|-------|-------|
| Operating mode | `PROVIDER` |
| Poll interval (ms) | `1000` |
| Remote upload FTP | **`false`** |
| Provider require hedging | `true` (or `false` only if netting account) |

3. Click OK. Experts log should show:
   ```text
   [INFO] MT5TradeCopier started in PROVIDER mode (poll 1000 ms)
   ```
4. Open a **small manual trade**. Confirm file exists:
   ```text
   File → Open Data Folder → Common\Files\MT5Copier-{providerLogin}-positions.csv
   ```

### Receiver terminal

1. Attach **MT5TradeCopier** to any chart.
2. Set inputs:

| Input | Value |
|-------|-------|
| Operating mode | `RECEIVER` |
| Provider account numbers | provider login, e.g. `12345678` |
| Poll interval (ms) | `1000` (match provider) |
| Remote download HTTP | **`false`** |
| Remote upload FTP | `false` |
| Lot sizing mode | `SAME_AS_PROVIDER` (for testing) |
| Receiver require hedging | `true` (see Error 1 if init fails) |
| Symbol remap | only if broker symbols differ |

3. Experts log should show:
   ```text
   [INFO] MT5TradeCopier started in RECEIVER mode (poll 1000 ms)
   ```
4. Within ~1–2 seconds, receiver should mirror provider positions.

---

## Remote copy setup (different PCs)

### Provider

| Input | Value |
|-------|-------|
| Operating mode | `PROVIDER` |
| Remote upload FTP | `true` |
| FTP remote path | your server path (optional) |

Configure **Tools → Options → FTP** (server, login, password).

### Receiver

| Input | Value |
|-------|-------|
| Operating mode | `RECEIVER` |
| Remote download HTTP | `true` |
| HTTP download URL | full URL to CSV, e.g. `https://example.com/MT5Copier-12345678-positions.csv` |
| HTTP username / password | if your server requires basic auth |

Add the URL under **Tools → Options → Expert Advisors → Allow WebRequest**.

---

## Common errors & fixes

### Error 1: Receiver requires a hedging account

**Log message:**
```text
[ERROR] Receiver requires a hedging account to mirror individual tickets safely.
[INFO] MT5TradeCopier stopped.
initializing of MT5TradeCopier failed with code 1
```

**Cause:** Receiver account is **netting**, not hedging. Default setting blocks startup.

**Not caused by:** market closed, weekend, or holidays.

**Fix (recommended):**
1. Open or switch to a **hedging** MT5 account with your broker.
2. Re-attach the EA on that account.

**Fix (testing only):**
- Set **Receiver require hedging** = `false`
- Ticket-level copy is unreliable on netting accounts.

**How to check account type:** Open two opposite trades on the same symbol. If they merge into one position → netting. If both stay open → hedging.

---

### Error 2: Remote HTTP enabled but URL is empty

**Log message:**
```text
[WARN] Remote HTTP enabled but URL is empty.
```
(repeats every poll interval)

**Cause:** **Remote download HTTP** = `true` but **HTTP download URL** is blank.

**Fix for local copy (same PC):**
- Set **Remote download HTTP** = `false`
- Leave URL empty
- Receiver reads from `Common\Files` automatically

**Fix for remote copy:**
- Set a valid **HTTP download URL**
- Whitelist URL in terminal WebRequest settings

---

### Error 3: Provider requires a hedging account

**Log message:**
```text
[ERROR] Provider requires a hedging account. Disable netting or use hedging account.
```

**Cause:** Provider runs in netting mode with **Provider require hedging** = `true`.

**Fix:** Use hedging provider account, or set **Provider require hedging** = `false`.

---

### Error 4: Receiver mode requires at least one provider account number

**Log message:**
```text
[ERROR] Receiver mode requires at least one provider account number.
```

**Cause:** **Provider account numbers** input is empty.

**Fix:** Enter provider login, e.g. `12345678`. Multiple providers: `12345,67890`.

---

### Error 5: CopierTypes.mqh / compile errors

**Log message (MetaEditor):**
```text
file 'CopierTypes.mqh' not found
```
or
```text
undeclared identifier 'SYMBOL_VOLUME_DIGITS'
```

**Cause:** Old or incomplete install — missing `.mqh` files or outdated version.

**Fix:**
1. Delete `MQL5/Experts/MT5TradeCopier/` entirely.
2. Re-copy all 8 files from [GitHub](https://github.com/bpareshgit/MT5TradeCopier).
3. Compile again (expect version **1.01**, 0 errors).

---

### Error 6: EA starts but no trades copy

**Possible causes and fixes:**

| Symptom | Check |
|---------|--------|
| No CSV on provider | Provider mode? Trade open on provider? Check `Common\Files\MT5Copier-*.csv` |
| Wrong provider number | **Provider account numbers** must match provider **login** exactly |
| Symbol missing on receiver | Add **Symbol remap**, e.g. `XAUUSD=XAUUSDm` |
| Risk filter blocking | Lower **Max price deviation**, disable **Ignore profitable**, check **Direction filter** |
| Equity reserve | Reduce **Equity reserve %** or free margin on receiver |
| Provider netting skipped | Provider snapshot says netting; use hedging provider |

Enable **Log level** = `DEBUG` and re-check Experts tab.

---

### Error 7: WebRequest failed

**Log message:**
```text
[ERROR] WebRequest failed (...). Add URL to allowed list: https://...
```

**Fix:**
1. **Tools → Options → Expert Advisors**
2. Enable **Allow WebRequest for listed URL**
3. Add the exact URL (or domain) from the error
4. Restart terminal

---

## Input cheat sheet

### Local copy (same PC)

| | Provider | Receiver |
|---|----------|----------|
| Operating mode | PROVIDER | RECEIVER |
| Remote upload FTP | false | false |
| Remote download HTTP | false | false |
| Provider account numbers | — | your provider login |
| Poll interval | 1000 | 1000 |

### Remote copy (different PCs)

| | Provider | Receiver |
|---|----------|----------|
| Remote upload FTP | true | false |
| Remote download HTTP | false | true |
| HTTP download URL | — | your CSV URL |

---

## Copying from another EA (e.g. TBR Executor)

1. Run your signal EA **and** MT5TradeCopier **Provider** on the **same** provider account.
2. One copier chart is enough — it copies **all** open positions.
3. Set copier poll to **1000–2000 ms** — do **not** match the other EA's scan rate (e.g. 15 s).
4. Receiver settings: same as local copy above.

---

## Still stuck?

1. Set **Log level** = `DEBUG`, **Log to file** = `true`
2. Check log in `Common\Files\MT5Copier-log.txt`
3. Open a [GitHub issue](https://github.com/bpareshgit/MT5TradeCopier/issues) with:
   - Provider vs receiver mode
   - Hedging or netting account
   - Local or remote copy
   - Full error line from Experts tab
   - Screenshot of EA inputs

---

[← Back to README](../README.md)
