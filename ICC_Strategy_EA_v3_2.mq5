//+------------------------------------------------------------------+
//|                                       ICC_Strategy_EA_v3_2.mq5  |
//|       ICC v3.2 — Backtest log issues fixed                      |
//+------------------------------------------------------------------+
#property copyright "ICC Strategy EA v3.2"
#property version   "3.20"
#property description "v3.2 fixes: Adaptive HTF data thresholds, HTF2-neutral fallback,"
#property description "duplicate-alert suppression, swing-level memory across phases."

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
  {
   HTF2_BLOCK   = 0,  // Block trades when HTF2 has no data (v3.1 behavior)
   HTF2_NEUTRAL = 1,  // Treat HTF2 no-data as NEUTRAL (don't block, don't boost)
   HTF2_DOWNGRADE = 2 // Auto-downgrade HTF2 to next available TF (recommended)
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== Multi-Timeframe Confluence ==="
input bool             UseMTF            = true;
input ENUM_MTF_MODE    MTF_Mode          = MTF_AUTO;
input ENUM_TIMEFRAMES  ManualHTF1        = PERIOD_H4;
input ENUM_TIMEFRAMES  ManualHTF2        = PERIOD_D1;
input bool             RequireBothHTF    = false;
input ENUM_HTF_METHOD  HTF_Method        = HTF_COMBINED;
input ENUM_HTF2_FALLBACK HTF2_Fallback   = HTF2_NEUTRAL;  // NEW: HTF2 no-data handling
input int              HTF_SwingLookback = 5;
input bool             AllowCounterTrend = false;
input int              HTF_CheckBars     = 200;
input int              HTF_EMA_Fast      = 21;
input int              HTF_EMA_Slow      = 50;
input int              HTF_MinBarsRequired = 30;          // NEW: lowered from 60
input bool             HTF_AdaptiveEMA    = true;          // NEW: shorter EMA when data limited
input bool             HTF_Debug         = false;          // CHANGED: default false to reduce spam
input int              HTF_DebugInterval = 200;            // NEW: print debug every N bars

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
input bool   AlertPopup     = false;   // CHANGED: default false in tester
input bool   AlertPush      = false;
input bool   AlertEmail     = false;
input bool   AlertSound     = false;
input string AlertSoundFile = "alert.wav";
input bool   SuppressDuplicateAlerts = true;  // NEW: don't re-fire same indication

input group "=== Visual Settings ==="
input bool  ShowSwingPoints = true;
input bool  ShowPhaseLabels = true;
input bool  ShowDashboard   = true;
input bool  ShowHTFZones    = false;  // CHANGED: off by default to reduce backtest clutter
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
   bool            hasData;       // NEW: true if HTF returned valid data
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

// NEW: track last alerted indication levels to prevent duplicate spam
double lastAlertedBullInd = 0;
double lastAlertedBearInd = 0;

bool   buySignalFired=false, sellSignalFired=false;
datetime lastAlertTime=0;
int    lastAlertBar=0;

ENUM_TIMEFRAMES lastTimeframe = PERIOD_CURRENT;
int    htfDebugCounter = 0;

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

// NEW: TF one step lower than the given TF (for HTF2 downgrade)
ENUM_TIMEFRAMES DowngradeTF(ENUM_TIMEFRAMES tf)
  { if(tf==PERIOD_MN1) return PERIOD_W1;
    if(tf==PERIOD_W1)  return PERIOD_D1;
    if(tf==PERIOD_D1)  return PERIOD_H4;
    if(tf==PERIOD_H4)  return PERIOD_H1;
    if(tf==PERIOD_H1)  return PERIOD_M30;
    return tf; }

//+------------------------------------------------------------------+
//| Configure MTF                                                    |
//+------------------------------------------------------------------+
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

   Print("═══ MTF CONFIG ═══ HTF1: ",EnumToString(HTF1.timeframe),
         " | HTF2: ",EnumToString(HTF2.timeframe),
         " | Method: ",EnumToString(HTF_Method),
         " | HTF2 Fallback: ",EnumToString(HTF2_Fallback));
  }

