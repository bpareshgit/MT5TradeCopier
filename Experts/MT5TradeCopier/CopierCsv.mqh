//+------------------------------------------------------------------+
//| CopierCsv.mqh - Minimal CSV helpers                              |
//+------------------------------------------------------------------+
#ifndef COPIER_CSV_MQH
#define COPIER_CSV_MQH

string CsvEscape(const string value)
  {
   if(StringFind(value, ",") < 0 && StringFind(value, "\"") < 0 && StringFind(value, "\n") < 0)
      return value;
   string escaped = value;
   StringReplace(escaped, "\"", "\"\"");
   return "\"" + escaped + "\"";
  }

void SplitCsvLine(const string line, string &parts[])
  {
   ArrayResize(parts, 0);
   int len = StringLen(line);
   string current = "";
   bool in_quotes = false;

   for(int i = 0; i < len; i++)
     {
      ushort ch = StringGetCharacter(line, i);
      if(ch == '"')
        {
         if(in_quotes && i + 1 < len && StringGetCharacter(line, i + 1) == '"')
           {
            current += "\"";
            i++;
           }
         else
           {
            in_quotes = !in_quotes;
           }
         continue;
        }
      if(ch == ',' && !in_quotes)
        {
         int n = ArraySize(parts);
         ArrayResize(parts, n + 1);
         parts[n] = current;
         current = "";
         continue;
        }
      current += ShortToString(ch);
     }

   int n = ArraySize(parts);
   ArrayResize(parts, n + 1);
   parts[n] = current;
  }

uint CsvChecksum(const string text)
  {
   uchar bytes[];
   int size = StringToCharArray(text, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   if(size <= 0)
      return 0;

   uint hash = 2166136261;
   for(int i = 0; i < size; i++)
     {
      hash ^= bytes[i];
      hash *= 16777619;
     }
   return hash;
  }

#endif // COPIER_CSV_MQH
