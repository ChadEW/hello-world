//+------------------------------------------------------------------+
//|                                     ICC_TradesBySci_v3_1.mq5      |
//|   COMBINED INDICATOR — Sci swings + body-close S/R + cascade      |
//|   dashboard + broken-level handling + retest state                |
//|   + flashing entry/exit boxes (with Entry / SL / TP prices)       |
//|   + NEW v3.1: RETEST-CONFIRMATION ENTRIES                         |
//|       A broken level retested from the other side that then       |
//|       REJECTS (closes back in the break direction) fires a real   |
//|       BUY/SELL signal — broken-S/R-becomes-opposite play.         |
//|   Built for Chad Woodyard, July 2026                              |
//+------------------------------------------------------------------+
#property copyright "Chad Woodyard"
#property version   "3.10"
#property indicator_chart_window
#property indicator_plots 0

//--- enums
enum ENUM_SR_DUR   { SR_DAYS = 0, SR_SESSIONS = 1 };
enum ENUM_BRK_MODE { BRK_GRAY = 0, BRK_DELETE = 1 };

//============================= INPUTS =================================
input group "Swing / Structure (Sci style)"
input int    SwingLen      = 5;                 // Swing pivot length (bars L/R)
input bool   ShowSwings    = true;              // Draw swing high/low rays
input int    MaxSwings     = 6;                 // Max recent swing lines kept
input color  ColHigh       = clrDodgerBlue;     // Swing High (sellers' line)
input color  ColLow        = clrCrimson;        // Swing Low (buyers' line)

input group "Timeframe Cascade (D1 -> H4 -> H1 -> M15)"
input ENUM_TIMEFRAMES BiasTF   = PERIOD_D1;     // Top bias TF
input ENUM_TIMEFRAMES MidTF    = PERIOD_H4;     // Mid TF
input ENUM_TIMEFRAMES WorkTF   = PERIOD_H1;     // Working TF
input ENUM_TIMEFRAMES TrigTF   = PERIOD_M15;    // Trigger TF
input bool   StrictAlign       = true;          // Require all 4 TFs to agree
input int    CascadeSwingLen   = 5;             // Pivot length per-TF for cascade
input bool   ShowDashboard     = true;          // Show cascade dashboard

input group "Support / Resistance (body-close levels)"
input bool         SR_Show      = true;         // Show body-close S/R levels
input int          SR_MinTouch  = 3;            // Min body closes to confirm a level
input double       SR_TolPips   = 10.0;         // Zone tolerance (pips)
input ENUM_SR_DUR  SR_DurMode   = SR_DAYS;      // Level duration unit
input int          SR_DurN      = 3;            // Level duration (days or sessions)
input color        SR_ColRes    = clrOrange;    // Resistance color
input color        SR_ColSup    = clrTeal;      // Support color
input bool         SR_UseZone   = true;         // Draw as shaded zone (rectangle) vs line
input bool         SR_ShowCnt   = true;         // Show touch-count label
input int          SR_RefLen    = 20;           // Reference SMA length (S/R classifier)

input group "Broken-Level Behavior"
input ENUM_BRK_MODE BrkMode     = BRK_GRAY;     // When a level is broken
input double        BrkBufPips   = 2.0;         // Break buffer beyond level (pips)
input color         BrkColor     = clrDimGray;  // Grayed-out color

input group "Entry / Exit Flashing Dialog"
input bool   FlashOn        = true;             // Show flashing entry/exit dialog box
input int    FlashSeconds   = 6;                // How long the box flashes (seconds)
input int    FlashMs        = 400;              // Flash toggle interval (ms)
input ENUM_BASE_CORNER FlashCorner = CORNER_LEFT_UPPER; // Anchor corner
input int    FlashX         = 220;              // X offset (px)
input int    FlashY         = 30;               // Y offset (px)
input color  ColBuy         = clrLime;          // BUY box color
input color  ColSell        = clrRed;           // SELL box color
input color  ColExit        = clrOrange;        // EXIT box color
input double FlashRR        = 2.0;              // TP reward:risk (for price display)
input bool   ShowFlashPrices= true;             // Show Entry / SL / TP prices in the box

