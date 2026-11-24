//+------------------------------------------------------------------+
//|                                       ICC_TradesBySci_v1.mq5     |
//|  ICC (Indication → Correction → Continuation) — TradesBySci EA   |
//|  Multi-Timeframe Cascade: D1 → H4 → H1 → M15 with correlation    |
//|  Auto-marks swing highs (BLUE = sellers) and lows (RED = buyers) |
//|  Built for Chad Woodyard — June 2026                             |
//+------------------------------------------------------------------+
#property copyright "ICC TradesBySci EA v1"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade  trade;

//=== USER INPUTS =====================================================
input group              "=== Timeframe Cascade ==="
input ENUM_TIMEFRAMES    BiasTF      = PERIOD_D1;   // Top bias (Indication)
input ENUM_TIMEFRAMES    MidTF       = PERIOD_H4;   // Correction mapping
input ENUM_TIMEFRAMES    WorkTF      = PERIOD_H1;   // Working / structure TF
input ENUM_TIMEFRAMES    TrigTF      = PERIOD_M15;  // Entry trigger TF
input bool               StrictAlign = true;        // Require ALL 4 TFs aligned

input group              "=== Structure / Marking ==="
input int                SwingLen    = 5;           // Bars L/R for pivot
input int                MaxSwingsKept = 6;         // Recent swings to draw
input bool               DrawSwings  = true;        // Auto-mark swings
input bool               DrawLabels  = true;        // HH/HL/LH/LL labels
input color              SwingHiCol  = clrDodgerBlue;   // Sci's blue (sellers)
input color              SwingLoCol  = clrCrimson;      // Buyers' line
input color              ZoneBullCol = clrSeaGreen;
input color              ZoneBearCol = clrIndianRed;

input group              "=== Entry / Risk ==="
input double             RiskPercent = 0.5;         // % equity per trade
input double             RR          = 2.0;         // Reward:Risk ratio
input bool               UseNYHours  = false;       // 09:30–16:00 NY
input ulong              Magic       = 26052026;
input int                Slippage    = 20;
input string             TradeComment= "ICC-Sci";

input group              "=== Diagnostics ==="
input bool               VerboseInit = true;
input bool               DrawCorrZone= true;

//=== GLOBAL STATE ====================================================
struct SwingCache { double lastHi, prevHi, lastLo, prevLo; datetime tHi, tLo; };
SwingCache cD1, cH4, cH1, cM15;

string PFX = "ICC_";   // object prefix
datetime lastBarTime  = 0;
datetime lastSigTime  = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(Slippage);
   if(VerboseInit)
     {
      Print("=== ICC TradesBySci EA v1 — init ===");
      Print("Symbol: ", _Symbol,
            " | StopsLevel: ", SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
            " | Spread: ",     SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
            " | Digits: ",     _Digits,
            " | Point: ",      _Point);
      Print("Cascade: ", EnumToString(BiasTF), " → ",
                          EnumToString(MidTF),  " → ",
                          EnumToString(WorkTF), " → ",
                          EnumToString(TrigTF));
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { ObjectsDeleteAll(0, PFX); }

//+------------------------------------------------------------------+
//| ---- Pivot detection on closed bars only (no repaint) ----        |
//+------------------------------------------------------------------+
bool IsPivotHigh(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid = iHigh(_Symbol, tf, shift);
   if(mid == 0) return false;
   for(int i=1; i<=L; i++)
     {
      if(iHigh(_Symbol, tf, shift-i) >= mid) return false;
      if(iHigh(_Symbol, tf, shift+i) >  mid) return false;
     }
   return true;
  }

bool IsPivotLow(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid = iLow(_Symbol, tf, shift);
   if(mid == 0) return false;
   for(int i=1; i<=L; i++)
     {
      if(iLow(_Symbol, tf, shift-i) <= mid) return false;
      if(iLow(_Symbol, tf, shift+i) <  mid) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| ---- Refresh swing cache for one TF (last 2 confirmed swings) -- |
//+------------------------------------------------------------------+
void RefreshSwings(ENUM_TIMEFRAMES tf, SwingCache &c)
  {
   c.lastHi = c.prevHi = c.lastLo = c.prevLo = 0;
   c.tHi = c.tLo = 0;
   int bars = Bars(_Symbol, tf);
   int found_hi = 0, found_lo = 0;
   // walk back from the last fully-closed bar (shift = SwingLen+1 minimum)
   for(int shift = SwingLen+1; shift < bars - SwingLen - 1 && (found_hi<2 || found_lo<2); shift++)
     {
      if(found_hi < 2 && IsPivotHigh(tf, shift, SwingLen))
        {
         double px = iHigh(_Symbol, tf, shift);
         datetime t = iTime(_Symbol, tf, shift);
         if(found_hi == 0) { c.lastHi = px; c.tHi = t; }
         else              { c.prevHi = px; }
         found_hi++;
        }
      if(found_lo < 2 && IsPivotLow(tf, shift, SwingLen))
        {
         double px = iLow(_Symbol, tf, shift);
         datetime t = iTime(_Symbol, tf, shift);
         if(found_lo == 0) { c.lastLo = px; c.tLo = t; }
         else              { c.prevLo = px; }
         found_lo++;
        }
     }
  }

//+------------------------------------------------------------------+
//| ---- Bias from a swing cache: +1 bull / -1 bear / 0 unclear ---  |
//+------------------------------------------------------------------+
int BiasOf(const SwingCache &c)
  {
   if(c.lastHi==0 || c.prevHi==0 || c.lastLo==0 || c.prevLo==0) return 0;
   if(c.lastHi > c.prevHi && c.lastLo > c.prevLo) return  1;
   if(c.lastHi < c.prevHi && c.lastLo < c.prevLo) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| ---- Auto chart marking (Sci color scheme) ------------------    |
//+------------------------------------------------------------------+
void DrawSwingLine(string name, datetime t, double px, color clr, string tag)
  {
   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t, px, TimeCurrent()+PeriodSeconds()*5, px))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_BACK,  true);
   ObjectSetString (0, name, OBJPROP_TEXT,  tag);

   if(DrawLabels)
     {
      string lblName = name + "_lbl";
      ObjectDelete(0, lblName);
      ObjectCreate(0, lblName, OBJ_TEXT, 0, t, px);
      ObjectSetString (0, lblName, OBJPROP_TEXT, tag);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 9);
     }
  }

