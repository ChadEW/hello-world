//+------------------------------------------------------------------+
//|              ICC_TradesBySci_v2.mq5                              |
//|   ICC (Indication -> Correction -> Continuation) — Sci style      |
//|   Swing marking + body-close Support/Resistance engine            |
//|   Built for Chad Woodyard, July 2026                              |
//|                                                                   |
//|   BODY-CLOSE SUPPORT / RESISTANCE:                                |
//|     * A level is confirmed only where candle BODIES (closes)      |
//|       land inside a tolerance zone at least N times (default 3).  |
//|     * Each confirmed level lives for a fixed DURATION: 3 calendar |
//|       days OR 3 trading sessions (selectable), then auto-removed. |
//+------------------------------------------------------------------+
#property copyright "Chad Woodyard"
#property version   "2.00"
#property indicator_chart_window
#property indicator_plots 0

//--- duration unit enum
enum ENUM_SR_DUR
  {
   SR_DAYS     = 0,   // Calendar Days
   SR_SESSIONS = 1    // Trading Sessions (daily bars)
  };

//============================= INPUTS =================================
input group "Swing / Structure (Sci style)"
input int    SwingLen      = 5;                 // Swing pivot length (bars L/R)
input bool   ShowSwings    = true;              // Draw swing high/low rays
input int    MaxSwings     = 6;                 // Max recent swing lines kept
input color  ColHigh       = clrDodgerBlue;     // Swing High (sellers' line)
input color  ColLow        = clrCrimson;        // Swing Low (buyers' line)

input group "Support / Resistance (body-close levels)"
input bool         SR_Show      = true;         // Show body-close S/R levels
input int          SR_MinTouch  = 3;            // Min body closes to confirm a level
input double       SR_TolPips   = 10.0;         // Zone tolerance (pips)
input ENUM_SR_DUR  SR_DurMode   = SR_DAYS;      // Level duration unit
input int          SR_DurN      = 3;            // Level duration (days or sessions)
input color        SR_ColRes    = clrOrange;    // Resistance color
input color        SR_ColSup    = clrTeal;      // Support color
input bool         SR_UseZone   = true;         // Draw as shaded zone (rectangle) instead of line
input bool         SR_ShowCnt   = true;         // Show touch-count label
input int          SR_RefLen    = 20;           // Reference SMA length (S/R classifier)

//============================ GLOBALS =================================
double  g_pip = 0.0;
double  g_tol = 0.0;

// running trading-session counter
int      g_sessCount   = 0;
int      g_lastDayKey  = -1;
datetime g_lastBarTime = 0;

// object bookkeeping for swings (rolling)
string   g_swingNames[];
int      g_uid = 0;

// SMA handle for classification
int      g_maHandle = INVALID_HANDLE;

// ---- S/R cluster storage (parallel arrays) ----
double   sr_price[];      // running-average price of the level
int      sr_count[];      // number of body closes inside the zone
datetime sr_birthTime[];  // time of first touch
int      sr_birthSes[];   // session index at first touch
datetime sr_birthBar[];   // bar time at first touch (drawing start)
bool     sr_isRes[];      // true = resistance, false = support
bool     sr_drawn[];      // has it been drawn yet?
string   sr_name[];       // base object name

//+------------------------------------------------------------------+
int OnInit()
  {
   g_pip = _Point * ((_Digits == 3 || _Digits == 5) ? 10 : 1);
   g_tol = SR_TolPips * g_pip;

   g_maHandle = iMA(_Symbol, _Period, SR_RefLen, 0, MODE_SMA, PRICE_CLOSE);
   if(g_maHandle == INVALID_HANDLE)
      Print("Warning: could not create SMA handle for S/R classifier.");

   IndicatorSetString(INDICATOR_SHORTNAME, "ICC-Sci v2");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_maHandle != INVALID_HANDLE) IndicatorRelease(g_maHandle);
   ObjectsDeleteAll(0, "SR_");
   ObjectsDeleteAll(0, "SW_");
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < SwingLen * 2 + 5)
      return(rates_total);

   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   // fire only when a brand-new bar has formed
   datetime curBarTime = time[0];
   if(curBarTime == g_lastBarTime)
     {
      UpdateActiveLevels(time[0]);     // keep growing active levels intra-bar
      return(rates_total);
     }
   g_lastBarTime = curBarTime;

   // ---- process the just-CLOSED bar (index 1) ----
   double c = close[1];
   datetime t = time[1];

   ProcessSwing(rates_total, time, high, low);   // Sci-style swing rays
   ProcessBar(c, t);                             // body-close S/R engine
   ExpireLevels(time[0]);                        // remove levels past their duration
   UpdateActiveLevels(time[0]);                  // extend active levels to now

   return(rates_total);
  }

