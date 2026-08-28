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
   void SetLogger(CCopierLogger *logger)
     {
      m_log = logger;
     }

   string GetSnapshotFilename(const long account) const
     {
      return SnapshotName(account);
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

      if(m_log != NULL)
         m_log.Debug(StringFormat("Wrote snapshot %s (%d rows)", final_name, count));
      return true;
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
         return false;

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
