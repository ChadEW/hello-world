//+------------------------------------------------------------------+
//|                                     ICC_TradesBySci_v3_2.mq5      |
//|   COMBINED INDICATOR — Sci swings + body-close S/R + cascade      |
//|   dashboard + broken-level handling + retest state                |
//|   + flashing entry/exit boxes (with Entry / SL / TP prices)       |
//|                                                                  |
//|   NEW v3.2: TRUE ICC PULLBACK SIGNALS (Sci style)                |
//|     Loosened bias (single break of structure) + HTF filter, plus |
//|     an Indication -> Correction -> Continuation state machine:   |
//|        Indication  = M15 close breaks last H1 swing (BOS)        |
//|        Correction  = pullback into a discount/premium fib zone   |
//|        Continuation= M15 resumption close -> BUY/SELL flash      |
//|     Retest-confirmation entries retained from v3.1.              |
//|                                                                  |
//|   Built for Chad Woodyard, July 2026                             |
//+------------------------------------------------------------------+
#property copyright "Chad Woodyard"
#property version   "3.30"
#property indicator_chart_window
#property indicator_plots 0
//+------------------------------------------------------------------+
//|  v3.3 MARKET-STRUCTURE ENGINE REPLACEMENT (see Appendix O)        |
//|  ----------------------------------------------------------------|
//|  NOTE: this file is the COMBINED INDICATOR twin (OnCalculate,     |
//|  no order placement). It marks structure and fires flash boxes +  |
//|  push notifications only; the EA (ICC_TradesBySci_EA_v3_0.mq5)    |
//|  executes live. Kept in sync so both platforms share one engine. |
//|                                                                  |
//|  PRESERVED unchanged: dashboard, flash-box entry/SL/TP display    |
//|  ("money/trade management" analog), virtual-position tracking,    |
//|  all v3.2 inputs, the soft-D1 HTF bias, the body-close S/R engine,|
//|  swing rays, retest logic, and the ICC state-machine skeleton     |
//|  (PH_NONE -> PH_INDICATION -> PH_CORRECTION -> signal).           |
//|                                                                  |
//|  REPLACED: the raw multi-TF pivot detection feeding the ICC       |
//|  engine is superseded by a modular Smart Money engine (MSE_*):    |
//|    1. Protected swing detection (internal + external fractals)   |
//|    2. Liquidity engine (BSL/SSL, equal H/L, sweep + reclaim)     |
//|    3. Fair Value Gaps (detect, draw, fill %, pullback required)  |
//|    4. Institutional displacement scoring (ATR/body/close/wick)   |
//|    5. Dual market structure (external=direction, internal=entry) |
//|    6. Order / mitigation blocks (Trades-by-Sci enhancement)      |
//|                                                                  |
//|  BACKWARD-COMPAT: every new gate sits behind an input. Turn the  |
//|  InpMSE_* requirement toggles OFF to reproduce v3.2 behaviour.   |
//+------------------------------------------------------------------+
//--- enums
enum ENUM_SR_DUR   { SR_DAYS = 0, SR_SESSIONS = 1 };
enum ENUM_BRK_MODE { BRK_GRAY = 0, BRK_DELETE = 1 };
enum ENUM_ICC_PHASE{ PH_NONE=0, PH_INDICATION=1, PH_CORRECTION=2 };
//============================= INPUTS =================================
input group "Swing / Structure (Sci style)"
input int    SwingLen      = 5;                 // Swing pivot length (bars L/R)
input bool   ShowSwings    = true;              // Draw swing high/low rays
input int    MaxSwings     = 6;                 // Max recent swing lines kept
input color  ColHigh       = clrDodgerBlue;     // Swing High (sellers' line)
input color  ColLow        = clrCrimson;        // Swing Low (buyers' line)

input group "Timeframe Cascade (D1 -> H4 -> H1 -> M15)"
input ENUM_TIMEFRAMES BiasTF   = PERIOD_D1;     // Top bias TF
input ENUM_TIMEFRAMES MidTF    = PERIOD_H4;     // Mid / primary Indication TF
input ENUM_TIMEFRAMES WorkTF   = PERIOD_H1;     // Working TF
input ENUM_TIMEFRAMES TrigTF   = PERIOD_M15;    // Trigger TF
input bool   StrictAlign       = false;         // Require all 4 TFs to agree (leave OFF for Sci)
input int    CascadeSwingLen   = 5;             // Pivot length per-TF for cascade
input bool   ShowDashboard     = true;          // Show cascade dashboard

input group "Bias / ICC Pullback (Sci Indication->Correction->Continuation)"
input bool   BiasLoose         = true;          // NEW: single BOS sets trend (HH w/o LL = bull)
input bool   UseD1Filter       = true;          // NEW: require D1 to not oppose H4 bias
input bool   UseICCPullback    = true;          // NEW: fire ICC continuation flash/alert
input bool   UseCascadeEntries = false;         // v1 breakout flash (buys the breakout)
input double CorrRetraceMin    = 0.500;         // Min pullback into discount/premium (fib)
input double CorrRetraceMax    = 0.900;         // Max pullback before setup invalidates (fib)
input int    ICC_ExpiryBars    = 30;            // Bars to complete correction+continuation
input bool   VerboseLog        = true;          // NEW: print bias/phase/signals per bar

//==================================================================
//  NEW INPUTS — SMC MARKET STRUCTURE ENGINE (v3.3). Every threshold
//  configurable. Requirement toggles default ON (new behaviour);
//  turn them OFF to reproduce the v3.2 raw-pivot workflow exactly.
//==================================================================
input group "=== SMC: Structure TF & Protected Swings ==="
input ENUM_TIMEFRAMES InpMSE_TF   = PERIOD_CURRENT; // Structure TF (PERIOD_CURRENT = chart)
input int    InpIntSwingStrength   = 2;          // Internal swing fractal strength (bars each side)
input int    InpExtSwingStrength   = 4;          // External swing fractal strength (bars each side)
input int    InpStructLookback     = 300;        // Bars scanned to locate protected swings
input bool   InpBOSUseClose        = true;       // BOS requires BODY close beyond the protected swing
input bool   InpExtTrendControlsDir= true;       // External trend gates trade DIRECTION
input bool   InpIntTrendControlsEnt= true;       // Internal BOS gates the ENTRY (Indication) trigger