input group "Retest Flash + Confirmation Entry"
input bool   RetestOn       = true;             // Flash a small RETEST box on broken-level return
input int    RetestSeconds  = 4;                // How long the RETEST box flashes (seconds)
input color  ColRetest      = clrGold;          // RETEST box color
//--- NEW retest-confirmation entry ---
input bool   RetestEntryOn      = true;         // Fire ENTRY when a retest REJECTS (break direction)
input double RetestConfBufPips  = 1.0;          // Rejection confirmation buffer (pips)
input int    RetestArmBars      = 5;            // Arm window (bars) after a retest
input bool   RetestSepBar       = true;         // Require a separate confirmation bar
input double RetestSLbufPips    = 3.0;          // Retest SL buffer beyond level (pips)
input color  ColRBuy        = clrLime;          // RETEST BUY box color
input color  ColRSell       = clrRed;           // RETEST SELL box color

//============================ GLOBALS =================================
double  g_pip = 0.0, g_tol = 0.0, g_brkBuf = 0.0, g_confBuf = 0.0, g_slBuf = 0.0;
int      g_sessCount = 0, g_lastDayKey = -1;
datetime g_lastBarTime = 0;
int      g_barCount = 0;          // running closed-bar counter (arm window)
string   g_swingNames[];
int      g_uid = 0;
int      g_maHandle = INVALID_HANDLE;

// ---- S/R cluster storage (parallel arrays) ----
double   sr_price[];      int      sr_count[];
datetime sr_birthTime[];  int      sr_birthSes[];
datetime sr_birthBar[];   bool     sr_isRes[];
bool     sr_drawn[];      bool     sr_broken[];
bool     sr_retested[];   bool     sr_armed[];
int      sr_armBar[];     string   sr_name[];

// ---- cascade bias cache ----
struct SwingCache { double lastHi, prevHi, lastLo, prevLo; };
SwingCache cD1, cH4, cH1, cM15;
int  biasD1=0, biasH4=0, biasH1=0, biasM15=0;
bool alignBull=false, alignBear=false;
double wkLastHi=0, wkLastLo=0;

// ---- virtual position (for entry/exit flashing) ----
int      g_posDir = 0;
double   g_posSL  = 0.0;

// ---- main flashing dialog state ----
string   FLASH_NAME = "ICCv3_FLASH";
bool     g_flashActive = false;
int      g_flashTicks  = 0;
bool     g_flashPhase  = false;
string   g_flashMsg    = "";
color    g_flashBase   = clrLime;
bool     g_flashHasPx  = false;
double   g_flashEntry  = 0.0, g_flashSL = 0.0, g_flashTP = 0.0;

// ---- RETEST flash state (smaller box) ----
string   RETEST_NAME = "ICCv3_RETEST";
bool     g_reActive  = false;
int      g_reTicks   = 0;
bool     g_rePhase   = false;
string   g_reMsg     = "";

string SR_PFX = "ICCv3_SR_";
string SW_PFX = "ICCv3_SW_";

//+------------------------------------------------------------------+
int OnInit()
  {
   g_pip     = _Point * ((_Digits==3 || _Digits==5) ? 10 : 1);
   g_tol     = SR_TolPips        * g_pip;
   g_brkBuf  = BrkBufPips        * g_pip;
   g_confBuf = RetestConfBufPips * g_pip;
   g_slBuf   = RetestSLbufPips   * g_pip;
   g_maHandle = iMA(_Symbol, _Period, SR_RefLen, 0, MODE_SMA, PRICE_CLOSE);
   if(g_maHandle==INVALID_HANDLE)
      Print("Warning: could not create SMA handle for S/R classifier.");
   IndicatorSetString(INDICATOR_SHORTNAME, "ICC-Sci v3.1");
   if(FlashOn) EventSetMillisecondTimer(FlashMs);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_maHandle!=INVALID_HANDLE) IndicatorRelease(g_maHandle);
   ObjectsDeleteAll(0, SR_PFX);
   ObjectsDeleteAll(0, SW_PFX);
   ObjectDelete(0, FLASH_NAME);      ObjectDelete(0, FLASH_NAME+"_bg");
   ObjectDelete(0, FLASH_NAME+"_e"); ObjectDelete(0, FLASH_NAME+"_sl");
   ObjectDelete(0, FLASH_NAME+"_tp");
   ObjectDelete(0, RETEST_NAME);     ObjectDelete(0, RETEST_NAME+"_bg");
   Comment("");
  }
