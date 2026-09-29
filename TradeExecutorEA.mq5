#property copyright ""
#property version   "1.0"
#property strict

input string QueueFolder = "ea_queue"; // Relative to MQL5/Files
input int PollIntervalSeconds = 1;
input int MaxSlippage = 20;
input double MaxLots = 1.0;
input bool EnableExecution = false; // Explicitly enable on an MT5 demo account first.

struct TradeMapping
{
   string source_id;
   long ticket;
   string symbol;
};

TradeMapping mappings[];
bool trading_halted = false;
string mappings_file = "TradeExecutorEA\\mapping.csv";
string log_file = "logs\\TradeExecutorEA.log";

int OnInit()
{
   if(!EnableExecution)
   {
      Print("EnableExecution is false. No queue files or trades will be processed.");
      return(INIT_FAILED);
   }
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("This copier requires a hedging account for independent source positions.");
      return(INIT_FAILED);
   }
   if(PollIntervalSeconds < 1 || MaxLots <= 0.0)
   {
      Print("Invalid polling interval or MaxLots.");
      return(INIT_FAILED);
   }
   EnsureFolders();
   if(!LoadMappings() || !SaveMappings())
   {
      Print("Mapping file unavailable or corrupt. No trades will be processed.");
      return(INIT_FAILED);
   }
   EventSetTimer(PollIntervalSeconds);
   Log("TradeExecutorEA initialized.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Log("TradeExecutorEA deinitialized.");
}