input group "=== SMC: Liquidity Engine ==="
input bool   InpRequireSweep       = true;       // Require a liquidity sweep + reclaim before Indication
input int    InpLiqLookback        = 120;        // Bars scanned for liquidity pools / equal levels
input double InpEqualLevelTolPips  = 2.0;        // Tolerance for equal highs / equal lows (pips)
input bool   InpRequireReclaim     = true;       // Require price to RECLAIM the swept level
input int    InpReclaimBars        = 3;          // Bars allowed for the reclaim to complete
input int    InpSweepValidBars     = 8;          // Sweep stays valid to arm an Indication for N bars
input double InpSweepMinPips        = 1.0;        // Min penetration beyond the level to count as a raid

input group "=== SMC: Fair Value Gaps ==="
input bool   InpRequireFVGpullback = true;       // Correction must pull back into an active FVG
input bool   InpDrawFVG            = true;       // Draw detected FVGs on the chart
input int    InpFVGScanBars        = 120;        // Bars scanned each update for new FVGs
input int    InpMaxTrackedFVG      = 40;         // Max FVGs held in memory (oldest dropped)
input double InpMinFVGPips          = 1.0;        // Min Fair Value Gap size (pips)
input double InpFVGFillInvalidate  = 100.0;      // Fill %% at which an FVG is retired (0..100)
input color  InpFVGBullColor       = clrTeal;    // Bullish FVG fill colour
input color  InpFVGBearColor       = clrMaroon;  // Bearish FVG fill colour

input group "=== SMC: Institutional Displacement ==="
input bool   InpRejectWeakBreaks   = true;       // Reject Indication breaks that score below threshold
input int    InpDispATRPeriod      = 14;         // ATR period for displacement normalisation
input double InpDispATRMult        = 1.5;        // Range >= ATR*mult scores full ATR points
input double InpDispMinBodyPct     = 0.50;       // Min body/range for a clean displacement
input double InpDispMinCloseStr    = 0.60;       // Min closing strength (close near the extreme)
input double InpDispMaxWickRatio   = 1.00;       // Max opposing-wick/body ratio tolerated
input double InpDispMinScore       = 60.0;       // Reject displacements scoring below this (0..100)

input group "=== SMC: Order / Mitigation Blocks ==="
input bool   InpUseOrderBlocks     = true;       // Enable order-block detection & tracking
input bool   InpRequireOB          = true;       // Continuation must occur inside an unmitigated OB
input int    InpOBScanBack         = 8;          // Bars searched back from a displacement for the OB
input int    InpMaxTrackedOB       = 40;         // Max order blocks held in memory
input bool   InpOBMitigateOnClose  = true;       // OB invalidated on a BODY close through it (else wick)
input bool   InpDrawOB             = true;       // Draw order blocks on the chart
input color  InpOBBullColor        = clrDarkGreen;// Bullish OB colour
input color  InpOBBearColor        = clrDarkRed; // Bearish OB colour

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
input bool   RetestEntryOn      = true;         // Fire ENTRY flash when a retest REJECTS
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
// ---- ICC pullback state machine ----
int    g_iccPhase=PH_NONE, g_iccDir=0;
double g_indLevel=0, g_indExtreme=0, g_corrExtreme=0;
int    g_iccStartBar=0;
// ---- virtual position (for entry/exit flashing) ----
int      g_posDir = 0;
double   g_posSL  = 0.0;
// ---- main flashing dialog state ----
string   FLASH_NAME = "ICCv32_FLASH";
bool     g_flashActive = false;
int      g_flashTicks  = 0;
bool     g_flashPhase  = false;
string   g_flashMsg    = "";
color    g_flashBase   = clrLime;
bool     g_flashHasPx  = false;
double   g_flashEntry  = 0.0, g_flashSL = 0.0, g_flashTP = 0.0;
// ---- RETEST flash state (smaller box) ----
string   RETEST_NAME = "ICCv32_RETEST";
bool     g_reActive  = false;
int      g_reTicks   = 0;
bool     g_rePhase   = false;
string   g_reMsg     = "";
string SR_PFX = "ICCv32_SR_";
string SW_PFX = "ICCv32_SW_";
// ---- v3.3 SMC market-structure engine state ----------------------
int      g_mseATR = INVALID_HANDLE;   // ATR handle on the structure TF
double   g_mseATRval = 0.0;
ENUM_TIMEFRAMES g_mseTF = PERIOD_CURRENT;
// dual structure
double   g_extProtHigh=0.0, g_extProtLow=0.0;   // external protected swings (direction)
double   g_intProtHigh=0.0, g_intProtLow=0.0;   // internal protected swings (entries)
int      g_extTrend=0, g_intTrend=0;            // 1 up / -1 down / 0 none
// liquidity
string   g_liqStatus="none";
double   g_bsl=0.0, g_ssl=0.0;                  // buy-/sell-side liquidity levels
int      g_sweepConfLong=0, g_sweepConfShort=0; // bars-remaining a sweep+reclaim stays valid
double   g_lastSweepLvl=0.0;
// displacement
double   g_lastDispScore=0.0;
// Fair Value Gap store
struct SFVG
  {
   double   top;      // upper edge
   double   bot;      // lower edge
   datetime time;     // middle-candle time (unique key)
   int      dir;      // 1 bullish / -1 bearish
   double   fillPct;  // max fill percentage seen (0..100)
   bool     active;   // still tradable
   string   obj;      // chart object name
  };
SFVG     g_fvg[];
// Order / Mitigation Block store
struct SOB
  {
   double   top;
   double   bot;
   datetime time;
   int      dir;      // 1 bullish OB / -1 bearish OB
   bool     mitigated;// price has returned into the block
   bool     active;   // not invalidated by an opposing close-through
   string   obj;
  };
