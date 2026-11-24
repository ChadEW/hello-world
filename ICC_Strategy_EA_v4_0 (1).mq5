//+------------------------------------------------------------------+
//|                                       ICC_Strategy_EA_v4_0.mq5   |
//|     ICC v4.0 — Sci Cascade + v3.3 Broker Protection              |
//|                                                                  |
//|  v4.0 MERGES:                                                    |
//|   • v3.3's symbol-aware Smart SL + broker diagnostics            |
//|   • v3.3's asset-class auto-scaling (forex/metal/index/crypto)   |
//|   • v3.3's trailing stop, break-even, alert dispatcher           |
//|   • v3.3's TF auto-profiles (M5/M15/H1/H4/D1)                    |
//|   • v3.3's skip/reject diagnostic counters                       |
//|   • v1's D1 → H4 → H1 → M15 four-TF pure-structure cascade       |
//|   • v1's Sci-style blue/red horizontal-ray chart marking         |
//|   • v1's HH/HL/LH/LL swing labels                                |
//|   • v1's correction-zone rectangle on the H1 swings              |
//|   • v1's cascade dashboard (top-right)                           |
//|                                                                  |
//|  v4.0 + S/R MODULE (July 2026, built for Chad Woodyard):         |
//|   • Body-close Support/Resistance engine                         |
//|       - A level is confirmed only where candle BODIES (closes)   |
//|         land inside a tolerance zone at least N times (def. 3).   |
//|       - Each level lives 3 calendar days OR 3 trading sessions    |
//|         (selectable), then is auto-removed.                       |
//|       - Auto-classified Support/Resistance vs a reference SMA.    |
//|       - Visual only: does NOT alter cascade entries/stops.        |
//|                                                                  |
//|  KEY TOGGLE: EntryMode                                           |
//|   • SCI_PURE = pure structure cascade (Sci's exact method)       |
//|   • FIB_FILT = v3.3 Fib-depth correction filter (30%-79%)        |
//+------------------------------------------------------------------+
#property copyright   "ICC Strategy EA v4.0"
#property version     "4.10"
#property description "ICC v4.0 — Sci D1->H4->H1->M15 Cascade + v3.3 Broker Protection + body-close S/R"
#property description "Auto-marks charts in Sci's blue/red scheme with HH/HL/LH/LL labels"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_ICC_PHASE
  { PHASE_NONE=0, PHASE_INDICATION=1, PHASE_CORRECTION=2, PHASE_CONTINUATION=3 };
enum ENUM_TREND
  { TREND_NONE=0, TREND_BULLISH=1, TREND_BEARISH=2 };
enum ENUM_ASSET_CLASS
  { ASSET_FOREX=0, ASSET_METAL=1, ASSET_INDEX=2, ASSET_CRYPTO=3, ASSET_OTHER=4 };
enum ENUM_SL_METHOD
  {
   SL_STRUCTURAL = 0, // Structural buffer only
   SL_ATR        = 1, // ATR × multiplier
   SL_SMART      = 2  // MAX(structural, ATR, broker min) - recommended
  };
enum ENUM_ENTRY_MODE
  {
   ENTRY_SCI_PURE = 0, // Sci style: M15 close > H1 swing in cascade direction
   ENTRY_FIB_FILT = 1  // v3.3 style: Fib-depth correction + continuation
  };
enum ENUM_SR_DUR
  {
   SR_DAYS     = 0,   // Calendar Days
   SR_SESSIONS = 1    // Trading Sessions (daily bars)
  };

//+------------------------------------------------------------------+
//| INPUTS — Mode Switch                                             |
//+------------------------------------------------------------------+
input group "=== v4.0 Mode Switch ==="
input ENUM_ENTRY_MODE EntryMode = ENTRY_SCI_PURE; // SCI_PURE = cascade only | FIB_FILT = v3.3 logic

input group "=== Timeframe Cascade (Sci D1->H4->H1->M15) ==="
input ENUM_TIMEFRAMES BiasTF      = PERIOD_D1;
input ENUM_TIMEFRAMES MidTF       = PERIOD_H4;
input ENUM_TIMEFRAMES WorkTF      = PERIOD_H1;
input ENUM_TIMEFRAMES TrigTF      = PERIOD_M15;
input bool            StrictAlign = true;       // Require all 4 TFs to agree
input int             CascadeSwingLen = 5;      // Pivot length used per-TF for cascade

input group "=== Stop Loss Method (v3.3 carryover) ==="
input ENUM_SL_METHOD SL_Method        = SL_SMART;
input double         ATR_Multiplier   = 1.5;
input int            ATR_Period       = 14;
input double         BrokerStopCushion= 1.2;
input bool           AutoScaleByAsset = true;
input bool           ShowDiagnostics  = true;

input group "=== ICC Structure (working TF — used by both modes) ==="
input bool   AutoSettings = true;
input int    SwingLookback_In = 5;
input double CorrMinPct_In    = 30.0;       // FIB_FILT mode only
input double CorrMaxPct_In    = 79.0;       // FIB_FILT mode only
input double RR_Ratio_In      = 2.0;
input int    SL_Buffer_In     = 50;

input group "=== Trade Management ==="
input double RiskPercent   = 0.5;
input double FixedLots     = 0.0;
input int    MaxOpenTrades = 1;

input group "=== Trailing Stop ==="
input bool   UseTrailingStop  = true;
input int    TrailingStart_In = 200;
input int    TrailingStep_In  = 100;

input group "=== Break Even ==="
input bool   UseBreakEven       = true;
input int    BreakEvenAt_In     = 150;
input int    BreakEvenProfit_In = 10;

input group "=== Session Filter ==="
input bool   UseSessionFilter = false;
input int    SessionStartHour = 13;  // 09:30 NY ≈ 13:30 UTC
input int    SessionEndHour   = 20;  // 16:00 NY ≈ 20:00 UTC

input group "=== Alerts ==="
input bool   AlertPopup     = false;
input bool   AlertPush      = false;
input bool   AlertEmail     = false;
input bool   AlertSound     = false;
input string AlertSoundFile = "alert.wav";

input group "=== Visuals — Sci Chart Marking ==="
input bool  DrawSwings      = true;
input bool  DrawLabels      = true;
input int   MaxSwingsKept   = 6;
input bool  DrawCorrZone    = true;
input bool  ShowDashboard   = true;
input color SwingHiCol      = clrDodgerBlue;   // Sci's blue (sellers' line)
input color SwingLoCol      = clrCrimson;      // Buyers' line
input color ZoneBullCol     = clrMediumSeaGreen;
input color ZoneBearCol     = clrIndianRed;
input color ZoneNeutralCol  = clrSilver;