//+------------------------------------------------------------------+
//| Timer: drives real-time flashing of BOTH dialog boxes            |
//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!FlashOn) return;
   bool redraw = false;
   if(g_flashActive)
     {
      g_flashPhase = !g_flashPhase;
      DrawFlashBox(g_flashPhase);
      g_flashTicks--;
      if(g_flashTicks <= 0)
        {
         g_flashActive = false;
         ObjectDelete(0, FLASH_NAME);      ObjectDelete(0, FLASH_NAME+"_bg");
         ObjectDelete(0, FLASH_NAME+"_e"); ObjectDelete(0, FLASH_NAME+"_sl");
         ObjectDelete(0, FLASH_NAME+"_tp");
        }
      redraw = true;
     }
   if(g_reActive)
     {
      g_rePhase = !g_rePhase;
      DrawRetestBox(g_rePhase);
      g_reTicks--;
      if(g_reTicks <= 0)
        {
         g_reActive = false;
         ObjectDelete(0, RETEST_NAME); ObjectDelete(0, RETEST_NAME+"_bg");
        }
      redraw = true;
     }
   if(redraw) ChartRedraw();
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
   if(rates_total < SwingLen*2 + 5) return(rates_total);
   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   datetime curBarTime = time[0];
   if(curBarTime == g_lastBarTime)
     {
      UpdateActiveLevels(time[0]);
      return(rates_total);
     }
   g_lastBarTime = curBarTime;
   g_barCount++;                         // new closed bar

   double   c = close[1];
   datetime t = time[1];

   // 1) cascade + dashboard
   EvaluateCascade();

   // 2) Sci swing rays
   ProcessSwing(rates_total, time, high, low);

   // 3) body-close S/R with broken + retest + confirmation
   if(SR_Show)
     {
      SR_CheckBroken(c);
      SR_CheckRetest(high[1], low[1], c);
      SR_CheckConfirm(c);              // NEW: retest-rejection entries
      ProcessBar(c, t);
      ExpireLevels(time[0]);
      UpdateActiveLevels(time[0]);
     }

   // 4) cascade entry/exit detection -> flashing box
   EvaluateSignals(c);

   if(ShowDashboard) UpdateDashboard();
   return(rates_total);
  }
//+==================================================================+
//|                 CASCADE BIAS ENGINE                              |
//+==================================================================+
bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid = iHigh(_Symbol, tf, shift);
   if(mid==0) return false;
   for(int i=1;i<=L;i++)
     {
      if(iHigh(_Symbol,tf,shift-i) >= mid) return false;
      if(iHigh(_Symbol,tf,shift+i) >  mid) return false;
     }
   return true;
  }
bool IsPivotLowTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid = iLow(_Symbol, tf, shift);
   if(mid==0) return false;
   for(int i=1;i<=L;i++)
     {
      if(iLow(_Symbol,tf,shift-i) <= mid) return false;
      if(iLow(_Symbol,tf,shift+i) <  mid) return false;
     }
   return true;
  }
void RefreshSwingsTF(ENUM_TIMEFRAMES tf, SwingCache &c)
  {
   c.lastHi=c.prevHi=c.lastLo=c.prevLo=0;
   int bars = Bars(_Symbol, tf);
   int fh=0, fl=0;
   for(int shift=CascadeSwingLen+1; shift<bars-CascadeSwingLen-1 && (fh<2||fl<2); shift++)
     {
      if(fh<2 && IsPivotHighTF(tf,shift,CascadeSwingLen))
        { double px=iHigh(_Symbol,tf,shift); if(fh==0) c.lastHi=px; else c.prevHi=px; fh++; }
      if(fl<2 && IsPivotLowTF(tf,shift,CascadeSwingLen))
        { double px=iLow(_Symbol,tf,shift);  if(fl==0) c.lastLo=px; else c.prevLo=px; fl++; }
     }
  }
int BiasOf(const SwingCache &c)
  {
   if(c.lastHi==0||c.prevHi==0||c.lastLo==0||c.prevLo==0) return 0;
   if(c.lastHi>c.prevHi && c.lastLo>c.prevLo) return  1;
   if(c.lastHi<c.prevHi && c.lastLo<c.prevLo) return -1;
   return 0;
  }