void MarkChartSwings()
  {
   if(!DrawSwings) return;
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   // clean previous swing markers
   ObjectsDeleteAll(0, PFX + "SW_");
   int hiCount = 0, loCount = 0;
   int bars = Bars(_Symbol, tf);
   double prevHi = 0, prevLo = 0;
   for(int shift = SwingLen+1;
       shift < bars - SwingLen - 1 && (hiCount < MaxSwingsKept || loCount < MaxSwingsKept);
       shift++)
     {
      if(hiCount < MaxSwingsKept && IsPivotHigh(tf, shift, SwingLen))
        {
         double px = iHigh(_Symbol, tf, shift);
         datetime t = iTime(_Symbol, tf, shift);
         string tag = (prevHi==0) ? "H" : (px > prevHi ? "HH" : "LH");
         DrawSwingLine(PFX+"SW_H_"+IntegerToString(hiCount), t, px, SwingHiCol, tag);
         prevHi = px;
         hiCount++;
        }
      if(loCount < MaxSwingsKept && IsPivotLow(tf, shift, SwingLen))
        {
         double px = iLow(_Symbol, tf, shift);
         datetime t = iTime(_Symbol, tf, shift);
         string tag = (prevLo==0) ? "L" : (px > prevLo ? "HL" : "LL");
         DrawSwingLine(PFX+"SW_L_"+IntegerToString(loCount), t, px, SwingLoCol, tag);
         prevLo = px;
         loCount++;
        }
     }
  }

//+------------------------------------------------------------------+
//| ---- Correction zone box between most recent H1 swings -------   |
//+------------------------------------------------------------------+
void DrawCorrectionZone(int h1Bias)
  {
   if(!DrawCorrZone) return;
   if(cH1.lastHi==0 || cH1.lastLo==0) return;
   string name = PFX + "CORR_ZONE";
   ObjectDelete(0, name);
   datetime t1 = TimeCurrent() - PeriodSeconds()*60;
   datetime t2 = TimeCurrent() + PeriodSeconds()*20;
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, cH1.lastHi, t2, cH1.lastLo))
      return;
   color c = h1Bias==1 ? ZoneBullCol : h1Bias==-1 ? ZoneBearCol : clrSilver;
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL,  true);
   ObjectSetInteger(0, name, OBJPROP_BACK,  true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

//+------------------------------------------------------------------+
//| ---- Dashboard panel -----------------------------------------    |
//+------------------------------------------------------------------+
void DrawDashboard(int bD1, int bH4, int bH1, int bM15, string cascade)
  {
   string base = PFX + "DASH_";
   string rows[6][2] = {
      {"TF",                "Bias"},
      {EnumToString(BiasTF),"D1"},
      {EnumToString(MidTF), "H4"},
      {EnumToString(WorkTF),"H1"},
      {EnumToString(TrigTF),"M15"},
      {"Cascade",           cascade}
   };
   int biases[4] = {bD1, bH4, bH1, bM15};
   for(int r=0; r<6; r++)
     {
      for(int col=0; col<2; col++)
        {
         string name = base + IntegerToString(r) + "_" + IntegerToString(col);
         ObjectDelete(0, name);
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_RIGHT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 220 - col*110);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 25 + r*18);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  9);
         string txt = rows[r][col];
         color clr  = clrWhite;
         if(r>=1 && r<=4 && col==1)
           {
            int b = biases[r-1];
            txt = b==1 ? "▲ BULL" : b==-1 ? "▼ BEAR" : "— flat";
            clr = b==1 ? clrLime : b==-1 ? clrTomato : clrSilver;
           }
         if(r==5 && col==1)
            clr = StringFind(cascade,"LONG") >=0 ? clrLime :
                  StringFind(cascade,"SHORT")>=0 ? clrTomato : clrSilver;
         ObjectSetString (0, name, OBJPROP_TEXT,  txt);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        }
     }
  }

