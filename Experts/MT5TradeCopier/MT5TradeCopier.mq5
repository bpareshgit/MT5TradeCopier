//+------------------------------------------------------------------+
//| MT5TradeCopier.mq5                                               |
//| Multi-terminal MT5 trade copier (Provider / Receiver modes)      |
//|                                                                  |
//| Local copy: snapshots in Terminal\Common\Files (FILE_COMMON).    |
//| Remote copy: provider SendFTP + receiver WebRequest HTTP GET.    |
//|                                                                  |
//| SETUP NOTES (see README.md):                                     |
//| - Enable Algo Trading.                                           |
//| - Add HTTP URLs to Tools -> Options -> Expert Advisors.            |
//| - For FTP upload configure Tools -> Options -> FTP tab.          |
//| - Hedging provider accounts require hedging receiver accounts.   |
//+------------------------------------------------------------------+
#property copyright "MT5 Trade Copier"
#property version   "1.00"
#property strict

#include "CopierTypes.mqh"
#include "CopierLogger.mqh"
#include "CopierCsv.mqh"
#include "CopierFileSync.mqh"
#include "CopierRemote.mqh"
#include "CopierState.mqh"
#include "CopierTrade.mqh"

//--- General
input group "=== General ==="
input ENUM_COPIER_MODE          InpMode                 = COPIER_RECEIVER;          // Operating mode
input int                       InpPollIntervalMs       = 1000;                     // Poll interval (ms)
input long                      InpMagicNumber          = 56001501;                 // Magic number for copied trades
input ENUM_COPIER_LOG_LEVEL     InpLogLevel             = COPIER_LOG_INFO;          // Log level
input bool                      InpLogToFile            = true;                     // Write rotating log file
input int                       InpLogMaxKb             = 512;                      // Rotate log after (KB)

//--- Provider
input group "=== Provider ==="
input bool                      InpProviderRequireHedging = true;                   // Refuse if account is netting

//--- Receiver
input group "=== Receiver ==="
input string                    InpProviderAccounts     = "12345678";               // Provider account numbers (comma-separated)
input ENUM_COPIER_LOT_MODE      InpLotMode              = LOT_SAME_AS_PROVIDER;     // Lot sizing mode
input bool                      InpFactorLeverage       = false;                    // Factor account leverage into lot sizing
input string                    InpSymbolMap            = "";                       // Symbol remap (EURUSD=EURUSD.micro;GBPUSD=GBPUSDm)
input int                       InpSlippagePoints       = 20;                       // Max slippage (points) for orders
input bool                      InpReceiverRequireHedging = true;                     // Refuse if account is netting

//--- Remote copy
input group "=== Remote Copy ==="
input bool                      InpRemoteUploadFtp       = false;                     // Provider: upload snapshot via FTP
input string                    InpFtpRemotePath         = "";                        // Provider: FTP remote path (SendFTP)
input bool                      InpRemoteDownloadHttp    = false;                     // Receiver: download snapshot via HTTP
input string                    InpHttpDownloadUrl       = "";                        // Receiver: snapshot URL (per provider; use {account} token)
input string                    InpHttpUsername          = "";                        // HTTP basic auth username
input string                    InpHttpPassword          = "";                        // HTTP basic auth password
input int                       InpHttpTimeoutMs         = 5000;                      // HTTP timeout (ms)
input int                       InpRemoteMinIntervalMs   = 2000;                      // Min interval between remote I/O (ms)

//--- Monitoring
input group "=== Monitoring ==="
input string                    InpHeartbeatUrl          = "";                        // Heartbeat URL (HTTP GET)
input int                       InpHeartbeatIntervalSec  = 60;                        // Heartbeat interval (sec)

