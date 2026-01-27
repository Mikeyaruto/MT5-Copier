#property copyright ""
#property version   "1.0"
#property strict

input string QueueFolder = "ea_queue"; // Relative to MQL5/Files
input int PollIntervalSeconds = 1;
input int MaxSlippage = 20;
input bool UseHttp = false;
input string HttpEndpoint = "http://127.0.0.1:5000/mt5";

struct TradeMapping
{
   string source_id;
   long ticket;
   string symbol;
};

TradeMapping mappings[];
string mappings_file = "TradeExecutorEA\\mapping.csv";
string log_file = "logs\\TradeExecutorEA.log";

int OnInit()
{
   EnsureFolders();
   LoadMappings();
   EventSetTimer(PollIntervalSeconds);
   Log("TradeExecutorEA initialized.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   SaveMappings();
   Log("TradeExecutorEA deinitialized.");
}

void OnTimer()
{
   if(UseHttp)
   {
      Log("HTTP mode enabled, but not implemented in this build. Using file queue only.");
      return;
   }
   ProcessFileQueue();
}

void EnsureFolders()
{
   FolderCreate("logs");
   FolderCreate("TradeExecutorEA");
   FolderCreate(QueueFolder);
   FolderCreate(QueueFolder + "\\inbox");
   FolderCreate(QueueFolder + "\\processed");
   FolderCreate(QueueFolder + "\\failed");
}

void Log(string message)
{
   int handle = FileOpen(log_file, FILE_WRITE|FILE_TXT|FILE_SHARE_WRITE);
   if(handle == INVALID_HANDLE)
      return;
   FileSeek(handle, 0, SEEK_END);
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   FileWrite(handle, timestamp + " " + message);
   FileClose(handle);
}

int FindMapping(string source_id)
{
   int total = ArraySize(mappings);
   for(int i = 0; i < total; i++)
   {
      if(mappings[i].source_id == source_id)
         return i;
   }
   return -1;
}

void AddMapping(string source_id, long ticket, string symbol)
{
   TradeMapping map;
   map.source_id = source_id;
   map.ticket = ticket;
   map.symbol = symbol;
   int size = ArraySize(mappings);
   ArrayResize(mappings, size + 1);
   mappings[size] = map;
   SaveMappings();
}

void RemoveMapping(string source_id)
{
   int index = FindMapping(source_id);
   if(index < 0)
      return;
   int size = ArraySize(mappings);
   for(int i = index; i < size - 1; i++)
      mappings[i] = mappings[i + 1];
   ArrayResize(mappings, size - 1);
   SaveMappings();
}

void LoadMappings()
{
   if(!FileIsExist(mappings_file))
      return;
   int handle = FileOpen(mappings_file, FILE_READ|FILE_TXT);
   if(handle == INVALID_HANDLE)
      return;
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(StringLen(line) == 0)
         continue;
      string parts[];
      int count = StringSplit(line, ',', parts);
      if(count >= 2)
      {
         TradeMapping map;
         map.source_id = parts[0];
         map.ticket = (long)StringToInteger(parts[1]);
         map.symbol = (count >= 3 ? parts[2] : "");
         int size = ArraySize(mappings);
         ArrayResize(mappings, size + 1);
         mappings[size] = map;
      }
   }
   FileClose(handle);
}

void SaveMappings()
{
   int handle = FileOpen(mappings_file, FILE_WRITE|FILE_TXT);
   if(handle == INVALID_HANDLE)
      return;
   int total = ArraySize(mappings);
   for(int i = 0; i < total; i++)
   {
      string line = mappings[i].source_id + "," + (string)mappings[i].ticket + "," + mappings[i].symbol;
      FileWrite(handle, line);
   }
   FileClose(handle);
}

string JsonGetString(string json, string key)
{
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos < 0)
      return "";
   pos = StringFind(json, ":", pos);
   if(pos < 0)
      return "";
   pos++;
   while(pos < StringLen(json) && StringGetCharacter(json, pos) <= ' ')
      pos++;
   if(pos >= StringLen(json) || StringGetCharacter(json, pos) != '"')
      return "";
   pos++;
   string value = "";
   while(pos < StringLen(json))
   {
      int ch = StringGetCharacter(json, pos);
      if(ch == '"')
         break;
      value += CharToString((ushort)ch);
      pos++;
   }
   return value;
}

bool JsonHasNull(string json, string key)
{
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos < 0)
      return true;
   pos = StringFind(json, ":", pos);
   if(pos < 0)
      return true;
   pos++;
   while(pos < StringLen(json) && StringGetCharacter(json, pos) <= ' ')
      pos++;
   if(pos + 3 < StringLen(json) && StringSubstr(json, pos, 4) == "null")
      return true;
   return false;
}

double JsonGetNumber(string json, string key, double default_value)
{
   string pattern = "\"" + key + "\"";
   int pos = StringFind(json, pattern);
   if(pos < 0)
      return default_value;
   pos = StringFind(json, ":", pos);
   if(pos < 0)
      return default_value;
   pos++;
   while(pos < StringLen(json) && StringGetCharacter(json, pos) <= ' ')
      pos++;
   int end = pos;
   while(end < StringLen(json))
   {
      int ch = StringGetCharacter(json, end);
      if((ch >= '0' && ch <= '9') || ch == '.' || ch == '-')
         end++;
      else
         break;
   }
   string value = StringSubstr(json, pos, end - pos);
   if(StringLen(value) == 0)
      return default_value;
   return StringToDouble(value);
}