input group "=== Body-Close Support / Resistance ==="
input bool         SR_Show     = true;         // Show body-close S/R levels
input int          SR_MinTouch = 3;            // Min body closes to confirm a level
input double       SR_TolPips  = 10.0;         // Zone tolerance (pips)
input ENUM_SR_DUR  SR_DurMode  = SR_DAYS;      // Level duration unit
input int          SR_DurN     = 3;            // Level duration (days or sessions)
input color        SR_ColRes   = clrOrange;    // Resistance color
input color        SR_ColSup   = clrTeal;      // Support color
input bool         SR_UseZone  = true;         // Draw as shaded zone (rectangle) vs line
input bool         SR_ShowCnt  = true;         // Show touch-count label
input int          SR_RefLen   = 20;           // Reference SMA length (S/R classifier)

input group "=== EA Settings ==="
input ulong  MagicNumber  = 20260630;
input int    Slippage     = 30;
input string TradeComment = "ICC-v4";
input bool   DebugLog     = false;

//+------------------------------------------------------------------+
//| Runtime state                                                    |
//+------------------------------------------------------------------+
int    SwingLookback;
double CorrectionMinPct;
double CorrectionMaxPct;
double RR_Ratio;
int    SL_Buffer_Points;
int    TrailingStart_Pts;
int    TrailingStep_Pts;
int    BreakEvenAt_Pts;
int    BreakEvenProfit;
string ActiveProfile;

ENUM_ASSET_CLASS AssetClass = ASSET_FOREX;
string AssetClassLabel = "FOREX";

CTrade        trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;

int    atrHandle = INVALID_HANDLE;

// Working-TF swing history (for FIB_FILT mode + entry stop placement)
double swingHighs[];
double swingLows[];
int    swingHighBars[];
int    swingLowBars[];
int    swingHighCount=0, swingLowCount=0;

ENUM_TREND     currentTrend  = TREND_NONE;
ENUM_ICC_PHASE currentPhase  = PHASE_NONE;
double indicationHigh=0, indicationLow=0;
double correctionHigh=0, correctionLow=0;
double lastSwingHigh=0,  lastSwingLow=0;
double prevSwingHigh=0,  prevSwingLow=0;
bool   buySignalFired=false, sellSignalFired=false;
datetime lastAlertTime=0;
int    lastAlertBar=0;
datetime lastTrigBar = 0;

// Cascade bias cache
struct SwingCache { double lastHi, prevHi, lastLo, prevLo; datetime tHi, tLo; };
SwingCache cD1, cH4, cH1, cM15;
int biasD1=0, biasH4=0, biasH1=0, biasM15=0;
bool alignBull=false, alignBear=false;

// Counters
int    invalidStopCount_BUY=0,  invalidStopCount_SELL=0;
int    skippedTrades_BUY=0,     skippedTrades_SELL=0;

string PFX = "ICCv4_";

//--- Body-close S/R engine state
double   g_srPip = 0.0, g_srTol = 0.0;
int      g_srSessCount = 0, g_srLastDayKey = -1;
int      g_srMaHandle = INVALID_HANDLE;
int      g_srUid = 0;
datetime g_srLastBar = 0;
string   SR_PFX = "ICCv4_SR_";

double   sr_price[];      int      sr_count[];
datetime sr_birthTime[];  int      sr_birthSes[];
datetime sr_birthBar[];   bool     sr_isRes[];   bool sr_drawn[];
string   sr_name[];

//+------------------------------------------------------------------+
//| ========= ASSET CLASS DETECTION (v3.3 carryover) ========         |
//+------------------------------------------------------------------+
ENUM_ASSET_CLASS DetectAssetClass()
  {
   string sym = _Symbol; StringToUpper(sym);
   if(StringFind(sym,"XAU")>=0 || StringFind(sym,"GOLD")>=0 ||
      StringFind(sym,"XAG")>=0 || StringFind(sym,"SILVER")>=0 ||
      StringFind(sym,"XPT")>=0 || StringFind(sym,"XPD")>=0)
     { AssetClassLabel="METAL"; return ASSET_METAL; }
   if(StringFind(sym,"BTC")>=0 || StringFind(sym,"ETH")>=0 ||
      StringFind(sym,"XRP")>=0 || StringFind(sym,"LTC")>=0 ||
      StringFind(sym,"BCH")>=0 || StringFind(sym,"SOL")>=0 ||
      StringFind(sym,"DOGE")>=0|| StringFind(sym,"ADA")>=0)
     { AssetClassLabel="CRYPTO"; return ASSET_CRYPTO; }
   if(StringFind(sym,"US30")>=0 || StringFind(sym,"US500")>=0 ||
      StringFind(sym,"NAS")>=0  || StringFind(sym,"SPX")>=0  ||
      StringFind(sym,"DJ")>=0   || StringFind(sym,"DAX")>=0  ||
      StringFind(sym,"FTSE")>=0 || StringFind(sym,"NIK")>=0  ||
      StringFind(sym,"HK50")>=0 || StringFind(sym,"AUS200")>=0||
      StringFind(sym,"GER")>=0  || StringFind(sym,"UK100")>=0)
     { AssetClassLabel="INDEX"; return ASSET_INDEX; }
   if(StringLen(sym)>=6) { AssetClassLabel="FOREX"; return ASSET_FOREX; }
   AssetClassLabel="OTHER"; return ASSET_OTHER;
  }
void ApplyAssetClassScaling()
  {
   if(!AutoScaleByAsset) return;
   int base = SL_Buffer_Points;
   int mult = 1;
   switch(AssetClass)
     {
      case ASSET_METAL:  mult = 30;  break;
      case ASSET_INDEX:  mult = 20;  break;
      case ASSET_CRYPTO: mult = 300; break;
      default: return;
     }
   SL_Buffer_Points   *= mult;
   TrailingStart_Pts  *= mult;
   TrailingStep_Pts   *= mult;
   BreakEvenAt_Pts    *= mult;
   BreakEvenProfit    *= mult;
   PrintFormat("ASSET SCALING [%s]: SL_Buffer %d -> %d | Trail: %d/%d",
               AssetClassLabel, base, SL_Buffer_Points,
               TrailingStart_Pts, TrailingStep_Pts);
  }

//+------------------------------------------------------------------+
//| ========= SMART STOP CALCULATIONS (v3.3 carryover) =====          |
//+------------------------------------------------------------------+
double GetMinStopDistance()
  {
   long stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread  = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * point;
   double minDist = MathMax((double)stopsLvl, (double)freezeLvl) * point;
   minDist = MathMax(minDist, spread * 3.0);
   minDist = MathMax(minDist, point * 10.0);
   return minDist;
  }
double GetATRStopDistance()
  {
   if(atrHandle == INVALID_HANDLE) return GetMinStopDistance() * 2;
   double atr[]; ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) < 1) return GetMinStopDistance() * 2;
   if(atr[0] <= 0) return GetMinStopDistance() * 2;
   return atr[0] * ATR_Multiplier;
  }
