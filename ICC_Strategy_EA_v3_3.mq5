//+------------------------------------------------------------------+
//|                                       ICC_Strategy_EA_v3_3.mq5  |
//|     ICC v3.3 — Symbol-Aware Stops + Broker Diagnostics          |
//|                                                                  |
//|  v3.3 FIXES OVER v3.2:                                          |
//|   • Symbol-aware SL: uses MAX(structural buffer, ATR, broker min)|
//|   • Detects XAUUSD/indices/crypto and auto-scales SL buffer     |
//|   • Pre-trade SL/TP validation prevents "Invalid Stops" errors  |
//|   • Init-time diagnostic: prints stops_level, spread, tick_value |
//|   • Per-asset-class default SL_Buffer overrides                 |
//+------------------------------------------------------------------+
#property copyright   "ICC Strategy EA v3.3"
#property version     "3.30"
#property description "ICC v3.3 — Symbol-Aware Stops + Diagnostics"
#property description "Auto-detects gold/indices/crypto and scales SL accordingly"

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

enum ENUM_MTF_MODE
  { MTF_AUTO=0, MTF_DUAL=1, MTF_MANUAL=2 };

enum ENUM_HTF_METHOD
  { HTF_SWING_ONLY=0, HTF_EMA_ONLY=1, HTF_COMBINED=2 };

enum ENUM_HTF2_FALLBACK
  { HTF2_BLOCK=0, HTF2_NEUTRAL=1, HTF2_DOWNGRADE=2 };

enum ENUM_ASSET_CLASS
  { ASSET_FOREX=0, ASSET_METAL=1, ASSET_INDEX=2, ASSET_CRYPTO=3, ASSET_OTHER=4 };

