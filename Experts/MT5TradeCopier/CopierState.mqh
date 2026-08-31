//+------------------------------------------------------------------+
//| CopierState.mqh - Persist provider ticket -> receiver ticket map  |
//+------------------------------------------------------------------+
#ifndef COPIER_STATE_MQH
#define COPIER_STATE_MQH

#include "CopierTypes.mqh"
#include "CopierCsv.mqh"
#include "CopierLogger.mqh"

class CCopierState
  {
private:
   CCopierLogger   *m_log;
   STicketMapping  m_mappings[];
   string           m_filename;

   string StateFilename(const long receiver_account, const long provider_account) const
     {
      return StringFormat("%s_%d_%d.csv", COPIER_STATE_PREFIX, receiver_account, provider_account);
     }

public:
   CCopierState()
     {
      m_log = NULL;
      m_filename = "";
     }

   void SetLogger(CCopierLogger *logger)
     {
      m_log = logger;
     }

   void SetContext(const long receiver_account, const long provider_account)
     {
      m_filename = StateFilename(receiver_account, provider_account);
     }

   int Count() const
     {
      return ArraySize(m_mappings);
     }

   bool Get(const int index, STicketMapping &mapping) const
     {
      if(index < 0 || index >= ArraySize(m_mappings))
         return false;
      mapping = m_mappings[index];
      return true;
     }

   int FindByProviderTicket(const ulong provider_ticket) const
     {
      for(int i = 0; i < ArraySize(m_mappings); i++)
        {
         if(m_mappings[i].provider_ticket == provider_ticket)
            return i;
        }
      return -1;
     }

   int FindByReceiverTicket(const ulong receiver_ticket) const
     {
      for(int i = 0; i < ArraySize(m_mappings); i++)
        {
         if(m_mappings[i].receiver_ticket == receiver_ticket)
            return i;
        }
      return -1;
     }

   void Upsert(const STicketMapping &mapping)
     {
      int idx = FindByProviderTicket(mapping.provider_ticket);
      if(idx < 0)
        {
         int n = ArraySize(m_mappings);
         ArrayResize(m_mappings, n + 1);
         m_mappings[n] = mapping;
        }
      else
        {
         m_mappings[idx] = mapping;
        }
     }

   void RemoveByIndex(const int index)
     {
      int n = ArraySize(m_mappings);
      if(index < 0 || index >= n)
         return;
      for(int i = index; i < n - 1; i++)
         m_mappings[i] = m_mappings[i + 1];
      ArrayResize(m_mappings, n - 1);
     }

   bool Load()
     {
      ArrayResize(m_mappings, 0);
      if(StringLen(m_filename) == 0)
         return false;

      if(!FileIsExist(m_filename, FILE_COMMON))
         return true;

      int handle = FileOpen(m_filename, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
      if(handle == INVALID_HANDLE)
         return false;

      while(!FileIsEnding(handle))
        {
         string line = FileReadString(handle);
         StringTrimLeft(line);
         StringTrimRight(line);
         if(StringLen(line) == 0 || StringFind(line, "provider_account") == 0)
            continue;

         string parts[];
         SplitCsvLine(line, parts);
         if(ArraySize(parts) < 7)
            continue;

         STicketMapping map;
         map.provider_account = (long)StringToInteger(parts[0]);
         map.provider_ticket = (ulong)StringToInteger(parts[1]);
         map.receiver_ticket = (ulong)StringToInteger(parts[2]);
         map.provider_symbol = parts[3];
         map.receiver_symbol = parts[4];
         map.provider_volume = StringToDouble(parts[5]);
         map.copied_volume = StringToDouble(parts[6]);

         int n = ArraySize(m_mappings);
         ArrayResize(m_mappings, n + 1);
         m_mappings[n] = map;
        }
      FileClose(handle);

      if(m_log != NULL)
        {
         string common = TerminalInfoString(TERMINAL_COMMONDATA_PATH);
         if(StringLen(common) > 0)
           {
            if(StringGetCharacter(common, StringLen(common) - 1) != '\\')
               common += "\\";
            common += "Files\\" + m_filename;
           }
         else
            common = "Terminal\\Common\\Files\\" + m_filename;

         m_log.Debug(StringFormat("Loaded %d mappings from %s", ArraySize(m_mappings), common));
        }
      return true;
     }

   bool Save()
     {
      if(StringLen(m_filename) == 0)
         return false;

      int handle = FileOpen(m_filename, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
      if(handle == INVALID_HANDLE)
         return false;

      FileWriteString(handle,
                      "provider_account,provider_ticket,receiver_ticket,provider_symbol,receiver_symbol,provider_volume,copied_volume\r\n");
      for(int i = 0; i < ArraySize(m_mappings); i++)
        {
         STicketMapping map = m_mappings[i];
         FileWriteString(handle,
                         StringFormat("%d,%I64u,%I64u,%s,%s,%.8f,%.8f\r\n",
                                      map.provider_account,
                                      map.provider_ticket,
                                      map.receiver_ticket,
                                      CsvEscape(map.provider_symbol),
                                      CsvEscape(map.receiver_symbol),
                                      map.provider_volume,
                                      map.copied_volume));
        }
      FileClose(handle);
      return true;
     }

   // Drop mappings whose receiver positions no longer exist.
   void ReconcileOpenPositions(const long magic_number)
     {
      for(int i = ArraySize(m_mappings) - 1; i >= 0; i--)
        {
         if(!PositionSelectByTicket(m_mappings[i].receiver_ticket))
           {
            if(m_log != NULL)
               m_log.Debug(StringFormat("Removing stale mapping provider %I64u -> receiver %I64u",
                                        m_mappings[i].provider_ticket,
                                        m_mappings[i].receiver_ticket));
            RemoveByIndex(i);
           }
         else if(PositionGetInteger(POSITION_MAGIC) != magic_number)
           {
            RemoveByIndex(i);
           }
        }
     }
  };

#endif // COPIER_STATE_MQH
