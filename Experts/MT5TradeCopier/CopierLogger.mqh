//+------------------------------------------------------------------+
//| CopierLogger.mqh - Leveled logging with optional file rotation   |
//+------------------------------------------------------------------+
#ifndef COPIER_LOGGER_MQH
#define COPIER_LOGGER_MQH

#include "CopierTypes.mqh"

class CCopierLogger
  {
private:
   ENUM_COPIER_LOG_LEVEL m_level;
   bool                  m_file_log;
   string                m_log_name;
   int                   m_max_kb;

   string LevelTag(const ENUM_COPIER_LOG_LEVEL level) const
     {
      switch(level)
        {
         case COPIER_LOG_ERROR: return "ERROR";
         case COPIER_LOG_WARN:  return "WARN";
         case COPIER_LOG_INFO:  return "INFO";
         case COPIER_LOG_DEBUG: return "DEBUG";
         default:               return "NONE";
        }
     }

   void RotateIfNeeded()
     {
      if(!m_file_log)
         return;

      if(!FileIsExist(m_log_name, FILE_COMMON))
         return;

      int handle = FileOpen(m_log_name, FILE_READ | FILE_BIN | FILE_COMMON);
      if(handle == INVALID_HANDLE)
         return;

      ulong size = (ulong)FileSize(handle);
      FileClose(handle);

      if((int)(size / 1024) < m_max_kb)
         return;

      string archive = m_log_name + "." + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      StringReplace(archive, ":", "-");
      StringReplace(archive, " ", "_");
      FileMove(m_log_name, FILE_COMMON, archive, FILE_COMMON);
     }

   void WriteFile(const string line)
     {
      if(!m_file_log)
         return;

      RotateIfNeeded();
      int handle = FileOpen(m_log_name, FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
      if(handle == INVALID_HANDLE)
        {
         handle = FileOpen(m_log_name, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
         if(handle == INVALID_HANDLE)
            return;
        }
      FileSeek(handle, 0, SEEK_END);
      FileWriteString(handle, line + "\r\n");
      FileClose(handle);
     }

public:
   CCopierLogger()
     {
      m_level = COPIER_LOG_INFO;
      m_file_log = false;
      m_log_name = COPIER_FILE_PREFIX + "-log.txt";
      m_max_kb = 512;
     }

   void Configure(const ENUM_COPIER_LOG_LEVEL level,
                  const bool file_log,
                  const string log_name,
                  const int max_kb)
     {
      m_level = level;
      m_file_log = file_log;
      if(StringLen(log_name) > 0)
         m_log_name = log_name;
      if(max_kb > 0)
         m_max_kb = max_kb;
     }

   void Log(const ENUM_COPIER_LOG_LEVEL level, const string message)
     {
      if(level == COPIER_LOG_NONE || level > m_level)
         return;

      string line = StringFormat("%s [%s] %s",
                                 TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                                 LevelTag(level),
                                 message);
      Print(line);
      WriteFile(line);
     }

   void Error(const string message) { Log(COPIER_LOG_ERROR, message); }
   void Warn(const string message)  { Log(COPIER_LOG_WARN, message); }
   void Info(const string message)  { Log(COPIER_LOG_INFO, message); }
   void Debug(const string message) { Log(COPIER_LOG_DEBUG, message); }
  };

#endif // COPIER_LOGGER_MQH