bool ProcessFileQueue()
{
   string search_path = QueueFolder + "\\inbox\\*.json";
   string filename = "";
   int attributes = 0;
   long size = 0;
   datetime modified = 0;
   long handle = FileFindFirst(search_path, filename, attributes, size, modified);
   if(handle == INVALID_HANDLE)
      return false;

   do
   {
      if(filename == "" || filename == "." || filename == "..")
         continue;
      string filepath = QueueFolder + "\\inbox\\" + filename;
      bool success = ProcessCommandFile(filepath);
      string target = QueueFolder + (success ? "\\processed\\" : "\\failed\\") + filename;
      if(!FileMove(filepath, target))
      {
         Log("Failed to move file: " + filepath + " -> " + target);
      }
   } while(FileFindNext(handle, filename, attributes, size, modified));
   FileFindClose(handle);
   return true;
}

bool ProcessCommandFile(string filepath)
{
   int handle = FileOpen(filepath, FILE_READ|FILE_TXT);
   if(handle == INVALID_HANDLE)
   {
      Log("Failed to open command file: " + filepath);
      return false;
   }
   string json = "";
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(StringLen(line) > 0)
         json += line;
   }
   FileClose(handle);

   string event = JsonGetString(json, "event");
   string source_id = JsonGetString(json, "source_trade_id");
   string symbol = JsonGetString(json, "symbol");
   string side = JsonGetString(json, "side");
   double lots = JsonGetNumber(json, "lots", 0.0);
   double sl = JsonHasNull(json, "sl") ? 0.0 : JsonGetNumber(json, "sl", 0.0);
   double tp = JsonHasNull(json, "tp") ? 0.0 : JsonGetNumber(json, "tp", 0.0);

   if(event == "OPEN")
      return HandleOpen(source_id, symbol, side, lots, sl, tp);
   if(event == "CLOSE")
      return HandleClose(source_id);

   Log("Unknown event type: " + event);
   return false;
}

bool HandleOpen(string source_id, string symbol, string side, double lots, double sl, double tp)
{
   if(source_id == "" || symbol == "" || lots <= 0)
   {
      Log("Invalid OPEN command: missing fields.");
      return false;
   }
   if(FindMapping(source_id) >= 0)
   {
      Log("Duplicate OPEN ignored: " + source_id);
      return true;
   }

   ENUM_ORDER_TYPE order_type = (side == "SELL") ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (order_type == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_DEAL;
   request.symbol = symbol;
   request.volume = lots;
   request.type = order_type;
   request.price = price;
   request.deviation = MaxSlippage;
   if(sl > 0.0)
      request.sl = sl;
   if(tp > 0.0)
      request.tp = tp;

   bool sent = false;
   for(int attempt = 0; attempt < 3; attempt++)
   {
      RefreshRates();
      if(OrderSend(request, result))
      {
         sent = true;
         break;
      }
      Sleep(500);
   }

   if(!sent || result.retcode != TRADE_RETCODE_DONE)
   {
      Log("OPEN failed: retcode=" + IntegerToString(result.retcode));
      return false;
   }

   long position_ticket = result.position;
   if(position_ticket <= 0)
   {
      if(PositionSelect(symbol))
         position_ticket = PositionGetInteger(POSITION_TICKET);
   }

   if(position_ticket <= 0)
   {
      Log("OPEN succeeded but position ticket not found for source: " + source_id);
      return false;
   }

   AddMapping(source_id, position_ticket, symbol);
   Log("OPEN executed. Source=" + source_id + " Ticket=" + (string)position_ticket);
   return true;
}

bool HandleClose(string source_id)
{
   int index = FindMapping(source_id);
   if(index < 0)
   {
      Log("CLOSE ignored. No mapping for: " + source_id);
      return true;
   }

   long ticket = mappings[index].ticket;
   if(!PositionSelectByTicket(ticket))
   {
      Log("Position not found for ticket: " + (string)ticket);
      RemoveMapping(source_id);
      return false;
   }

   string symbol = PositionGetString(POSITION_SYMBOL);
   double volume = PositionGetDouble(POSITION_VOLUME);
   ENUM_POSITION_TYPE position_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   ENUM_ORDER_TYPE close_type = (position_type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (close_type == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = symbol;
   request.volume = volume;
   request.type = close_type;
   request.price = price;
   request.deviation = MaxSlippage;

   bool sent = false;
   for(int attempt = 0; attempt < 3; attempt++)
   {
      RefreshRates();
      if(OrderSend(request, result))
      {
         sent = true;
         break;
      }
      Sleep(500);
   }

   if(!sent || result.retcode != TRADE_RETCODE_DONE)
   {
      Log("CLOSE failed: retcode=" + IntegerToString(result.retcode));
      return false;
   }

   RemoveMapping(source_id);
   Log("CLOSE executed. Source=" + source_id + " Ticket=" + (string)ticket);
   return true;
}