//+------------------------------------------------------------------+
//| Analyze HTF (with v3.2 fixes)                                    |
//+------------------------------------------------------------------+
void AnalyzeHTF(SMTFData &htf)
  {
   if(!htf.isValid) return;

   htf.trend      = TREND_NONE;
   htf.trendLabel = "NONE";
   htf.methodUsed = "---";
   htf.hasData    = false;

   int bars = Bars(_Symbol, htf.timeframe);

   //--- ADAPTIVE thresholds (v3.2) ---
   int minBars      = HTF_MinBarsRequired;          // Default 30 (down from 60)
   int emaFastUsed  = HTF_EMA_Fast;
   int emaSlowUsed  = HTF_EMA_Slow;

   // If adaptive EMA enabled and data is limited, switch to shorter EMAs
   if(HTF_AdaptiveEMA && bars < HTF_EMA_Slow + 5)
     { emaFastUsed = 8;  emaSlowUsed = 21; }

   if(bars < minBars)
     {
      htf.trendLabel = "NO DATA (" + IntegerToString(bars) + " bars)";
      htf.methodUsed = "INSUFFICIENT";
      return;
     }

   //--- EMA Calculation ---
   double emaFastArr[], emaSlowArr[];
   ArraySetAsSeries(emaFastArr,true);
   ArraySetAsSeries(emaSlowArr,true);

   int hFast = iMA(_Symbol, htf.timeframe, emaFastUsed, 0, MODE_EMA, PRICE_CLOSE);
   int hSlow = iMA(_Symbol, htf.timeframe, emaSlowUsed, 0, MODE_EMA, PRICE_CLOSE);
   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE)
     { htf.trendLabel="EMA HANDLE FAIL"; htf.methodUsed="ERROR"; return; }

   int cf = CopyBuffer(hFast,0,0,3,emaFastArr);
   int cs = CopyBuffer(hSlow,0,0,3,emaSlowArr);
   IndicatorRelease(hFast); IndicatorRelease(hSlow);

   if(cf<3 || cs<3)
     { htf.trendLabel="EMA COPY FAIL"; htf.methodUsed="ERROR"; return; }

   htf.emaFast = emaFastArr[0];
   htf.emaSlow = emaSlowArr[0];
   htf.hasData = true;

   bool emaBull = emaFastArr[0] > emaSlowArr[0];
   bool emaBear = emaFastArr[0] < emaSlowArr[0];
   bool emaRising  = emaFastArr[0] > emaFastArr[1];
   bool emaFalling = emaFastArr[0] < emaFastArr[1];

   //--- EMA-only mode ---
   if(HTF_Method == HTF_EMA_ONLY)
     {
      if(emaBull) { htf.trend=TREND_BULLISH; htf.trendLabel="BULLISH ▲ (EMA)"; }
      else if(emaBear){ htf.trend=TREND_BEARISH; htf.trendLabel="BEARISH ▼ (EMA)"; }
      else { htf.trendLabel="FLAT (EMA)"; }
      htf.methodUsed = StringFormat("EMA(%d/%d)", emaFastUsed, emaSlowUsed);
      return;
     }

   //--- Swing structure (only if enough bars) ---
   bool swingFound = false;
   ENUM_TREND swingTrend = TREND_NONE;

   if(bars >= HTF_SwingLookback*2+10)
     {
      double H[], L[];
      ArraySetAsSeries(H,true); ArraySetAsSeries(L,true);
      int copyLen = MathMin(HTF_CheckBars, bars-1);
      int cH=CopyHigh(_Symbol,htf.timeframe,0,copyLen,H);
      int cL=CopyLow(_Symbol,htf.timeframe,0,copyLen,L);

      if(cH>=HTF_SwingLookback*2+5 && cL>=HTF_SwingLookback*2+5)
        {
         double shArr[], slArr[];
         ArrayResize(shArr,0); ArrayResize(slArr,0);
         int lb = HTF_SwingLookback;
         int scanEnd = cH-lb;

         for(int b=lb; b<scanEnd && ArraySize(shArr)<4; b++)
           { bool isSH=true;
             for(int k=1;k<=lb;k++)
               if(H[b-k]>=H[b]||H[b+k]>=H[b]){isSH=false;break;}
             if(isSH){ int sz=ArraySize(shArr); ArrayResize(shArr,sz+1); shArr[sz]=H[b]; } }

         for(int b=lb; b<scanEnd && ArraySize(slArr)<4; b++)
           { bool isSL=true;
             for(int k=1;k<=lb;k++)
               if(L[b-k]<=L[b]||L[b+k]<=L[b]){isSL=false;break;}
             if(isSL){ int sz=ArraySize(slArr); ArrayResize(slArr,sz+1); slArr[sz]=L[b]; } }

         if(ArraySize(shArr)>=2 && ArraySize(slArr)>=2)
           {
            htf.swingHigh     = shArr[0]; htf.prevSwingHigh = shArr[1];
            htf.swingLow      = slArr[0]; htf.prevSwingLow  = slArr[1];
            bool hh=htf.swingHigh>htf.prevSwingHigh;
            bool hl=htf.swingLow>htf.prevSwingLow;
            bool ll=htf.swingLow<htf.prevSwingLow;
            bool lh=htf.swingHigh<htf.prevSwingHigh;
            if(hh&&hl){ swingTrend=TREND_BULLISH; swingFound=true; }
            else if(ll&&lh){ swingTrend=TREND_BEARISH; swingFound=true; }
            else if(hh){ swingTrend=TREND_BULLISH; swingFound=true; }
            else if(ll){ swingTrend=TREND_BEARISH; swingFound=true; }
           }
        }
     }

   //--- Decide final trend ---
   if(HTF_Method == HTF_SWING_ONLY)
     {
      if(swingFound)
        { htf.trend=swingTrend;
          htf.trendLabel=(swingTrend==TREND_BULLISH?"BULLISH ▲":"BEARISH ▼")+" (Swing)";
          htf.methodUsed="SWING"; }
      else { htf.trendLabel="FORMING"; htf.methodUsed="SWING-NONE"; }
     }
   else // COMBINED
     {
      if(swingFound)
        { htf.trend=swingTrend;
          htf.trendLabel=(swingTrend==TREND_BULLISH?"BULLISH ▲":"BEARISH ▼")+" (Swing)";
          htf.methodUsed="SWING";
          if((swingTrend==TREND_BULLISH&&emaBull)||(swingTrend==TREND_BEARISH&&emaBear))
            { htf.trendLabel+="+EMA"; htf.methodUsed="SWING+EMA"; } }
      else
        { // EMA fallback
          if(emaBull && emaRising){ htf.trend=TREND_BULLISH; htf.trendLabel="BULLISH ▲ (EMA↑)"; }
          else if(emaBull){ htf.trend=TREND_BULLISH; htf.trendLabel="BULLISH ▲ (EMA)"; }
          else if(emaBear && emaFalling){ htf.trend=TREND_BEARISH; htf.trendLabel="BEARISH ▼ (EMA↓)"; }
          else if(emaBear){ htf.trend=TREND_BEARISH; htf.trendLabel="BEARISH ▼ (EMA)"; }
          else htf.trendLabel="FLAT (EMA)";
          htf.methodUsed = StringFormat("EMA-FB(%d/%d)", emaFastUsed, emaSlowUsed); }
     }
  }

