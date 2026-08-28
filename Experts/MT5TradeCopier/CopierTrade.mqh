//+------------------------------------------------------------------+
//| CopierTrade.mqh - Symbol remap, lot sizing, trade execution      |
//+------------------------------------------------------------------+
#ifndef COPIER_TRADE_MQH
#define COPIER_TRADE_MQH

#include <Trade/Trade.mqh>
#include "CopierTypes.mqh"
#include "CopierLogger.mqh"

class CCopierTrade
  {
private:
   CTrade          m_trade;
   CCopierLogger  *m_log;
   long            m_magic;
   string          m_symbol_map_raw;
   string          m_map_from[];
   string          m_map_to[];

   void ParseSymbolMap()
     {
      ArrayResize(m_map_from, 0);
      ArrayResize(m_map_to, 0);
      if(StringLen(m_symbol_map_raw) == 0)
         return;

      string pairs[];
      int count = StringSplit(m_symbol_map_raw, ';', pairs);
      for(int i = 0; i < count; i++)
        {
         string pair = pairs[i];
         StringTrimLeft(pair);
         StringTrimRight(pair);
         if(StringLen(pair) == 0)
            continue;

         string parts[];
         if(StringSplit(pair, '=', parts) != 2)
            continue;

         string from = parts[0];
         string to = parts[1];
         StringTrimLeft(from);
         StringTrimRight(from);
         StringTrimLeft(to);
         StringTrimRight(to);

         int n = ArraySize(m_map_from);
         ArrayResize(m_map_from, n + 1);
         ArrayResize(m_map_to, n + 1);
         m_map_from[n] = from;
         m_map_to[n] = to;
        }
     }

   string BuildComment(const long provider_account, const ulong provider_ticket) const
     {
      return StringFormat("%s|%d|%I64u", COPIER_COMMENT_PREFIX, provider_account, provider_ticket);
     }

   bool IsExcludedTicket(const ulong ticket, const string excluded_csv) const
     {
      if(StringLen(excluded_csv) == 0)
         return false;

      string parts[];
      int count = StringSplit(excluded_csv, ',', parts);
      for(int i = 0; i < count; i++)
        {
         string item = parts[i];
         StringTrimLeft(item);
         StringTrimRight(item);
         if((ulong)StringToInteger(item) == ticket)
            return true;
        }
      return false;
     }

public:
   CCopierTrade()
     {
      m_log = NULL;
      m_magic = 0;
      m_symbol_map_raw = "";
     }

   void Configure(CCopierLogger *logger,
                  const long magic,
                  const int slippage_points,
                  const string symbol_map)
     {
      m_log = logger;
      m_magic = magic;
      m_symbol_map_raw = symbol_map;
      ParseSymbolMap();

      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippage_points);
      m_trade.SetAsyncMode(true);
     }

   string MapSymbol(const string provider_symbol) const
     {
      for(int i = 0; i < ArraySize(m_map_from); i++)
        {
         if(m_map_from[i] == provider_symbol)
            return m_map_to[i];
        }
      return provider_symbol;
     }

   bool EnsureSymbol(const string symbol)
     {
      if(!SymbolSelect(symbol, true))
        {
         if(m_log != NULL)
            m_log.Warn("Symbol not available: " + symbol);
         return false;
        }
      return true;
     }

   double NormalizeVolume(const string symbol, double volume)
     {
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0)
         step = 0.01;

      volume = MathFloor(volume / step) * step;
      if(volume < min_lot)
         volume = min_lot;
      if(volume > max_lot)
         volume = max_lot;

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_VOLUME_DIGITS);
      return NormalizeDouble(volume, digits);
     }

   double CalculateLotSize(const SProviderPosition &pos,
                           const SProviderMeta &meta,
                           const ENUM_COPIER_LOT_MODE lot_mode,
                           const bool factor_leverage)
     {
      double lot = pos.volume;

      if(lot_mode == LOT_PROPORTIONAL_TO_BALANCE)
        {
         if(meta.balance > 0.0)
            lot = pos.volume * (AccountInfoDouble(ACCOUNT_BALANCE) / meta.balance);
        }
      else if(lot_mode == LOT_PROPORTIONAL_TO_FREE_MARGIN)
        {
         if(meta.free_margin > 0.0)
            lot = pos.volume * (AccountInfoDouble(ACCOUNT_MARGIN_FREE) / meta.free_margin);
        }

      if(factor_leverage && meta.leverage > 0)
        {
         lot *= ((double)AccountInfoInteger(ACCOUNT_LEVERAGE) / (double)meta.leverage);
        }

      return lot;
     }

   bool PassesRiskFilters(const SProviderPosition &pos,
                          const string receiver_symbol,
                          const ENUM_COPIER_DIRECTION_FILTER direction_filter,
                          const int max_deviation_points,
                          const int max_age_minutes,
                          const bool ignore_profitable,
                          const string excluded_tickets) const
     {
      if(IsExcludedTicket(pos.ticket, excluded_tickets))
         return false;

      if(direction_filter == DIRECTION_BUY_ONLY && pos.type != POSITION_TYPE_BUY)
         return false;
      if(direction_filter == DIRECTION_SELL_ONLY && pos.type != POSITION_TYPE_SELL)
         return false;

      if(ignore_profitable && pos.profit > 0.0)
         return false;

      if(max_age_minutes > 0)
        {
         int age_sec = (int)(TimeCurrent() - pos.open_time);
         if(age_sec > max_age_minutes * 60)
            return false;
        }

      if(max_deviation_points > 0)
        {
         double current = (pos.type == POSITION_TYPE_BUY)
                          ? SymbolInfoDouble(receiver_symbol, SYMBOL_ASK)
                          : SymbolInfoDouble(receiver_symbol, SYMBOL_BID);
         double point = SymbolInfoDouble(receiver_symbol, SYMBOL_POINT);
         if(point > 0.0)
           {
            double deviation = MathAbs(current - pos.open_price) / point;
            if(deviation > max_deviation_points)
               return false;
           }
        }

      return true;
     }

   bool EquityReserveBreached(const double reserve_percent) const
     {
      if(reserve_percent <= 0.0)
         return false;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double committed = equity - AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double max_committed = equity * (1.0 - reserve_percent / 100.0);
      return (committed >= max_committed);
     }

   bool OpenPosition(const SProviderPosition &pos,
                     const string receiver_symbol,
                     const double volume,
                     ulong &receiver_ticket)
     {
      receiver_ticket = 0;
      if(!EnsureSymbol(receiver_symbol))
         return false;

      double lots = NormalizeVolume(receiver_symbol, volume);
      if(lots <= 0.0)
         return false;

      string comment = BuildComment(pos.provider_account, pos.ticket);
      bool ok = false;

      if(pos.type == POSITION_TYPE_BUY)
         ok = m_trade.Buy(lots, receiver_symbol, 0.0, pos.sl, pos.tp, comment);
      else
         ok = m_trade.Sell(lots, receiver_symbol, 0.0, pos.sl, pos.tp, comment);

      if(!ok)
        {
         if(m_log != NULL)
            m_log.Error(StringFormat("Open failed %s %.2f: %s",
                                     receiver_symbol, volume, m_trade.ResultRetcodeDescription()));
         return false;
        }

      receiver_ticket = m_trade.ResultOrder();
      if(receiver_ticket == 0)
         receiver_ticket = m_trade.ResultDeal();

      // Wait briefly for position ticket in hedging mode.
      for(int i = 0; i < 20; i++)
        {
         if(PositionSelect(receiver_symbol))
           {
            if(PositionGetInteger(POSITION_MAGIC) == m_magic &&
               PositionGetString(POSITION_COMMENT) == comment)
              {
               receiver_ticket = (ulong)PositionGetInteger(POSITION_TICKET);
               break;
              }
           }
         Sleep(50);
        }

      if(m_log != NULL)
         m_log.Info(StringFormat("Opened %s %.2f ticket %I64u <- provider %I64u",
                                 receiver_symbol, lots, receiver_ticket, pos.ticket));
      return (receiver_ticket > 0);
     }

   double ManagedVolumeForProvider(const long provider_account, const ulong provider_ticket) const
     {
      string needle = StringFormat("%s|%d|%I64u", COPIER_COMMENT_PREFIX, provider_account, provider_ticket);
      double total = 0.0;
      int count = PositionsTotal();
      for(int i = 0; i < count; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;
         if(PositionGetString(POSITION_COMMENT) != needle)
            continue;
         total += PositionGetDouble(POSITION_VOLUME);
        }
      return total;
     }

   bool ClosePosition(const ulong receiver_ticket, const double volume = 0.0)
     {
      if(!PositionSelectByTicket(receiver_ticket))
         return false;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double pos_volume = PositionGetDouble(POSITION_VOLUME);
      double close_volume = (volume > 0.0) ? volume : pos_volume;
      close_volume = NormalizeVolume(symbol, MathMin(close_volume, pos_volume));

      bool ok = false;
      if(close_volume + 1e-8 < pos_volume)
         ok = m_trade.PositionClosePartial(receiver_ticket, close_volume);
      else
         ok = m_trade.PositionClose(receiver_ticket);

      if(!ok && m_log != NULL)
         m_log.Error(StringFormat("Close failed ticket %I64u: %s",
                                  receiver_ticket, m_trade.ResultRetcodeDescription()));
      return ok;
     }

   bool ModifyPosition(const ulong receiver_ticket, const double sl, const double tp)
     {
      if(!PositionSelectByTicket(receiver_ticket))
         return false;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(!EnsureSymbol(symbol))
         return false;

      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      if(MathAbs(current_sl - sl) < SymbolInfoDouble(symbol, SYMBOL_POINT) &&
         MathAbs(current_tp - tp) < SymbolInfoDouble(symbol, SYMBOL_POINT))
         return true;

      bool ok = m_trade.PositionModify(receiver_ticket, sl, tp);
      if(!ok && m_log != NULL)
         m_log.Warn(StringFormat("Modify failed ticket %I64u: %s",
                                 receiver_ticket, m_trade.ResultRetcodeDescription()));
      return ok;
     }

   bool IsManagedPosition(const ulong ticket) const
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      if(PositionGetInteger(POSITION_MAGIC) != m_magic)
         return false;
      string comment = PositionGetString(POSITION_COMMENT);
      return (StringFind(comment, COPIER_COMMENT_PREFIX + "|") == 0);
     }

   void SendMassCloseAlert(const int losing_count)
     {
      string msg = StringFormat("MT5TradeCopier: %d losing positions require closing at once.", losing_count);
      SendNotification(msg);
      SendMail("MT5TradeCopier mass close alert", msg);
      if(m_log != NULL)
         m_log.Warn(msg);
     }
  };

#endif // COPIER_TRADE_MQH