enum ENUM_SL_METHOD
  {
   SL_STRUCTURAL = 0,  // Original: correctionLow/High + buffer
   SL_ATR        = 1,  // ATR × multiplier
   SL_SMART      = 2   // MAX of structural, ATR, broker min (recommended)
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== Stop Loss Method (v3.3) ==="
input ENUM_SL_METHOD SL_Method        = SL_SMART;   // SL calculation method
input double         ATR_Multiplier   = 1.5;        // ATR multiplier for SL
input int            ATR_Period       = 14;         // ATR period
input double         BrokerStopCushion = 1.2;       // Multiplier above broker min stop (1.2 = 20% above)
input bool           AutoScaleByAsset = true;       // Auto-scale SL_Buffer based on asset class
input bool           ShowDiagnostics  = true;       // Print broker diagnostics on init

input group "=== Multi-Timeframe Confluence ==="
input bool             UseMTF            = true;
input ENUM_MTF_MODE    MTF_Mode          = MTF_AUTO;
input ENUM_TIMEFRAMES  ManualHTF1        = PERIOD_H4;
input ENUM_TIMEFRAMES  ManualHTF2        = PERIOD_D1;
input bool             RequireBothHTF    = false;
input ENUM_HTF_METHOD  HTF_Method        = HTF_COMBINED;
input ENUM_HTF2_FALLBACK HTF2_Fallback   = HTF2_NEUTRAL;
input int              HTF_SwingLookback = 5;
input bool             AllowCounterTrend = false;
input int              HTF_CheckBars     = 200;
input int              HTF_EMA_Fast      = 21;
input int              HTF_EMA_Slow      = 50;
input int              HTF_MinBarsRequired = 30;
input bool             HTF_AdaptiveEMA   = true;
input bool             HTF_Debug         = false;
input int              HTF_DebugInterval = 200;

input group "=== Auto-Timeframe Settings ==="
input bool   AutoSettings = true;

input group "=== ICC Structure (manual overrides if AutoSettings=false) ==="
input int    SwingLookback_In = 5;
input double CorrMinPct_In    = 30.0;
input double CorrMaxPct_In    = 79.0;
input double RR_Ratio_In      = 2.0;
input int    SL_Buffer_In     = 50;

input group "=== Trade Management ==="
input double RiskPercent   = 1.0;
input double FixedLots     = 0.0;
input int    MaxOpenTrades = 1;

input group "=== Trailing Stop ==="
input bool   UseTrailingStop  = true;
input int    TrailingStart_In = 200;
input int    TrailingStep_In  = 100;

input group "=== Break Even ==="
input bool   UseBreakEven     = true;
input int    BreakEvenAt_In   = 150;
input int    BreakEvenProfit_In = 10;

input group "=== Session Filter ==="
input bool   UseSessionFilter = false;
input int    SessionStartHour = 2;
input int    SessionEndHour   = 17;

input group "=== Alert Settings ==="
input bool   AlertPopup     = false;
input bool   AlertPush      = false;
input bool   AlertEmail     = false;
input bool   AlertSound     = false;
input string AlertSoundFile = "alert.wav";
input bool   SuppressDuplicateAlerts = true;

input group "=== Visual Settings ==="
input bool  ShowSwingPoints = true;
input bool  ShowPhaseLabels = true;
input bool  ShowDashboard   = true;
input bool  ShowHTFZones    = false;
input color BullColor       = clrDodgerBlue;
input color BearColor       = clrOrangeRed;
input color CorrColor       = clrGold;
input color HTF_BullZone    = clrMediumSeaGreen;
input color HTF_BearZone    = clrCrimson;

input group "=== EA Settings ==="
input int MagicNumber = 20260612;

//+------------------------------------------------------------------+
//| ACTIVE RUNTIME SETTINGS                                          |
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

//+------------------------------------------------------------------+
//| MTF CONFLUENCE DATA                                              |
//+------------------------------------------------------------------+
struct SMTFData
  {
   ENUM_TIMEFRAMES timeframe;
   ENUM_TREND      trend;
   double          swingHigh;
   double          swingLow;
   double          prevSwingHigh;
   double          prevSwingLow;
   double          emaFast;
   double          emaSlow;
   string          trendLabel;
   string          methodUsed;
   bool            isValid;
   bool            hasData;
  };

SMTFData HTF1, HTF2;
bool   mtfConfluenceBull;
bool   mtfConfluenceBear;
string mtfStatusMsg;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade        trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;

int    atrHandle = INVALID_HANDLE;

double swingHighs[];
double swingLows[];
int    swingHighBars[];
int    swingLowBars[];
int    swingHighCount=0, swingLowCount=0;

ENUM_TREND     currentTrend  = TREND_NONE;
ENUM_ICC_PHASE currentPhase  = PHASE_NONE;
ENUM_TREND     previousTrend = TREND_NONE;

double indicationHigh=0, indicationLow=0;
double correctionHigh=0, correctionLow=0;
double lastSwingHigh=0,  lastSwingLow=0;
double prevSwingHigh=0,  prevSwingLow=0;

double lastAlertedBullInd = 0;
double lastAlertedBearInd = 0;

bool   buySignalFired=false, sellSignalFired=false;
datetime lastAlertTime=0;
int    lastAlertBar=0;

ENUM_TIMEFRAMES lastTimeframe = PERIOD_CURRENT;
int    htfDebugCounter = 0;

// Diagnostic counters
int    invalidStopCount_BUY  = 0;
int    invalidStopCount_SELL = 0;
int    skippedTrades_BUY     = 0;
int    skippedTrades_SELL    = 0;

//+------------------------------------------------------------------+
//| v3.3 — SYMBOL-AWARE STOP CALCULATIONS                            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Detect asset class from symbol name                              |
//+------------------------------------------------------------------+
ENUM_ASSET_CLASS DetectAssetClass()
  {
   string sym = _Symbol;
   StringToUpper(sym);

   if(StringFind(sym,"XAU")>=0 || StringFind(sym,"GOLD")>=0 ||
      StringFind(sym,"XAG")>=0 || StringFind(sym,"SILVER")>=0 ||
      StringFind(sym,"XPT")>=0 || StringFind(sym,"XPD")>=0)
     { AssetClassLabel="METAL"; return ASSET_METAL; }

   if(StringFind(sym,"BTC")>=0 || StringFind(sym,"ETH")>=0 ||
      StringFind(sym,"XRP")>=0 || StringFind(sym,"LTC")>=0 ||
      StringFind(sym,"BCH")>=0 || StringFind(sym,"SOL")>=0 ||
      StringFind(sym,"DOGE")>=0 || StringFind(sym,"ADA")>=0)
     { AssetClassLabel="CRYPTO"; return ASSET_CRYPTO; }

   if(StringFind(sym,"US30")>=0 || StringFind(sym,"US500")>=0 ||
      StringFind(sym,"NAS")>=0  || StringFind(sym,"SPX")>=0 ||
      StringFind(sym,"DJ")>=0   || StringFind(sym,"DAX")>=0 ||
      StringFind(sym,"FTSE")>=0 || StringFind(sym,"NIK")>=0 ||
      StringFind(sym,"HK50")>=0 || StringFind(sym,"AUS200")>=0 ||
      StringFind(sym,"GER")>=0  || StringFind(sym,"UK100")>=0)
     { AssetClassLabel="INDEX"; return ASSET_INDEX; }

   if(StringLen(sym)>=6)
     { AssetClassLabel="FOREX"; return ASSET_FOREX; }

   AssetClassLabel="OTHER";
   return ASSET_OTHER;
  }

//+------------------------------------------------------------------+
//| Apply asset-class scaling to SL_Buffer                           |
//+------------------------------------------------------------------+
void ApplyAssetClassScaling()
  {
   if(!AutoScaleByAsset) return;
   int baseBuffer = SL_Buffer_Points;

   switch(AssetClass)
     {
      case ASSET_FOREX: break;
      case ASSET_METAL:
         SL_Buffer_Points = baseBuffer * 30;
         TrailingStart_Pts = TrailingStart_Pts * 30;
         TrailingStep_Pts  = TrailingStep_Pts * 30;
         BreakEvenAt_Pts   = BreakEvenAt_Pts * 30;
         BreakEvenProfit   = BreakEvenProfit * 30;
         break;
      case ASSET_INDEX:
         SL_Buffer_Points = baseBuffer * 20;
         TrailingStart_Pts = TrailingStart_Pts * 20;
         TrailingStep_Pts  = TrailingStep_Pts * 20;
         BreakEvenAt_Pts   = BreakEvenAt_Pts * 20;
         BreakEvenProfit   = BreakEvenProfit * 20;
         break;
      case ASSET_CRYPTO:
         SL_Buffer_Points = baseBuffer * 300;
         TrailingStart_Pts = TrailingStart_Pts * 300;
         TrailingStep_Pts  = TrailingStep_Pts * 300;
         BreakEvenAt_Pts   = BreakEvenAt_Pts * 300;
         BreakEvenProfit   = BreakEvenProfit * 300;
         break;
     }

   if(AssetClass != ASSET_FOREX)
      Print("ASSET SCALING [",AssetClassLabel,"]: SL_Buffer ",baseBuffer," → ",SL_Buffer_Points,
            " | Trail: ",TrailingStart_Pts,"/",TrailingStep_Pts);
  }

//+------------------------------------------------------------------+
//| Get broker's minimum stop distance (in PRICE units)              |
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

//+------------------------------------------------------------------+
//| Get ATR-based stop distance (in PRICE units)                     |
//+------------------------------------------------------------------+
double GetATRStopDistance()
  {
   if(atrHandle == INVALID_HANDLE) return GetMinStopDistance() * 2;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, atr) < 1)
      return GetMinStopDistance() * 2;
   if(atr[0] <= 0) return GetMinStopDistance() * 2;
   return atr[0] * ATR_Multiplier;
  }

