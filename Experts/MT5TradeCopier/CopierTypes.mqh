//+------------------------------------------------------------------+
//| CopierTypes.mqh - Shared types and constants for MT5TradeCopier  |
//+------------------------------------------------------------------+
#ifndef COPIER_TYPES_MQH
#define COPIER_TYPES_MQH

#define COPIER_FILE_PREFIX     "MT5Copier"
#define COPIER_FILE_VERSION    "1"
#define COPIER_COMMENT_PREFIX  "MCP"
#define COPIER_STATE_PREFIX    "MT5Copier_state"

enum ENUM_COPIER_MODE
  {
   COPIER_PROVIDER = 0,
   COPIER_RECEIVER = 1
  };

enum ENUM_COPIER_LOG_LEVEL
  {
   COPIER_LOG_NONE  = 0,
   COPIER_LOG_ERROR = 1,
   COPIER_LOG_WARN  = 2,
   COPIER_LOG_INFO  = 3,
   COPIER_LOG_DEBUG = 4
  };

enum ENUM_COPIER_LOT_MODE
  {
   LOT_SAME_AS_PROVIDER           = 0,
   LOT_PROPORTIONAL_TO_BALANCE    = 1,
   LOT_PROPORTIONAL_TO_FREE_MARGIN = 2
  };

enum ENUM_COPIER_DIRECTION_FILTER
  {
   DIRECTION_BOTH      = 0,
   DIRECTION_BUY_ONLY  = 1,
   DIRECTION_SELL_ONLY = 2
  };

enum ENUM_COPIER_MASS_CLOSE_MODE
  {
   MASS_CLOSE_AUTO   = 0,
   MASS_CLOSE_ALERT  = 1
  };

// Snapshot of one provider position (parsed from CSV).
struct SProviderPosition
  {
   long              provider_account;
   ulong             ticket;
   string            symbol;
   ENUM_POSITION_TYPE type;
   double            volume;
   double            open_price;
   datetime          open_time;
   double            sl;
   double            tp;
   double            profit;
  };

// Provider file header metadata used for lot scaling and validation.
struct SProviderMeta
  {
   long              account;
   double            balance;
   double            equity;
   double            free_margin;
   int               leverage;
   bool              hedging;
   datetime          snapshot_time;
   int               row_count;
   uint              checksum;
   bool              valid;
  };

// Persisted mapping between provider and receiver tickets.
struct STicketMapping
  {
   long              provider_account;
   ulong             provider_ticket;
   ulong             receiver_ticket;
   string            provider_symbol;
   string            receiver_symbol;
   double            provider_volume;
   double            copied_volume;
  };

#endif // COPIER_TYPES_MQH