//+------------------------------------------------------------------+
//| Evaluate MTF Confluence (with v3.2 fixes)                        |
//+------------------------------------------------------------------+
void EvaluateMTFConfluence()
  {
   if(!UseMTF)
     { mtfConfluenceBull=true; mtfConfluenceBear=true;
       mtfStatusMsg="MTF DISABLED"; return; }

   AnalyzeHTF(HTF1);
   if(HTF2.isValid) AnalyzeHTF(HTF2);

   //--- HTF2 No-data fallback (v3.2 NEW) ---
   if(HTF2.isValid && !HTF2.hasData)
     {
      if(HTF2_Fallback == HTF2_DOWNGRADE)
        {
         ENUM_TIMEFRAMES alt = DowngradeTF(HTF2.timeframe);
         if(alt > _Period && alt != HTF2.timeframe)
           {
            ENUM_TIMEFRAMES original = HTF2.timeframe;
            HTF2.timeframe = alt;
            AnalyzeHTF(HTF2);
            if(HTF2.hasData)
              { htfDebugCounter=0;  // Force a debug print
                if(HTF_Debug)
                  Print("HTF2 DOWNGRADE: ", EnumToString(original),
                        " → ", EnumToString(alt), " due to insufficient data"); }
           }
        }
      // For HTF2_NEUTRAL or HTF2_BLOCK: handled below
     }

   bool htf1Bull = (HTF1.trend == TREND_BULLISH);
   bool htf1Bear = (HTF1.trend == TREND_BEARISH);

   //--- HTF2 contribution depends on data availability + fallback mode ---
   bool htf2Bull, htf2Bear;
   if(!HTF2.isValid)
     { htf2Bull=true; htf2Bear=true; }
   else if(!HTF2.hasData)
     {
      // No data — depends on fallback mode
      if(HTF2_Fallback == HTF2_NEUTRAL || HTF2_Fallback == HTF2_DOWNGRADE)
        { htf2Bull=true; htf2Bear=true; }   // Treat as neutral
      else // HTF2_BLOCK
        { htf2Bull=false; htf2Bear=false; }
     }
   else
     { htf2Bull = (HTF2.trend==TREND_BULLISH);
       htf2Bear = (HTF2.trend==TREND_BEARISH); }

   if(RequireBothHTF && HTF2.isValid && HTF2.hasData)
     { mtfConfluenceBull = htf1Bull && htf2Bull;
       mtfConfluenceBear = htf1Bear && htf2Bear; }
   else
     { mtfConfluenceBull = htf1Bull;
       mtfConfluenceBear = htf1Bear; }

   mtfStatusMsg = "HTF1("+EnumToString(HTF1.timeframe)+"): "+HTF1.trendLabel;
   if(HTF2.isValid)
      mtfStatusMsg += " | HTF2("+EnumToString(HTF2.timeframe)+"): "+HTF2.trendLabel;

   // Throttled debug print
   if(HTF_Debug && htfDebugCounter % HTF_DebugInterval == 0)
     {
      Print("═══ MTF ═══ HTF1: ",HTF1.trendLabel," [",HTF1.methodUsed,"] | ",
            "HTF2: ",HTF2.trendLabel," [",HTF2.methodUsed,"] | ",
            "Bull: ",mtfConfluenceBull?"YES":"NO",
            " | Bear: ",mtfConfluenceBear?"YES":"NO");
     }
   htfDebugCounter++;
  }

