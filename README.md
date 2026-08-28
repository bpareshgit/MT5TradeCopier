# MT5 Trade Copier

MetaTrader 5 Expert Advisor that copies trades between two or more MT5 terminals using a shared snapshot file. One terminal runs in **Provider** mode (publishes open positions); other terminals run in **Receiver** mode (mirror those positions).

## Files

```
Experts/MT5TradeCopier/
  MT5TradeCopier.mq5      Main EA
  CopierTypes.mqh         Shared enums/structs
  CopierLogger.mqh        Leveled logging + optional file rotation
  CopierCsv.mqh           CSV parsing/checksum helpers
  CopierFileSync.mqh      Atomic snapshot read/write (Common\Files)
  CopierRemote.mqh        HTTP download, FTP upload, heartbeat
  CopierState.mqh         Persisted provider→receiver ticket mapping
  CopierTrade.mqh         Lot sizing, symbol remap, order execution
```

Copy the `MT5TradeCopier` folder into your terminal's `MQL5/Experts/` directory and compile `MT5TradeCopier.mq5` in MetaEditor.

## How it works

1. **Provider** polls open positions on a timer and writes `MT5Copier-{account}-positions.csv` into the terminal **Common\Files** folder using an atomic temp-file rename.
2. **Receiver** reads the same file(s), diffs against persisted ticket mappings, and opens/closes/modifies only trades tagged with the configured magic number and `MCP|{providerAccount}|{providerTicket}` comment.
3. **Remote copy**: provider optionally uploads via `SendFTP()`; receiver optionally downloads via `WebRequest()` HTTP GET (with basic auth).

## Terminal permissions

In **Tools → Options → Expert Advisors**:

- Enable **Allow algorithmic trading**
- Enable **Allow WebRequest for listed URL** and add:
  - Receiver HTTP download URL(s)
  - Heartbeat URL (if used)
- For FTP upload: configure **Tools → Options → FTP** (server, login, password, passive mode if needed)

`SendFTP()` only uploads files from the terminal `MQL5/Files` folder; the EA copies the snapshot there automatically before upload.

Local copy between terminals on the same machine uses **Common\Files** (`FILE_COMMON`) — both terminals must run on the same PC (or share that folder).

## Quick setup

### 1) Local copy test (same PC, two terminals)

**Provider terminal**

| Input | Value |
|-------|-------|
| Operating mode | `PROVIDER` |
| Poll interval | `1000` ms |
| Remote upload FTP | `false` |

Attach the EA to any chart on the provider account. Open a small manual trade and confirm a file appears in:

`Terminal\Common\Files\MT5Copier-{providerLogin}-positions.csv`

**Receiver terminal**

| Input | Value |
|-------|-------|
| Operating mode | `RECEIVER` |
| Provider account numbers | provider login, e.g. `12345678` |
| Lot sizing mode | `SAME_AS_PROVIDER` (for testing) |
| Remote download HTTP | `false` |
| Symbol remap | set if broker symbols differ, e.g. `EURUSD=EURUSD.micro` |

Attach on the receiver account. The receiver should open a matching trade within one poll interval.

State mappings are stored in:

`Common\Files\MT5Copier_state_{receiverLogin}_{providerLogin}.csv`

Stop/restart the EA — it should reconcile from this file without duplicating trades.

### 2) Remote copy (different machines)

**Provider**

1. Configure terminal FTP settings.
2. Set **Remote upload FTP** = `true`.
3. Set **FTP remote path** if your server needs a subfolder.
4. Ensure your web/FTP server exposes the uploaded CSV via HTTP for receivers.

**Receiver**

1. Add the download URL to allowed WebRequest URLs.
2. Set **Remote download HTTP** = `true`.
3. Set **HTTP download URL**, e.g. `https://example.com/copier/MT5Copier-{account}-positions.csv`
4. Set HTTP username/password if required.

Test HTTP download first (browser or `curl`) before relying on the EA.

## Input reference (by group)

- **General**: mode, poll interval, magic number, logging
- **Provider**: hedging requirement
- **Receiver**: provider list, lot mode, leverage factor, symbol map, slippage
- **Remote Copy**: FTP upload / HTTP download settings
- **Monitoring**: heartbeat URL + interval
- **Risk**: deviation, age filter, direction filter, exclusions, equity reserve, mass-close alert mode

## Lot sizing

| Mode | Behavior |
|------|----------|
| `SAME_AS_PROVIDER` | Copy provider volume (rounded to symbol step/min/max) |
| `PROPORTIONAL_TO_BALANCE` | Scale by receiver_balance / provider_balance |
| `PROPORTIONAL_TO_FREE_MARGIN` | Scale by receiver_free_margin / provider_free_margin |

Enable **Factor leverage** to multiply by `receiver_leverage / provider_leverage`.

## Known limitations

- **Hedging recommended**: ticket-level copy is designed for hedging accounts. Netting accounts are warned/blocked by default.
- **No raw sockets**: all HTTP must use `WebRequest()` with whitelisted URLs.
- **FTP**: MQL5 only supports uploading a single file via `SendFTP()` using terminal FTP settings (not per-EA FTP credentials).
- **Partial closes**: when provider volume shrinks, receiver closes proportionally; volume increases open an additional slice on the same mapped ticket where possible.
- **Async orders**: execution uses async `CTrade`; mapping waits briefly for the position ticket to appear.
- **Garbled reads**: checksum + row-count header rejects partial writes; receiver skips that poll cycle.
- **Mass close alert**: when multiple losing provider closes happen at once, alert mode sends push/email instead of auto-closing.

## License

Original implementation in this repository (not ported from GPL reference code). Use and modify as you wish; add your own license if you distribute binaries.

## Attribution

Architecture inspired by the community file-sync copier pattern (e.g. [sharing-is-caring](https://github.com/wait4signal/sharing-is-caring)); this codebase is an independent implementation.