double CalculateSLDistance(double structuralDist)
  {
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bufStop = SL_Buffer_Points * point + structuralDist;
   double minStop = GetMinStopDistance();
   double atrStop = GetATRStopDistance();
   double finalDist;
   switch(SL_Method)
     {
      case SL_STRUCTURAL: finalDist = bufStop; break;
      case SL_ATR:        finalDist = atrStop; break;
      case SL_SMART:
      default:
         finalDist = MathMax(MathMax(bufStop, atrStop), minStop * BrokerStopCushion);
         break;
     }
   finalDist = MathMax(finalDist, minStop * BrokerStopCushion);
   return finalDist;
  }
void PrintBrokerDiagnostics()
  {
   if(!ShowDiagnostics) return;
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   digits  = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   long   spread    = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minStop   = GetMinStopDistance();
   double atrStop   = GetATRStopDistance();
   double bufStop   = SL_Buffer_Points * point;
   Print("==============================================================");
   Print("           ICC EA v4.0 - BROKER DIAGNOSTICS                 ");
   Print("==============================================================");
   Print(" Symbol:        ", _Symbol);
   Print(" Asset Class:   ", AssetClassLabel);
   Print(" Chart TF:      ", EnumToString(_Period));
   Print(" Entry Mode:    ", EnumToString(EntryMode));
   Print(" Cascade:       ", EnumToString(BiasTF), " -> ", EnumToString(MidTF),
                         " -> ", EnumToString(WorkTF), " -> ", EnumToString(TrigTF));
   Print(" Strict Align:  ", StrictAlign ? "YES (all 4 TFs)" : "NO (H1+M15 only)");
   Print(" Profile:       ", ActiveProfile);
   Print("== PRICE INFO ================================================");
   Print(" Bid:           ", DoubleToString(bid,(int)digits));
   Print(" Ask:           ", DoubleToString(ask,(int)digits));
   Print(" Digits/Point:  ", digits, " / ", DoubleToString(point,(int)digits));
   Print(" Tick Sz/Val:   ", DoubleToString(tickSize,(int)digits),
                       " / $", DoubleToString(tickValue,4));
   Print("== BROKER LIMITS ============================================");
   Print(" Stops Level:   ", stopsLvl,
         " pts (",DoubleToString(stopsLvl*point,(int)digits),")");
   Print(" Freeze Level:  ", freezeLvl,
         " pts (",DoubleToString(freezeLvl*point,(int)digits),")");
   Print(" Spread:        ", spread,
         " pts (",DoubleToString(spread*point,(int)digits),")");
   Print(" Lots min/max:  ", DoubleToString(minLot,2)," / ",
                        DoubleToString(maxLot,2)," step ", DoubleToString(lotStep,2));
   Print("== SL CONFIG ================================================");
   Print(" SL Method:     ", EnumToString(SL_Method));
   Print(" SL_Buffer:     ", SL_Buffer_Points,
         " pts (=", DoubleToString(bufStop,(int)digits),")");
   Print(" ATR Stop:      ", DoubleToString(atrStop,(int)digits),
         " (ATRx", DoubleToString(ATR_Multiplier,1),")");
   Print(" Min Safe Stop: ", DoubleToString(minStop,(int)digits),
         " | x Cushion: ", DoubleToString(minStop*BrokerStopCushion,(int)digits));
   Print(" RR Ratio:      ", DoubleToString(RR_Ratio,1));
   Print("==============================================================");
  }

//+------------------------------------------------------------------+
//| ========= TF AUTO-CONFIGURE (v3.3 carryover) ============         |
//+------------------------------------------------------------------+
void AutoConfigure()
  {
   ENUM_TIMEFRAMES tf = _Period;
   if(!AutoSettings)
     { SwingLookback=SwingLookback_In; CorrectionMinPct=CorrMinPct_In;
       CorrectionMaxPct=CorrMaxPct_In; RR_Ratio=RR_Ratio_In;
       SL_Buffer_Points=SL_Buffer_In; TrailingStart_Pts=TrailingStart_In;
       TrailingStep_Pts=TrailingStep_In; BreakEvenAt_Pts=BreakEvenAt_In;
       BreakEvenProfit=BreakEvenProfit_In; ActiveProfile="MANUAL";
       ApplyAssetClassScaling(); return; }
   if(tf==PERIOD_M5)
     { SwingLookback=3; CorrectionMinPct=25; CorrectionMaxPct=65; RR_Ratio=1.2;
       SL_Buffer_Points=20; TrailingStart_Pts=80; TrailingStep_Pts=40;
       BreakEvenAt_Pts=60; BreakEvenProfit=5; ActiveProfile="M5 SCALP"; }
   else if(tf==PERIOD_M15)
     { SwingLookback=3; CorrectionMinPct=30; CorrectionMaxPct=70; RR_Ratio=1.5;
       SL_Buffer_Points=30; TrailingStart_Pts=120; TrailingStep_Pts=60;
       BreakEvenAt_Pts=100; BreakEvenProfit=8; ActiveProfile="M15 SCALP"; }
   else if(tf==PERIOD_H1)
     { SwingLookback=5; CorrectionMinPct=30; CorrectionMaxPct=79; RR_Ratio=2.0;
       SL_Buffer_Points=50; TrailingStart_Pts=200; TrailingStep_Pts=100;
       BreakEvenAt_Pts=150; BreakEvenProfit=10; ActiveProfile="H1 INTRADAY"; }
   else if(tf==PERIOD_H4)
     { SwingLookback=7; CorrectionMinPct=38; CorrectionMaxPct=79; RR_Ratio=3.0;
       SL_Buffer_Points=100; TrailingStart_Pts=400; TrailingStep_Pts=200;
       BreakEvenAt_Pts=300; BreakEvenProfit=20; ActiveProfile="H4 SWING"; }
   else if(tf==PERIOD_D1)
     { SwingLookback=10; CorrectionMinPct=38; CorrectionMaxPct=79; RR_Ratio=3.5;
       SL_Buffer_Points=200; TrailingStart_Pts=800; TrailingStep_Pts=400;
       BreakEvenAt_Pts=600; BreakEvenProfit=50; ActiveProfile="D1 POSITION"; }
   else
     { SwingLookback=SwingLookback_In; CorrectionMinPct=CorrMinPct_In;
       CorrectionMaxPct=CorrMaxPct_In; RR_Ratio=RR_Ratio_In;
       SL_Buffer_Points=SL_Buffer_In; TrailingStart_Pts=TrailingStart_In;
       TrailingStep_Pts=TrailingStep_In; BreakEvenAt_Pts=BreakEvenAt_In;
       BreakEvenProfit=BreakEvenProfit_In; ActiveProfile="CUSTOM"; }
   ApplyAssetClassScaling();
  }

//+------------------------------------------------------------------+
//| ========= CASCADE: PER-TF SWING + BIAS (v1 carryover) ===         |
//+------------------------------------------------------------------+
bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid = iHigh(_Symbol, tf, shift);
   if(mid==0) return false;
   for(int i=1; i<=L; i++)
     {
      if(iHigh(_Symbol, tf, shift-i) >= mid) return false;
      if(iHigh(_Symbol, tf, shift+i) >  mid) return false;
     }
   return true;
  }