//+------------------------------------------------------------------+
//| Auto-Configure                                                   |
//+------------------------------------------------------------------+
void AutoConfigure()
  {
   ENUM_TIMEFRAMES tf=_Period;
   if(!AutoSettings)
     { SwingLookback=SwingLookback_In;CorrectionMinPct=CorrMinPct_In;
       CorrectionMaxPct=CorrMaxPct_In;RR_Ratio=RR_Ratio_In;
       SL_Buffer_Points=SL_Buffer_In;TrailingStart_Pts=TrailingStart_In;
       TrailingStep_Pts=TrailingStep_In;BreakEvenAt_Pts=BreakEvenAt_In;
       BreakEvenProfit=BreakEvenProfit_In;ActiveProfile="MANUAL";
       ConfigureMTF(); return; }

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
  }

//+------------------------------------------------------------------+
//| OnInit / OnDeinit                                                |
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
   AutoConfigure();
   EvaluateMTFConfluence();
   Print("ICC EA v3.2 | ",ActiveProfile," | MTF: ",UseMTF?"ON":"OFF",
         " | HTF2 Fallback: ",EnumToString(HTF2_Fallback));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  { ObjectsDeleteAll(0,"ICC_"); Comment(""); }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| MonitorSLTP                                                      |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| ICC Phase Detection (v3.2 — duplicate alert suppression)         |
