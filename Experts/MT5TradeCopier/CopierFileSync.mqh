//+------------------------------------------------------------------+
//| CopierFileSync.mqh - Atomic snapshot read/write in Common\Files  |
//+------------------------------------------------------------------+
#ifndef COPIER_FILE_SYNC_MQH
#define COPIER_FILE_SYNC_MQH

#include "CopierTypes.mqh"
#include "CopierCsv.mqh"
#include "CopierLogger.mqh"

class CCopierFileSync
  {
private:
   CCopierLogger *m_log;
   int            m_status_rows;
   bool           m_status_ok;
   long           m_status_account;
   datetime       m_status_time;
   string         m_status_text;

   string SnapshotName(const long account) const
     {
      return StringFormat("%s-%d-positions.csv", COPIER_FILE_PREFIX, account);
     }

   string TempName(const long account) const
     {
      return SnapshotName(account) + ".tmp";
     }

   bool ReadAllText(const string filename, string &content, const bool common = true)
     {
      content = "";
      int flags = FILE_READ | FILE_TXT | FILE_ANSI;
      if(common)
         flags |= FILE_COMMON;

      if(!FileIsExist(filename, common ? FILE_COMMON : 0))
         return false;

      int handle = FileOpen(filename, flags);
      if(handle == INVALID_HANDLE)
         return false;

      while(!FileIsEnding(handle))
        {
         content += FileReadString(handle);
         if(!FileIsEnding(handle))
            content += "\n";
        }
      FileClose(handle);
      return StringLen(content) > 0;
     }

   bool WriteAllText(const string filename, const string content, const bool common = true)
     {
      int flags = FILE_WRITE | FILE_TXT | FILE_ANSI;
      if(common)
         flags |= FILE_COMMON;

      int handle = FileOpen(filename, flags);
      if(handle == INVALID_HANDLE)
         return false;

      FileWriteString(handle, content);
      FileClose(handle);
      return true;
     }

   bool ParseHeaderLine(const string line, SProviderMeta &meta)
     {
      if(StringFind(line, "# account:") == 0)
        {
         meta.account = (long)StringToInteger(StringSubstr(line, 10));
         return true;
        }
      if(StringFind(line, "# balance:") == 0)
        {
         meta.balance = StringToDouble(StringSubstr(line, 10));
         return true;
        }
      if(StringFind(line, "# equity:") == 0)
        {
         meta.equity = StringToDouble(StringSubstr(line, 9));
         return true;
        }
      if(StringFind(line, "# free_margin:") == 0)
        {
         meta.free_margin = StringToDouble(StringSubstr(line, 14));
         return true;
        }
      if(StringFind(line, "# leverage:") == 0)
        {
         meta.leverage = (int)StringToInteger(StringSubstr(line, 11));
         return true;
        }
      if(StringFind(line, "# hedging:") == 0)
        {
         meta.hedging = (StringSubstr(line, 10) == "1");
         return true;
        }
      if(StringFind(line, "# ts:") == 0)
        {
         meta.snapshot_time = (datetime)StringToInteger(StringSubstr(line, 5));
         return true;
        }
      if(StringFind(line, "# rows:") == 0)
        {
         meta.row_count = (int)StringToInteger(StringSubstr(line, 7));
         return true;
        }
      if(StringFind(line, "# checksum:") == 0)
        {
         meta.checksum = (uint)StringToInteger(StringSubstr(line, 11));
         return true;
        }
      return false;
     }

public:
   CCopierFileSync()
     {
      m_log = NULL;
      m_status_rows = 0;
      m_status_ok = false;
      m_status_account = 0;
      m_status_time = 0;
      m_status_text = "STARTING";
     }

   void SetLogger(CCopierLogger *logger)
     {
      m_log = logger;
     }

   int LastStatusRows() const { return m_status_rows; }
   bool LastStatusOk() const { return m_status_ok; }
   long LastStatusAccount() const { return m_status_account; }
   datetime LastStatusTime() const { return m_status_time; }
   string LastStatusText() const { return m_status_text; }

   string GetSnapshotFilename(const long account) const
     {
      return SnapshotName(account);
     }

   // Full Windows path to Terminal\Common\Files\ (shared by all MT5 instances on this PC).
   string CommonFilesDir() const
     {
      string path = TerminalInfoString(TERMINAL_COMMONDATA_PATH);
      if(StringLen(path) == 0)
         return "Terminal\\Common\\Files\\";
      if(StringGetCharacter(path, StringLen(path) - 1) != '\\')
         path += "\\";
      path += "Files\\";
      return path;
     }

   string SnapshotFullPath(const long account) const
     {
      return CommonFilesDir() + SnapshotName(account);
     }

   string StateFullPath(const long receiver_account, const long provider_account) const
     {
      return CommonFilesDir() +
             StringFormat("%s_%d_%d.csv", COPIER_STATE_PREFIX, receiver_account, provider_account);
     }

   string LogFullPath() const
     {
      return CommonFilesDir() + COPIER_FILE_PREFIX + "-log.txt";
     }

   // Provider: collect open positions and write atomically to Common\Files.
   bool WriteProviderSnapshot(const long account,
                              SProviderPosition &positions[],
                              string &written_body)
     {
      int count = ArraySize(positions);
      string body = "";
      body += "ticket,symbol,type,volume,open_price,open_time,sl,tp,profit\n";

      for(int i = 0; i < count; i++)
        {
         body += StringFormat("%I64u,%s,%d,%.8f,%.8f,%I64d,%.8f,%.8f,%.2f\n",
                              positions[i].ticket,
                              CsvEscape(positions[i].symbol),
                              (int)positions[i].type,
                              positions[i].volume,
                              positions[i].open_price,
                              (long)positions[i].open_time,
                              positions[i].sl,
                              positions[i].tp,
                              positions[i].profit);
        }

      uint checksum = CsvChecksum(body);
      string header = "";
      header += "# MT5TradeCopier v" + COPIER_FILE_VERSION + "\n";
      header += "# account:" + (string)account + "\n";
      header += "# balance:" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
      header += "# equity:" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
      header += "# free_margin:" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + "\n";
      header += "# leverage:" + (string)AccountInfoInteger(ACCOUNT_LEVERAGE) + "\n";
      header += "# hedging:" + (string)(IsHedgingAccount() ? 1 : 0) + "\n";
      header += "# ts:" + (string)(long)TimeCurrent() + "\n";
      header += "# rows:" + (string)count + "\n";
      header += "# checksum:" + (string)checksum + "\n";

      string full = header + body;
      written_body = full;

      string temp = TempName(account);
      string final_name = SnapshotName(account);

      if(!WriteAllText(temp, full, true))
        {
         if(m_log != NULL)
            m_log.Error("Failed writing temp snapshot: " + temp);
         return false;
        }

      if(FileIsExist(final_name, FILE_COMMON))
         FileDelete(final_name, FILE_COMMON);

      if(!FileMove(temp, FILE_COMMON, final_name, FILE_COMMON))
        {
         // Fallback: direct overwrite if move is unavailable.
         if(!WriteAllText(final_name, full, true))
           {
            if(m_log != NULL)
               m_log.Error("Failed publishing snapshot: " + final_name);
            return false;
           }
        }

      m_status_ok = true;
      m_status_rows = count;
      m_status_account = account;
      m_status_time = TimeCurrent();
      m_status_text = (count > 0) ? "PUBLISHED" : "PUBLISHED (0 trades)";

      if(m_log != NULL)
        {
         m_log.Debug(StringFormat("Wrote snapshot %s (%d rows)", final_name, count));
         LogProviderHandshake(account, count, TimeCurrent());
        }
      return true;
     }

   // INFO on first publish and when row count changes; periodic reminder every 60s.
   void LogProviderHandshake(const long account, const int rows, const datetime snapshot_ts)
     {
      if(m_log == NULL)
         return;

      static long    s_account = 0;
      static int     s_last_rows = -1;
      static datetime s_last_info = 0;
      static bool    s_announced = false;

      if(account != s_account)
        {
         s_account = account;
         s_last_rows = -1;
         s_announced = false;
         s_last_info = 0;
        }

      datetime now = TimeCurrent();
      bool first = !s_announced;
      bool changed = (rows != s_last_rows);
      bool periodic = (s_last_info == 0 || (now - s_last_info) >= 60);

      if(!first && !changed && !periodic)
         return;

      if(first)
        {
         m_log.Info("[HANDSHAKE] PROVIDER active — writing position snapshot for receivers");
         m_log.Info("[PATH] Snapshot CSV: " + SnapshotFullPath(account));
         s_announced = true;
        }

      if(changed || first)
         m_log.Info(StringFormat("[HANDSHAKE] PROVIDER published %d open position(s) for account %d",
                                 rows, account));
      else if(periodic)
         m_log.Info(StringFormat("[HANDSHAKE] PROVIDER heartbeat — %d position(s), account %d",
                                 rows, account));

      s_last_rows = rows;
      s_last_info = now;
     }

   // INFO when receiver first reads a valid snapshot; WARN if file missing (throttled).
   void LogReceiverHandshake(const long provider_account,
                             const bool read_ok,
                             const SProviderMeta &meta,
                             const int position_count)
     {
      if(m_log == NULL)
         return;

      static long     s_providers[];
      static bool     s_linked[];
      static int      s_last_rows[];
      static datetime s_last_missing[];
      static int      s_count = 0;

      int idx = -1;
      for(int i = 0; i < s_count; i++)
        {
         if(s_providers[i] == provider_account)
           {
            idx = i;
            break;
           }
        }
      if(idx < 0)
        {
         idx = s_count;
         s_count++;
         ArrayResize(s_providers, s_count);
         ArrayResize(s_linked, s_count);
         ArrayResize(s_last_rows, s_count);
         ArrayResize(s_last_missing, s_count);
         s_providers[idx] = provider_account;
         s_linked[idx] = false;
         s_last_rows[idx] = -1;
         s_last_missing[idx] = 0;
        }

      if(!read_ok)
        {
         m_status_ok = false;
         m_status_rows = 0;
         m_status_account = provider_account;
         m_status_time = TimeCurrent();
         m_status_text = "WAITING FOR CSV";

         datetime now = TimeCurrent();
         if(s_last_missing[idx] == 0 || (now - s_last_missing[idx]) >= 60)
           {
            m_log.Warn(StringFormat("[HANDSHAKE] RECEIVER waiting — snapshot not found for provider %d",
                                    provider_account));
            m_log.Warn("[PATH] Expected file: " + SnapshotFullPath(provider_account));
            m_log.Warn("[PATH] Fix: attach PROVIDER copier on account " + (string)provider_account +
                       " (same PC → Common\\Files is shared)");
            s_last_missing[idx] = now;
           }
         s_linked[idx] = false;
         return;
        }

      s_last_missing[idx] = 0;
      bool first_link = !s_linked[idx];
      bool rows_changed = (position_count != s_last_rows[idx]);

      m_status_ok = true;
      m_status_rows = position_count;
      m_status_account = provider_account;
      m_status_time = TimeCurrent();
      m_status_text = (position_count > 0) ? "LINKED" : "LINKED (0 trades)";

      if(first_link)
        {
         m_log.Info(StringFormat("[HANDSHAKE] RECEIVER linked to provider %d — CSV read OK",
                                 provider_account));
         m_log.Info("[PATH] Reading snapshot: " + SnapshotFullPath(provider_account));
         s_linked[idx] = true;
        }

      if(first_link || rows_changed)
        {
         m_log.Info(StringFormat("[HANDSHAKE] RECEIVER synced %d position(s) from provider %d (snapshot %s)",
                                 position_count,
                                 provider_account,
                                 TimeToString(meta.snapshot_time, TIME_DATE | TIME_SECONDS)));
         s_last_rows[idx] = position_count;
        }
     }

   // Receiver: read and parse provider snapshot with checksum validation.
   bool ReadProviderSnapshot(const long account,
                             SProviderPosition &positions[],
                             SProviderMeta &meta)
     {
      ArrayResize(positions, 0);
      meta.valid = false;

      string content;
      if(!ReadAllText(SnapshotName(account), content, true))
        {
         if(m_log != NULL)
           {
            SProviderMeta empty_meta;
            empty_meta.valid = false;
            LogReceiverHandshake(account, false, empty_meta, 0);
           }
         return false;
        }

      string lines[];
      int line_count = StringSplit(content, '\n', lines);
      if(line_count < 2)
         return false;

      for(int i = 0; i < line_count; i++)
        {
         string line = lines[i];
         StringTrimLeft(line);
         StringTrimRight(line);
         if(StringLen(line) == 0)
            continue;
         if(StringFind(line, "#") == 0)
           {
            ParseHeaderLine(line, meta);
            continue;
           }
         if(StringFind(line, "ticket,symbol") == 0)
            continue;

         string parts[];
         SplitCsvLine(line, parts);
         if(ArraySize(parts) < 9)
            continue;

         SProviderPosition pos;
         pos.provider_account = account;
         pos.ticket = (ulong)StringToInteger(parts[0]);
         pos.symbol = parts[1];
         pos.type = (ENUM_POSITION_TYPE)StringToInteger(parts[2]);
         pos.volume = StringToDouble(parts[3]);
         pos.open_price = StringToDouble(parts[4]);
         pos.open_time = (datetime)StringToInteger(parts[5]);
         pos.sl = StringToDouble(parts[6]);
         pos.tp = StringToDouble(parts[7]);
         pos.profit = StringToDouble(parts[8]);

         int n = ArraySize(positions);
         ArrayResize(positions, n + 1);
         positions[n] = pos;
        }

      // Rebuild body for checksum verification.
      string body = "ticket,symbol,type,volume,open_price,open_time,sl,tp,profit\n";
      for(int i = 0; i < ArraySize(positions); i++)
        {
         body += StringFormat("%I64u,%s,%d,%.8f,%.8f,%I64d,%.8f,%.8f,%.2f\n",
                              positions[i].ticket,
                              CsvEscape(positions[i].symbol),
                              (int)positions[i].type,
                              positions[i].volume,
                              positions[i].open_price,
                              (long)positions[i].open_time,
                              positions[i].sl,
                              positions[i].tp,
                              positions[i].profit);
        }

      uint checksum = CsvChecksum(body);
      if(meta.checksum != 0 && checksum != meta.checksum)
        {
         if(m_log != NULL)
            m_log.Warn(StringFormat("Checksum mismatch for provider %d; skipping partial read", account));
         ArrayResize(positions, 0);
         return false;
        }

      if(meta.row_count > 0 && meta.row_count != ArraySize(positions))
        {
         if(m_log != NULL)
            m_log.Warn(StringFormat("Row count mismatch for provider %d; skipping read", account));
         ArrayResize(positions, 0);
         return false;
        }

      meta.valid = true;
      if(m_log != NULL)
         LogReceiverHandshake(account, true, meta, ArraySize(positions));
      return true;
     }

   // Copy snapshot from Common to terminal Files folder for SendFTP().
   bool CopySnapshotForFtp(const long account, string &local_name)
     {
      string content;
      if(!ReadAllText(SnapshotName(account), content, true))
         return false;

      local_name = SnapshotName(account);
      return WriteAllText(local_name, content, false);
     }

   bool WriteDownloadedSnapshot(const long account, const string content)
     {
      string temp = TempName(account);
      if(!WriteAllText(temp, content, true))
         return false;

      string final_name = SnapshotName(account);
      if(FileIsExist(final_name, FILE_COMMON))
         FileDelete(final_name, FILE_COMMON);

      if(!FileMove(temp, FILE_COMMON, final_name, FILE_COMMON))
         return WriteAllText(final_name, content, true);
      return true;
     }

   static bool IsHedgingAccount()
     {
      return ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) ==
              ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
     }
  };

#endif // COPIER_FILE_SYNC_MQH