bool IsPivotLowTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid = iLow(_Symbol, tf, shift);
   if(mid==0) return false;
   for(int i=1; i<=L; i++)
     {
      if(iLow(_Symbol, tf, shift-i) <= mid) return false;
      if(iLow(_Symbol, tf, shift+i) <  mid) return false;
     }
   return true;
  }
void RefreshSwingsTF(ENUM_TIMEFRAMES tf, SwingCache &c)
  {
   c.lastHi=c.prevHi=c.lastLo=c.prevLo=0;
   c.tHi=c.tLo=0;
   int bars = Bars(_Symbol, tf);
   int found_hi=0, found_lo=0;
   for(int shift=CascadeSwingLen+1;
       shift < bars - CascadeSwingLen - 1 && (found_hi<2 || found_lo<2);
       shift++)
     {
      if(found_hi<2 && IsPivotHighTF(tf, shift, CascadeSwingLen))
        {
         double px = iHigh(_Symbol, tf, shift);
         datetime t= iTime(_Symbol, tf, shift);
         if(found_hi==0){ c.lastHi=px; c.tHi=t; } else c.prevHi=px;
         found_hi++;
        }
      if(found_lo<2 && IsPivotLowTF(tf, shift, CascadeSwingLen))
        {
         double px = iLow(_Symbol, tf, shift);
         datetime t= iTime(_Symbol, tf, shift);
         if(found_lo==0){ c.lastLo=px; c.tLo=t; } else c.prevLo=px;
         found_lo++;
        }
     }
  }
int BiasOf(const SwingCache &c)
  {
   if(c.lastHi==0 || c.prevHi==0 || c.lastLo==0 || c.prevLo==0) return 0;
   if(c.lastHi > c.prevHi && c.lastLo > c.prevLo) return  1;
   if(c.lastHi < c.prevHi && c.lastLo < c.prevLo) return -1;
   return 0;
  }
void EvaluateCascade()
  {
   RefreshSwingsTF(BiasTF, cD1);
   RefreshSwingsTF(MidTF,  cH4);
   RefreshSwingsTF(WorkTF, cH1);
   RefreshSwingsTF(TrigTF, cM15);
   biasD1 = BiasOf(cD1);
   biasH4 = BiasOf(cH4);
   biasH1 = BiasOf(cH1);
   biasM15= BiasOf(cM15);
   alignBull = StrictAlign
       ? (biasD1== 1 && biasH4== 1 && biasH1== 1 && biasM15== 1)
       : (biasH1== 1 && biasM15== 1);
   alignBear = StrictAlign
       ? (biasD1==-1 && biasH4==-1 && biasH1==-1 && biasM15==-1)
       : (biasH1==-1 && biasM15==-1);
  }

//+------------------------------------------------------------------+
//| ========= WORKING-TF SWINGS (for FIB_FILT + entry stops) =        |
//+------------------------------------------------------------------+
void DetectSwingPoints()
  {
   int bars = Bars(_Symbol, _Period);
   if(bars < SwingLookback*2+1) return;
   double highs[], lows[];
   ArrayResize(highs, SwingLookback*2+1);
   ArrayResize(lows,  SwingLookback*2+1);
   int cb = SwingLookback;
   if(CopyHigh(_Symbol, _Period, 1, SwingLookback*2+1, highs) <= 0) return;
   if(CopyLow (_Symbol, _Period, 1, SwingLookback*2+1, lows ) <= 0) return;
   bool isSH=true;
   for(int i=0;i<SwingLookback*2+1;i++)
     { if(i==cb) continue; if(highs[i]>=highs[cb]){isSH=false;break;} }
   if(isSH && swingHighCount<100)
     if(swingHighCount==0 || swingHighs[swingHighCount-1]!=highs[cb])
       { swingHighs[swingHighCount]=highs[cb];
         swingHighBars[swingHighCount]=cb+1; swingHighCount++;
         prevSwingHigh=lastSwingHigh; lastSwingHigh=highs[cb]; }
   bool isSL=true;
   for(int i=0;i<SwingLookback*2+1;i++)
     { if(i==cb) continue; if(lows[i]<=lows[cb]){isSL=false;break;} }
   if(isSL && swingLowCount<100)
     if(swingLowCount==0 || swingLows[swingLowCount-1]!=lows[cb])
       { swingLows[swingLowCount]=lows[cb];
         swingLowBars[swingLowCount]=cb+1; swingLowCount++;
         prevSwingLow=lastSwingLow; lastSwingLow=lows[cb]; }
   if(swingHighCount>50) TrimSwingArray(swingHighs, swingHighBars, swingHighCount);
   if(swingLowCount>50)  TrimSwingArray(swingLows,  swingLowBars,  swingLowCount);
  }
void TrimSwingArray(double &a[], int &b[], int &c)
  { int k=25; for(int i=0;i<k;i++){a[i]=a[c-k+i]; b[i]=b[c-k+i];} c=k; }
void DetermineMarketStructure()
  {
   if(swingHighCount<2 || swingLowCount<2) return;
   double sh1=swingHighs[swingHighCount-1], sh2=swingHighs[swingHighCount-2];
   double sl1=swingLows [swingLowCount -1], sl2=swingLows [swingLowCount -2];
   if(sh1>sh2 && sl1>sl2)      currentTrend=TREND_BULLISH;
   else if(sl1<sl2 && sh1<sh2) currentTrend=TREND_BEARISH;
  }

