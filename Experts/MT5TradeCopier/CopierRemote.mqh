//+------------------------------------------------------------------+
//| CopierRemote.mqh - HTTP download, FTP upload, heartbeat ping     |
//+------------------------------------------------------------------+
#ifndef COPIER_REMOTE_MQH
#define COPIER_REMOTE_MQH

#include "CopierLogger.mqh"

class CCopierRemote
  {
private:
   CCopierLogger *m_log;
   datetime       m_last_heartbeat;
   datetime       m_last_download_attempt;

   string BuildAuthHeader(const string user, const string password) const
     {
      if(StringLen(user) == 0)
         return "";

      string token = user + ":" + password;
      uchar src[];
      int len = StringToCharArray(token, src, 0, WHOLE_ARRAY, CP_UTF8);
      if(len > 0)
         len--;

      return "Authorization: Basic " + Base64Encode(src, len) + "\r\n";
     }

   string Base64Encode(const uchar &data[], const int length) const
     {
      static const string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      string out = "";
      int i = 0;
      while(i < length)
        {
         int b0 = data[i++];
         int b1 = (i < length) ? data[i++] : -1;
         int b2 = (i < length) ? data[i++] : -1;

         out += StringSubstr(alphabet, (b0 >> 2) & 0x3F, 1);
         out += StringSubstr(alphabet, ((b0 & 0x03) << 4) | ((b1 >= 0 ? b1 : 0) >> 4), 1);
         out += (b1 < 0) ? "=" : StringSubstr(alphabet, ((b1 & 0x0F) << 2) | ((b2 >= 0 ? b2 : 0) >> 6), 1);
         out += (b2 < 0) ? "=" : StringSubstr(alphabet, b2 & 0x3F, 1);
        }
      return out;
     }

public:
   CCopierRemote()
     {
      m_log = NULL;
      m_last_heartbeat = 0;
      m_last_download_attempt = 0;
     }

   void SetLogger(CCopierLogger *logger)
     {
      m_log = logger;
     }

   // HTTP GET download. URL must be whitelisted in terminal settings.
   bool HttpDownload(const string url,
                     const string username,
                     const string password,
                     const int timeout_ms,
                     string &content)
     {
      content = "";
      if(StringLen(url) == 0)
         return false;

      uchar data[];
      uchar result[];
      string headers = BuildAuthHeader(username, password);
      string response_headers = "";

      ResetLastError();
      int code = WebRequest("GET", url, headers, timeout_ms, data, result, response_headers);
      if(code == -1)
        {
         if(m_log != NULL)
            m_log.Error(StringFormat("WebRequest failed (%d). Add URL to allowed list: %s",
                                     GetLastError(), url));
         return false;
        }

      if(code < 200 || code >= 300)
        {
         if(m_log != NULL)
            m_log.Warn(StringFormat("HTTP download returned %d for %s", code, url));
         return false;
        }

      content = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      return StringLen(content) > 0;
     }

   bool ShouldDownload(const int interval_ms) const
     {
      if(interval_ms <= 0)
         return true;
      return ((int)((TimeCurrent() - m_last_download_attempt) * 1000) >= interval_ms);
     }

   void MarkDownloadAttempt()
     {
      m_last_download_attempt = TimeCurrent();
     }

   // SendFTP uses terminal FTP tab settings; optional remote path override.
   bool FtpUpload(const string local_filename, const string remote_path)
     {
      if(StringLen(local_filename) == 0)
         return false;

      ResetLastError();
      bool ok = SendFTP(local_filename, remote_path);
      if(!ok && m_log != NULL)
         m_log.Error(StringFormat("SendFTP failed for %s (%d). Check Tools->Options->FTP.",
                                  local_filename, GetLastError()));
      return ok;
     }

   bool SendHeartbeat(const string url, const int interval_sec, const int timeout_ms)
     {
      if(StringLen(url) == 0 || interval_sec <= 0)
         return true;

      if(m_last_heartbeat > 0 && (TimeCurrent() - m_last_heartbeat) < interval_sec)
         return true;

      uchar data[];
      uchar result[];
      string response_headers = "";
      ResetLastError();
      int code = WebRequest("GET", url, "", timeout_ms, data, result, response_headers);
      m_last_heartbeat = TimeCurrent();

      if(code == -1)
        {
         if(m_log != NULL)
            m_log.Warn(StringFormat("Heartbeat failed (%d): %s", GetLastError(), url));
         return false;
        }

      if(m_log != NULL)
         m_log.Debug(StringFormat("Heartbeat %d -> %s", code, url));
      return (code >= 200 && code < 300);
     }
  };

#endif // COPIER_REMOTE_MQH