void EvaluateCascade()
  {
   RefreshSwingsTF(BiasTF, cD1);
   RefreshSwingsTF(MidTF,  cH4);
   RefreshSwingsTF(WorkTF, cH1);
   RefreshSwingsTF(TrigTF, cM15);
   biasD1=BiasOf(cD1); biasH4=BiasOf(cH4); biasH1=BiasOf(cH1); biasM15=BiasOf(cM15);
   wkLastHi = cH1.lastHi;
   wkLastLo = cH1.lastLo;
   if(StrictAlign)
     {
      alignBull = (biasD1==1 && biasH4==1 && biasH1==1 && biasM15==1);
      alignBear = (biasD1==-1&& biasH4==-1&& biasH1==-1&& biasM15==-1);
     }
   else
     {
      alignBull = (biasH1==1 && biasM15==1);
      alignBear = (biasH1==-1&& biasM15==-1);
     }
  }
//+==================================================================+
//|                 CASCADE ENTRY / EXIT SIGNALS                     |
//+==================================================================+
void EvaluateSignals(double barClose)
  {
   double trigClose = iClose(_Symbol, TrigTF, 1);
   bool buySig  = alignBull && wkLastHi>0 && trigClose > wkLastHi;
   bool sellSig = alignBear && wkLastLo>0 && trigClose < wkLastLo;

   // exits first (no prices on exit)
   if(g_posDir==1)
     {
      if(sellSig || (g_posSL>0 && barClose < g_posSL))
        { TriggerFlash("EXIT LONG",  ColExit, false,0,0,0); g_posDir=0; g_posSL=0; }
     }
   else if(g_posDir==-1)
     {
      if(buySig || (g_posSL>0 && barClose > g_posSL))
        { TriggerFlash("EXIT SHORT", ColExit, false,0,0,0); g_posDir=0; g_posSL=0; }
     }

   // cascade entries when flat (retest entries handled in SR_CheckConfirm)
   if(g_posDir==0 && buySig)
     {
      double e=barClose, sl=wkLastLo, tp=barClose+(barClose-wkLastLo)*FlashRR;
      TriggerFlash("BUY ENTRY", ColBuy, true, e, sl, tp);
      g_posDir=1; g_posSL=wkLastLo;
     }
   else if(g_posDir==0 && sellSig)
     {
      double e=barClose, sl=wkLastHi, tp=barClose-(wkLastHi-barClose)*FlashRR;
      TriggerFlash("SELL ENTRY", ColSell, true, e, sl, tp);
      g_posDir=-1; g_posSL=wkLastHi;
     }
  }
//+==================================================================+
//|                 FLASHING DIALOG BOXES                            |
//+==================================================================+
void TriggerFlash(string msg, color base, bool hasPx, double e, double sl, double tp)
  {
   if(!FlashOn) return;
   g_flashActive = true;
   g_flashMsg    = msg;
   g_flashBase   = base;
   g_flashPhase  = true;
   g_flashHasPx  = (hasPx && ShowFlashPrices);
   g_flashEntry  = e;  g_flashSL = sl;  g_flashTP = tp;
   g_flashTicks  = (int)MathMax(2, (FlashSeconds*1000)/MathMax(50,FlashMs));
   DrawFlashBox(true);
   ChartRedraw();
   Alert("ICC v3.1: ", msg, " | ", _Symbol);
  }
void SetLabel(string nm, int corner, int x, int y, string txt, color col, int fsize, string font)
  {
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,   corner);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,nm,OBJPROP_TEXT,     txt);
   ObjectSetString (0,nm,OBJPROP_FONT,     font);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE, fsize);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,    col);
  }
