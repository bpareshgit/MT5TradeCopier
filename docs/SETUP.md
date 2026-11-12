# Setup & troubleshooting guide

Step-by-step setup for **MT5 Trade Copier v1.08**, plus fixes for common Experts-log errors.

---

## Before you start

- [ ] MetaTrader 5 installed  
- [ ] **Algo Trading** enabled (toolbar button green) on both terminals  
- [ ] EA compiled with **0 errors** in MetaEditor (**version 1.08**)  
- [ ] Full folder copied to `MQL5/Experts/MT5TradeCopier/` (all `.mq5` + `.mqh` files)  
- [ ] You know your **master** and **slave** account login numbers  
- [ ] Prefer **hedging** accounts  

### Words

| Word | Meaning |
|------|---------|
| **Master / Provider** | Account where you open trades |
| **Slave / Receiver** | Account that copies those trades |
| **Master account number** | Input **#1** on the slave — the master’s MT5 login |

---

## Choose local or remote

```
Same computer, two MT5 terminals?
├── YES → LOCAL COPY  (FTP = false, HTTP = false)   ← start here
└── NO  → REMOTE COPY (FTP on master + HTTP on slave)
```

---

## Local copy (same PC)

### 1) Master terminal (PROVIDER)

1. Attach **MT5TradeCopier** to any chart.  
2. Set:

| Input | Value |
|-------|-------|
| Operating mode | `PROVIDER` |
| Poll interval (ms) | `1000` (or `200` for faster) |
| Remote upload FTP | **`false`** |

3. Experts log should show something like:

   ```text
   [INFO] MT5TradeCopier v1.08 started in PROVIDER mode (poll 1000 ms)
   [HANDSHAKE] PROVIDER ready on account 128862787
   ```

4. Open a small test trade. Confirm:

   ```text
   File → Open Data Folder → Common\Files\MT5Copier-128862787-positions.csv
   ```

   (Use **your** master login in the file name.)

### 2) Slave terminal (RECEIVER)

1. Attach **MT5TradeCopier** to any chart.  
2. Set:

| Input | Value |
|-------|-------|
| **1. Master account number** | **REQUIRED** — e.g. `128862787` (exact master login) |
| Operating mode | `RECEIVER` |
| Poll interval (ms) | same as master |
| Full mirror | **`true`** |
| Respect local close | **`true`** |
| Remote download HTTP | **`false`** |
| Lot sizing mode | `SAME_AS_PROVIDER` |
| Symbol remap | only if symbol names differ |

3. Good log:

   ```text
   [INFO] MT5TradeCopier v1.08 started in RECEIVER mode
   [INFO] Full mirror: ON
   [INFO] Respect local close: ON
   [HANDSHAKE] RECEIVER linked to provider 128862787 — CSV read OK
   ```

4. Within about 1 second the slave should mirror the master trade.

### Quick test checklist

| Action on master | Expected on slave |
|------------------|-------------------|
| Open buy/sell | Same side opens |
| Change SL / TP | SL / TP updates |
| Close trade | Slave closes |
| Close only on slave | Stays closed (does not reopen) |

---

## Remote copy (different PCs)

### Master

| Input | Value |
|-------|-------|
| Operating mode | `PROVIDER` |
| Remote upload FTP | `true` |
| FTP remote path | optional |

Also configure **Tools → Options → FTP**.

### Slave

| Input | Value |
|-------|-------|
| **Master account number** | real master login |
| Operating mode | `RECEIVER` |
| Remote download HTTP | `true` |
| HTTP download URL | URL to the CSV (may use `{account}`) |

Allow the URL under **Tools → Options → Expert Advisors → Allow WebRequest**.

---

## Common errors & fixes

### Error 1: Master account number is REQUIRED

**Log:**
```text
[ERROR] [HANDSHAKE] RECEIVER ERROR — Master account number is REQUIRED.
```

**Cause:** Input #1 is empty.

**Fix:** Paste the **master** MT5 login into **Master account number** (first input).  
Example: `128862787`  
Several masters: `128862787,7004348`

---

### Error 2: Placeholder login rejected

**Log:**
```text
… is a placeholder, not a real master login.
```

**Cause:** Still using an example like `12345678`.