//+------------------------------------------------------------------+
//| Calculate SAFE SL distance using selected method                 |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Print broker diagnostics on init                                 |
//+------------------------------------------------------------------+
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
   double contract  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   double minStop   = GetMinStopDistance();
   double atrStop   = GetATRStopDistance();
   double bufStop   = SL_Buffer_Points * point;

   Print("╔══════════════════════════════════════════════════════════╗");
   Print("║          ICC EA v3.3 — BROKER DIAGNOSTICS                ║");
   Print("╠══════════════════════════════════════════════════════════╣");
   Print("║ Symbol:           ", _Symbol);
   Print("║ Asset Class:      ", AssetClassLabel);
   Print("║ Timeframe:        ", EnumToString(_Period));
   Print("║ Profile:          ", ActiveProfile);
   Print("╠══ PRICE INFO ════════════════════════════════════════════╣");
   Print("║ Bid:              ", DoubleToString(bid, (int)digits));
   Print("║ Ask:              ", DoubleToString(ask, (int)digits));
   Print("║ Digits:           ", digits);
   Print("║ Point:            ", DoubleToString(point, (int)digits));
   Print("║ Tick Size:        ", DoubleToString(tickSize, (int)digits));
   Print("║ Tick Value:       $", DoubleToString(tickValue, 4));
   Print("║ Contract Size:    ", DoubleToString(contract, 2));
   Print("╠══ BROKER LIMITS ═════════════════════════════════════════╣");
   Print("║ Stops Level:      ", stopsLvl, " points (", DoubleToString(stopsLvl*point, (int)digits),")");
   Print("║ Freeze Level:     ", freezeLvl, " points (", DoubleToString(freezeLvl*point, (int)digits),")");
   Print("║ Current Spread:   ", spread, " points (", DoubleToString(spread*point, (int)digits),")");
   Print("║ Min Lot:          ", DoubleToString(minLot, 2));
   Print("║ Max Lot:          ", DoubleToString(maxLot, 2));
   Print("║ Lot Step:         ", DoubleToString(lotStep, 2));
   Print("╠══ SL CONFIGURATION ══════════════════════════════════════╣");
   Print("║ SL Method:        ", EnumToString(SL_Method));
   Print("║ SL_Buffer_Points: ", SL_Buffer_Points, " (= ",DoubleToString(bufStop,(int)digits),")");
   Print("║ ATR Stop:         ", DoubleToString(atrStop, (int)digits),
         " (ATR x ", DoubleToString(ATR_Multiplier,1), ")");
   Print("║ Min Safe Stop:    ", DoubleToString(minStop, (int)digits),
         " | x Cushion: ", DoubleToString(minStop*BrokerStopCushion, (int)digits));
   Print("║ RR Ratio:         ", DoubleToString(RR_Ratio, 1));
   Print("╠══ SANITY CHECK ══════════════════════════════════════════╣");

   if(bufStop < minStop)
     Print("║ ⚠ WARNING: SL_Buffer (",DoubleToString(bufStop,(int)digits),
           ") is BELOW broker minimum (",DoubleToString(minStop,(int)digits),")!");
   else
     Print("║ ✓ SL_Buffer is above broker minimum.");

   if(SL_Method == SL_SMART)
     Print("║ ✓ Using SL_SMART — will auto-correct to safe distance.");

   Print("╚══════════════════════════════════════════════════════════╝");
  }

//+------------------------------------------------------------------+
//| Auto-select HTFs                                                 |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetAutoHTF1(ENUM_TIMEFRAMES tf)
  { if(tf==PERIOD_M5) return PERIOD_M15;
    if(tf==PERIOD_M15) return PERIOD_H1;
    if(tf==PERIOD_H1)  return PERIOD_H4;
    if(tf==PERIOD_H4)  return PERIOD_D1;
    if(tf==PERIOD_D1)  return PERIOD_W1;
    return PERIOD_H4; }

ENUM_TIMEFRAMES GetAutoHTF2(ENUM_TIMEFRAMES tf)
  { if(tf==PERIOD_M5) return PERIOD_H1;
    if(tf==PERIOD_M15) return PERIOD_H4;
    if(tf==PERIOD_H1)  return PERIOD_D1;
    if(tf==PERIOD_H4)  return PERIOD_W1;
    if(tf==PERIOD_D1)  return PERIOD_MN1;
    return PERIOD_D1; }

ENUM_TIMEFRAMES DowngradeTF(ENUM_TIMEFRAMES tf)
  { if(tf==PERIOD_MN1) return PERIOD_W1;
    if(tf==PERIOD_W1)  return PERIOD_D1;
    if(tf==PERIOD_D1)  return PERIOD_H4;
    if(tf==PERIOD_H4)  return PERIOD_H1;
    if(tf==PERIOD_H1)  return PERIOD_M30;
    return tf; }

void ConfigureMTF()
  {
   if(!UseMTF)
     { HTF1.isValid=false; HTF2.isValid=false;
       mtfConfluenceBull=true; mtfConfluenceBear=true;
       mtfStatusMsg="MTF: DISABLED"; return; }

   switch(MTF_Mode)
     {
      case MTF_AUTO:
        HTF1.timeframe = GetAutoHTF1(_Period);
        HTF2.timeframe = GetAutoHTF2(_Period); break;
      case MTF_DUAL:
        HTF1.timeframe = GetAutoHTF1(_Period);
        HTF2.timeframe = ManualHTF2; break;
      case MTF_MANUAL:
        HTF1.timeframe = ManualHTF1;
        HTF2.timeframe = ManualHTF2; break;
     }
   HTF1.isValid=true; HTF2.isValid=true;

   if(HTF1.timeframe<=_Period) HTF1.timeframe=GetAutoHTF1(_Period);
   if(HTF2.timeframe<=_Period) HTF2.timeframe=GetAutoHTF2(_Period);
  }