//+------------------------------------------------------------------+
//| ========= FIB-FILTERED PHASE MACHINE (v3.3 carryover) ===         |
//+------------------------------------------------------------------+
void IdentifyICCPhases_FibFilt()
  {
   if(swingHighCount<2 || swingLowCount<2) return;
   double close[];
   if(CopyClose(_Symbol,_Period,0,3,close)<3) return;
   double cc=close[2];
   if(currentTrend==TREND_BULLISH)
     {
      double sh1=swingHighs[swingHighCount-1], sh2=swingHighs[swingHighCount-2];
      double sl1=swingLows [swingLowCount -1];
      if(sh1>sh2 && currentPhase!=PHASE_CORRECTION && currentPhase!=PHASE_CONTINUATION)
        { currentPhase=PHASE_INDICATION; indicationHigh=sh1; indicationLow=sl1;
          buySignalFired=false; }
      if(currentPhase==PHASE_INDICATION && cc<indicationHigh)
        { double ms=indicationHigh-indicationLow;
          double pp=(ms>0)?((indicationHigh-cc)/ms)*100.0:0;
          if(pp>=CorrectionMinPct && pp<=CorrectionMaxPct)
            { currentPhase=PHASE_CORRECTION; correctionLow=cc; correctionHigh=indicationHigh; }
          if(currentPhase==PHASE_CORRECTION && cc<correctionLow)
            { double np=((indicationHigh-cc)/ms)*100.0;
              if(np<=CorrectionMaxPct) correctionLow=cc;
              else currentPhase=PHASE_NONE; } }
      if(currentPhase==PHASE_CORRECTION)
        { double mid=indicationLow+(indicationHigh-indicationLow)*0.5;
          if(cc>mid && cc>correctionLow && close[2]>close[1])
            currentPhase=PHASE_CONTINUATION; }
     }
   if(currentTrend==TREND_BEARISH)
     {
      double sl1=swingLows[swingLowCount-1], sl2=swingLows[swingLowCount-2];
      double sh1=swingHighs[swingHighCount-1];
      if(sl1<sl2 && currentPhase!=PHASE_CORRECTION && currentPhase!=PHASE_CONTINUATION)
        { currentPhase=PHASE_INDICATION; indicationLow=sl1; indicationHigh=sh1;
          sellSignalFired=false; }
      if(currentPhase==PHASE_INDICATION && cc>indicationLow)
        { double ms=indicationHigh-indicationLow;
          double pp=(ms>0)?((cc-indicationLow)/ms)*100.0:0;
          if(pp>=CorrectionMinPct && pp<=CorrectionMaxPct)
            { currentPhase=PHASE_CORRECTION; correctionHigh=cc; correctionLow=indicationLow; }
          if(currentPhase==PHASE_CORRECTION && cc>correctionHigh)
            { double np=((cc-indicationLow)/ms)*100.0;
              if(np<=CorrectionMaxPct) correctionHigh=cc;
              else currentPhase=PHASE_NONE; } }
      if(currentPhase==PHASE_CORRECTION)
        { double mid=indicationLow+(indicationHigh-indicationLow)*0.5;
          if(cc<mid && cc<correctionHigh && close[2]<close[1])
            currentPhase=PHASE_CONTINUATION; }
     }
  }

//+------------------------------------------------------------------+
//| ========= SCI-STYLE CHART MARKING (v1 carryover) ========         |
//+------------------------------------------------------------------+
void DrawSwingRay(string name, datetime t, double px, color clr, string tag)
  {
   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t, px, TimeCurrent()+PeriodSeconds()*5, px))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_BACK,      true);
   ObjectSetString (0, name, OBJPROP_TEXT,      tag);
   if(DrawLabels)
     {
      string lblName = name + "_lbl";
      ObjectDelete(0, lblName);
      ObjectCreate(0, lblName, OBJ_TEXT, 0, t, px);
      ObjectSetString (0, lblName, OBJPROP_TEXT,     tag);
      ObjectSetInteger(0, lblName, OBJPROP_COLOR,    clr);
      ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 9);
     }
  }
void MarkChartSwings()
  {
   if(!DrawSwings) return;
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   ObjectsDeleteAll(0, PFX + "SW_");
   int hiCount=0, loCount=0;
   int bars = Bars(_Symbol, tf);
   double prevHi=0, prevLo=0;
   for(int shift=SwingLookback+1;
       shift < bars - SwingLookback - 1 &&
       (hiCount < MaxSwingsKept || loCount < MaxSwingsKept);
       shift++)
     {
      if(hiCount < MaxSwingsKept && IsPivotHighTF(tf, shift, SwingLookback))
        {
         double px = iHigh(_Symbol, tf, shift);
         datetime t= iTime(_Symbol, tf, shift);
         string tag = (prevHi==0) ? "H" : (px > prevHi ? "HH" : "LH");
         DrawSwingRay(PFX+"SW_H_"+IntegerToString(hiCount), t, px, SwingHiCol, tag);
         prevHi = px; hiCount++;
        }
      if(loCount < MaxSwingsKept && IsPivotLowTF(tf, shift, SwingLookback))
        {
         double px = iLow(_Symbol, tf, shift);
         datetime t= iTime(_Symbol, tf, shift);
         string tag = (prevLo==0) ? "L" : (px > prevLo ? "HL" : "LL");
         DrawSwingRay(PFX+"SW_L_"+IntegerToString(loCount), t, px, SwingLoCol, tag);
         prevLo = px; loCount++;
        }
     }
  }
void DrawCorrectionZone()
  {
   if(!DrawCorrZone) return;
   if(cH1.lastHi==0 || cH1.lastLo==0) return;
   string name = PFX + "CORR_ZONE";
   ObjectDelete(0, name);
   datetime t1 = TimeCurrent() - PeriodSeconds()*60;
   datetime t2 = TimeCurrent() + PeriodSeconds()*20;
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, cH1.lastHi, t2, cH1.lastLo))
      return;
   color c = biasH1 ==  1 ? ZoneBullCol :
             biasH1 == -1 ? ZoneBearCol : ZoneNeutralCol;
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL,  true);
   ObjectSetInteger(0, name, OBJPROP_BACK,  true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
  }

//+------------------------------------------------------------------+
//| ========= BODY-CLOSE SUPPORT / RESISTANCE ENGINE ========        |
//+------------------------------------------------------------------+
void SR_Init()
  {
   g_srPip = _Point * ((_Digits==3 || _Digits==5) ? 10 : 1);
   g_srTol = SR_TolPips * g_srPip;
   g_srMaHandle = iMA(_Symbol, _Period, SR_RefLen, 0, MODE_SMA, PRICE_CLOSE);
   if(g_srMaHandle == INVALID_HANDLE)
      Print("Warning: could not create SMA handle for S/R classifier.");
  }

double SR_RefSMA()
  {
   if(g_srMaHandle==INVALID_HANDLE) return(SymbolInfoDouble(_Symbol,SYMBOL_BID));
   double buf[]; ArraySetAsSeries(buf,true);
   if(CopyBuffer(g_srMaHandle,0,1,1,buf)==1) return(buf[0]);
   return(SymbolInfoDouble(_Symbol,SYMBOL_BID));
  }

// call once per NEW bar, passing the just-closed bar's close & time
void SR_ProcessBar(double c, datetime t)
  {
   if(!SR_Show) return;

   // session counter: new calendar day = new session
   MqlDateTime mt; TimeToStruct(t,mt);
   int dayKey = mt.year*10000 + mt.mon*100 + mt.day;
   if(dayKey != g_srLastDayKey){ g_srSessCount++; g_srLastDayKey = dayKey; }

   // 1) match this close to an existing cluster
   bool matched=false;
   for(int i=0;i<ArraySize(sr_price);i++)
     {
      if(MathAbs(c - sr_price[i]) <= g_srTol)
        {
         int nc = sr_count[i] + 1;
         sr_price[i] = (sr_price[i]*sr_count[i] + c)/nc;   // running average
         sr_count[i] = nc;
         matched = true;
         if(nc==SR_MinTouch && !sr_drawn[i])
           { sr_drawn[i]=true; sr_isRes[i]=(sr_price[i]>=SR_RefSMA()); SR_DrawLevel(i); }
         else if(nc>SR_MinTouch && SR_ShowCnt && sr_drawn[i])
            SR_UpdateLabel(i);
         break;
        }
     }

   // 2) no match -> new candidate cluster
   if(!matched)
     {
      int n=ArraySize(sr_price);
      ArrayResize(sr_price,n+1);     ArrayResize(sr_count,n+1);
      ArrayResize(sr_birthTime,n+1); ArrayResize(sr_birthSes,n+1);
      ArrayResize(sr_birthBar,n+1);  ArrayResize(sr_isRes,n+1);
      ArrayResize(sr_drawn,n+1);     ArrayResize(sr_name,n+1);
      sr_price[n]=c; sr_count[n]=1; sr_birthTime[n]=t; sr_birthSes[n]=g_srSessCount;
      sr_birthBar[n]=t; sr_isRes[n]=false; sr_drawn[n]=false;
      sr_name[n]=SR_PFX+IntegerToString(g_srUid++);
      if(ArraySize(sr_price)>60) SR_RemoveAt(0);
     }
  }