**Fix:** Use the real login from the **master** Experts log / Navigator.

---

### Error 3: Handshake failed / snapshot missing

**Log / chart:**
```text
[ERROR] Snapshot missing for provider account …
Status: HANDSHAKE FAILED
```

**Cause:** Wrong master login, or provider EA not running / not writing CSV.

**Fix:**
1. Set **Master account number** = exact master login.  
2. On master, confirm CSV: `Common\Files\MT5Copier-<that-login>-positions.csv`.  
3. Same PC for local copy (shared `Common\Files`).  
4. Algo Trading ON on master.

**Note:** Brief “LINKED (refreshing)” is normal while the master rewrites the CSV. Real failures only after the file stays missing for several seconds.

---

### Error 4: Receiver requires a hedging account

**Log:**
```text
[ERROR] Receiver requires a hedging account …
initializing of MT5TradeCopier failed with code 1
```

**Fix (recommended):** Use a hedging account.  
**Fix (testing only):** Set **Receiver require hedging** = `false` (ticket-level copy is weaker on netting).

**Check:** Two opposite trades on one symbol — if they merge → netting; if both stay → hedging.

---

### Error 5: Remote HTTP enabled but URL is empty

**Cause:** HTTP = true but URL blank.

**Local copy fix:** set **Remote download HTTP** = `false`.  
**Remote fix:** set a valid URL and whitelist it for WebRequest.

---

### Error 6: Compile — `CopierTypes.mqh not found`

**Cause:** Incomplete copy (only `.mq5` installed).

**Fix:**
1. Delete `MQL5/Experts/MT5TradeCopier/`.  
2. Re-copy **all** files from [GitHub](https://github.com/bpareshgit/MT5TradeCopier).  
3. Compile again → version **1.08**, 0 errors.

---

### Error 7: EA runs but nothing copies

| Check | Action |
|-------|--------|
| CSV exists on master? | `Common\Files\MT5Copier-*.csv` |
| Master account number exact? | Must match master login digit-for-digit |
| Local copy? | HTTP = false, FTP = false |
| Symbol names differ? | Use **Symbol remap** |
| Full mirror? | Keep `true` for SL/TP + close |
| Risk filters? | With Full mirror ON, deviation/age are ignored |

Set **Log level** = `DEBUG` if you need more detail.

---

### Error 8: Slave closes, then trade reopens

**Cause:** Old EA version, or **Respect local close** was off.

**Fix:** Use **v1.08+**, set **Respect local close** = `true`, recompile and re-attach on the slave.  
Log should show: `Local close locked — will not reopen provider ticket …`

---

### Error 9: WebRequest failed

**Fix:**
1. **Tools → Options → Expert Advisors**  
2. Allow WebRequest for listed URL  
3. Add the exact URL from the error  
4. Restart the terminal  

---

## Input cheat sheet

### Local (same PC)

| | Master (PROVIDER) | Slave (RECEIVER) |
|---|-------------------|------------------|
| Master account number | — | **your master login** |
| Operating mode | PROVIDER | RECEIVER |
| Remote upload FTP | false | false |
| Remote download HTTP | false | false |
| Full mirror | — | true |
| Respect local close | — | true |
| Poll interval | 1000 or 200 | same |

### Remote (different PCs)

| | Master | Slave |
|---|--------|-------|
| Remote upload FTP | true | false |
| Remote download HTTP | false | true |
| HTTP download URL | — | your CSV URL |
| Master account number | — | master login |

---

## Copying from another EA

1. Run your signal EA **and** MT5TradeCopier **PROVIDER** on the **same** master account.  
2. One copier chart is enough — it copies **all** open positions.  
3. Set copier poll to **200–1000 ms** (do not match a slow 15s signal timer).  
4. Slave settings: same as local copy above.

---

## Still stuck?

1. Log level = `DEBUG`, Log to file = `true`  
2. Open `Common\Files\MT5Copier-log.txt`  
3. Open a [GitHub issue](https://github.com/bpareshgit/MT5TradeCopier/issues) with:  
   - Provider vs receiver  
   - Hedging or netting  
   - Local or remote  
   - Full error line  
   - Screenshot of inputs  

---

[← Back to README](../README.md)