void DrawFlashBox(bool on)
  {
   int boxH = g_flashHasPx ? 92 : 40;
   string bg = FLASH_NAME+"_bg";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,   FlashCorner);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,FlashX);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,FlashY);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,    180);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,    boxH);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,  on ? g_flashBase : clrBlack);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,    g_flashBase);
   ObjectSetInteger(0,bg,OBJPROP_WIDTH,    2);
   ObjectSetInteger(0,bg,OBJPROP_BACK,     false);

   SetLabel(FLASH_NAME, FlashCorner, FlashX+12, FlashY+11, g_flashMsg,
            on ? clrWhite : g_flashBase, 12, "Arial Black");

   if(g_flashHasPx)
     {
      SetLabel(FLASH_NAME+"_e",  FlashCorner, FlashX+12, FlashY+34,
               "E:  "+DoubleToString(g_flashEntry,_Digits), clrWhite,  9, "Consolas");
      SetLabel(FLASH_NAME+"_sl", FlashCorner, FlashX+12, FlashY+53,
               "SL: "+DoubleToString(g_flashSL,_Digits),    clrTomato, 9, "Consolas");
      SetLabel(FLASH_NAME+"_tp", FlashCorner, FlashX+12, FlashY+72,
               "TP: "+DoubleToString(g_flashTP,_Digits),    clrLime,   9, "Consolas");
     }
   else
     {
      ObjectDelete(0, FLASH_NAME+"_e");
      ObjectDelete(0, FLASH_NAME+"_sl");
      ObjectDelete(0, FLASH_NAME+"_tp");
     }
  }
void TriggerRetest(string msg)
  {
   if(!RetestOn) return;
   g_reActive = true;
   g_reMsg    = msg;
   g_rePhase  = true;
   g_reTicks  = (int)MathMax(2, (RetestSeconds*1000)/MathMax(50,FlashMs));
   DrawRetestBox(true);
   ChartRedraw();
  }
void DrawRetestBox(bool on)
  {
   int rx = FlashX;
   int ry = FlashY + (g_flashHasPx ? 100 : 48);
   string bg = RETEST_NAME+"_bg";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,   FlashCorner);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,rx);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,ry);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,    180);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,    26);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,  on ? ColRetest : clrBlack);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,    ColRetest);
   ObjectSetInteger(0,bg,OBJPROP_WIDTH,    1);
   ObjectSetInteger(0,bg,OBJPROP_BACK,     false);
   SetLabel(RETEST_NAME, FlashCorner, rx+10, ry+6, g_reMsg,
            on ? clrBlack : ColRetest, 9, "Arial Black");
  }
//+==================================================================+
//|                 BODY-CLOSE S/R ENGINE                            |
//+==================================================================+
void SR_CheckBroken(double c)
  {
   for(int i=ArraySize(sr_price)-1; i>=0; i--)
     {
      if(!sr_drawn[i] || sr_broken[i]) continue;
      double lvl = sr_price[i];
      bool brokeUp   = ( sr_isRes[i] && c > lvl + g_brkBuf);
      bool brokeDown = (!sr_isRes[i] && c < lvl - g_brkBuf);
      if(brokeUp || brokeDown)
        {
         if(BrkMode==BRK_DELETE) { DeleteLevelObjects(i); RemoveAt(i); }
         else                    { sr_broken[i]=true; GrayOutLevel(i); }
        }
     }
  }
//+------------------------------------------------------------------+
//| Retest: a broken level is revisited from the other side.         |
//+------------------------------------------------------------------+
void SR_CheckRetest(double barHigh, double barLow, double barClose)
  {
   if(BrkMode!=BRK_GRAY) return;
   for(int i=ArraySize(sr_price)-1; i>=0; i--)
     {
      if(!sr_broken[i] || sr_retested[i]) continue;
      double lvl = sr_price[i];
      bool retRes = ( sr_isRes[i] && barLow  <= lvl + g_brkBuf && barClose >= lvl - g_brkBuf);
      bool retSup = (!sr_isRes[i] && barHigh >= lvl - g_brkBuf && barClose <= lvl + g_brkBuf);
      if(retRes || retSup)
        {
         sr_retested[i] = true;
         sr_armed[i]    = true;
         sr_armBar[i]   = g_barCount;
         TriggerRetest(sr_isRes[i] ? "RETEST (old R -> S)" : "RETEST (old S -> R)");
        }
     }
  }