//+------------------------------------------------------------------+
//| Analyze HTF                                                      |
//+------------------------------------------------------------------+
void AnalyzeHTF(SMTFData &htf)
  {
   if(!htf.isValid) return;
   htf.trend=TREND_NONE; htf.trendLabel="NONE"; htf.methodUsed="---"; htf.hasData=false;

   int bars = Bars(_Symbol, htf.timeframe);
   int minBars=HTF_MinBarsRequired, eF=HTF_EMA_Fast, eS=HTF_EMA_Slow;
   if(HTF_AdaptiveEMA && bars < HTF_EMA_Slow+5) { eF=8; eS=21; }
   if(bars < minBars)
     { htf.trendLabel="NO DATA ("+IntegerToString(bars)+" bars)";
       htf.methodUsed="INSUFFICIENT"; return; }

   double emaFastArr[], emaSlowArr[];
   ArraySetAsSeries(emaFastArr,true); ArraySetAsSeries(emaSlowArr,true);
   int hF=iMA(_Symbol,htf.timeframe,eF,0,MODE_EMA,PRICE_CLOSE);
   int hS=iMA(_Symbol,htf.timeframe,eS,0,MODE_EMA,PRICE_CLOSE);
   if(hF==INVALID_HANDLE||hS==INVALID_HANDLE)
     { htf.trendLabel="EMA HANDLE FAIL"; htf.methodUsed="ERROR"; return; }
   int cf=CopyBuffer(hF,0,0,3,emaFastArr);
   int cs=CopyBuffer(hS,0,0,3,emaSlowArr);
   IndicatorRelease(hF); IndicatorRelease(hS);
   if(cf<3||cs<3){ htf.trendLabel="EMA COPY FAIL"; htf.methodUsed="ERROR"; return; }

   htf.emaFast=emaFastArr[0]; htf.emaSlow=emaSlowArr[0]; htf.hasData=true;
   bool emaBull=emaFastArr[0]>emaSlowArr[0], emaBear=emaFastArr[0]<emaSlowArr[0];
   bool emaR=emaFastArr[0]>emaFastArr[1], emaFl=emaFastArr[0]<emaFastArr[1];

   if(HTF_Method==HTF_EMA_ONLY)
     { if(emaBull){htf.trend=TREND_BULLISH;htf.trendLabel="BULLISH ▲ (EMA)";}
       else if(emaBear){htf.trend=TREND_BEARISH;htf.trendLabel="BEARISH ▼ (EMA)";}
       else htf.trendLabel="FLAT (EMA)";
       htf.methodUsed=StringFormat("EMA(%d/%d)",eF,eS); return; }

   bool swingFound=false; ENUM_TREND swingTrend=TREND_NONE;
   if(bars>=HTF_SwingLookback*2+10)
     {
      double H[],L[];
      ArraySetAsSeries(H,true);ArraySetAsSeries(L,true);
      int copyLen=MathMin(HTF_CheckBars,bars-1);
      int cH=CopyHigh(_Symbol,htf.timeframe,0,copyLen,H);
      int cL=CopyLow(_Symbol,htf.timeframe,0,copyLen,L);
      if(cH>=HTF_SwingLookback*2+5 && cL>=HTF_SwingLookback*2+5)
        {
         double shArr[],slArr[]; ArrayResize(shArr,0);ArrayResize(slArr,0);
         int lb=HTF_SwingLookback, scanEnd=cH-lb;
         for(int b=lb;b<scanEnd && ArraySize(shArr)<4;b++)
           { bool isSH=true;
             for(int k=1;k<=lb;k++)
               if(H[b-k]>=H[b]||H[b+k]>=H[b]){isSH=false;break;}
             if(isSH){int sz=ArraySize(shArr);ArrayResize(shArr,sz+1);shArr[sz]=H[b];} }
         for(int b=lb;b<scanEnd && ArraySize(slArr)<4;b++)
           { bool isSL=true;
             for(int k=1;k<=lb;k++)
               if(L[b-k]<=L[b]||L[b+k]<=L[b]){isSL=false;break;}
             if(isSL){int sz=ArraySize(slArr);ArrayResize(slArr,sz+1);slArr[sz]=L[b];} }
         if(ArraySize(shArr)>=2 && ArraySize(slArr)>=2)
           {
            htf.swingHigh=shArr[0]; htf.prevSwingHigh=shArr[1];
            htf.swingLow=slArr[0];  htf.prevSwingLow=slArr[1];
            bool hh=htf.swingHigh>htf.prevSwingHigh, hl=htf.swingLow>htf.prevSwingLow;
            bool ll=htf.swingLow<htf.prevSwingLow,   lh=htf.swingHigh<htf.prevSwingHigh;
            if(hh&&hl){swingTrend=TREND_BULLISH;swingFound=true;}
            else if(ll&&lh){swingTrend=TREND_BEARISH;swingFound=true;}
            else if(hh){swingTrend=TREND_BULLISH;swingFound=true;}
            else if(ll){swingTrend=TREND_BEARISH;swingFound=true;}
           }
        }
     }

   if(HTF_Method==HTF_SWING_ONLY)
     { if(swingFound){htf.trend=swingTrend;
         htf.trendLabel=(swingTrend==TREND_BULLISH?"BULLISH ▲":"BEARISH ▼")+" (Swing)";
         htf.methodUsed="SWING";}
       else{htf.trendLabel="FORMING";htf.methodUsed="SWING-NONE";} }
   else
     { if(swingFound)
         { htf.trend=swingTrend;
           htf.trendLabel=(swingTrend==TREND_BULLISH?"BULLISH ▲":"BEARISH ▼")+" (Swing)";
           htf.methodUsed="SWING";
           if((swingTrend==TREND_BULLISH&&emaBull)||(swingTrend==TREND_BEARISH&&emaBear))
             { htf.trendLabel+="+EMA"; htf.methodUsed="SWING+EMA"; } }
       else
         { if(emaBull&&emaR){htf.trend=TREND_BULLISH;htf.trendLabel="BULLISH ▲ (EMA↑)";}
           else if(emaBull){htf.trend=TREND_BULLISH;htf.trendLabel="BULLISH ▲ (EMA)";}
           else if(emaBear&&emaFl){htf.trend=TREND_BEARISH;htf.trendLabel="BEARISH ▼ (EMA↓)";}
           else if(emaBear){htf.trend=TREND_BEARISH;htf.trendLabel="BEARISH ▼ (EMA)";}
           else htf.trendLabel="FLAT (EMA)";
           htf.methodUsed=StringFormat("EMA-FB(%d/%d)",eF,eS); } }
  }

void EvaluateMTFConfluence()
  {
   if(!UseMTF){ mtfConfluenceBull=true; mtfConfluenceBear=true;
     mtfStatusMsg="MTF DISABLED"; return; }

   AnalyzeHTF(HTF1);
   if(HTF2.isValid) AnalyzeHTF(HTF2);

   if(HTF2.isValid && !HTF2.hasData && HTF2_Fallback==HTF2_DOWNGRADE)
     { ENUM_TIMEFRAMES alt=DowngradeTF(HTF2.timeframe);
       if(alt>_Period && alt!=HTF2.timeframe)
         { HTF2.timeframe=alt; AnalyzeHTF(HTF2); } }

   bool htf1Bull=(HTF1.trend==TREND_BULLISH);
   bool htf1Bear=(HTF1.trend==TREND_BEARISH);
   bool htf2Bull,htf2Bear;
   if(!HTF2.isValid){htf2Bull=true;htf2Bear=true;}
   else if(!HTF2.hasData)
     { if(HTF2_Fallback==HTF2_NEUTRAL||HTF2_Fallback==HTF2_DOWNGRADE)
         {htf2Bull=true;htf2Bear=true;}
       else {htf2Bull=false;htf2Bear=false;} }
   else { htf2Bull=(HTF2.trend==TREND_BULLISH); htf2Bear=(HTF2.trend==TREND_BEARISH); }

   if(RequireBothHTF && HTF2.isValid && HTF2.hasData)
     { mtfConfluenceBull=htf1Bull&&htf2Bull; mtfConfluenceBear=htf1Bear&&htf2Bear; }
   else
     { mtfConfluenceBull=htf1Bull; mtfConfluenceBear=htf1Bear; }

   mtfStatusMsg="HTF1("+EnumToString(HTF1.timeframe)+"): "+HTF1.trendLabel;
   if(HTF2.isValid) mtfStatusMsg+=" | HTF2("+EnumToString(HTF2.timeframe)+"): "+HTF2.trendLabel;

   if(HTF_Debug && htfDebugCounter%HTF_DebugInterval==0)
      Print("MTF | HTF1: ",HTF1.trendLabel," | HTF2: ",HTF2.trendLabel,
            " | Bull: ",mtfConfluenceBull?"YES":"NO",
            " | Bear: ",mtfConfluenceBear?"YES":"NO");
   htfDebugCounter++;
  }