//--- Risk
input group "=== Risk ==="
input int                       InpMaxPriceDeviationPts  = 50;                        // Skip if price deviates more than (points)
input int                       InpMaxTradeAgeMinutes    = 0;                         // Skip trades older than (minutes, 0=off)
input bool                      InpIgnoreProfitable      = false;                     // Skip trades already in profit on provider
input ENUM_COPIER_DIRECTION_FILTER InpDirectionFilter    = DIRECTION_BOTH;            // Direction filter
input string                    InpExcludedTickets       = "";                        // Excluded provider tickets (comma-separated)
input double                    InpEquityReservePercent  = 10.0;                      // Reserve equity % (stop copying when breached)
input ENUM_COPIER_MASS_CLOSE_MODE InpMassCloseMode       = MASS_CLOSE_AUTO;           // Multiple losing closes at once

//--- Module instances
CCopierLogger   g_logger;
CCopierFileSync g_files;
CCopierRemote   g_remote;
CCopierTrade    g_trade;

long            g_provider_accounts[];
bool            g_initialized = false;
uint            g_timer_ms = 0;

//+------------------------------------------------------------------+
//| Parse comma-separated account list                               |
//+------------------------------------------------------------------+
bool ParseProviderAccounts(const string csv)
  {
   ArrayResize(g_provider_accounts, 0);
   if(StringLen(csv) == 0)
      return false;

   string parts[];
   int count = StringSplit(csv, ',', parts);
   for(int i = 0; i < count; i++)
     {
      string item = parts[i];
      StringTrimLeft(item);
      StringTrimRight(item);
      if(StringLen(item) == 0)
         continue;

      long account = (long)StringToInteger(item);
      if(account <= 0)
         continue;

      int n = ArraySize(g_provider_accounts);
      ArrayResize(g_provider_accounts, n + 1);
      g_provider_accounts[n] = account;
     }
   return (ArraySize(g_provider_accounts) > 0);
  }

//+------------------------------------------------------------------+
//| Account margin mode helpers                                      |
//+------------------------------------------------------------------+
bool IsHedgingAccount()
  {
   return ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) ==
           ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }

bool ValidateAccountType()
  {
   bool hedging = IsHedgingAccount();

   if(InpMode == COPIER_PROVIDER && InpProviderRequireHedging && !hedging)
     {
      g_logger.Error("Provider requires a hedging account. Disable netting or use hedging account.");
      return false;
     }

   if(InpMode == COPIER_RECEIVER && InpReceiverRequireHedging && !hedging)
     {
      g_logger.Error("Receiver requires a hedging account to mirror individual tickets safely.");
      return false;
     }

   if(!hedging)
      g_logger.Warn("Netting account detected. Ticket-level copy is limited; hedging is strongly recommended.");

   return true;
  }

//+------------------------------------------------------------------+
//| Provider: collect open positions                                 |
//+------------------------------------------------------------------+
int CollectProviderPositions(SProviderPosition &positions[])
  {
   ArrayResize(positions, 0);
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      SProviderPosition pos;
      pos.provider_account = AccountInfoInteger(ACCOUNT_LOGIN);
      pos.ticket = ticket;
      pos.symbol = PositionGetString(POSITION_SYMBOL);
      pos.type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      pos.volume = PositionGetDouble(POSITION_VOLUME);
      pos.open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      pos.open_time = (datetime)PositionGetInteger(POSITION_TIME);
      pos.sl = PositionGetDouble(POSITION_SL);
      pos.tp = PositionGetDouble(POSITION_TP);
      pos.profit = PositionGetDouble(POSITION_PROFIT);

      int n = ArraySize(positions);
      ArrayResize(positions, n + 1);
      positions[n] = pos;
     }
   return ArraySize(positions);
  }

//+------------------------------------------------------------------+
//| Provider tick: write snapshot (+ optional FTP upload)              |
//+------------------------------------------------------------------+
void RunProviderCycle()
  {
   SProviderPosition positions[];
   CollectProviderPositions(positions);

   string body;
   long account = AccountInfoInteger(ACCOUNT_LOGIN);
   if(!g_files.WriteProviderSnapshot(account, positions, body))
      return;

   if(InpRemoteUploadFtp)
     {
      string local_name;
      if(g_files.CopySnapshotForFtp(account, local_name))
        {
         g_remote.FtpUpload(local_name, InpFtpRemotePath);
        }
     }
  }