//+------------------------------------------------------------------+
//| NEW: retest-confirmation entry. An armed level that REJECTS in    |
//| the break direction fires a BUY/SELL with its own flash + alert.  |
//+------------------------------------------------------------------+
void SR_CheckConfirm(double c)
  {
   if(!RetestEntryOn) return;
   for(int i=ArraySize(sr_price)-1; i>=0; i--)
     {
      if(!sr_armed[i]) continue;
      double lvl   = sr_price[i];
      int    age   = g_barCount - sr_armBar[i];
      if(age > RetestArmBars) { sr_armed[i]=false; continue; }
      bool canCheck = RetestSepBar ? (age>=1) : (age>=0);
      if(!canCheck) continue;
      // broken resistance now support -> close back ABOVE = BUY
      bool confBuy  = ( sr_isRes[i] && c > lvl + g_confBuf);
      // broken support now resistance -> close back BELOW = SELL
      bool confSell = (!sr_isRes[i] && c < lvl - g_confBuf);
      if(confBuy && g_posDir==0)
        {
         sr_armed[i]=false;
         double sl=lvl-g_slBuf, tp=c+(c-sl)*FlashRR;
         TriggerFlash("RETEST BUY", ColRBuy, true, c, sl, tp);
         SendNotification("ICC v3.1 RETEST BUY "+_Symbol+" @ "+DoubleToString(c,_Digits));
         g_posDir=1; g_posSL=sl;
        }
      else if(confSell && g_posDir==0)
        {
         sr_armed[i]=false;
         double sl=lvl+g_slBuf, tp=c-(sl-c)*FlashRR;
         TriggerFlash("RETEST SELL", ColRSell, true, c, sl, tp);
         SendNotification("ICC v3.1 RETEST SELL "+_Symbol+" @ "+DoubleToString(c,_Digits));
         g_posDir=-1; g_posSL=sl;
        }
     }
  }
void GrayOutLevel(int i)
  {
   string nm=sr_name[i];
   if(SR_UseZone && ObjectFind(0,nm+"_box")>=0)
     {
      ObjectSetInteger(0,nm+"_box",OBJPROP_COLOR,BrkColor);
      ObjectSetInteger(0,nm+"_box",OBJPROP_STYLE,STYLE_DOT);
     }
   if(!SR_UseZone && ObjectFind(0,nm+"_ln")>=0)
     {
      ObjectSetInteger(0,nm+"_ln",OBJPROP_COLOR,BrkColor);
      ObjectSetInteger(0,nm+"_ln",OBJPROP_STYLE,STYLE_DASH);
     }
   if(SR_ShowCnt && ObjectFind(0,nm+"_lb")>=0)
     {
      ObjectSetInteger(0,nm+"_lb",OBJPROP_COLOR,BrkColor);
      ObjectSetString (0,nm+"_lb",OBJPROP_TEXT,
                       "x "+(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i]));
     }
  }
void ProcessBar(double c, datetime t)
  {
   MqlDateTime mt; TimeToStruct(t,mt);
   int dayKey = mt.year*10000 + mt.mon*100 + mt.day;
   if(dayKey!=g_lastDayKey){ g_sessCount++; g_lastDayKey=dayKey; }

   bool matched=false;
   for(int i=0;i<ArraySize(sr_price);i++)
     {
      if(sr_broken[i]) continue;
      if(MathAbs(c - sr_price[i]) <= g_tol)
        {
         int nc = sr_count[i]+1;
         sr_price[i] = (sr_price[i]*sr_count[i] + c)/nc;
         sr_count[i] = nc;
         matched=true;
         if(nc==SR_MinTouch && !sr_drawn[i])
           { sr_drawn[i]=true; sr_isRes[i]=(sr_price[i]>=RefSMA()); DrawLevel(i); }
         else if(nc>SR_MinTouch && SR_ShowCnt && sr_drawn[i])
            UpdateLabel(i);
         break;
        }
     }
   if(!matched)
     {
      int n=ArraySize(sr_price);
      ArrayResize(sr_price,n+1);     ArrayResize(sr_count,n+1);
      ArrayResize(sr_birthTime,n+1); ArrayResize(sr_birthSes,n+1);
      ArrayResize(sr_birthBar,n+1);  ArrayResize(sr_isRes,n+1);
      ArrayResize(sr_drawn,n+1);     ArrayResize(sr_broken,n+1);
      ArrayResize(sr_retested,n+1);  ArrayResize(sr_armed,n+1);
      ArrayResize(sr_armBar,n+1);    ArrayResize(sr_name,n+1);
      sr_price[n]=c; sr_count[n]=1; sr_birthTime[n]=t; sr_birthSes[n]=g_sessCount;
      sr_birthBar[n]=t; sr_isRes[n]=false; sr_drawn[n]=false; sr_broken[n]=false;
      sr_retested[n]=false; sr_armed[n]=false; sr_armBar[n]=0;
      sr_name[n]=SR_PFX+IntegerToString(g_uid++);
      if(ArraySize(sr_price)>60) RemoveAt(0);
     }
  }