SOB      g_ob[];
string   FVG_PFX="ICCv33_FVG_";
string   OB_PFX ="ICCv33_OB_";
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
   // v3.3: dedicated ATR on the SMC structure TF for displacement scoring
   g_mseTF=(InpMSE_TF==PERIOD_CURRENT)? (ENUM_TIMEFRAMES)_Period : InpMSE_TF;
   g_mseATR=iATR(_Symbol,g_mseTF,InpDispATRPeriod);
   if(g_mseATR==INVALID_HANDLE)
      Print("Warning: SMC ATR handle failed; displacement ATR score will be 0.");
   g_iccPhase=PH_NONE; g_iccDir=0;
   IndicatorSetString(INDICATOR_SHORTNAME, "ICC-Sci v3.3 (SMC)");
   if(FlashOn) EventSetMillisecondTimer(FlashMs);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_maHandle!=INVALID_HANDLE) IndicatorRelease(g_maHandle);
   if(g_mseATR!=INVALID_HANDLE)   IndicatorRelease(g_mseATR);   // v3.3
   ObjectsDeleteAll(0, SR_PFX);
   ObjectsDeleteAll(0, SW_PFX);
   ObjectsDeleteAll(0, FVG_PFX);   // v3.3 FVG rectangles
   ObjectsDeleteAll(0, OB_PFX);    // v3.3 order-block rectangles
   ObjectDelete(0, FLASH_NAME);      ObjectDelete(0, FLASH_NAME+"_bg");
   ObjectDelete(0, FLASH_NAME+"_e"); ObjectDelete(0, FLASH_NAME+"_sl");
   ObjectDelete(0, FLASH_NAME+"_tp");
   ObjectDelete(0, RETEST_NAME);     ObjectDelete(0, RETEST_NAME+"_bg");
   Comment("");
  }
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
        { g_reActive = false; ObjectDelete(0, RETEST_NAME); ObjectDelete(0, RETEST_NAME+"_bg"); }
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
     { UpdateActiveLevels(time[0]); return(rates_total); }
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
      SR_CheckConfirm(c);              // retest-rejection entries
      ProcessBar(c, t);
      ExpireLevels(time[0]);
      UpdateActiveLevels(time[0]);
     }
   // 3b) v3.3 SMC structure engine: protected swings, liquidity, FVGs,
   //     order blocks. Also overrides wkLastHi/wkLastLo with PROTECTED
   //     internal swings so the ICC Indication only breaks a protected swing.
   MSE_Update();
   // 4) ICC Indication->Correction->Continuation pullback engine
   ICC_Update();
   // 5) v1 cascade entry/exit detection -> flashing box (optional)
   EvaluateSignals(c);
   if(ShowDashboard) UpdateDashboard();
   return(rates_total);
  }