void AutoConfigure()
  {
   ENUM_TIMEFRAMES tf=_Period;
   if(!AutoSettings)
     { SwingLookback=SwingLookback_In;CorrectionMinPct=CorrMinPct_In;
       CorrectionMaxPct=CorrMaxPct_In;RR_Ratio=RR_Ratio_In;
       SL_Buffer_Points=SL_Buffer_In;TrailingStart_Pts=TrailingStart_In;
       TrailingStep_Pts=TrailingStep_In;BreakEvenAt_Pts=BreakEvenAt_In;
       BreakEvenProfit=BreakEvenProfit_In;ActiveProfile="MANUAL";
       ConfigureMTF(); ApplyAssetClassScaling(); return; }

   if(tf==PERIOD_M5){ SwingLookback=3;CorrectionMinPct=25;CorrectionMaxPct=65;RR_Ratio=1.2;
     SL_Buffer_Points=20;TrailingStart_Pts=80;TrailingStep_Pts=40;
     BreakEvenAt_Pts=60;BreakEvenProfit=5;ActiveProfile="M5 SCALP"; }
   else if(tf==PERIOD_M15){ SwingLookback=3;CorrectionMinPct=30;CorrectionMaxPct=70;RR_Ratio=1.5;
     SL_Buffer_Points=30;TrailingStart_Pts=120;TrailingStep_Pts=60;
     BreakEvenAt_Pts=100;BreakEvenProfit=8;ActiveProfile="M15 SCALP"; }
   else if(tf==PERIOD_H1){ SwingLookback=5;CorrectionMinPct=30;CorrectionMaxPct=79;RR_Ratio=2.0;
     SL_Buffer_Points=50;TrailingStart_Pts=200;TrailingStep_Pts=100;
     BreakEvenAt_Pts=150;BreakEvenProfit=10;ActiveProfile="H1 INTRADAY"; }
   else if(tf==PERIOD_H4){ SwingLookback=7;CorrectionMinPct=38;CorrectionMaxPct=79;RR_Ratio=3.0;
     SL_Buffer_Points=100;TrailingStart_Pts=400;TrailingStep_Pts=200;
     BreakEvenAt_Pts=300;BreakEvenProfit=20;ActiveProfile="H4 SWING"; }
   else if(tf==PERIOD_D1){ SwingLookback=10;CorrectionMinPct=38;CorrectionMaxPct=79;RR_Ratio=3.5;
     SL_Buffer_Points=200;TrailingStart_Pts=800;TrailingStep_Pts=400;
     BreakEvenAt_Pts=600;BreakEvenProfit=50;ActiveProfile="D1 POSITION"; }
   else { SwingLookback=SwingLookback_In;CorrectionMinPct=CorrMinPct_In;
     CorrectionMaxPct=CorrMaxPct_In;RR_Ratio=RR_Ratio_In;
     SL_Buffer_Points=SL_Buffer_In;TrailingStart_Pts=TrailingStart_In;
     TrailingStep_Pts=TrailingStep_In;BreakEvenAt_Pts=BreakEvenAt_In;
     BreakEvenProfit=BreakEvenProfit_In;ActiveProfile="CUSTOM"; }

   ConfigureMTF();
   ApplyAssetClassScaling();
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   symInfo.Name(_Symbol); symInfo.Refresh();
   ArrayResize(swingHighs,100); ArrayResize(swingLows,100);
   ArrayResize(swingHighBars,100); ArrayResize(swingLowBars,100);

   lastTimeframe=_Period;
   AssetClass = DetectAssetClass();
   AutoConfigure();

   atrHandle = iATR(_Symbol, _Period, ATR_Period);
   if(atrHandle == INVALID_HANDLE)
      Print("WARNING: ATR handle creation failed. ATR-based SL will fallback.");

   EvaluateMTFConfluence();

   Print("ICC EA v3.3 | ",ActiveProfile," | Asset: ",AssetClassLabel,
         " | MTF: ",UseMTF?"ON":"OFF"," | SL: ",EnumToString(SL_Method));

   PrintBrokerDiagnostics();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   ObjectsDeleteAll(0,"ICC_");
   Comment("");
   if(invalidStopCount_BUY>0 || invalidStopCount_SELL>0 ||
      skippedTrades_BUY>0 || skippedTrades_SELL>0)
     {
      Print("═══ TRADE EXECUTION SUMMARY ═══");
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

   if(_Period!=lastTimeframe)
     { lastTimeframe=_Period; ResetState(); AutoConfigure(); EvaluateMTFConfluence(); }

   if(!IsNewBar()) return;
   symInfo.Refresh();
   if(UseSessionFilter && !IsWithinSession()) return;

   EvaluateMTFConfluence();
   DetectSwingPoints();
   DetermineMarketStructure();
   IdentifyICCPhases();
   CheckEntrySignals();

   if(ShowDashboard) UpdateDashboard();
  }

void MonitorSLTP()
  {
   symInfo.Refresh();
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber || posInfo.Symbol()!=_Symbol) continue;
      ulong tk=posInfo.Ticket();
      double op=posInfo.PriceOpen(),sl=posInfo.StopLoss(),tp=posInfo.TakeProfit();
      double pt=symInfo.Point();

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        { double bid=symInfo.Bid();
          if(tp>0 && bid>=tp){ if(trade.PositionClose(tk))
            SendAlertForced("✅ BUY TP HIT | "+_Symbol+" | +"+DoubleToString((bid-op)/pt,0)+" pts"); }
          else if(sl>0 && bid<=sl){ if(trade.PositionClose(tk))
            SendAlertForced("🛑 BUY SL HIT | "+_Symbol+" | -"+DoubleToString((op-bid)/pt,0)+" pts"); } }
      if(posInfo.PositionType()==POSITION_TYPE_SELL)
        { double ask=symInfo.Ask();
          if(tp>0 && ask<=tp){ if(trade.PositionClose(tk))
            SendAlertForced("✅ SELL TP HIT | "+_Symbol+" | +"+DoubleToString((op-ask)/pt,0)+" pts"); }
          else if(sl>0 && ask>=sl){ if(trade.PositionClose(tk))
            SendAlertForced("🛑 SELL SL HIT | "+_Symbol+" | -"+DoubleToString((ask-op)/pt,0)+" pts"); } }
     }
  }

void ResetState()
  { currentTrend=TREND_NONE;currentPhase=PHASE_NONE;previousTrend=TREND_NONE;
    swingHighCount=0;swingLowCount=0;
    indicationHigh=0;indicationLow=0;correctionHigh=0;correctionLow=0;
    lastSwingHigh=0;lastSwingLow=0;prevSwingHigh=0;prevSwingLow=0;
    buySignalFired=false;sellSignalFired=false;lastAlertBar=0;
    lastAlertedBullInd=0; lastAlertedBearInd=0;
    ObjectsDeleteAll(0,"ICC_"); }