void OnTimer()
{
   if(trading_halted)
      return;
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
   Print(message);
   int handle = FileOpen(log_file, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ, 0, CP_UTF8);
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

bool AddMapping(string source_id, long ticket, string symbol)
{
   TradeMapping map;
   map.source_id = source_id;
   map.ticket = ticket;
   map.symbol = symbol;
   int size = ArraySize(mappings);
   ArrayResize(mappings, size + 1);
   mappings[size] = map;
   if(!SaveMappings())
   {
      trading_halted = true;
      Log("FATAL: mapping not saved after OPEN. Manual reconciliation required.");
      return false;
   }
   return true;
}

bool RemoveMapping(string source_id)
{
   int index = FindMapping(source_id);
   if(index < 0)
      return false;
   int size = ArraySize(mappings);
   for(int i = index; i < size - 1; i++)
      mappings[i] = mappings[i + 1];
   ArrayResize(mappings, size - 1);
   if(!SaveMappings())
   {
      trading_halted = true;
      Log("FATAL: mapping not saved after CLOSE. Manual reconciliation required.");
      return false;
   }
   return true;
}

bool LoadMappings()
{
   if(!FileIsExist(mappings_file))
      return true;
   int handle = FileOpen(mappings_file, FILE_READ|FILE_TXT|FILE_ANSI, 0, CP_UTF8);
   if(handle == INVALID_HANDLE)
      return false;
   while(!FileIsEnding(handle))
   {
      string line = FileReadString(handle);
      if(StringLen(line) == 0)
         continue;
      string parts[];
      int count = StringSplit(line, ',', parts);
      if(count < 3 || parts[0] == "" || StringToInteger(parts[1]) <= 0)
      {
         FileClose(handle);
         return false;
      }
      TradeMapping map;
      map.source_id = parts[0];
      map.ticket = (long)StringToInteger(parts[1]);
      map.symbol = parts[2];
      int size = ArraySize(mappings);
      ArrayResize(mappings, size + 1);
      mappings[size] = map;
   }
   FileClose(handle);
   return true;
}

bool SaveMappings()
{
   string temp_path = mappings_file + ".tmp";
   int handle = FileOpen(temp_path, FILE_WRITE|FILE_TXT|FILE_ANSI, 0, CP_UTF8);
   if(handle == INVALID_HANDLE)
      return false;
   int total = ArraySize(mappings);
   for(int i = 0; i < total; i++)
   {
      string line = mappings[i].source_id + "," + (string)mappings[i].ticket + "," + mappings[i].symbol;
      FileWrite(handle, line);
   }
   FileClose(handle);
   return FileMove(temp_path, 0, mappings_file, FILE_REWRITE);
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
   long handle = FileFindFirst(search_path, filename);
   if(handle == INVALID_HANDLE)
      return false;

   do
   {
      if(filename == "" || filename == "." || filename == "..")
         continue;
      string filepath = QueueFolder + "\\inbox\\" + filename;
      bool success = ProcessCommandFile(filepath);
      string target = QueueFolder + (success ? "\\processed\\" : "\\failed\\") + filename;
      if(!FileMove(filepath, 0, target, 0))
      {
         Log("Failed to move file: " + filepath + " -> " + target);
         trading_halted = true;
      }
      if(!success)
         trading_halted = true;
      if(trading_halted)
         break;
   } while(FileFindNext(handle, filename));
   FileFindClose(handle);
   return true;
}

bool ProcessCommandFile(string filepath)
{
   int handle = FileOpen(filepath, FILE_READ|FILE_TXT|FILE_ANSI, 0, CP_UTF8);
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
   if(source_id == "" || symbol == "" || (side != "BUY" && side != "SELL") || lots <= 0 || lots > MaxLots)
   {
      Log("Invalid OPEN command: missing fields.");
      return false;
   }
   if(FindMapping(source_id) >= 0)
   {
      Log("Duplicate OPEN ignored: " + source_id);
      return true;
   }

   if(!SymbolSelect(symbol, true))
   {
      Log("Unknown broker symbol: " + symbol);
      return false;
   }
   double minimum = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(lots < minimum || lots > maximum || step <= 0.0 ||
      MathAbs(lots / step - MathRound(lots / step)) > 0.000001)
   {
      Log("OPEN volume fails broker minimum, maximum or step: " + DoubleToString(lots, 4));
      return false;
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
   request.magic = 860197;
   long filling = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      request.type_filling = ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      request.type_filling = ORDER_FILLING_IOC;
   else
   {
      Log("No supported FOK/IOC filling mode for " + symbol);
      return false;
   }
   if(sl > 0.0)
      request.sl = sl;
   if(tp > 0.0)
      request.tp = tp;

   bool sent = OrderSend(request, result);

   if(!sent || result.retcode != TRADE_RETCODE_DONE)
   {
      Log("OPEN failed: retcode=" + IntegerToString(result.retcode));
      if(result.deal > 0 || result.retcode == TRADE_RETCODE_DONE_PARTIAL)
         trading_halted = true;
      return false;
   }

   long position_id = 0;
   if(result.deal > 0 && HistoryDealSelect(result.deal))
      position_id = HistoryDealGetInteger(result.deal, DEAL_POSITION_ID);
   long position_ticket = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong candidate_ticket = PositionGetTicket(i);
      if(candidate_ticket > 0 && PositionGetInteger(POSITION_IDENTIFIER) == position_id && position_id > 0)
      {
         position_ticket = (long)candidate_ticket;
         break;
      }
   }

   if(position_ticket <= 0)
   {
      Log("OPEN succeeded but position ticket not found for source: " + source_id);
      trading_halted = true;
      return false;
   }

   if(!AddMapping(source_id, position_ticket, symbol))
      return false;
   Log("OPEN executed. Source=" + source_id + " Ticket=" + (string)position_ticket);
   return true;
}

bool HandleClose(string source_id)
{
   int index = FindMapping(source_id);
   if(index < 0)
   {
      Log("CLOSE failed. No mapping for: " + source_id);
      return false;
   }

   long ticket = mappings[index].ticket;
   if(!PositionSelectByTicket(ticket))
   {
      Log("Position not found for ticket: " + (string)ticket);
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
   request.magic = 860197;
   long filling = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      request.type_filling = ORDER_FILLING_FOK;
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      request.type_filling = ORDER_FILLING_IOC;
   else
   {
      Log("No supported FOK/IOC filling mode for CLOSE: " + symbol);
      return false;
   }

   bool sent = OrderSend(request, result);

   if(!sent || result.retcode != TRADE_RETCODE_DONE)
   {
      Log("CLOSE failed: retcode=" + IntegerToString(result.retcode));
      if(result.deal > 0 || result.retcode == TRADE_RETCODE_DONE_PARTIAL)
         trading_halted = true;
      return false;
   }

   if(!RemoveMapping(source_id))
      return false;
   Log("CLOSE executed. Source=" + source_id + " Ticket=" + (string)ticket);
   return true;
}