//+------------------------------------------------------------------+
//| ---- Session filter -----------------------------------------    |
//+------------------------------------------------------------------+
bool InNYSession()
  {
   if(!UseNYHours) return true;
   MqlDateTime dt; TimeCurrent(dt);
   int hh = dt.hour;  // server time; user can adjust if broker offset differs
   return (hh >= 13 && hh < 20);   // ~09:30–16:00 NY in UTC
  }

//+------------------------------------------------------------------+
//| ---- Position management ------------------------------------    |
//+------------------------------------------------------------------+
bool HasPosition()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(PositionSelectByTicket(tk) &&
         PositionGetInteger(POSITION_MAGIC)==Magic &&
         PositionGetString(POSITION_SYMBOL)==_Symbol)
         return true;
     }
   return false;
  }

double LotByRisk(double slPoints)
  {
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk = eq * RiskPercent / 100.0;
   double tv   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts==0 || tv==0 || slPoints<=0) return SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double pointValue = tv / (ts / _Point);
   double lots = risk / (slPoints * pointValue);
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stp  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathMax(minL, MathMin(maxL, MathFloor(lots/stp)*stp));
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| ---- Execution -------------------------------------------------- |
//+------------------------------------------------------------------+
void TryBuy()
  {
   if(HasPosition()) return;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl  = cH1.lastLo;             // beneath the last buyers' line
   if(sl >= ask) return;
   double slPts = (ask - sl) / _Point;
   long stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(slPts < stopsLvl + 2) slPts = stopsLvl + 2;
   sl = ask - slPts * _Point;
   double tp = ask + slPts * RR * _Point;
   double lots = LotByRisk(slPts);
   if(trade.Buy(lots, _Symbol, ask, sl, tp, TradeComment))
      Print("ICC BUY filled @ ", ask, " SL=", sl, " TP=", tp, " lots=", lots);
   else
      Print("ICC BUY failed: ", trade.ResultRetcode(), " ", trade.ResultComment());
  }

void TrySell()
  {
   if(HasPosition()) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = cH1.lastHi;             // above the last sellers' line
   if(sl <= bid) return;
   double slPts = (sl - bid) / _Point;
   long stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(slPts < stopsLvl + 2) slPts = stopsLvl + 2;
   sl = bid + slPts * _Point;
   double tp = bid - slPts * RR * _Point;
   double lots = LotByRisk(slPts);
   if(trade.Sell(lots, _Symbol, bid, sl, tp, TradeComment))
      Print("ICC SELL filled @ ", bid, " SL=", sl, " TP=", tp, " lots=", lots);
   else
      Print("ICC SELL failed: ", trade.ResultRetcode(), " ", trade.ResultComment());
  }

//+------------------------------------------------------------------+
//| ---- Main loop -------------------------------------------------- |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Operate once per closed trigger-TF bar
   datetime tNow = iTime(_Symbol, TrigTF, 0);
   if(tNow == lastBarTime) return;
   lastBarTime = tNow;

   // 1) Refresh swing cache on every TF
   RefreshSwings(BiasTF, cD1);
   RefreshSwings(MidTF,  cH4);
   RefreshSwings(WorkTF, cH1);
   RefreshSwings(TrigTF, cM15);

   int bD1 = BiasOf(cD1), bH4 = BiasOf(cH4),
       bH1 = BiasOf(cH1), bM15= BiasOf(cM15);

   // 2) Auto-mark current chart with Sci-style swing lines
   MarkChartSwings();
   DrawCorrectionZone(bH1);

   // 3) Correlation cascade gate
   bool alignBull = StrictAlign
       ? (bD1== 1 && bH4== 1 && bH1== 1 && bM15== 1)
       : (bH1== 1 && bM15== 1);
   bool alignBear = StrictAlign
       ? (bD1==-1 && bH4==-1 && bH1==-1 && bM15==-1)
       : (bH1==-1 && bM15==-1);

   string cascade = alignBull ? "▲ ALIGNED LONG" :
                    alignBear ? "▼ ALIGNED SHORT" : "✗ NOT ALIGNED";
   DrawDashboard(bD1, bH4, bH1, bM15, cascade);

   // 4) Continuation trigger on closed M15 bar
   double trigClose = iClose(_Symbol, TrigTF, 1);

   bool buyContin  = alignBull && cH1.lastHi>0 && trigClose > cH1.lastHi;
   bool sellContin = alignBear && cH1.lastLo>0 && trigClose < cH1.lastLo;

   // Session filter
   if(!InNYSession()) { buyContin = false; sellContin = false; }

   // Debounce same-bar signals
   if(tNow == lastSigTime) return;

   // 5) Execute
   if(buyContin)        { TryBuy();  lastSigTime = tNow; }
   else if(sellContin)  { TrySell(); lastSigTime = tNow; }
  }
//+------------------------------------------------------------------+