//+==================================================================+
//|                 CASCADE BIAS ENGINE (loosened)                   |
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
//--- v3.2 loosened bias: single break of structure sets a trend ----
int BiasOf(const SwingCache &c)
  {
   if(c.lastHi==0||c.prevHi==0||c.lastLo==0||c.prevLo==0) return 0;
   bool hh=c.lastHi>c.prevHi, hl=c.lastLo>c.prevLo;
   bool lh=c.lastHi<c.prevHi, ll=c.lastLo<c.prevLo;
   if(BiasLoose)
     {
      if(hh && !ll) return  1;
      if(ll && !hh) return -1;
      return 0;
     }
   if(hh && hl) return  1;
   if(lh && ll) return -1;
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
int HTFbias()
  {
   if(UseD1Filter)
     {
      if(biasH4==1  && biasD1!=-1) return  1;
      if(biasH4==-1 && biasD1!= 1) return -1;
      return 0;
     }
   return biasH4;
  }
string PhaseTxt(int p){ return p==PH_INDICATION?"IND":p==PH_CORRECTION?"COR":"---"; }

//+==================================================================+
//|==================================================================|
//|   v3.3 SMART MONEY STRUCTURE ENGINE (MSE_*)                       |
//|   Replaces the raw multi-TF pivot detection that fed the ICC      |
//|   engine. Fully modular; each concern is its own function and     |
//|   operates on the configurable structure TF (g_mseTF).            |
//|==================================================================|
//+==================================================================+

//--- Strict fractal high on the structure TF (greater than 'strength'
//    bars on each side). Confirmed once 'strength' newer bars exist.
bool MSE_IsFractalHigh(int shift,int strength)
  {
   double h=iHigh(_Symbol,g_mseTF,shift);
   if(h<=0) return false;
   for(int k=1;k<=strength;k++)
     {
      if(iHigh(_Symbol,g_mseTF,shift+k)>=h) return false; // older side
      if(iHigh(_Symbol,g_mseTF,shift-k)>=h) return false; // newer side
     }
   return true;
  }
//--- Strict fractal low on the structure TF.
bool MSE_IsFractalLow(int shift,int strength)
  {
   double l=iLow(_Symbol,g_mseTF,shift);
   if(l<=0) return false;
   for(int k=1;k<=strength;k++)
     {
      if(iLow(_Symbol,g_mseTF,shift+k)<=l) return false;
      if(iLow(_Symbol,g_mseTF,shift-k)<=l) return false;
     }
   return true;
  }
//--- Newest confirmed protected swing high & low for a given strength.
//    These are, by definition, the PROTECTED swings whose break = BOS.
void MSE_FindProtected(int strength,double &protHigh,double &protLow)
  {
   protHigh=0.0; protLow=0.0;
   int bars=Bars(_Symbol,g_mseTF);
   int maxBars=MathMin(InpStructLookback,bars-(strength+2));
   bool haveH=false,haveL=false;
   for(int s=strength+1;s<=maxBars && !(haveH&&haveL);s++)
     {
      if(!haveH && MSE_IsFractalHigh(s,strength)){ protHigh=iHigh(_Symbol,g_mseTF,s); haveH=true; }
      if(!haveL && MSE_IsFractalLow (s,strength)){ protLow =iLow (_Symbol,g_mseTF,s); haveL=true; }
     }
  }
//--- Generic BOS-driven trend update for one structural scale.
//    BOS is only ever measured against a PROTECTED swing (per spec).
void MSE_UpdateTrendScale(int strength,double &protHigh,double &protLow,int &trend)
  {
   MSE_FindProtected(strength,protHigh,protLow);
   double c1=iClose(_Symbol,g_mseTF,1);
   double bH=InpBOSUseClose? c1 : iHigh(_Symbol,g_mseTF,1);
   double bL=InpBOSUseClose? c1 : iLow (_Symbol,g_mseTF,1);
   if(protHigh>0.0 && bH>protHigh)      trend=1;   // bullish BOS on protected high
   else if(protLow>0.0 && bL<protLow)   trend=-1;  // bearish BOS on protected low
  }
//--- DUAL MARKET STRUCTURE: external governs DIRECTION, internal ENTRY.
void MSE_UpdateStructure()
  {
   MSE_UpdateTrendScale(InpExtSwingStrength,g_extProtHigh,g_extProtLow,g_extTrend);
   MSE_UpdateTrendScale(InpIntSwingStrength,g_intProtHigh,g_intProtLow,g_intTrend);
  }

//==================================================================
//  LIQUIDITY ENGINE  (BSL/SSL, equal highs/lows, sweep, reclaim)
//==================================================================
bool MSE_DetectEqualHighs(double &level)
  {
   double tol=InpEqualLevelTolPips*g_pip, first=0.0; bool haveFirst=false;
   int str=InpExtSwingStrength;
   for(int s=str+1;s<=InpLiqLookback;s++)
     {
      if(!MSE_IsFractalHigh(s,str)) continue;
      double h=iHigh(_Symbol,g_mseTF,s);
      if(!haveFirst){ first=h; haveFirst=true; continue; }
      if(MathAbs(h-first)<=tol){ level=(h+first)/2.0; return true; }
      first=h;
     }
   return false;
  }
bool MSE_DetectEqualLows(double &level)
  {
   double tol=InpEqualLevelTolPips*g_pip, first=0.0; bool haveFirst=false;
   int str=InpExtSwingStrength;
   for(int s=str+1;s<=InpLiqLookback;s++)
     {
      if(!MSE_IsFractalLow(s,str)) continue;
      double l=iLow(_Symbol,g_mseTF,s);
      if(!haveFirst){ first=l; haveFirst=true; continue; }
      if(MathAbs(l-first)<=tol){ level=(l+first)/2.0; return true; }
      first=l;
     }
   return false;
  }
double MSE_BuildBSL()
  {
   double lvl=g_extProtHigh;
   double eqH; if(MSE_DetectEqualHighs(eqH)) lvl=MathMax(lvl,eqH);
   int hi=iHighest(_Symbol,g_mseTF,MODE_HIGH,CascadeSwingLen*2,2);
   if(hi>=0) lvl=MathMax(lvl,iHigh(_Symbol,g_mseTF,hi));
   return lvl;
  }
double MSE_BuildSSL()
  {
   double lvl=(g_extProtLow>0.0)? g_extProtLow : DBL_MAX;
   double eqL; if(MSE_DetectEqualLows(eqL)) lvl=MathMin(lvl,eqL);
   int lo=iLowest(_Symbol,g_mseTF,MODE_LOW,CascadeSwingLen*2,2);
   if(lo>=0) lvl=MathMin(lvl,iLow(_Symbol,g_mseTF,lo));
   if(lvl==DBL_MAX) lvl=0.0;
   return lvl;
  }
//--- Sweep = wick beyond the pool + close back on the origin side.
//    dir=+1 tests a SELL-SIDE sweep (raid of lows -> look LONG);
//    dir=-1 tests a BUY-SIDE  sweep (raid of highs -> look SHORT).
bool MSE_DetectSweep(int dir,double &sweepWick,double &sweptLevel)
  {
   double hi1=iHigh (_Symbol,g_mseTF,1);
   double lo1=iLow  (_Symbol,g_mseTF,1);
   double cl1=iClose(_Symbol,g_mseTF,1);
   double buf=InpSweepMinPips*g_pip;
   if(dir==1)
     { if(g_ssl>0.0 && (lo1<g_ssl-buf) && (cl1>g_ssl)){ sweepWick=lo1; sweptLevel=g_ssl; return true; } }
   else if(dir==-1)
     { if(g_bsl>0.0 && (hi1>g_bsl+buf) && (cl1<g_bsl)){ sweepWick=hi1; sweptLevel=g_bsl; return true; } }
   return false;
  }
//--- Reclaim: within InpReclaimBars a close returns through the swept level.
bool MSE_ReclaimConfirmed(int dir,double lvl)
  {
   if(!InpRequireReclaim) return true;
   for(int s=1;s<=InpReclaimBars;s++)
     {
      double c=iClose(_Symbol,g_mseTF,s);
      if(dir==1  && c>lvl) return true;
      if(dir==-1 && c<lvl) return true;
     }
   return false;
  }
void MSE_UpdateLiquidity()
  {
   g_bsl=MSE_BuildBSL();
   g_ssl=MSE_BuildSSL();
   if(g_sweepConfLong >0) g_sweepConfLong--;
   if(g_sweepConfShort>0) g_sweepConfShort--;
   double wick=0.0,lvl=0.0;
   if(MSE_DetectSweep(1,wick,lvl) && MSE_ReclaimConfirmed(1,lvl))
     { g_sweepConfLong=InpSweepValidBars; g_lastSweepLvl=lvl; g_liqStatus="SSL swept+reclaim"; }
   else if(MSE_DetectSweep(-1,wick,lvl) && MSE_ReclaimConfirmed(-1,lvl))
     { g_sweepConfShort=InpSweepValidBars; g_lastSweepLvl=lvl; g_liqStatus="BSL swept+reclaim"; }
   else if(g_sweepConfLong>0)  g_liqStatus="long armed ("+IntegerToString(g_sweepConfLong)+")";
   else if(g_sweepConfShort>0) g_liqStatus="short armed ("+IntegerToString(g_sweepConfShort)+")";
   else                        g_liqStatus="watching pools";
  }

//==================================================================
//  INSTITUTIONAL DISPLACEMENT SCORING (ATR + body% + close + wick)
//  Blends four components into a single 0..100 score; weak breaks
//  are rejected upstream in the ICC Indication gate.
//==================================================================
double MSE_ScoreDisplacement(int shift,int dir)
  {
   double o=iOpen (_Symbol,g_mseTF,shift);
   double c=iClose(_Symbol,g_mseTF,shift);
   double h=iHigh (_Symbol,g_mseTF,shift);
   double l=iLow  (_Symbol,g_mseTF,shift);
   double range=h-l;
   if(range<=0.0) return 0.0;
   bool dirOk=(dir==1)?(c>o):(c<o);
   if(!dirOk) return 0.0;
   double body    =MathAbs(c-o);
   double bodyPct =body/range;
   double closeStr=(dir==1)?(c-l)/range:(h-c)/range;
   double oppWick =(dir==1)?(h-c):(c-l);
   double wickRat =(body>0.0)? oppWick/body : 999.0;
   double atrFac  =(g_mseATRval>0.0)? range/g_mseATRval : 0.0;
   double sBody =MathMin(bodyPct /MathMax(InpDispMinBodyPct ,0.01),1.0)*30.0;
   double sClose=MathMin(closeStr/MathMax(InpDispMinCloseStr,0.01),1.0)*25.0;
   double sWick =MathMin(InpDispMaxWickRatio/MathMax(wickRat,0.0001),1.0)*15.0;
   double sATR  =MathMin(atrFac /MathMax(InpDispATRMult   ,0.01),1.0)*30.0;
   g_lastDispScore=MathMin(sBody+sClose+sWick+sATR,100.0);
   return g_lastDispScore;
  }

//==================================================================
//  FAIR VALUE GAP ENGINE  (detect all, draw, track fill %, retire)
//==================================================================
bool MSE_FVGExists(datetime midTime)
  { for(int i=0;i<ArraySize(g_fvg);i++) if(g_fvg[i].time==midTime) return true; return false; }
void MSE_DropOldestFVG()
  {
   int n=ArraySize(g_fvg); if(n<=0) return;
   if(g_fvg[0].obj!="") ObjectDelete(0,g_fvg[0].obj);
   for(int i=0;i<n-1;i++) g_fvg[i]=g_fvg[i+1];
   ArrayResize(g_fvg,n-1);
  }
void MSE_AddFVG(double top,double bot,datetime midTime,int dir)
  {
   if(MSE_FVGExists(midTime)) return;
   if(ArraySize(g_fvg)>=InpMaxTrackedFVG) MSE_DropOldestFVG();
   int n=ArraySize(g_fvg); ArrayResize(g_fvg,n+1);
   g_fvg[n].top=top; g_fvg[n].bot=bot; g_fvg[n].time=midTime; g_fvg[n].dir=dir;
   g_fvg[n].fillPct=0.0; g_fvg[n].active=true;
   g_fvg[n].obj=FVG_PFX+IntegerToString((int)midTime);
  }
void MSE_ScanFVGs()
  {
   int maxBars=MathMin(InpFVGScanBars,Bars(_Symbol,g_mseTF)-4);
   for(int s=1;s<=maxBars;s++)
     {
      double lowNear=iLow (_Symbol,g_mseTF,s);
      double highFar=iHigh(_Symbol,g_mseTF,s+2);
      if((lowNear-highFar)/g_pip>=InpMinFVGPips)
         MSE_AddFVG(lowNear,highFar,iTime(_Symbol,g_mseTF,s+1),1);
      double highNear=iHigh(_Symbol,g_mseTF,s);
      double lowFar  =iLow (_Symbol,g_mseTF,s+2);
      if((lowFar-highNear)/g_pip>=InpMinFVGPips)
         MSE_AddFVG(lowFar,highNear,iTime(_Symbol,g_mseTF,s+1),-1);
     }
  }
void MSE_UpdateFVGFills()
  {
   double hi1=iHigh(_Symbol,g_mseTF,1);
   double lo1=iLow (_Symbol,g_mseTF,1);
   for(int i=0;i<ArraySize(g_fvg);i++)
     {
      if(!g_fvg[i].active) continue;
      double span=g_fvg[i].top-g_fvg[i].bot;
      if(span<=0.0){ g_fvg[i].active=false; continue; }
      double pct=g_fvg[i].fillPct;
      if(g_fvg[i].dir==1){ if(lo1<g_fvg[i].top){ double pen=g_fvg[i].top-MathMax(lo1,g_fvg[i].bot); pct=MathMax(pct,100.0*pen/span); } }
      else              { if(hi1>g_fvg[i].bot){ double pen=MathMin(hi1,g_fvg[i].top)-g_fvg[i].bot; pct=MathMax(pct,100.0*pen/span); } }
      g_fvg[i].fillPct=pct;
      if(pct>=InpFVGFillInvalidate) g_fvg[i].active=false;
     }
  }
void MSE_DrawFVGs()
  {
   if(!InpDrawFVG) return;
   datetime tRight=iTime(_Symbol,g_mseTF,0);
   for(int i=0;i<ArraySize(g_fvg);i++)
     {
      string nm=g_fvg[i].obj;
      if(!g_fvg[i].active){ if(ObjectFind(0,nm)>=0) ObjectDelete(0,nm); continue; }
      color col=(g_fvg[i].dir==1)? InpFVGBullColor : InpFVGBearColor;
      if(ObjectFind(0,nm)<0)
        {
         ObjectCreate(0,nm,OBJ_RECTANGLE,0,g_fvg[i].time,g_fvg[i].top,tRight,g_fvg[i].bot);
         ObjectSetInteger(0,nm,OBJPROP_FILL,true);
         ObjectSetInteger(0,nm,OBJPROP_BACK,true);
         ObjectSetInteger(0,nm,OBJPROP_COLOR,col);
        }
      ObjectMove(0,nm,0,g_fvg[i].time,g_fvg[i].top);
      ObjectMove(0,nm,1,tRight,g_fvg[i].bot);
     }
  }
void MSE_UpdateFVGs(){ MSE_ScanFVGs(); MSE_UpdateFVGFills(); MSE_DrawFVGs(); }
int MSE_NearestActiveFVG(int tradeDir)
  {
   int best=-1; double bestD=DBL_MAX; double px=iClose(_Symbol,g_mseTF,1);
   for(int i=0;i<ArraySize(g_fvg);i++)
     {
      if(!g_fvg[i].active || g_fvg[i].dir!=tradeDir) continue;
      double mid=(g_fvg[i].top+g_fvg[i].bot)/2.0, d=MathAbs(px-mid);
      if(d<bestD){ bestD=d; best=i; }
     }
   return best;
  }
bool MSE_InActiveFVG(int tradeDir,double price)
  {
   for(int i=0;i<ArraySize(g_fvg);i++)
     {
      if(!g_fvg[i].active || g_fvg[i].dir!=tradeDir) continue;
      if(price<=g_fvg[i].top && price>=g_fvg[i].bot) return true;
     }
   return false;
  }

//==================================================================
//  ORDER / MITIGATION BLOCK ENGINE  (Trades-by-Sci enhancement)
//  Bullish OB = last down-close candle before an up displacement;
//  bearish OB = last up-close candle before a down displacement.
//==================================================================
bool MSE_OBExists(datetime tm)
  { for(int i=0;i<ArraySize(g_ob);i++) if(g_ob[i].time==tm) return true; return false; }
void MSE_DropOldestOB()
  {
   int n=ArraySize(g_ob); if(n<=0) return;
   if(g_ob[0].obj!="") ObjectDelete(0,g_ob[0].obj);
   for(int i=0;i<n-1;i++) g_ob[i]=g_ob[i+1];
   ArrayResize(g_ob,n-1);
  }
void MSE_AddOB(double top,double bot,datetime tm,int dir)
  {
   if(MSE_OBExists(tm)) return;
   if(ArraySize(g_ob)>=InpMaxTrackedOB) MSE_DropOldestOB();
   int n=ArraySize(g_ob); ArrayResize(g_ob,n+1);
   g_ob[n].top=top; g_ob[n].bot=bot; g_ob[n].time=tm; g_ob[n].dir=dir;
   g_ob[n].mitigated=false; g_ob[n].active=true;
   g_ob[n].obj=OB_PFX+IntegerToString((int)tm);
  }
void MSE_ScanOBs()
  {
   int maxBars=MathMin(InpFVGScanBars,Bars(_Symbol,g_mseTF)-(InpOBScanBack+3));
   for(int s=1;s<=maxBars;s++)
     {
      if(MSE_ScoreDisplacement(s,1)>=InpDispMinScore)
         for(int k=s+1;k<=s+InpOBScanBack;k++)
            if(iClose(_Symbol,g_mseTF,k)<iOpen(_Symbol,g_mseTF,k))
              { MSE_AddOB(iHigh(_Symbol,g_mseTF,k),iLow(_Symbol,g_mseTF,k),iTime(_Symbol,g_mseTF,k),1); break; }
      if(MSE_ScoreDisplacement(s,-1)>=InpDispMinScore)
         for(int k=s+1;k<=s+InpOBScanBack;k++)
            if(iClose(_Symbol,g_mseTF,k)>iOpen(_Symbol,g_mseTF,k))
              { MSE_AddOB(iHigh(_Symbol,g_mseTF,k),iLow(_Symbol,g_mseTF,k),iTime(_Symbol,g_mseTF,k),-1); break; }
     }
  }
void MSE_UpdateOBMitigation()
  {
   double hi1=iHigh (_Symbol,g_mseTF,1);
   double lo1=iLow  (_Symbol,g_mseTF,1);
   double cl1=iClose(_Symbol,g_mseTF,1);
   for(int i=0;i<ArraySize(g_ob);i++)
     {
      if(!g_ob[i].active) continue;
      if(g_ob[i].dir==1)
        {
         if(lo1<=g_ob[i].top && hi1>=g_ob[i].bot) g_ob[i].mitigated=true;
         double thru=InpOBMitigateOnClose? cl1 : lo1;
         if(thru<g_ob[i].bot) g_ob[i].active=false;
        }
      else
        {
         if(hi1>=g_ob[i].bot && lo1<=g_ob[i].top) g_ob[i].mitigated=true;
         double thru=InpOBMitigateOnClose? cl1 : hi1;
         if(thru>g_ob[i].top) g_ob[i].active=false;
        }
     }
  }
void MSE_DrawOBs()
  {
   if(!InpDrawOB) return;
   datetime tRight=iTime(_Symbol,g_mseTF,0);
   for(int i=0;i<ArraySize(g_ob);i++)
     {
      string nm=g_ob[i].obj;
      if(!g_ob[i].active){ if(ObjectFind(0,nm)>=0) ObjectDelete(0,nm); continue; }
      color col=(g_ob[i].dir==1)? InpOBBullColor : InpOBBearColor;
      if(ObjectFind(0,nm)<0)
        {
         ObjectCreate(0,nm,OBJ_RECTANGLE,0,g_ob[i].time,g_ob[i].top,tRight,g_ob[i].bot);
         ObjectSetInteger(0,nm,OBJPROP_FILL,false);
         ObjectSetInteger(0,nm,OBJPROP_BACK,true);
         ObjectSetInteger(0,nm,OBJPROP_WIDTH,2);
         ObjectSetInteger(0,nm,OBJPROP_COLOR,col);
        }
      ObjectSetInteger(0,nm,OBJPROP_STYLE,g_ob[i].mitigated? STYLE_DOT : STYLE_SOLID);
      ObjectMove(0,nm,0,g_ob[i].time,g_ob[i].top);
      ObjectMove(0,nm,1,tRight,g_ob[i].bot);
     }
  }
void MSE_UpdateOrderBlocks(){ MSE_ScanOBs(); MSE_UpdateOBMitigation(); MSE_DrawOBs(); }
int MSE_NearestUnmitigatedOB(int tradeDir)
  {
   int best=-1; double bestD=DBL_MAX; double px=iClose(_Symbol,g_mseTF,1);
   for(int i=0;i<ArraySize(g_ob);i++)
     {
      if(!g_ob[i].active || g_ob[i].mitigated || g_ob[i].dir!=tradeDir) continue;
      double mid=(g_ob[i].top+g_ob[i].bot)/2.0, d=MathAbs(px-mid);
      if(d<bestD){ bestD=d; best=i; }
     }
   return best;
  }
bool MSE_InUnmitigatedOB(int tradeDir,double price)
  {
   for(int i=0;i<ArraySize(g_ob);i++)
     {
      if(!g_ob[i].active || g_ob[i].mitigated || g_ob[i].dir!=tradeDir) continue;
      if(price<=g_ob[i].top && price>=g_ob[i].bot) return true;
     }
   return false;
  }

//==================================================================
//  DASHBOARD TEXT HELPERS + MASTER REFRESH
//==================================================================
string MSE_TrendText(int t){ return t==1?"^ BULL":t==-1?"v BEAR":"- none"; }
string MSE_NearestFVGText(int dir)
  {
   int idx=MSE_NearestActiveFVG(dir);
   if(idx<0) return "none";
   return DoubleToString(g_fvg[idx].bot,_Digits)+"-"+DoubleToString(g_fvg[idx].top,_Digits)+
          " ("+DoubleToString(g_fvg[idx].fillPct,0)+"%)";
  }
//--- Master per-bar refresh: structure -> liquidity -> FVGs -> OBs.
//    Also feeds the PROTECTED internal swings to the ICC anchors so
//    the ICC Indication only ever breaks a protected swing.
void MSE_Update()
  {
   g_mseTF=(InpMSE_TF==PERIOD_CURRENT)? (ENUM_TIMEFRAMES)_Period : InpMSE_TF;
   double a[]; ArraySetAsSeries(a,true);
   if(g_mseATR!=INVALID_HANDLE && CopyBuffer(g_mseATR,0,1,1,a)==1) g_mseATRval=a[0];
   MSE_UpdateStructure();
   MSE_UpdateLiquidity();
   MSE_UpdateFVGs();
   if(InpUseOrderBlocks) MSE_UpdateOrderBlocks();
   if(InpIntTrendControlsEnt)
     {
      if(g_intProtHigh>0.0) wkLastHi=g_intProtHigh;
      if(g_intProtLow >0.0) wkLastLo=g_intProtLow;
     }
  }
//+==================================================================+
//|        ICC PULLBACK ENGINE (Indication->Correction->Continuation)|
//|        Fires TriggerFlash + Alert on the continuation.           |
//+==================================================================+
void ICC_Reset()
  { g_iccPhase=PH_NONE; g_iccDir=0; g_indLevel=0; g_indExtreme=0; g_corrExtreme=0; g_iccStartBar=0; }
void ICC_Update()
  {
   if(!UseICCPullback) return;
   int    htf   = HTFbias();
   double m15c1 = iClose(_Symbol,TrigTF,1);
   double m15h2 = iHigh (_Symbol,TrigTF,2);
   double m15l2 = iLow  (_Symbol,TrigTF,2);
   double wkH1  = iHigh (_Symbol,WorkTF,1);
   double wkL1  = iLow  (_Symbol,WorkTF,1);
   if(m15c1<=0 || wkH1<=0 || wkL1<=0)
     { if(VerboseLog) Print("[ICC] data guard: TrigTF/WorkTF not ready"); return; }

   if(g_iccPhase!=PH_NONE && g_iccDir!=0 && htf!=0 && htf!=g_iccDir) ICC_Reset();
   if(g_iccPhase!=PH_NONE && (g_barCount-g_iccStartBar)>ICC_ExpiryBars) ICC_Reset();

   bool fireBuy=false, fireSell=false; double slOut=0;

   if(htf==1)
     {
      if(g_iccPhase==PH_NONE)
        {
         // INDICATION (v3.3): break of a PROTECTED internal swing (wkLastHi now
         // carries the protected swing), gated by external trend + a confirmed
         // liquidity sweep+reclaim + an institutional displacement (reject weak).
         bool extOK   = (!InpExtTrendControlsDir) || g_extTrend>=0;     // external not bearish
         bool sweepOK = (!InpRequireSweep)        || g_sweepConfLong>0;  // SSL swept+reclaimed
         bool dispOK  = (!InpRejectWeakBreaks)    || (MSE_ScoreDisplacement(1,1)>=InpDispMinScore);
         if(wkLastHi>0 && m15c1>wkLastHi && extOK && sweepOK && dispOK)
           { g_iccPhase=PH_INDICATION; g_iccDir=1; g_indLevel=wkLastHi;
             g_indExtreme=MathMax(wkH1,m15c1); g_corrExtreme=wkL1; g_iccStartBar=g_barCount; }
        }
      else if(g_iccPhase==PH_INDICATION && g_iccDir==1)
        {
         if(wkH1>g_indExtreme) g_indExtreme=wkH1;
         double leg=g_indExtreme-g_indLevel;
         if(leg>0)
           {
            double disc=g_indExtreme-leg*CorrRetraceMin;
            double inval=g_indExtreme-leg*CorrRetraceMax;
            if(wkL1<=inval) ICC_Reset();
            else if(wkL1<=disc){ g_iccPhase=PH_CORRECTION; g_corrExtreme=wkL1; }
           }
        }
      else if(g_iccPhase==PH_CORRECTION && g_iccDir==1)
        {
         if(wkL1<g_corrExtreme) g_corrExtreme=wkL1;
         double leg=g_indExtreme-g_indLevel;
         double inval=(leg>0)?g_indExtreme-leg*CorrRetraceMax:0;
         if(leg>0 && wkL1<=inval) ICC_Reset();
         else
           {
            // CONTINUATION (v3.3): resume up ONLY if the correction pulled into an
            // active bullish FVG and (optionally) an unmitigated bullish order block.
            bool fvgOK = (!InpRequireFVGpullback) || MSE_InActiveFVG(1,g_corrExtreme);
            bool obOK  = (!InpRequireOB) || !InpUseOrderBlocks || MSE_InUnmitigatedOB(1,g_corrExtreme);
            if(m15h2>0 && m15c1>m15h2 && fvgOK && obOK)
              { fireBuy=true; slOut=g_corrExtreme-g_slBuf; ICC_Reset(); }
           }
        }
     }
   else if(htf==-1)
     {
      if(g_iccPhase==PH_NONE)
        {
         // INDICATION (v3.3): break of a PROTECTED internal swing low, gated by
         // external trend + a confirmed BSL sweep+reclaim + institutional displacement.
         bool extOK   = (!InpExtTrendControlsDir) || g_extTrend<=0;     // external not bullish
         bool sweepOK = (!InpRequireSweep)        || g_sweepConfShort>0; // BSL swept+reclaimed
         bool dispOK  = (!InpRejectWeakBreaks)    || (MSE_ScoreDisplacement(1,-1)>=InpDispMinScore);
         if(wkLastLo>0 && m15c1<wkLastLo && extOK && sweepOK && dispOK)
           { g_iccPhase=PH_INDICATION; g_iccDir=-1; g_indLevel=wkLastLo;
             g_indExtreme=MathMin(wkL1,m15c1); g_corrExtreme=wkH1; g_iccStartBar=g_barCount; }
        }
      else if(g_iccPhase==PH_INDICATION && g_iccDir==-1)
        {
         if(wkL1<g_indExtreme) g_indExtreme=wkL1;
         double leg=g_indLevel-g_indExtreme;
         if(leg>0)
           {
            double prem=g_indExtreme+leg*CorrRetraceMin;
            double inval=g_indExtreme+leg*CorrRetraceMax;
            if(wkH1>=inval) ICC_Reset();
            else if(wkH1>=prem){ g_iccPhase=PH_CORRECTION; g_corrExtreme=wkH1; }
           }
        }
      else if(g_iccPhase==PH_CORRECTION && g_iccDir==-1)
        {
         if(wkH1>g_corrExtreme) g_corrExtreme=wkH1;
         double leg=g_indLevel-g_indExtreme;
         double inval=(leg>0)?g_indExtreme+leg*CorrRetraceMax:0;
         if(leg>0 && wkH1>=inval) ICC_Reset();
         else
           {
            // CONTINUATION (v3.3): resume down ONLY if the correction pulled into an
            // active bearish FVG and (optionally) an unmitigated bearish order block.
            bool fvgOK = (!InpRequireFVGpullback) || MSE_InActiveFVG(-1,g_corrExtreme);
            bool obOK  = (!InpRequireOB) || !InpUseOrderBlocks || MSE_InUnmitigatedOB(-1,g_corrExtreme);
            if(m15l2>0 && m15c1<m15l2 && fvgOK && obOK)
              { fireSell=true; slOut=g_corrExtreme+g_slBuf; ICC_Reset(); }
           }
        }
     }
   else
     { if(g_iccPhase==PH_NONE) ICC_Reset(); }

   if(VerboseLog)
      PrintFormat("[ICC] bar=%d bias D1/H4/H1/M15=%d/%d/%d/%d HTF=%d | phase=%s dir=%d ind=%.2f ext=%.2f corr=%.2f | fire b/s=%d/%d",
         g_barCount,biasD1,biasH4,biasH1,biasM15,htf,PhaseTxt(g_iccPhase),g_iccDir,
         g_indLevel,g_indExtreme,g_corrExtreme,(int)fireBuy,(int)fireSell);

   if(fireBuy && g_posDir==0)
     {
      double e=m15c1, sl=slOut, tp=e+(e-sl)*FlashRR;
      TriggerFlash("ICC BUY (continuation)", ColBuy, true, e, sl, tp);
      SendNotification("ICC v3.2 BUY "+_Symbol+" @ "+DoubleToString(e,_Digits));
      g_posDir=1; g_posSL=sl;
     }
   else if(fireSell && g_posDir==0)
     {
      double e=m15c1, sl=slOut, tp=e-(sl-e)*FlashRR;
      TriggerFlash("ICC SELL (continuation)", ColSell, true, e, sl, tp);
      SendNotification("ICC v3.2 SELL "+_Symbol+" @ "+DoubleToString(e,_Digits));
      g_posDir=-1; g_posSL=sl;
     }
  }
//+==================================================================+
//|                 v1 CASCADE ENTRY / EXIT SIGNALS (optional)       |
//+==================================================================+
void EvaluateSignals(double barClose)
  {
   double trigClose = iClose(_Symbol, TrigTF, 1);
   bool buySig  = UseCascadeEntries && alignBull && wkLastHi>0 && trigClose > wkLastHi;
   bool sellSig = UseCascadeEntries && alignBear && wkLastLo>0 && trigClose < wkLastLo;
   // exits first (no prices on exit)
   if(g_posDir==1)
     {
      if((UseCascadeEntries && sellSig) || (g_posSL>0 && barClose < g_posSL))
        { TriggerFlash("EXIT LONG",  ColExit, false,0,0,0); g_posDir=0; g_posSL=0; }
     }
   else if(g_posDir==-1)
     {
      if((UseCascadeEntries && buySig) || (g_posSL>0 && barClose > g_posSL))
        { TriggerFlash("EXIT SHORT", ColExit, false,0,0,0); g_posDir=0; g_posSL=0; }
     }
   if(!UseCascadeEntries) return;
   if(g_posDir==0 && buySig)
     {
      double e=barClose, sl=wkLastLo, tp=barClose+(barClose-wkLastLo)*FlashRR;
      TriggerFlash("BUY ENTRY (breakout)", ColBuy, true, e, sl, tp);
      g_posDir=1; g_posSL=wkLastLo;
     }
   else if(g_posDir==0 && sellSig)
     {
      double e=barClose, sl=wkLastHi, tp=barClose-(wkLastHi-barClose)*FlashRR;
      TriggerFlash("SELL ENTRY (breakout)", ColSell, true, e, sl, tp);
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
   Alert("ICC v3.2: ", msg, " | ", _Symbol);
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
      bool confBuy  = ( sr_isRes[i] && c > lvl + g_confBuf);
      bool confSell = (!sr_isRes[i] && c < lvl - g_confBuf);
      if(confBuy && g_posDir==0)
        {
         sr_armed[i]=false;
         double sl=lvl-g_slBuf, tp=c+(c-sl)*FlashRR;
         TriggerFlash("RETEST BUY", ColRBuy, true, c, sl, tp);
         SendNotification("ICC v3.2 RETEST BUY "+_Symbol+" @ "+DoubleToString(c,_Digits));
         g_posDir=1; g_posSL=sl;
        }
      else if(confSell && g_posDir==0)
        {
         sr_armed[i]=false;
         double sl=lvl+g_slBuf, tp=c-(sl-c)*FlashRR;
         TriggerFlash("RETEST SELL", ColRSell, true, c, sl, tp);
         SendNotification("ICC v3.2 RETEST SELL "+_Symbol+" @ "+DoubleToString(c,_Digits));
         g_posDir=-1; g_posSL=sl;
        }
     }
  }
void GrayOutLevel(int i)
  {
   string nm=sr_name[i];
   if(SR_UseZone && ObjectFind(0,nm+"_box")>=0)
     { ObjectSetInteger(0,nm+"_box",OBJPROP_COLOR,BrkColor); ObjectSetInteger(0,nm+"_box",OBJPROP_STYLE,STYLE_DOT); }
   if(!SR_UseZone && ObjectFind(0,nm+"_ln")>=0)
     { ObjectSetInteger(0,nm+"_ln",OBJPROP_COLOR,BrkColor); ObjectSetInteger(0,nm+"_ln",OBJPROP_STYLE,STYLE_DASH); }
   if(SR_ShowCnt && ObjectFind(0,nm+"_lb")>=0)
     { ObjectSetInteger(0,nm+"_lb",OBJPROP_COLOR,BrkColor);
       ObjectSetString (0,nm+"_lb",OBJPROP_TEXT,"x "+(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i])); }
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
         sr_count[i] = nc; matched=true;
         if(nc==SR_MinTouch && !sr_drawn[i])
           { sr_drawn[i]=true; sr_isRes[i]=(sr_price[i]>=RefSMA()); DrawLevel(i); }
         else if(nc>SR_MinTouch && SR_ShowCnt && sr_drawn[i]) UpdateLabel(i);
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
  { int cnt=0; for(int i=0;i<ArraySize(sr_drawn);i++) if(sr_drawn[i] && !sr_broken[i]) cnt++; return cnt; }
int ArmedCount()
  { int cnt=0; for(int i=0;i<ArraySize(sr_armed);i++) if(sr_armed[i]) cnt++; return cnt; }
void UpdateDashboard()
  {
   string bD = biasD1==1?"^":biasD1==-1?"v":"-";
   string b4 = biasH4==1?"^":biasH4==-1?"v":"-";
   string b1 = biasH1==1?"^":biasH1==-1?"v":"-";
   string b5 = biasM15==1?"^":biasM15==-1?"v":"-";
   string htf= HTFbias()==1?"^ BULL":HTFbias()==-1?"v BEAR":"- flat";
   string posTxt = g_posDir==1?"LONG":g_posDir==-1?"SHORT":"flat";
   string d = "=== ICC TradesBySci v3.3 (SMC) ==========\n";
   d += " Cascade (D1 H4 H1 M15): "+bD+" "+b4+" "+b1+" "+b5+"\n";
   d += " HTF filter: "+htf+"\n";
   d += " ICC phase:  "+PhaseTxt(g_iccPhase)+" (dir "+IntegerToString(g_iccDir)+")\n";
   d += " Position:   "+posTxt+"\n";
   d += " S/R lvls: "+IntegerToString(ActiveSRCount())+"  | armed: "+IntegerToString(ArmedCount())+"\n";
   // ---- v3.3 SMC structure engine rows ----
   d += "--- SMC Structure Engine ----------------\n";
   d += " External trend: "+MSE_TrendText(g_extTrend)+"   Internal: "+MSE_TrendText(g_intTrend)+"\n";
   d += " Protected High: "+(g_extProtHigh>0?DoubleToString(g_extProtHigh,_Digits):"-")+"\n";
   d += " Protected Low:  "+(g_extProtLow >0?DoubleToString(g_extProtLow ,_Digits):"-")+"\n";
   d += " Liquidity: "+g_liqStatus+"\n";
   d += " Displacement score: "+DoubleToString(g_lastDispScore,0)+"/100\n";
   d += " Nearest Bull FVG: "+MSE_NearestFVGText(1)+"\n";
   d += " Nearest Bear FVG: "+MSE_NearestFVGText(-1)+"\n";
   d += "=========================================";
   Comment(d);
  }
//+------------------------------------------------------------------+