void SR_Expire(datetime now)
  {
   for(int i=ArraySize(sr_price)-1;i>=0;i--)
     {
      bool expired=false;
      if(SR_DurMode==SR_DAYS) expired=((now-sr_birthTime[i])>=(long)SR_DurN*86400);
      else                    expired=((g_srSessCount-sr_birthSes[i])>=SR_DurN);
      if(expired){ SR_DeleteObjects(i); SR_RemoveAt(i); }
     }
  }

void SR_UpdateActive(datetime now)
  {
   for(int i=0;i<ArraySize(sr_price);i++)
     {
      if(!sr_drawn[i]) continue;
      string nm=sr_name[i];
      if(SR_UseZone){ if(ObjectFind(0,nm+"_box")>=0) ObjectSetInteger(0,nm+"_box",OBJPROP_TIME,1,now); }
      else          { if(ObjectFind(0,nm+"_ln")>=0)  ObjectSetInteger(0,nm+"_ln",OBJPROP_TIME,1,now); }
      if(SR_ShowCnt && ObjectFind(0,nm+"_lb")>=0) ObjectSetInteger(0,nm+"_lb",OBJPROP_TIME,now);
     }
  }

void SR_DrawLevel(int i)
  {
   string nm=sr_name[i]; color col=sr_isRes[i]?SR_ColRes:SR_ColSup;
   double p=sr_price[i]; datetime t1=sr_birthBar[i]; datetime t2=TimeCurrent();
   if(SR_UseZone)
     {
      string on=nm+"_box";
      ObjectCreate(0,on,OBJ_RECTANGLE,0,t1,p+g_srTol/2.0,t2,p-g_srTol/2.0);
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

void SR_UpdateLabel(int i)
  {
   string lb=sr_name[i]+"_lb";
   if(ObjectFind(0,lb)>=0)
      ObjectSetString(0,lb,OBJPROP_TEXT,(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i]));
  }

void SR_DeleteObjects(int i)
  { string nm=sr_name[i]; ObjectDelete(0,nm+"_box"); ObjectDelete(0,nm+"_ln"); ObjectDelete(0,nm+"_lb"); }

void SR_RemoveAt(int idx)
  {
   int n=ArraySize(sr_price); if(idx<0||idx>=n) return;
   for(int i=idx;i<n-1;i++)
     {
      sr_price[i]=sr_price[i+1];     sr_count[i]=sr_count[i+1];
      sr_birthTime[i]=sr_birthTime[i+1]; sr_birthSes[i]=sr_birthSes[i+1];
      sr_birthBar[i]=sr_birthBar[i+1];   sr_isRes[i]=sr_isRes[i+1];
      sr_drawn[i]=sr_drawn[i+1];         sr_name[i]=sr_name[i+1];
     }
   ArrayResize(sr_price,n-1);     ArrayResize(sr_count,n-1);
   ArrayResize(sr_birthTime,n-1); ArrayResize(sr_birthSes,n-1);
   ArrayResize(sr_birthBar,n-1);  ArrayResize(sr_isRes,n-1);
   ArrayResize(sr_drawn,n-1);     ArrayResize(sr_name,n-1);
  }

// convenience driver — call this from OnTick (self-gated on new bars)
void SR_OnTick()
  {
   if(!SR_Show) return;
   datetime curBar = iTime(_Symbol,_Period,0);
   if(curBar != g_srLastBar)
     {
      g_srLastBar = curBar;
      double c = iClose(_Symbol,_Period,1);   // just-closed bar body
      datetime t = iTime(_Symbol,_Period,1);
      SR_ProcessBar(c, t);
      SR_Expire(curBar);
     }
   SR_UpdateActive(curBar);
  }

//+------------------------------------------------------------------+
//| ========= DASHBOARD (cascade + v3.3 stops combined) ====          |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!ShowDashboard) { Comment(""); return; }
   string tStr = currentTrend==TREND_BULLISH ? "BULLISH ^" :
                 currentTrend==TREND_BEARISH ? "BEARISH v" : "NONE";
   string pStr = "Scanning...";
   if(currentPhase==PHASE_INDICATION)   pStr="1. INDICATION";
   if(currentPhase==PHASE_CORRECTION)   pStr="2. CORRECTION";
   if(currentPhase==PHASE_CONTINUATION) pStr="3. CONTINUATION";
   string bD = biasD1==1?"^":biasD1==-1?"v":"-";
   string b4 = biasH4==1?"^":biasH4==-1?"v":"-";
   string b1 = biasH1==1?"^":biasH1==-1?"v":"-";
   string b5 = biasM15==1?"^":biasM15==-1?"v":"-";
   string casc = alignBull ? "^ ALIGNED LONG"
               : alignBear ? "v ALIGNED SHORT"
                           : "x NOT ALIGNED";
   string d = "=== ICC EA v4.0 =========================\n";
   d += " Profile:  "+ActiveProfile+" | "+AssetClassLabel+"\n";
   d += " Mode:     "+(EntryMode==ENTRY_SCI_PURE?"SCI PURE":"FIB FILTERED")+"\n";
   d += " Trend:    "+tStr+"\n";
   if(EntryMode==ENTRY_FIB_FILT) d += " Phase:    "+pStr+"\n";
   d += "=== CASCADE =============================\n";
   d += " D1 "+bD+"  H4 "+b4+"  H1 "+b1+"  M15 "+b5+"\n";
   d += " "+casc+"\n";
   d += "=== STOPS ===============================\n";
   d += " SL Method: "+EnumToString(SL_Method)+"\n";
   d += " MinStop:   "+DoubleToString(GetMinStopDistance(),_Digits)+"\n";
   d += " S/R lvls:  "+IntegerToString(ActiveSRCount())+"\n";
   d += " Trades:    "+IntegerToString(CountOpenTrades())+
                  "/"+IntegerToString(MaxOpenTrades)+"\n";
   if(skippedTrades_BUY>0 || skippedTrades_SELL>0)
     d += " Skipped:   B"+IntegerToString(skippedTrades_BUY)+
                       " S"+IntegerToString(skippedTrades_SELL)+"\n";
   d += "=========================================";
   Comment(d);
  }