//+------------------------------------------------------------------+
void IdentifyICCPhases()
  {
   if(swingHighCount<2||swingLowCount<2) return;
   double close[];
   if(CopyClose(_Symbol,_Period,0,3,close)<3) return;
   double cc=close[2];

   //--- BULLISH ICC ---
   if(currentTrend==TREND_BULLISH)
     {
      double sh1=swingHighs[swingHighCount-1],sh2=swingHighs[swingHighCount-2];
      double sl1=swingLows[swingLowCount-1];

      if(sh1>sh2 && currentPhase!=PHASE_CORRECTION && currentPhase!=PHASE_CONTINUATION)
        {
         currentPhase=PHASE_INDICATION; indicationHigh=sh1; indicationLow=sl1;
         buySignalFired=false;
         // v3.2: only alert if this is a NEW swing high level
         if(!SuppressDuplicateAlerts || sh1!=lastAlertedBullInd)
           { SendAlert("ICC INDICATION (Bull): HH @ "+DoubleToString(sh1,_Digits));
             lastAlertedBullInd = sh1; }
        }

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

   //--- BEARISH ICC ---
   if(currentTrend==TREND_BEARISH)
     {
      double sl1=swingLows[swingLowCount-1],sl2=swingLows[swingLowCount-2];
      double sh1=swingHighs[swingHighCount-1];

      if(sl1<sl2 && currentPhase!=PHASE_CORRECTION && currentPhase!=PHASE_CONTINUATION)
        {
         currentPhase=PHASE_INDICATION; indicationLow=sl1; indicationHigh=sh1;
         sellSignalFired=false;
         // v3.2: only alert if this is a NEW swing low level
         if(!SuppressDuplicateAlerts || sl1!=lastAlertedBearInd)
           { SendAlert("ICC INDICATION (Bear): LL @ "+DoubleToString(sl1,_Digits));
             lastAlertedBearInd = sl1; }
        }

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
//| Check Entry Signals (v3.2 — improved block handling)             |
//+------------------------------------------------------------------+
void CheckEntrySignals()
  {
   if(currentPhase!=PHASE_CONTINUATION) return;
   int currentBar=Bars(_Symbol,_Period);
   if(currentBar==lastAlertBar) return;
   if(CountOpenTrades()>=MaxOpenTrades) return;

   double ask=symInfo.Ask(),bid=symInfo.Bid(),pt=symInfo.Point();

   //--- BULLISH ENTRY ---
   if(currentTrend==TREND_BULLISH && !buySignalFired)
     {
      if(UseMTF && !mtfConfluenceBull && !AllowCounterTrend)
        { // v3.2: silent block — don't alert; just reset phase & mark
          buySignalFired=true; currentPhase=PHASE_NONE;
          if(HTF_Debug) Print("🚫 BUY blocked | ",mtfStatusMsg);
          return; }

      double slPrice=correctionLow-SL_Buffer_Points*pt;
      double slDist=ask-slPrice;
      double tpPrice=ask+slDist*RR_Ratio;
      if(UseMTF && mtfConfluenceBull && HTF2.isValid && HTF2.hasData && HTF2.trend==TREND_BULLISH)
         tpPrice=ask+slDist*RR_Ratio*1.25;
      double lots=CalculateLotSize(slDist);
      if(lots>0)
        {
         string tag = UseMTF ? (HTF2.isValid && HTF2.hasData && HTF2.trend==TREND_BULLISH ?
                                "FULL CONFLUENCE" : "HTF1 ALIGNED") : "MTF OFF";
         if(trade.Buy(lots,_Symbol,ask,slPrice,tpPrice,"ICC Buy "+ActiveProfile))
           { string msg=StringFormat("🟢 BUY | %s | %s\nE:%s SL:%s TP:%s | %s",
               _Symbol,ActiveProfile,
               DoubleToString(ask,_Digits),DoubleToString(slPrice,_Digits),
               DoubleToString(tpPrice,_Digits),tag);
             SendAlertForced(msg);
             buySignalFired=true; lastAlertBar=currentBar; currentPhase=PHASE_NONE; }
        }
     }

   //--- BEARISH ENTRY ---
   if(currentTrend==TREND_BEARISH && !sellSignalFired)
     {
      if(UseMTF && !mtfConfluenceBear && !AllowCounterTrend)
        { sellSignalFired=true; currentPhase=PHASE_NONE;
          if(HTF_Debug) Print("🚫 SELL blocked | ",mtfStatusMsg);
          return; }

      double slPrice=correctionHigh+SL_Buffer_Points*pt;
      double slDist=slPrice-bid;
      double tpPrice=bid-slDist*RR_Ratio;
      if(UseMTF && mtfConfluenceBear && HTF2.isValid && HTF2.hasData && HTF2.trend==TREND_BEARISH)
         tpPrice=bid-slDist*RR_Ratio*1.25;
      double lots=CalculateLotSize(slDist);
      if(lots>0)
        {
         string tag = UseMTF ? (HTF2.isValid && HTF2.hasData && HTF2.trend==TREND_BEARISH ?
                                "FULL CONFLUENCE" : "HTF1 ALIGNED") : "MTF OFF";
         if(trade.Sell(lots,_Symbol,bid,slPrice,tpPrice,"ICC Sell "+ActiveProfile))
           { string msg=StringFormat("🔴 SELL | %s | %s\nE:%s SL:%s TP:%s | %s",
               _Symbol,ActiveProfile,
               DoubleToString(bid,_Digits),DoubleToString(slPrice,_Digits),
               DoubleToString(tpPrice,_Digits),tag);
             SendAlertForced(msg);
             sellSignalFired=true; lastAlertBar=currentBar; currentPhase=PHASE_NONE; }
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

//+------------------------------------------------------------------+
//| Utilities                                                        |
//+------------------------------------------------------------------+
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

   string d="╔═══ ICC EA v3.2 ═══════════════════════╗\n";
   d+="║ Profile: "+ActiveProfile+"\n";
   d+="║ Trend:   "+tStr+"\n";
   d+="║ Phase:   "+pStr+"\n";
   d+="╠═══ MTF ════════════════════════════════╣\n";
   if(UseMTF)
     { d+="║ HTF1: "+HTF1.trendLabel+" ["+HTF1.methodUsed+"]\n";
       if(HTF2.isValid) d+="║ HTF2: "+HTF2.trendLabel+" ["+HTF2.methodUsed+"]\n";
       d+="║ Bull:"+mB+" | Bear:"+mE+" | "+q+"\n"; }
   else d+="║ MTF: DISABLED\n";
   d+="╠═══ STATS ══════════════════════════════╣\n";
   d+="║ Trades: "+IntegerToString(CountOpenTrades())+"/"+IntegerToString(MaxOpenTrades)+"\n";
   d+="╚════════════════════════════════════════╝";
   Comment(d);
  }
//+------------------------------------------------------------------+