void DetectSwingPoints()
  {
   int bars=Bars(_Symbol,_Period);
   if(bars<SwingLookback*2+1) return;
   double highs[],lows[];
   ArrayResize(highs,SwingLookback*2+1);ArrayResize(lows,SwingLookback*2+1);
   int cb=SwingLookback;
   if(CopyHigh(_Symbol,_Period,1,SwingLookback*2+1,highs)<=0) return;
   if(CopyLow(_Symbol,_Period,1,SwingLookback*2+1,lows)<=0) return;

   bool isSH=true;
   for(int i=0;i<SwingLookback*2+1;i++)
     { if(i==cb) continue; if(highs[i]>=highs[cb]){isSH=false;break;} }
   if(isSH && swingHighCount<100)
     if(swingHighCount==0 || swingHighs[swingHighCount-1]!=highs[cb])
       { swingHighs[swingHighCount]=highs[cb];
         swingHighBars[swingHighCount]=cb+1; swingHighCount++;
         prevSwingHigh=lastSwingHigh; lastSwingHigh=highs[cb];
         if(ShowSwingPoints) DrawSwingPoint(true,highs[cb],cb+1); }

   bool isSL=true;
   for(int i=0;i<SwingLookback*2+1;i++)
     { if(i==cb) continue; if(lows[i]<=lows[cb]){isSL=false;break;} }
   if(isSL && swingLowCount<100)
     if(swingLowCount==0 || swingLows[swingLowCount-1]!=lows[cb])
       { swingLows[swingLowCount]=lows[cb];
         swingLowBars[swingLowCount]=cb+1; swingLowCount++;
         prevSwingLow=lastSwingLow; lastSwingLow=lows[cb];
         if(ShowSwingPoints) DrawSwingPoint(false,lows[cb],cb+1); }

   if(swingHighCount>50) TrimSwingArray(swingHighs,swingHighBars,swingHighCount);
   if(swingLowCount>50)  TrimSwingArray(swingLows,swingLowBars,swingLowCount);
  }

void DetermineMarketStructure()
  {
   if(swingHighCount<2||swingLowCount<2) return;
   previousTrend=currentTrend;
   double sh1=swingHighs[swingHighCount-1],sh2=swingHighs[swingHighCount-2];
   double sl1=swingLows[swingLowCount-1],sl2=swingLows[swingLowCount-2];
   if(sh1>sh2 && sl1>sl2)      currentTrend=TREND_BULLISH;
   else if(sl1<sl2 && sh1<sh2) currentTrend=TREND_BEARISH;
  }

void IdentifyICCPhases()
  {
   if(swingHighCount<2||swingLowCount<2) return;
   double close[];
   if(CopyClose(_Symbol,_Period,0,3,close)<3) return;
   double cc=close[2];

   if(currentTrend==TREND_BULLISH)
     {
      double sh1=swingHighs[swingHighCount-1],sh2=swingHighs[swingHighCount-2];
      double sl1=swingLows[swingLowCount-1];
      if(sh1>sh2 && currentPhase!=PHASE_CORRECTION && currentPhase!=PHASE_CONTINUATION)
        { currentPhase=PHASE_INDICATION; indicationHigh=sh1; indicationLow=sl1;
          buySignalFired=false;
          if(!SuppressDuplicateAlerts || sh1!=lastAlertedBullInd)
            { SendAlert("ICC INDICATION (Bull): HH @ "+DoubleToString(sh1,_Digits));
              lastAlertedBullInd=sh1; } }

      if(currentPhase==PHASE_INDICATION && cc<indicationHigh)
        { double ms=indicationHigh-indicationLow;
          double pp=(ms>0)?((indicationHigh-cc)/ms)*100.0:0;
          if(pp>=CorrectionMinPct && pp<=CorrectionMaxPct)
            { currentPhase=PHASE_CORRECTION; correctionLow=cc; correctionHigh=indicationHigh;
              SendAlert("ICC CORRECTION (Bull): "+DoubleToString(pp,1)+"%"); }
          if(currentPhase==PHASE_CORRECTION && cc<correctionLow)
            { double np=((indicationHigh-cc)/ms)*100.0;
              if(np<=CorrectionMaxPct) correctionLow=cc;
              else { currentPhase=PHASE_NONE; SendAlert("ICC INVALIDATED"); } } }

      if(currentPhase==PHASE_CORRECTION)
        { double mid=indicationLow+(indicationHigh-indicationLow)*0.5;
          if(cc>mid && cc>correctionLow && close[2]>close[1])
            currentPhase=PHASE_CONTINUATION; }
     }

   if(currentTrend==TREND_BEARISH)
     {
      double sl1=swingLows[swingLowCount-1],sl2=swingLows[swingLowCount-2];
      double sh1=swingHighs[swingHighCount-1];
      if(sl1<sl2 && currentPhase!=PHASE_CORRECTION && currentPhase!=PHASE_CONTINUATION)
        { currentPhase=PHASE_INDICATION; indicationLow=sl1; indicationHigh=sh1;
          sellSignalFired=false;
          if(!SuppressDuplicateAlerts || sl1!=lastAlertedBearInd)
            { SendAlert("ICC INDICATION (Bear): LL @ "+DoubleToString(sl1,_Digits));
              lastAlertedBearInd=sl1; } }

      if(currentPhase==PHASE_INDICATION && cc>indicationLow)
        { double ms=indicationHigh-indicationLow;
          double pp=(ms>0)?((cc-indicationLow)/ms)*100.0:0;
          if(pp>=CorrectionMinPct && pp<=CorrectionMaxPct)
            { currentPhase=PHASE_CORRECTION; correctionHigh=cc; correctionLow=indicationLow;
              SendAlert("ICC CORRECTION (Bear): "+DoubleToString(pp,1)+"%"); }
          if(currentPhase==PHASE_CORRECTION && cc>correctionHigh)
            { double np=((cc-indicationLow)/ms)*100.0;
              if(np<=CorrectionMaxPct) correctionHigh=cc;
              else { currentPhase=PHASE_NONE; SendAlert("ICC INVALIDATED"); } } }

      if(currentPhase==PHASE_CORRECTION)
        { double mid=indicationLow+(indicationHigh-indicationLow)*0.5;
          if(cc<mid && cc<correctionHigh && close[2]<close[1])
            currentPhase=PHASE_CONTINUATION; }
     }
  }