void ExpireLevels(datetime now)
  {
   for(int i=ArraySize(sr_price)-1;i>=0;i--)
     {
      bool expired=false;
      if(SR_DurMode==SR_DAYS) expired=((now-sr_birthTime[i])>=(long)SR_DurN*86400);
      else                    expired=((g_sessCount-sr_birthSes[i])>=SR_DurN);
      if(expired){ DeleteLevelObjects(i); RemoveAt(i); }
     }
  }
void UpdateActiveLevels(datetime now)
  {
   for(int i=0;i<ArraySize(sr_price);i++)
     {
      if(!sr_drawn[i] || sr_broken[i]) continue;
      string nm=sr_name[i];
      if(SR_UseZone){ if(ObjectFind(0,nm+"_box")>=0) ObjectSetInteger(0,nm+"_box",OBJPROP_TIME,1,now); }
      else          { if(ObjectFind(0,nm+"_ln")>=0)  ObjectSetInteger(0,nm+"_ln",OBJPROP_TIME,1,now); }
      if(SR_ShowCnt && ObjectFind(0,nm+"_lb")>=0) ObjectSetInteger(0,nm+"_lb",OBJPROP_TIME,now);
     }
  }
void DrawLevel(int i)
  {
   string nm=sr_name[i]; color col=sr_isRes[i]?SR_ColRes:SR_ColSup;
   double p=sr_price[i]; datetime t1=sr_birthBar[i]; datetime t2=TimeCurrent();
   if(SR_UseZone)
     {
      string on=nm+"_box";
      ObjectCreate(0,on,OBJ_RECTANGLE,0,t1,p+g_tol/2.0,t2,p-g_tol/2.0);
      ObjectSetInteger(0,on,OBJPROP_COLOR,col);
      ObjectSetInteger(0,on,OBJPROP_FILL,true);
      ObjectSetInteger(0,on,OBJPROP_BACK,true);
     }
   else
     {
      string on=nm+"_ln";
      ObjectCreate(0,on,OBJ_TREND,0,t1,p,t2,p);
      ObjectSetInteger(0,on,OBJPROP_COLOR,col);
      ObjectSetInteger(0,on,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,on,OBJPROP_RAY_RIGHT,false);
     }
   if(SR_ShowCnt)
     {
      string lb=nm+"_lb";
      ObjectCreate(0,lb,OBJ_TEXT,0,t2,p);
      ObjectSetString(0,lb,OBJPROP_TEXT,(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i]));
      ObjectSetInteger(0,lb,OBJPROP_COLOR,col);
      ObjectSetInteger(0,lb,OBJPROP_ANCHOR,sr_isRes[i]?ANCHOR_LOWER:ANCHOR_UPPER);
      ObjectSetInteger(0,lb,OBJPROP_FONTSIZE,8);
     }
  }
void UpdateLabel(int i)
  {
   string lb=sr_name[i]+"_lb";
   if(ObjectFind(0,lb)>=0)
      ObjectSetString(0,lb,OBJPROP_TEXT,(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i]));
  }
void DeleteLevelObjects(int i)
  { string nm=sr_name[i]; ObjectDelete(0,nm+"_box"); ObjectDelete(0,nm+"_ln"); ObjectDelete(0,nm+"_lb"); }