int ActiveSRCount()
  {
   int cnt=0;
   for(int i=0;i<ArraySize(sr_drawn);i++) if(sr_drawn[i]) cnt++;
   return cnt;
  }

//+------------------------------------------------------------------+
//| ========= ENTRY (mode-aware) =============================       |
//+------------------------------------------------------------------+
void TryEntries()
  {
   int curBar = Bars(_Symbol, _Period);
   if(curBar == lastAlertBar) return;
   if(CountOpenTrades() >= MaxOpenTrades) return;
   if(UseSessionFilter && !IsWithinSession()) return;
   // ---- BUY ----
   bool buyOK=false;
   double slAnchor=0;       // structural anchor (last counter-swing)
   if(EntryMode==ENTRY_SCI_PURE)
     {
      // Sci rule: cascade aligned bull + M15 close above last H1 swing high
      double trigClose = iClose(_Symbol, TrigTF, 1);
      buyOK = alignBull && cH1.lastHi>0 && trigClose > cH1.lastHi;
      slAnchor = cH1.lastLo;   // SL beneath buyers' line
     }
   else // ENTRY_FIB_FILT
     {
      buyOK = (currentTrend==TREND_BULLISH) &&
              (currentPhase==PHASE_CONTINUATION) &&
              alignBull && !buySignalFired;
      slAnchor = correctionLow;
     }
   if(buyOK) ExecuteBuy(slAnchor, curBar);
   // ---- SELL ----
   bool sellOK=false;
   if(EntryMode==ENTRY_SCI_PURE)
     {
      double trigClose = iClose(_Symbol, TrigTF, 1);
      sellOK = alignBear && cH1.lastLo>0 && trigClose < cH1.lastLo;
      slAnchor = cH1.lastHi;
     }
   else
     {
      sellOK = (currentTrend==TREND_BEARISH) &&
               (currentPhase==PHASE_CONTINUATION) &&
               alignBear && !sellSignalFired;
      slAnchor = correctionHigh;
     }
   if(sellOK) ExecuteSell(slAnchor, curBar);
  }
void ExecuteBuy(double slAnchor, int curBar)
  {
   double ask = symInfo.Ask();
   double minStop = GetMinStopDistance();
   double structDist = ask - slAnchor;
   if(structDist < 0) structDist = 0;
   double slDist  = CalculateSLDistance(structDist);
   double slPrice = NormalizeDouble(ask - slDist, _Digits);
   if(ask - slPrice < minStop * BrokerStopCushion)
     {
      skippedTrades_BUY++;
      if(DebugLog) PrintFormat("BUY SKIPPED: SL too close. ask=%g sl=%g minStop=%g",
                               ask, slPrice, minStop);
      buySignalFired=true; currentPhase=PHASE_NONE; return;
     }
   double slDistFinal = ask - slPrice;
   double tpPrice = NormalizeDouble(ask + slDistFinal * RR_Ratio, _Digits);
   if(tpPrice - ask < minStop * BrokerStopCushion)
     {
      skippedTrades_BUY++;
      if(DebugLog) Print("BUY SKIPPED: TP too close.");
      buySignalFired=true; currentPhase=PHASE_NONE; return;
     }
   double lots = CalculateLotSize(slDistFinal);
   if(lots<=0) return;
   if(trade.Buy(lots, _Symbol, ask, slPrice, tpPrice, TradeComment+" "+ActiveProfile))
     {
      string msg = StringFormat("BUY | %s | %s\nE:%s SL:%s TP:%s | RR:%.2f",
         _Symbol, ActiveProfile,
         DoubleToString(ask,_Digits),
         DoubleToString(slPrice,_Digits),
         DoubleToString(tpPrice,_Digits),
         (tpPrice-ask)/(ask-slPrice));
      SendAlertForced(msg);
      buySignalFired=true; lastAlertBar=curBar; currentPhase=PHASE_NONE;
     }
   else
     {
      invalidStopCount_BUY++;
      PrintFormat("BUY FAILED [retcode %d]: %s | ask=%g SL=%g TP=%g | dist=%g minStop=%g",
         trade.ResultRetcode(), trade.ResultRetcodeDescription(),
         ask, slPrice, tpPrice, ask-slPrice, minStop);
     }
  }
void ExecuteSell(double slAnchor, int curBar)
  {
   double bid = symInfo.Bid();
   double minStop = GetMinStopDistance();
   double structDist = slAnchor - bid;
   if(structDist < 0) structDist = 0;
   double slDist  = CalculateSLDistance(structDist);
   double slPrice = NormalizeDouble(bid + slDist, _Digits);
   if(slPrice - bid < minStop * BrokerStopCushion)
     {
      skippedTrades_SELL++;
      if(DebugLog) PrintFormat("SELL SKIPPED: SL too close. bid=%g sl=%g minStop=%g",
                               bid, slPrice, minStop);
      sellSignalFired=true; currentPhase=PHASE_NONE; return;
     }
   double slDistFinal = slPrice - bid;
   double tpPrice = NormalizeDouble(bid - slDistFinal * RR_Ratio, _Digits);
   if(bid - tpPrice < minStop * BrokerStopCushion)
     {
      skippedTrades_SELL++;
      if(DebugLog) Print("SELL SKIPPED: TP too close.");
      sellSignalFired=true; currentPhase=PHASE_NONE; return;
     }
   double lots = CalculateLotSize(slDistFinal);
   if(lots<=0) return;
   if(trade.Sell(lots, _Symbol, bid, slPrice, tpPrice, TradeComment+" "+ActiveProfile))
     {
      string msg = StringFormat("SELL | %s | %s\nE:%s SL:%s TP:%s | RR:%.2f",
         _Symbol, ActiveProfile,
         DoubleToString(bid,_Digits),
         DoubleToString(slPrice,_Digits),
         DoubleToString(tpPrice,_Digits),
         (bid-tpPrice)/(slPrice-bid));
      SendAlertForced(msg);
      sellSignalFired=true; lastAlertBar=curBar; currentPhase=PHASE_NONE;
     }
   else
     {
      invalidStopCount_SELL++;
      PrintFormat("SELL FAILED [retcode %d]: %s | bid=%g SL=%g TP=%g | dist=%g minStop=%g",
         trade.ResultRetcode(), trade.ResultRetcodeDescription(),
         bid, slPrice, tpPrice, slPrice-bid, minStop);
     }
  }

//+------------------------------------------------------------------+
//| ========= POSITION / RISK MANAGEMENT (v3.3 carryover) ==          |
//+------------------------------------------------------------------+
double CalculateLotSize(double sd)
  {
   if(FixedLots>0) return NormalizeLots(FixedLots);
   if(sd<=0) return 0;
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * RiskPercent / 100.0;
   double tv   = symInfo.TickValue();
   double ts   = symInfo.TickSize();
   if(tv<=0 || ts<=0) return symInfo.LotsMin();
   return NormalizeLots(risk / ((sd/ts) * tv));
  }