//+------------------------------------------------------------------+
//| CheckEntrySignals (v3.3 — symbol-aware stops)                    |
//+------------------------------------------------------------------+
void CheckEntrySignals()
  {
   if(currentPhase!=PHASE_CONTINUATION) return;
   int currentBar=Bars(_Symbol,_Period);
   if(currentBar==lastAlertBar) return;
   if(CountOpenTrades()>=MaxOpenTrades) return;

   double ask=symInfo.Ask(),bid=symInfo.Bid();
   double minStop = GetMinStopDistance();

   // BULLISH ENTRY
   if(currentTrend==TREND_BULLISH && !buySignalFired)
     {
      if(UseMTF && !mtfConfluenceBull && !AllowCounterTrend)
        { buySignalFired=true; currentPhase=PHASE_NONE;
          if(HTF_Debug) Print("🚫 BUY blocked | ",mtfStatusMsg);
          return; }

      double structDist = ask - correctionLow;
      if(structDist < 0) structDist = 0;
      double slDist = CalculateSLDistance(structDist);
      double slPrice = NormalizeDouble(ask - slDist, _Digits);

      if(ask - slPrice < minStop * BrokerStopCushion)
        {
         skippedTrades_BUY++;
         if(HTF_Debug)
           Print("⚠ BUY SKIPPED: SL too close. ask=",ask," slPrice=",slPrice,
                 " minStop=",minStop," (skip count=",skippedTrades_BUY,")");
         buySignalFired=true; currentPhase=PHASE_NONE;
         return;
        }

      double slDistFinal = ask - slPrice;
      double tpPrice = NormalizeDouble(ask + slDistFinal * RR_Ratio, _Digits);

      if(UseMTF && mtfConfluenceBull && HTF2.isValid && HTF2.hasData && HTF2.trend==TREND_BULLISH)
         tpPrice = NormalizeDouble(ask + slDistFinal * RR_Ratio * 1.25, _Digits);

      if(tpPrice - ask < minStop * BrokerStopCushion)
        { skippedTrades_BUY++;
          if(HTF_Debug) Print("⚠ BUY SKIPPED: TP too close.");
          buySignalFired=true; currentPhase=PHASE_NONE; return; }

      double lots = CalculateLotSize(slDistFinal);
      if(lots>0)
        {
         string tag = UseMTF ? (HTF2.isValid && HTF2.hasData && HTF2.trend==TREND_BULLISH ?
                                "FULL CONFLUENCE" : "HTF1 ALIGNED") : "MTF OFF";
         if(trade.Buy(lots,_Symbol,ask,slPrice,tpPrice,"ICC Buy "+ActiveProfile))
           { string msg=StringFormat("🟢 BUY | %s | %s\nE:%s SL:%s TP:%s | RR:%.2f | %s",
               _Symbol,ActiveProfile,
               DoubleToString(ask,_Digits),DoubleToString(slPrice,_Digits),
               DoubleToString(tpPrice,_Digits),
               (tpPrice-ask)/(ask-slPrice), tag);
             SendAlertForced(msg);
             buySignalFired=true; lastAlertBar=currentBar; currentPhase=PHASE_NONE; }
         else
           { invalidStopCount_BUY++;
             Print("BUY FAILED [retcode ",trade.ResultRetcode(),"]: ",
                   trade.ResultRetcodeDescription(),
                   " | ask=",ask," SL=",slPrice," TP=",tpPrice,
                   " | dist SL=",DoubleToString(ask-slPrice,_Digits),
                   " minStop=",DoubleToString(minStop,_Digits)); }
        }
     }

   // BEARISH ENTRY
   if(currentTrend==TREND_BEARISH && !sellSignalFired)
     {
      if(UseMTF && !mtfConfluenceBear && !AllowCounterTrend)
        { sellSignalFired=true; currentPhase=PHASE_NONE;
          if(HTF_Debug) Print("🚫 SELL blocked | ",mtfStatusMsg);
          return; }

      double structDist = correctionHigh - bid;
      if(structDist < 0) structDist = 0;
      double slDist = CalculateSLDistance(structDist);
      double slPrice = NormalizeDouble(bid + slDist, _Digits);

      if(slPrice - bid < minStop * BrokerStopCushion)
        {
         skippedTrades_SELL++;
         if(HTF_Debug)
           Print("⚠ SELL SKIPPED: SL too close. bid=",bid," slPrice=",slPrice,
                 " minStop=",minStop," (skip count=",skippedTrades_SELL,")");
         sellSignalFired=true; currentPhase=PHASE_NONE;
         return;
        }

      double slDistFinal = slPrice - bid;
      double tpPrice = NormalizeDouble(bid - slDistFinal * RR_Ratio, _Digits);

      if(UseMTF && mtfConfluenceBear && HTF2.isValid && HTF2.hasData && HTF2.trend==TREND_BEARISH)
         tpPrice = NormalizeDouble(bid - slDistFinal * RR_Ratio * 1.25, _Digits);

      if(bid - tpPrice < minStop * BrokerStopCushion)
        { skippedTrades_SELL++;
          if(HTF_Debug) Print("⚠ SELL SKIPPED: TP too close.");
          sellSignalFired=true; currentPhase=PHASE_NONE; return; }

      double lots = CalculateLotSize(slDistFinal);
      if(lots>0)
        {
         string tag = UseMTF ? (HTF2.isValid && HTF2.hasData && HTF2.trend==TREND_BEARISH ?
                                "FULL CONFLUENCE" : "HTF1 ALIGNED") : "MTF OFF";
         if(trade.Sell(lots,_Symbol,bid,slPrice,tpPrice,"ICC Sell "+ActiveProfile))
           { string msg=StringFormat("🔴 SELL | %s | %s\nE:%s SL:%s TP:%s | RR:%.2f | %s",
               _Symbol,ActiveProfile,
               DoubleToString(bid,_Digits),DoubleToString(slPrice,_Digits),
               DoubleToString(tpPrice,_Digits),
               (bid-tpPrice)/(slPrice-bid), tag);
             SendAlertForced(msg);
             sellSignalFired=true; lastAlertBar=currentBar; currentPhase=PHASE_NONE; }
         else
           { invalidStopCount_SELL++;
             Print("SELL FAILED [retcode ",trade.ResultRetcode(),"]: ",
                   trade.ResultRetcodeDescription(),
                   " | bid=",bid," SL=",slPrice," TP=",tpPrice,
                   " | dist SL=",DoubleToString(slPrice-bid,_Digits),
                   " minStop=",DoubleToString(minStop,_Digits)); }
        }
     }
  }

void ManagePositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(),sl=posInfo.StopLoss(),tp=posInfo.TakeProfit();
      double pt=symInfo.Point(); ulong tk=posInfo.Ticket();
      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        { double bid=symInfo.Bid(),pp=(bid-op)/pt;
          if(UseBreakEven && pp>=BreakEvenAt_Pts)
            { double ns=op+BreakEvenProfit*pt; if(sl<ns) trade.PositionModify(tk,ns,tp); }
          if(UseTrailingStop && pp>=TrailingStart_Pts)
            { double ts=bid-TrailingStep_Pts*pt; if(ts>sl) trade.PositionModify(tk,ts,tp); } }
      if(posInfo.PositionType()==POSITION_TYPE_SELL)
        { double ask=symInfo.Ask(),pp=(op-ask)/pt;
          if(UseBreakEven && pp>=BreakEvenAt_Pts)
            { double ns=op-BreakEvenProfit*pt; if(sl>ns||sl==0) trade.PositionModify(tk,ns,tp); }
          if(UseTrailingStop && pp>=TrailingStart_Pts)
            { double ts=ask+TrailingStep_Pts*pt; if(ts<sl||sl==0) trade.PositionModify(tk,ts,tp); } }
     }
  }

double CalculateLotSize(double sd)
  { if(FixedLots>0) return NormalizeLots(FixedLots);
    if(sd<=0) return 0;
    double bal=AccountInfoDouble(ACCOUNT_BALANCE);
    double risk=bal*RiskPercent/100.0;
    double tv=symInfo.TickValue(),ts=symInfo.TickSize();
    if(tv<=0||ts<=0) return symInfo.LotsMin();
    return NormalizeLots(risk/((sd/ts)*tv)); }

double NormalizeLots(double l)
  { double mn=symInfo.LotsMin(),mx=symInfo.LotsMax(),st=symInfo.LotsStep();
    l=MathMax(l,mn);l=MathMin(l,mx);l=MathFloor(l/st)*st;
    return NormalizeDouble(l,2); }

int CountOpenTrades()
  { int c=0;for(int i=PositionsTotal()-1;i>=0;i--)
      if(posInfo.SelectByIndex(i))
        if(posInfo.Magic()==MagicNumber && posInfo.Symbol()==_Symbol) c++;
    return c; }

bool IsNewBar()
  { static datetime lt=0; datetime ct=iTime(_Symbol,_Period,0);
    if(ct!=lt){lt=ct;return true;} return false; }

bool IsWithinSession()
  { MqlDateTime dt;TimeCurrent(dt);
    if(SessionStartHour<SessionEndHour)
      return(dt.hour>=SessionStartHour && dt.hour<SessionEndHour);
    return(dt.hour>=SessionStartHour || dt.hour<SessionEndHour); }

void SendAlert(string m)
  { if(TimeCurrent()-lastAlertTime<60) return;
    DispatchAlert(m); lastAlertTime=TimeCurrent(); }

void SendAlertForced(string m)
  { DispatchAlert(m); lastAlertTime=TimeCurrent(); }

void DispatchAlert(string m)
  { Print("ICC: ",m);
    if(AlertPopup) Alert(m);
    if(AlertPush) SendNotification(m);
    if(AlertEmail) SendMail("ICC - "+_Symbol,m);
    if(AlertSound) PlaySound(AlertSoundFile); }

void DrawSwingPoint(bool isH,double price,int shift)
  { datetime t=iTime(_Symbol,_Period,shift);
    string n="ICC_SW_"+(isH?"H_":"L_")+TimeToString(t);
    ObjectDelete(0,n);ObjectCreate(0,n,OBJ_ARROW,0,t,price);
    ObjectSetInteger(0,n,OBJPROP_ARROWCODE,isH?234:233);
    ObjectSetInteger(0,n,OBJPROP_COLOR,isH?BearColor:BullColor);
    ObjectSetInteger(0,n,OBJPROP_WIDTH,2); }

void TrimSwingArray(double &a[],int &b[],int &c)
  { int k=25; for(int i=0;i<k;i++){a[i]=a[c-k+i];b[i]=b[c-k+i];} c=k; }

void UpdateDashboard()
  {
   string tStr=currentTrend==TREND_BULLISH?"BULLISH ▲":currentTrend==TREND_BEARISH?"BEARISH ▼":"NONE";
   string pStr="Scanning...";
   if(currentPhase==PHASE_INDICATION) pStr="1. INDICATION";
   if(currentPhase==PHASE_CORRECTION) pStr="2. CORRECTION";
   if(currentPhase==PHASE_CONTINUATION) pStr="3. CONTINUATION";
   string mB=mtfConfluenceBull?"YES":"NO", mE=mtfConfluenceBear?"YES":"NO";
   string q="---";
   if(currentTrend==TREND_BULLISH && mtfConfluenceBull)
      q=(HTF2.isValid&&HTF2.hasData&&HTF2.trend==TREND_BULLISH)?"A+ FULL":"A HTF1";
   else if(currentTrend==TREND_BEARISH && mtfConfluenceBear)
      q=(HTF2.isValid&&HTF2.hasData&&HTF2.trend==TREND_BEARISH)?"A+ FULL":"A HTF1";
   else if(currentTrend!=TREND_NONE) q="B/C NO CONF";

   string d="╔═══ ICC EA v3.3 ═══════════════════════╗\n";
   d+="║ Profile: "+ActiveProfile+" | "+AssetClassLabel+"\n";
   d+="║ Trend:   "+tStr+"\n";
   d+="║ Phase:   "+pStr+"\n";
   d+="╠═══ MTF ════════════════════════════════╣\n";
   if(UseMTF)
     { d+="║ HTF1: "+HTF1.trendLabel+" ["+HTF1.methodUsed+"]\n";
       if(HTF2.isValid) d+="║ HTF2: "+HTF2.trendLabel+" ["+HTF2.methodUsed+"]\n";
       d+="║ Bull:"+mB+" | Bear:"+mE+" | "+q+"\n"; }
   else d+="║ MTF: DISABLED\n";
   d+="╠═══ STOPS ══════════════════════════════╣\n";
   d+="║ Method: "+EnumToString(SL_Method)+"\n";
   d+="║ MinStop: "+DoubleToString(GetMinStopDistance(),_Digits)+"\n";
   d+="║ Trades: "+IntegerToString(CountOpenTrades())+"/"+IntegerToString(MaxOpenTrades)+"\n";
   if(skippedTrades_BUY>0||skippedTrades_SELL>0)
     d+="║ Skipped: B"+IntegerToString(skippedTrades_BUY)+
       " S"+IntegerToString(skippedTrades_SELL)+"\n";
   d+="╚════════════════════════════════════════╝";
   Comment(d);
  }
//+------------------------------------------------------------------+