//+==================================================================+
//|                 BODY-CLOSE S/R ENGINE                            |
//+==================================================================+
void ProcessBar(double c, datetime t)
  {
   // --- session counter: a new calendar day = a new session ---
   MqlDateTime mt;
   TimeToStruct(t, mt);
   int dayKey = mt.year * 10000 + mt.mon * 100 + mt.day;
   if(dayKey != g_lastDayKey)
     {
      g_sessCount++;
      g_lastDayKey = dayKey;
     }

   // --- 1) try to match this close to an existing cluster ---
   bool matched = false;
   for(int i = 0; i < ArraySize(sr_price); i++)
     {
      if(MathAbs(c - sr_price[i]) <= g_tol)
        {
         int nc = sr_count[i] + 1;
         sr_price[i] = (sr_price[i] * sr_count[i] + c) / nc;   // running average
         sr_count[i] = nc;
         matched = true;

         // promote to a drawn level once threshold reached
         if(nc == SR_MinTouch && SR_Show && !sr_drawn[i])
           {
            sr_drawn[i] = true;
            sr_isRes[i] = (sr_price[i] >= RefSMA());
            DrawLevel(i);
           }
         // keep count label current on later touches
         else if(nc > SR_MinTouch && SR_Show && SR_ShowCnt && sr_drawn[i])
            UpdateLabel(i);
         break;
        }
     }

   // --- 2) no match -> open a new candidate cluster ---
   if(!matched)
     {
      int n = ArraySize(sr_price);
      ArrayResize(sr_price,     n + 1);
      ArrayResize(sr_count,     n + 1);
      ArrayResize(sr_birthTime, n + 1);
      ArrayResize(sr_birthSes,  n + 1);
      ArrayResize(sr_birthBar,  n + 1);
      ArrayResize(sr_isRes,     n + 1);
      ArrayResize(sr_drawn,     n + 1);
      ArrayResize(sr_name,      n + 1);

      sr_price[n]     = c;
      sr_count[n]     = 1;
      sr_birthTime[n] = t;
      sr_birthSes[n]  = g_sessCount;
      sr_birthBar[n]  = t;
      sr_isRes[n]     = false;
      sr_drawn[n]     = false;
      sr_name[n]      = "SR_" + IntegerToString(g_uid++);

      // bound memory: drop oldest if > 60
      if(ArraySize(sr_price) > 60)
         RemoveAt(0);
     }
  }

//+------------------------------------------------------------------+
void ExpireLevels(datetime now)
  {
   for(int i = ArraySize(sr_price) - 1; i >= 0; i--)
     {
      bool expired = false;
      if(SR_DurMode == SR_DAYS)
         expired = ((now - sr_birthTime[i]) >= (long)SR_DurN * 86400);
      else
         expired = ((g_sessCount - sr_birthSes[i]) >= SR_DurN);

      if(expired)
        {
         DeleteLevelObjects(i);
         RemoveAt(i);
        }
     }
  }

//+------------------------------------------------------------------+
void UpdateActiveLevels(datetime now)
  {
   for(int i = 0; i < ArraySize(sr_price); i++)
     {
      if(!sr_drawn[i])
         continue;
      string nm = sr_name[i];
      if(SR_UseZone)
        {
         if(ObjectFind(0, nm + "_box") >= 0)
            ObjectSetInteger(0, nm + "_box", OBJPROP_TIME, 1, now);
        }
      else
        {
         if(ObjectFind(0, nm + "_ln") >= 0)
            ObjectSetInteger(0, nm + "_ln", OBJPROP_TIME, 1, now);
        }
      if(SR_ShowCnt && ObjectFind(0, nm + "_lb") >= 0)
         ObjectSetInteger(0, nm + "_lb", OBJPROP_TIME, now);
     }
  }

//+------------------------------------------------------------------+
void DrawLevel(int i)
  {
   string nm  = sr_name[i];
   color  col = sr_isRes[i] ? SR_ColRes : SR_ColSup;
   double p   = sr_price[i];
   datetime t1= sr_birthBar[i];
   datetime t2= TimeCurrent();

   if(SR_UseZone)
     {
      string on = nm + "_box";
      ObjectCreate(0, on, OBJ_RECTANGLE, 0, t1, p + g_tol/2.0, t2, p - g_tol/2.0);
      ObjectSetInteger(0, on, OBJPROP_COLOR, col);
      ObjectSetInteger(0, on, OBJPROP_FILL, true);
      ObjectSetInteger(0, on, OBJPROP_BACK, true);
      ObjectSetInteger(0, on, OBJPROP_WIDTH, 1);
     }
   else
     {
      string on = nm + "_ln";
      ObjectCreate(0, on, OBJ_TREND, 0, t1, p, t2, p);
      ObjectSetInteger(0, on, OBJPROP_COLOR, col);
      ObjectSetInteger(0, on, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, on, OBJPROP_RAY_RIGHT, false);
     }

   if(SR_ShowCnt)
     {
      string ln = nm + "_lb";
      ObjectCreate(0, ln, OBJ_TEXT, 0, t2, p);
      ObjectSetString(0, ln, OBJPROP_TEXT,
                      (sr_isRes[i] ? "R x" : "S x") + IntegerToString(sr_count[i]));
      ObjectSetInteger(0, ln, OBJPROP_COLOR, col);
      ObjectSetInteger(0, ln, OBJPROP_ANCHOR,
                       sr_isRes[i] ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, ln, OBJPROP_FONTSIZE, 8);
     }
  }