double NormalizeLots(double l)
  {
   double mn=symInfo.LotsMin(), mx=symInfo.LotsMax(), st=symInfo.LotsStep();
   l=MathMax(l,mn); l=MathMin(l,mx); l=MathFloor(l/st)*st;
   return NormalizeDouble(l,2);
  }
int CountOpenTrades()
  {
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     if(posInfo.SelectByIndex(i))
       if(posInfo.Magic()==MagicNumber && posInfo.Symbol()==_Symbol) c++;
   return c;
  }
void ManagePositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber || posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss(), tp=posInfo.TakeProfit();
      double pt=symInfo.Point();   ulong tk=posInfo.Ticket();
      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        { double bid=symInfo.Bid(), pp=(bid-op)/pt;
          if(UseBreakEven && pp>=BreakEvenAt_Pts)
            { double ns=op+BreakEvenProfit*pt; if(sl<ns) trade.PositionModify(tk,ns,tp); }
          if(UseTrailingStop && pp>=TrailingStart_Pts)
            { double ts=bid-TrailingStep_Pts*pt; if(ts>sl) trade.PositionModify(tk,ts,tp); } }
      if(posInfo.PositionType()==POSITION_TYPE_SELL)
        { double ask=symInfo.Ask(), pp=(op-ask)/pt;
          if(UseBreakEven && pp>=BreakEvenAt_Pts)
            { double ns=op-BreakEvenProfit*pt; if(sl>ns || sl==0) trade.PositionModify(tk,ns,tp); }
          if(UseTrailingStop && pp>=TrailingStart_Pts)
            { double ts=ask+TrailingStep_Pts*pt; if(ts<sl || sl==0) trade.PositionModify(tk,ts,tp); } }
     }
  }
void MonitorSLTP()
  {
   symInfo.Refresh();
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber || posInfo.Symbol()!=_Symbol) continue;
      ulong tk=posInfo.Ticket();
      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss(), tp=posInfo.TakeProfit();
      double pt=symInfo.Point();
      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        { double bid=symInfo.Bid();
          if(tp>0 && bid>=tp){ if(trade.PositionClose(tk))
            SendAlertForced("BUY TP HIT | "+_Symbol+" | +"+DoubleToString((bid-op)/pt,0)+" pts"); }
          else if(sl>0 && bid<=sl){ if(trade.PositionClose(tk))
            SendAlertForced("BUY SL HIT | "+_Symbol+" | -"+DoubleToString((op-bid)/pt,0)+" pts"); } }
      if(posInfo.PositionType()==POSITION_TYPE_SELL)
        { double ask=symInfo.Ask();
          if(tp>0 && ask<=tp){ if(trade.PositionClose(tk))
            SendAlertForced("SELL TP HIT | "+_Symbol+" | +"+DoubleToString((op-ask)/pt,0)+" pts"); }
          else if(sl>0 && ask>=sl){ if(trade.PositionClose(tk))
            SendAlertForced("SELL SL HIT | "+_Symbol+" | -"+DoubleToString((ask-op)/pt,0)+" pts"); } }
     }
  }

//+------------------------------------------------------------------+
//| ========= ALERTS (v3.3 carryover) ========================       |
//+------------------------------------------------------------------+
void SendAlert(string m)
  { if(TimeCurrent()-lastAlertTime<60) return;
    DispatchAlert(m); lastAlertTime=TimeCurrent(); }
void SendAlertForced(string m)
  { DispatchAlert(m); lastAlertTime=TimeCurrent(); }
void DispatchAlert(string m)
  { Print("ICCv4: ",m);
    if(AlertPopup) Alert(m);
    if(AlertPush)  SendNotification(m);
    if(AlertEmail) SendMail("ICC v4.0 - "+_Symbol, m);
    if(AlertSound) PlaySound(AlertSoundFile); }
bool IsWithinSession()
  { MqlDateTime dt; TimeCurrent(dt);
    if(SessionStartHour<SessionEndHour)
      return(dt.hour>=SessionStartHour && dt.hour<SessionEndHour);
    return(dt.hour>=SessionStartHour || dt.hour<SessionEndHour); }
bool IsNewBar()
  { static datetime lt=0; datetime ct=iTime(_Symbol,_Period,0);
    if(ct!=lt){ lt=ct; return true; } return false; }

//+------------------------------------------------------------------+
//| ========= LIFECYCLE ======================================        |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   symInfo.Name(_Symbol); symInfo.Refresh();
   ArrayResize(swingHighs,    100);
   ArrayResize(swingLows,     100);
   ArrayResize(swingHighBars, 100);
   ArrayResize(swingLowBars,  100);
   AssetClass = DetectAssetClass();
   AutoConfigure();
   atrHandle = iATR(_Symbol, _Period, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
      Print("WARNING: ATR handle creation failed. ATR-based SL will fallback.");
   SR_Init();                               // <-- body-close S/R engine
   EvaluateCascade();
   PrintFormat("ICC EA v4.0 | %s | Asset: %s | Mode: %s | Cascade: %s->%s->%s->%s",
      ActiveProfile, AssetClassLabel, EnumToString(EntryMode),
      EnumToString(BiasTF), EnumToString(MidTF),
      EnumToString(WorkTF), EnumToString(TrigTF));
   PrintBrokerDiagnostics();
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  {
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(g_srMaHandle != INVALID_HANDLE) IndicatorRelease(g_srMaHandle);  // <-- S/R SMA
   ObjectsDeleteAll(0, PFX);            // also removes ICCv4_SR_* objects
   Comment("");
   if(invalidStopCount_BUY>0 || invalidStopCount_SELL>0 ||
      skippedTrades_BUY>0    || skippedTrades_SELL>0)
     {
      Print("=== TRADE EXECUTION SUMMARY ===");
      Print("  Skipped BUYs (SL invalid):  ", skippedTrades_BUY);
      Print("  Skipped SELLs (SL invalid): ", skippedTrades_SELL);
      Print("  Broker BUY rejections:      ", invalidStopCount_BUY);
      Print("  Broker SELL rejections:     ", invalidStopCount_SELL);
     }
  }
void OnTick()
  {
   MonitorSLTP();
   ManagePositions();
   if(!IsNewBar()) return;
   symInfo.Refresh();
   // 1) Refresh the 4-TF cascade
   EvaluateCascade();
   // 2) Working-TF structure (drives SL anchor + FIB_FILT phase machine)
   DetectSwingPoints();
   DetermineMarketStructure();
   if(EntryMode == ENTRY_FIB_FILT) IdentifyICCPhases_FibFilt();
   // 3) Visuals — Sci-style + body-close S/R
   MarkChartSwings();
   DrawCorrectionZone();
   SR_OnTick();                         // <-- body-close S/R engine
   UpdateDashboard();
   // 4) Entry routing
   TryEntries();
  }
//+------------------------------------------------------------------+