void RemoveAt(int idx)
  {
   int n=ArraySize(sr_price); if(idx<0||idx>=n) return;
   for(int i=idx;i<n-1;i++)
     {
      sr_price[i]=sr_price[i+1];         sr_count[i]=sr_count[i+1];
      sr_birthTime[i]=sr_birthTime[i+1]; sr_birthSes[i]=sr_birthSes[i+1];
      sr_birthBar[i]=sr_birthBar[i+1];   sr_isRes[i]=sr_isRes[i+1];
      sr_drawn[i]=sr_drawn[i+1];         sr_broken[i]=sr_broken[i+1];
      sr_retested[i]=sr_retested[i+1];   sr_armed[i]=sr_armed[i+1];
      sr_armBar[i]=sr_armBar[i+1];       sr_name[i]=sr_name[i+1];
     }
   ArrayResize(sr_price,n-1);     ArrayResize(sr_count,n-1);
   ArrayResize(sr_birthTime,n-1); ArrayResize(sr_birthSes,n-1);
   ArrayResize(sr_birthBar,n-1);  ArrayResize(sr_isRes,n-1);
   ArrayResize(sr_drawn,n-1);     ArrayResize(sr_broken,n-1);
   ArrayResize(sr_retested,n-1);  ArrayResize(sr_armed,n-1);
   ArrayResize(sr_armBar,n-1);    ArrayResize(sr_name,n-1);
  }
double RefSMA()
  {
   if(g_maHandle==INVALID_HANDLE) return(SymbolInfoDouble(_Symbol,SYMBOL_BID));
   double buf[]; ArraySetAsSeries(buf,true);
   if(CopyBuffer(g_maHandle,0,1,1,buf)==1) return(buf[0]);
   return(SymbolInfoDouble(_Symbol,SYMBOL_BID));
  }
//+==================================================================+
//|                 SCI-STYLE SWING RAYS                             |
//+==================================================================+
void ProcessSwing(int rates_total, const datetime &time[],
                  const double &high[], const double &low[])
  {
   if(!ShowSwings) return;
   int c = SwingLen;
   bool isHigh=true, isLow=true;
   for(int k=1;k<=SwingLen;k++)
     {
      if(high[c] <= high[c+k] || high[c] <= high[c-k]) isHigh=false;
      if(low[c]  >= low[c+k]  || low[c]  >= low[c-k])  isLow =false;
     }
   if(isHigh) MakeSwing(time[c], high[c], ColHigh);
   if(isLow)  MakeSwing(time[c], low[c],  ColLow);
  }
void MakeSwing(datetime t, double px, color col)
  {
   string nm = SW_PFX + IntegerToString(g_uid++);
   ObjectCreate(0,nm,OBJ_TREND,0,t,px,TimeCurrent(),px);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,col);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,true);
   int n=ArraySize(g_swingNames); ArrayResize(g_swingNames,n+1); g_swingNames[n]=nm;
   while(ArraySize(g_swingNames) > MaxSwings*2)
     {
      ObjectDelete(0,g_swingNames[0]);
      for(int i=0;i<ArraySize(g_swingNames)-1;i++) g_swingNames[i]=g_swingNames[i+1];
      ArrayResize(g_swingNames,ArraySize(g_swingNames)-1);
     }
  }
//+==================================================================+
//|                 CASCADE DASHBOARD                                |
//+==================================================================+
int ActiveSRCount()
  {
   int cnt=0;
   for(int i=0;i<ArraySize(sr_drawn);i++) if(sr_drawn[i] && !sr_broken[i]) cnt++;
   return cnt;
  }
int ArmedCount()
  {
   int cnt=0;
   for(int i=0;i<ArraySize(sr_armed);i++) if(sr_armed[i]) cnt++;
   return cnt;
  }
void UpdateDashboard()
  {
   string bD = biasD1==1?"^":biasD1==-1?"v":"-";
   string b4 = biasH4==1?"^":biasH4==-1?"v":"-";
   string b1 = biasH1==1?"^":biasH1==-1?"v":"-";
   string b5 = biasM15==1?"^":biasM15==-1?"v":"-";
   string casc = alignBull ? "^ ALIGNED LONG" : alignBear ? "v ALIGNED SHORT" : "x NOT ALIGNED";
   string posTxt = g_posDir==1?"LONG":g_posDir==-1?"SHORT":"flat";
   string d = "=== ICC TradesBySci v3.1 ================\n";
   d += " Cascade (D1 H4 H1 M15): "+bD+" "+b4+" "+b1+" "+b5+"\n";
   d += " Status:   "+casc+"\n";
   d += " Position: "+posTxt+"\n";
   d += " S/R lvls: "+IntegerToString(ActiveSRCount())+
              "  | armed: "+IntegerToString(ArmedCount())+"\n";
   d += "=========================================";
   Comment(d);
  }
//+------------------------------------------------------------------+