//+------------------------------------------------------------------+
void UpdateLabel(int i)
  {
   string ln = sr_name[i] + "_lb";
   if(ObjectFind(0, ln) >= 0)
      ObjectSetString(0, ln, OBJPROP_TEXT,
                      (sr_isRes[i] ? "R x" : "S x") + IntegerToString(sr_count[i]));
  }

//+------------------------------------------------------------------+
void DeleteLevelObjects(int i)
  {
   string nm = sr_name[i];
   ObjectDelete(0, nm + "_box");
   ObjectDelete(0, nm + "_ln");
   ObjectDelete(0, nm + "_lb");
  }

//+------------------------------------------------------------------+
void RemoveAt(int idx)
  {
   int n = ArraySize(sr_price);
   if(idx < 0 || idx >= n)
      return;
   for(int i = idx; i < n - 1; i++)
     {
      sr_price[i]     = sr_price[i+1];
      sr_count[i]     = sr_count[i+1];
      sr_birthTime[i] = sr_birthTime[i+1];
      sr_birthSes[i]  = sr_birthSes[i+1];
      sr_birthBar[i]  = sr_birthBar[i+1];
      sr_isRes[i]     = sr_isRes[i+1];
      sr_drawn[i]     = sr_drawn[i+1];
      sr_name[i]      = sr_name[i+1];
     }
   ArrayResize(sr_price,     n - 1);
   ArrayResize(sr_count,     n - 1);
   ArrayResize(sr_birthTime, n - 1);
   ArrayResize(sr_birthSes,  n - 1);
   ArrayResize(sr_birthBar,  n - 1);
   ArrayResize(sr_isRes,     n - 1);
   ArrayResize(sr_drawn,     n - 1);
   ArrayResize(sr_name,      n - 1);
  }

//+------------------------------------------------------------------+
double RefSMA()
  {
   if(g_maHandle == INVALID_HANDLE)
      return(SymbolInfoDouble(_Symbol, SYMBOL_BID));
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(g_maHandle, 0, 1, 1, buf) == 1)
      return(buf[0]);
   return(SymbolInfoDouble(_Symbol, SYMBOL_BID));
  }

//+==================================================================+
//|                 SCI-STYLE SWING RAYS                             |
//+==================================================================+
void ProcessSwing(int rates_total, const datetime &time[],
                  const double &high[], const double &low[])
  {
   if(!ShowSwings)
      return;

   int c = SwingLen;                  // candidate pivot index (series)
   // pivot high / low
   bool isHigh = true, isLow = true;
   for(int k = 1; k <= SwingLen; k++)
     {
      if(high[c] <= high[c+k] || high[c] <= high[c-k]) isHigh = false;
      if(low[c]  >= low[c+k]  || low[c]  >= low[c-k])  isLow  = false;
     }

   if(isHigh)
      MakeSwing(time[c], high[c], ColHigh, true);
   if(isLow)
      MakeSwing(time[c], low[c], ColLow, false);
  }

//+------------------------------------------------------------------+
void MakeSwing(datetime t, double px, color col, bool isHigh)
  {
   string nm = "SW_" + IntegerToString(g_uid++);
   ObjectCreate(0, nm, OBJ_TREND, 0, t, px, TimeCurrent(), px);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT, true);

   int n = ArraySize(g_swingNames);
   ArrayResize(g_swingNames, n + 1);
   g_swingNames[n] = nm;

   // trim oldest swing rays beyond MaxSwings (both sides ~ approximate)
   while(ArraySize(g_swingNames) > MaxSwings * 2)
     {
      ObjectDelete(0, g_swingNames[0]);
      for(int i = 0; i < ArraySize(g_swingNames) - 1; i++)
         g_swingNames[i] = g_swingNames[i+1];
      ArrayResize(g_swingNames, ArraySize(g_swingNames) - 1);
     }
  }
//+------------------------------------------------------------------+