//+------------------------------------------------------------------+
//| Build per-provider HTTP URL (supports {account} placeholder)     |
//+------------------------------------------------------------------+
string ProviderDownloadUrl(const long provider_account)
  {
   string url = InpHttpDownloadUrl;
   if(StringFind(url, "{account}") >= 0)
      StringReplace(url, "{account}", (string)provider_account);
   return url;
  }

//+------------------------------------------------------------------+
//| Receiver: optionally download remote snapshot before local read    |
//+------------------------------------------------------------------+
bool EnsureProviderSnapshot(const long provider_account)
  {
   if(!InpRemoteDownloadHttp)
      return true;

   if(!g_remote.ShouldDownload(InpRemoteMinIntervalMs))
      return true;

   g_remote.MarkDownloadAttempt();

   string url = ProviderDownloadUrl(provider_account);
   if(StringLen(url) == 0)
     {
      g_logger.Warn("Remote HTTP enabled but URL is empty.");
      return false;
     }

   string content;
   if(!g_remote.HttpDownload(url, InpHttpUsername, InpHttpPassword, InpHttpTimeoutMs, content))
      return false;

   if(!g_files.WriteDownloadedSnapshot(provider_account, content))
     {
      g_logger.Error("Failed to store downloaded snapshot for provider " + (string)provider_account);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Receiver sync algorithm (core diff-and-reconcile)                |
//|                                                                  |
//| For each provider account:                                       |
//| 1) Load persisted ticket mappings (provider_ticket->receiver).   |
//| 2) Read provider snapshot CSV from Common\Files.                 |
//| 3) For each provider position:                                   |
//|    - existing mapping: adjust volume / SL / TP                   |
//|    - no mapping: open new managed trade if risk filters pass     |
//| 4) For mappings missing from snapshot: close receiver trade        |
//| 5) Save updated mappings to state file                           |
//+------------------------------------------------------------------+
void SyncProviderAccount(const long provider_account)
  {
   if(!EnsureProviderSnapshot(provider_account))
      return;

   SProviderPosition provider_positions[];
   SProviderMeta meta;
   meta.valid = false;

   if(!g_files.ReadProviderSnapshot(provider_account, provider_positions, meta))
     {
      g_logger.Debug("No valid snapshot for provider " + (string)provider_account);
      return;
     }

   if(InpReceiverRequireHedging && meta.valid && !meta.hedging)
     {
      g_logger.Warn(StringFormat("Provider %d snapshot indicates netting account; skipping.", provider_account));
      return;
     }

   CCopierState state;
   state.SetLogger(&g_logger);
   state.SetContext(AccountInfoInteger(ACCOUNT_LOGIN), provider_account);
   state.Load();
   state.ReconcileOpenPositions(InpMagicNumber);

   // Index provider positions by ticket for O(1) lookup.
   ulong provider_tickets[];
   int provider_index[];
   ArrayResize(provider_tickets, 0);
   ArrayResize(provider_index, 0);

   for(int i = 0; i < ArraySize(provider_positions); i++)
     {
      int n = ArraySize(provider_tickets);
      ArrayResize(provider_tickets, n + 1);
      ArrayResize(provider_index, n + 1);
      provider_tickets[n] = provider_positions[i].ticket;
      provider_index[n] = i;
     }

   // Step 3: reconcile open / modified provider positions.
   for(int i = 0; i < ArraySize(provider_positions); i++)
     {
      SProviderPosition pos = provider_positions[i];
      pos.provider_account = provider_account;

      int map_idx = state.FindByProviderTicket(pos.ticket);
      string receiver_symbol = g_trade.MapSymbol(pos.symbol);

      if(map_idx >= 0)
        {
         STicketMapping mapping;
         state.Get(map_idx, mapping);

         if(!PositionSelectByTicket(mapping.receiver_ticket))
           {
            state.RemoveByIndex(map_idx);
            continue;
           }

         double receiver_volume = g_trade.ManagedVolumeForProvider(provider_account, pos.ticket);
         double target_volume = g_trade.CalculateLotSize(pos, meta, InpLotMode, InpFactorLeverage);
         target_volume = g_trade.NormalizeVolume(receiver_symbol, target_volume);

         // Partial close when provider volume shrinks.
         if(pos.volume + 1e-8 < mapping.provider_volume && mapping.provider_volume > 0.0)
           {
            double ratio = pos.volume / mapping.provider_volume;
            double desired = g_trade.NormalizeVolume(receiver_symbol, receiver_volume * ratio);
            double close_amount = receiver_volume - desired;
            if(close_amount > 0.0)
               g_trade.ClosePosition(mapping.receiver_ticket, close_amount);
            receiver_volume = g_trade.ManagedVolumeForProvider(provider_account, pos.ticket);
           }
         // Additional volume when provider position grows.
         else if(pos.volume > mapping.provider_volume + 1e-8)
           {
            double added_provider = pos.volume - mapping.provider_volume;
            SProviderPosition delta = pos;
            delta.volume = added_provider;
            double open_lot = g_trade.CalculateLotSize(delta, meta, InpLotMode, InpFactorLeverage);

            if(!g_trade.EquityReserveBreached(InpEquityReservePercent))
              {
               ulong new_ticket = 0;
               if(g_trade.OpenPosition(delta, receiver_symbol, open_lot, new_ticket))
                  receiver_volume = g_trade.ManagedVolumeForProvider(provider_account, pos.ticket);
              }
           }

         if(PositionSelectByTicket(mapping.receiver_ticket))
            g_trade.ModifyPosition(mapping.receiver_ticket, pos.sl, pos.tp);

         mapping.provider_volume = pos.volume;
         mapping.copied_volume = receiver_volume;
         state.Upsert(mapping);
         continue;
        }

      // New provider position -> open managed receiver trade.
      if(g_trade.EquityReserveBreached(InpEquityReservePercent))
        {
         g_logger.Warn("Equity reserve breached; skipping new copies.");
         continue;
        }

      if(!g_trade.PassesRiskFilters(pos,
                                    receiver_symbol,
                                    InpDirectionFilter,
                                    InpMaxPriceDeviationPts,
                                    InpMaxTradeAgeMinutes,
                                    InpIgnoreProfitable,
                                    InpExcludedTickets))
        {
         g_logger.Debug(StringFormat("Skipped provider ticket %I64u by risk filters", pos.ticket));
         continue;
        }

      double lot = g_trade.CalculateLotSize(pos, meta, InpLotMode, InpFactorLeverage);
      ulong receiver_ticket = 0;
      if(!g_trade.OpenPosition(pos, receiver_symbol, lot, receiver_ticket))
         continue;

      STicketMapping mapping;
      mapping.provider_account = provider_account;
      mapping.provider_ticket = pos.ticket;
      mapping.receiver_ticket = receiver_ticket;
      mapping.provider_symbol = pos.symbol;
      mapping.receiver_symbol = receiver_symbol;
      mapping.provider_volume = pos.volume;
      mapping.copied_volume = lot;
      state.Upsert(mapping);
     }

   // Step 4: provider positions that disappeared -> close receiver copies.
   ulong close_tickets[];
   int losing_close_count = 0;

   for(int i = state.Count() - 1; i >= 0; i--)
     {
      STicketMapping mapping;
      state.Get(i, mapping);

      bool still_open = false;
      for(int p = 0; p < ArraySize(provider_tickets); p++)
        {
         if(provider_tickets[p] == mapping.provider_ticket)
           {
            still_open = true;
            break;
           }
        }

      if(still_open)
         continue;

      // Close every managed receiver leg tagged to this provider ticket.
      string needle = StringFormat("%s|%d|%I64u",
                                   COPIER_COMMENT_PREFIX,
                                   provider_account,
                                   mapping.provider_ticket);
      bool any_found = false;
      int total = PositionsTotal();
      for(int p = total - 1; p >= 0; p--)
        {
         ulong ticket = PositionGetTicket(p);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
            continue;
         if(PositionGetString(POSITION_COMMENT) != needle)
            continue;

         any_found = true;
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit < 0.0)
            losing_close_count++;

         int n = ArraySize(close_tickets);
         ArrayResize(close_tickets, n + 1);
         close_tickets[n] = ticket;
        }

      if(!any_found)
        {
         state.RemoveByIndex(i);
         continue;
        }
     }

   if(losing_close_count > 1 && InpMassCloseMode == MASS_CLOSE_ALERT)
     {
      g_trade.SendMassCloseAlert(losing_close_count);
     }
   else
     {
      for(int c = 0; c < ArraySize(close_tickets); c++)
         g_trade.ClosePosition(close_tickets[c]);

      for(int i = state.Count() - 1; i >= 0; i--)
        {
         STicketMapping mapping;
         state.Get(i, mapping);

         bool still_open = false;
         for(int p = 0; p < ArraySize(provider_tickets); p++)
           {
            if(provider_tickets[p] == mapping.provider_ticket)
              {
               still_open = true;
               break;
              }
           }
         if(!still_open)
            state.RemoveByIndex(i);
        }
     }

   state.Save();
  }

//+------------------------------------------------------------------+
//| Receiver tick: sync all configured providers                     |
//+------------------------------------------------------------------+
void RunReceiverCycle()
  {
   for(int i = 0; i < ArraySize(g_provider_accounts); i++)
      SyncProviderAccount(g_provider_accounts[i]);
  }

//+------------------------------------------------------------------+
//| Timer callback (non-blocking polling)                            |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!g_initialized)
      return;

   if(InpMode == COPIER_PROVIDER)
      RunProviderCycle();
   else
      RunReceiverCycle();

   g_remote.SendHeartbeat(InpHeartbeatUrl, InpHeartbeatIntervalSec, InpHttpTimeoutMs);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_logger.Configure(InpLogLevel, InpLogToFile, COPIER_FILE_PREFIX + "-log.txt", InpLogMaxKb);
   g_files.SetLogger(&g_logger);
   g_remote.SetLogger(&g_logger);
   g_trade.Configure(&g_logger, InpMagicNumber, InpSlippagePoints, InpSymbolMap);

   if(!ValidateAccountType())
      return INIT_FAILED;

   if(InpMode == COPIER_RECEIVER && !ParseProviderAccounts(InpProviderAccounts))
     {
      g_logger.Error("Receiver mode requires at least one provider account number.");
      return INIT_FAILED;
     }

   int interval = InpPollIntervalMs;
   if(interval < 200)
     {
      g_logger.Warn("Poll interval raised to 200ms minimum.");
      interval = 200;
     }

   g_timer_ms = (uint)interval;
   if(!EventSetMillisecondTimer(g_timer_ms))
     {
      int sec = (int)MathMax(1, MathCeil(interval / 1000.0));
      if(!EventSetTimer(sec))
        {
         g_logger.Error("Failed to start timer.");
         return INIT_FAILED;
        }
      g_logger.Warn(StringFormat("Millisecond timer unavailable; using %d second timer.", sec));
     }

   g_initialized = true;
   g_logger.Info(StringFormat("MT5TradeCopier started in %s mode (poll %d ms)",
                              (InpMode == COPIER_PROVIDER ? "PROVIDER" : "RECEIVER"),
                              interval));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_initialized = false;
   g_logger.Info("MT5TradeCopier stopped.");
  }

//+------------------------------------------------------------------+
//| OnTick is intentionally empty; timer drives sync work.           |
//+------------------------------------------------------------------+
void OnTick()
  {
  }

//+------------------------------------------------------------------+
