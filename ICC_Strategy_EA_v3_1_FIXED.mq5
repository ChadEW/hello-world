//+------------------------------------------------------------------+
//|                                           ICC_Strategy_EA_v3.mq5 |
//|            ICC - Indication, Correction, Continuation v3.1       |
//|  FIXED: HTF confluence now works in Strategy Tester backtesting  |
//+------------------------------------------------------------------+
#property copyright   "ICC Strategy EA v3.1"
#property link        ""
#property version     "3.10"
#property description "ICC v3.1 — MTF Confluence (Backtest-Fixed)"
#property description "Fixed: HTF analysis works in Strategy Tester"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_ICC_PHASE
  {
   PHASE_NONE        = 0,
   PHASE_INDICATION  = 1,
   PHASE_CORRECTION  = 2,
   PHASE_CONTINUATION= 3
  };

enum ENUM_TREND
  {
   TREND_NONE    = 0,
   TREND_BULLISH = 1,
   TREND_BEARISH = 2
  };

enum ENUM_MTF_MODE
  {
   MTF_AUTO      = 0,
   MTF_DUAL      = 1,
   MTF_MANUAL    = 2
  };

enum ENUM_HTF_METHOD
  {
   HTF_SWING_ONLY  = 0,  // Swing structure only
   HTF_EMA_ONLY    = 1,  // EMA crossover only
   HTF_COMBINED    = 2,  // Swing + EMA fallback (recommended)
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== Multi-Timeframe Confluence ==="
input bool           UseMTF            = true;
input ENUM_MTF_MODE  MTF_Mode          = MTF_AUTO;
input ENUM_TIMEFRAMES ManualHTF1       = PERIOD_H4;
input ENUM_TIMEFRAMES ManualHTF2       = PERIOD_D1;
input bool           RequireBothHTF    = false;
input ENUM_HTF_METHOD HTF_Method       = HTF_COMBINED;  // HTF trend detection method
input int            HTF_SwingLookback = 5;             // HTF swing lookback (reduced from 7)
input bool           AllowCounterTrend = false;
input int            HTF_CheckBars     = 200;           // HTF bars to analyze (increased from 100)
input int            HTF_EMA_Fast      = 21;            // HTF fast EMA period
input int            HTF_EMA_Slow      = 50;            // HTF slow EMA period
input bool           HTF_Debug         = true;          // Print HTF debug info to Journal

input group "=== Auto-Timeframe Settings ==="
input bool     AutoSettings       = true;

input group "=== ICC Structure (manual overrides if AutoSettings=false) ==="
input int      SwingLookback_In   = 5;
input double   CorrMinPct_In      = 30.0;
input double   CorrMaxPct_In      = 79.0;
input double   RR_Ratio_In        = 2.0;
input int      SL_Buffer_In       = 50;

input group "=== Trade Management ==="
input double   RiskPercent        = 1.0;
input double   FixedLots          = 0.0;
input int      MaxOpenTrades      = 1;

input group "=== Trailing Stop ==="
input bool     UseTrailingStop    = true;
input int      TrailingStart_In   = 200;
input int      TrailingStep_In    = 100;

input group "=== Break Even ==="
input bool     UseBreakEven       = true;
input int      BreakEvenAt_In     = 150;
input int      BreakEvenProfit_In = 10;

input group "=== Session Filter ==="
input bool     UseSessionFilter   = false;
input int      SessionStartHour   = 2;
input int      SessionEndHour     = 17;

input group "=== Alert Settings ==="
input bool     AlertPopup         = true;
input bool     AlertPush          = true;
input bool     AlertEmail         = false;
input bool     AlertSound         = true;
input string   AlertSoundFile     = "alert.wav";

input group "=== Visual Settings ==="
input bool     ShowSwingPoints    = true;
input bool     ShowPhaseLabels    = true;
input bool     ShowDashboard      = true;
input bool     ShowHTFZones       = true;
input color    BullColor          = clrDodgerBlue;
input color    BearColor          = clrOrangeRed;
input color    CorrColor          = clrGold;
input color    HTF_BullZone       = clrMediumSeaGreen;
input color    HTF_BearZone       = clrCrimson;

input group "=== EA Settings ==="
input int      MagicNumber        = 20260612;

//+------------------------------------------------------------------+
//| ACTIVE RUNTIME SETTINGS                                          |
//+------------------------------------------------------------------+
int      SwingLookback;
double   CorrectionMinPct;
double   CorrectionMaxPct;
double   RR_Ratio;
int      SL_Buffer_Points;
int      TrailingStart_Pts;
int      TrailingStep_Pts;
int      BreakEvenAt_Pts;
int      BreakEvenProfit;
string   ActiveProfile;

//+------------------------------------------------------------------+
//| MTF CONFLUENCE DATA                                              |
//+------------------------------------------------------------------+
struct SMTFData
  {
   ENUM_TIMEFRAMES   timeframe;
   ENUM_TREND        trend;
   double            swingHigh;
   double            swingLow;
   double            prevSwingHigh;
   double            prevSwingLow;
   double            emaFast;
   double            emaSlow;
   string            trendLabel;
   string            methodUsed;     // Which method determined the trend
   bool              isValid;
  };

SMTFData  HTF1;
SMTFData  HTF2;
bool      mtfConfluenceBull;
bool      mtfConfluenceBear;
string    mtfStatusMsg;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

double         swingHighs[];
double         swingLows[];
int            swingHighBars[];
int            swingLowBars[];
int            swingHighCount = 0;
int            swingLowCount  = 0;

ENUM_TREND     currentTrend       = TREND_NONE;
ENUM_ICC_PHASE currentPhase       = PHASE_NONE;
ENUM_TREND     previousTrend      = TREND_NONE;

double         indicationHigh     = 0;
double         indicationLow      = 0;
double         correctionHigh     = 0;
double         correctionLow      = 0;
double         lastSwingHigh      = 0;
double         lastSwingLow       = 0;
double         prevSwingHigh      = 0;
double         prevSwingLow       = 0;

bool           buySignalFired     = false;
bool           sellSignalFired    = false;
datetime       lastAlertTime      = 0;
int            lastAlertBar       = 0;

ENUM_TIMEFRAMES lastTimeframe     = PERIOD_CURRENT;
int            htfDebugCounter    = 0;

//+------------------------------------------------------------------+
//| AUTO-SELECT Higher Timeframe                                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetAutoHTF1(ENUM_TIMEFRAMES entryTF)
  {
   if(entryTF == PERIOD_M5)   return PERIOD_M15;
   if(entryTF == PERIOD_M15)  return PERIOD_H1;
   if(entryTF == PERIOD_H1)   return PERIOD_H4;
   if(entryTF == PERIOD_H4)   return PERIOD_D1;
   if(entryTF == PERIOD_D1)   return PERIOD_W1;
   return PERIOD_H4;
  }

ENUM_TIMEFRAMES GetAutoHTF2(ENUM_TIMEFRAMES entryTF)
  {
   if(entryTF == PERIOD_M5)   return PERIOD_H1;
   if(entryTF == PERIOD_M15)  return PERIOD_H4;
   if(entryTF == PERIOD_H1)   return PERIOD_D1;
   if(entryTF == PERIOD_H4)   return PERIOD_W1;
   if(entryTF == PERIOD_D1)   return PERIOD_MN1;
   return PERIOD_D1;
  }

//+------------------------------------------------------------------+
//| Configure MTF timeframes                                         |
//+------------------------------------------------------------------+
void ConfigureMTF()
  {
   if(!UseMTF)
     {
      HTF1.isValid = false;
      HTF2.isValid = false;
      mtfConfluenceBull = true;
      mtfConfluenceBear = true;
      mtfStatusMsg = "MTF: DISABLED";
      return;
     }

   switch(MTF_Mode)
     {
      case MTF_AUTO:
         HTF1.timeframe = GetAutoHTF1(_Period);
         HTF2.timeframe = GetAutoHTF2(_Period);
         break;
      case MTF_DUAL:
         HTF1.timeframe = GetAutoHTF1(_Period);
         HTF2.timeframe = ManualHTF2;
         break;
      case MTF_MANUAL:
         HTF1.timeframe = ManualHTF1;
         HTF2.timeframe = ManualHTF2;
         break;
     }
   HTF1.isValid = true;
   HTF2.isValid = true;

   if(HTF1.timeframe <= _Period)
      HTF1.timeframe = GetAutoHTF1(_Period);
   if(HTF2.isValid && HTF2.timeframe <= _Period)
      HTF2.timeframe = GetAutoHTF2(_Period);

   Print("═══ MTF CONFIG ═══ HTF1: ", EnumToString(HTF1.timeframe),
         " | HTF2: ", EnumToString(HTF2.timeframe),
         " | Method: ", EnumToString(HTF_Method));
  }

//+------------------------------------------------------------------+
//| ANALYZE HTF — FIXED for Strategy Tester compatibility            |
//| Uses three methods: Swing, EMA, or Combined (swing + EMA fallback)|
//+------------------------------------------------------------------+
void AnalyzeHTF(SMTFData &htf)
  {
   if(!htf.isValid) return;

   htf.trend      = TREND_NONE;
   htf.trendLabel = "NONE";
   htf.methodUsed = "---";

   //--- Check available bars on HTF ---
   int bars = Bars(_Symbol, htf.timeframe);
   if(bars < 60)
     {
      htf.trendLabel = "NO DATA (" + IntegerToString(bars) + " bars)";
      htf.methodUsed = "INSUFFICIENT";
      if(HTF_Debug)
         Print("HTF DEBUG [", EnumToString(htf.timeframe), "]: Only ",
               bars, " bars available. Need >= 60.");
      return;
     }

   //--- METHOD 1: EMA Crossover (always computed — fast & reliable in tester) ---
   double emaFastArr[], emaSlowArr[];
   int copyLen = MathMin(HTF_CheckBars, bars - 1);

   // Use iMA handles for proper EMA calculation in Strategy Tester
   int handleFast = iMA(_Symbol, htf.timeframe, HTF_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   int handleSlow = iMA(_Symbol, htf.timeframe, HTF_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   if(handleFast == INVALID_HANDLE || handleSlow == INVALID_HANDLE)
     {
      htf.trendLabel = "EMA ERROR";
      htf.methodUsed = "ERROR";
      if(HTF_Debug)
         Print("HTF DEBUG [", EnumToString(htf.timeframe), "]: iMA handle creation failed.");
      return;
     }

   ArraySetAsSeries(emaFastArr, true);
   ArraySetAsSeries(emaSlowArr, true);

   int copiedFast = CopyBuffer(handleFast, 0, 0, 3, emaFastArr);
   int copiedSlow = CopyBuffer(handleSlow, 0, 0, 3, emaSlowArr);

   IndicatorRelease(handleFast);
   IndicatorRelease(handleSlow);

   if(copiedFast < 3 || copiedSlow < 3)
     {
      htf.trendLabel = "EMA COPY FAIL";
      htf.methodUsed = "ERROR";
      if(HTF_Debug)
         Print("HTF DEBUG [", EnumToString(htf.timeframe), "]: CopyBuffer failed. Fast=",
               copiedFast, " Slow=", copiedSlow);
      return;
     }

   htf.emaFast = emaFastArr[0];
   htf.emaSlow = emaSlowArr[0];

   bool emaBull = emaFastArr[0] > emaSlowArr[0];
   bool emaBear = emaFastArr[0] < emaSlowArr[0];
   // EMA momentum: is the gap widening?
   bool emaFastRising = emaFastArr[0] > emaFastArr[1];
   bool emaFastFalling = emaFastArr[0] < emaFastArr[1];

   //--- If EMA-only mode, use EMA result directly ---
   if(HTF_Method == HTF_EMA_ONLY)
     {
      if(emaBull)
        { htf.trend = TREND_BULLISH; htf.trendLabel = "BULLISH ▲ (EMA)"; }
      else if(emaBear)
        { htf.trend = TREND_BEARISH; htf.trendLabel = "BEARISH ▼ (EMA)"; }
      else
        { htf.trend = TREND_NONE; htf.trendLabel = "FLAT (EMA)"; }
      htf.methodUsed = "EMA";
      return;
     }

   //--- METHOD 2: Swing Structure Detection ---
   bool swingTrendFound = false;
   ENUM_TREND swingTrend = TREND_NONE;

   double htfHighs[], htfLows[];
   ArraySetAsSeries(htfHighs, true);
   ArraySetAsSeries(htfLows, true);

   int copiedH = CopyHigh(_Symbol, htf.timeframe, 0, copyLen, htfHighs);
   int copiedL = CopyLow(_Symbol, htf.timeframe, 0, copyLen, htfLows);

   if(copiedH >= 60 && copiedL >= 60)
     {
      double shArr[];
      double slArr[];
      ArrayResize(shArr, 0);
      ArrayResize(slArr, 0);

      int lookback = HTF_SwingLookback;
      int scanEnd  = copiedH - lookback;

      // Scan for swing highs (index 0 = most recent, so scan from recent to old)
      for(int b = lookback; b < scanEnd && ArraySize(shArr) < 4; b++)
        {
         bool isSH = true;
         for(int k = 1; k <= lookback; k++)
           {
            if(htfHighs[b - k] >= htfHighs[b] || htfHighs[b + k] >= htfHighs[b])
              { isSH = false; break; }
           }
         if(isSH)
           {
            int sz = ArraySize(shArr);
            ArrayResize(shArr, sz + 1);
            shArr[sz] = htfHighs[b];
           }
        }

      // Scan for swing lows
      for(int b = lookback; b < scanEnd && ArraySize(slArr) < 4; b++)
        {
         bool isSL = true;
         for(int k = 1; k <= lookback; k++)
           {
            if(htfLows[b - k] <= htfLows[b] || htfLows[b + k] <= htfLows[b])
              { isSL = false; break; }
           }
         if(isSL)
           {
            int sz = ArraySize(slArr);
            ArrayResize(slArr, sz + 1);
            slArr[sz] = htfLows[b];
           }
        }

      int shCount_htf = ArraySize(shArr);
      int slCount_htf = ArraySize(slArr);

      if(HTF_Debug && htfDebugCounter % 50 == 0)
         Print("HTF DEBUG [", EnumToString(htf.timeframe), "]: Bars copied=",
               copiedH, " | Swing Highs found=", shCount_htf,
               " | Swing Lows found=", slCount_htf);

      if(shCount_htf >= 2 && slCount_htf >= 2)
        {
         // Index 0 = most recent swing, index 1 = previous
         htf.swingHigh     = shArr[0];
         htf.prevSwingHigh = shArr[1];
         htf.swingLow      = slArr[0];
         htf.prevSwingLow  = slArr[1];

         bool hh = htf.swingHigh > htf.prevSwingHigh;
         bool hl = htf.swingLow  > htf.prevSwingLow;
         bool ll = htf.swingLow  < htf.prevSwingLow;
         bool lh = htf.swingHigh < htf.prevSwingHigh;

         if(hh && hl)
           { swingTrend = TREND_BULLISH; swingTrendFound = true; }
         else if(ll && lh)
           { swingTrend = TREND_BEARISH; swingTrendFound = true; }
         else if(hh)  // Partial bullish
           { swingTrend = TREND_BULLISH; swingTrendFound = true; }
         else if(ll)  // Partial bearish
           { swingTrend = TREND_BEARISH; swingTrendFound = true; }
        }
     }

   //--- METHOD 3: Combined — use swing if found, EMA as fallback ---
   if(HTF_Method == HTF_SWING_ONLY)
     {
      if(swingTrendFound)
        {
         htf.trend = swingTrend;
         htf.trendLabel = (swingTrend == TREND_BULLISH ? "BULLISH ▲" : "BEARISH ▼") + " (Swing)";
         htf.methodUsed = "SWING";
        }
      else
        {
         htf.trendLabel = "FORMING (no swings)";
         htf.methodUsed = "SWING-NONE";
        }
     }
   else // HTF_COMBINED
     {
      if(swingTrendFound)
        {
         htf.trend = swingTrend;
         htf.trendLabel = (swingTrend == TREND_BULLISH ? "BULLISH ▲" : "BEARISH ▼") + " (Swing)";
         htf.methodUsed = "SWING";

         // Bonus: if EMA confirms swing, mark as strong
         if((swingTrend == TREND_BULLISH && emaBull) ||
            (swingTrend == TREND_BEARISH && emaBear))
           {
            htf.trendLabel += "+EMA";
            htf.methodUsed = "SWING+EMA";
           }
        }
      else
        {
         // FALLBACK: Use EMA when swing detection fails
         if(emaBull && emaFastRising)
           { htf.trend = TREND_BULLISH; htf.trendLabel = "BULLISH ▲ (EMA↑)"; }
         else if(emaBull)
           { htf.trend = TREND_BULLISH; htf.trendLabel = "BULLISH ▲ (EMA)"; }
         else if(emaBear && emaFastFalling)
           { htf.trend = TREND_BEARISH; htf.trendLabel = "BEARISH ▼ (EMA↓)"; }
         else if(emaBear)
           { htf.trend = TREND_BEARISH; htf.trendLabel = "BEARISH ▼ (EMA)"; }
         else
           { htf.trendLabel = "FLAT (EMA)"; }
         htf.methodUsed = "EMA-FALLBACK";
        }
     }
  }

//+------------------------------------------------------------------+
//| Evaluate MTF confluence                                          |
//+------------------------------------------------------------------+
void EvaluateMTFConfluence()
  {
   if(!UseMTF)
     {
      mtfConfluenceBull = true;
      mtfConfluenceBear = true;
      mtfStatusMsg = "MTF DISABLED";
      return;
     }

   AnalyzeHTF(HTF1);
   if(HTF2.isValid) AnalyzeHTF(HTF2);

   bool htf1Bull = (HTF1.trend == TREND_BULLISH);
   bool htf1Bear = (HTF1.trend == TREND_BEARISH);
   bool htf2Bull = !HTF2.isValid || (HTF2.trend == TREND_BULLISH);
   bool htf2Bear = !HTF2.isValid || (HTF2.trend == TREND_BEARISH);

   if(RequireBothHTF && HTF2.isValid)
     {
      mtfConfluenceBull = htf1Bull && htf2Bull;
      mtfConfluenceBear = htf1Bear && htf2Bear;
     }
   else
     {
      mtfConfluenceBull = htf1Bull;
      mtfConfluenceBear = htf1Bear;
     }

   mtfStatusMsg = "HTF1(" + EnumToString(HTF1.timeframe) + "): " + HTF1.trendLabel;
   if(HTF2.isValid)
      mtfStatusMsg += " | HTF2(" + EnumToString(HTF2.timeframe) + "): " + HTF2.trendLabel;

   // Debug logging (every 50 bars to avoid spam)
   if(HTF_Debug && htfDebugCounter % 50 == 0)
     {
      Print("═══ MTF CONFLUENCE ═══");
      Print("  HTF1 [", EnumToString(HTF1.timeframe), "]: ", HTF1.trendLabel,
            " | Method: ", HTF1.methodUsed);
      if(HTF2.isValid)
         Print("  HTF2 [", EnumToString(HTF2.timeframe), "]: ", HTF2.trendLabel,
               " | Method: ", HTF2.methodUsed);
      Print("  Bull Confluence: ", mtfConfluenceBull ? "YES" : "NO",
            " | Bear Confluence: ", mtfConfluenceBear ? "YES" : "NO");
      Print("═════════════════════");
     }
   htfDebugCounter++;

   if(ShowHTFZones)
      DrawHTFZones();
  }

//+------------------------------------------------------------------+
//| Draw HTF zones                                                   |
//+------------------------------------------------------------------+
void DrawHTFZones()
  {
   // Simplified zone drawing
   if(!HTF1.isValid) return;
   double point = symInfo.Point();
   datetime t1 = iTime(_Symbol, _Period, MathMin(Bars(_Symbol, _Period) - 1, 200));
   datetime t2 = iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period) * 20;

   string name;
   color  clr;

   // HTF1 High
   name = "ICC_HTF1_SH";
   ObjectDelete(0, name);
   clr = HTF1.trend == TREND_BULLISH ? HTF_BullZone : HTF_BearZone;
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, HTF1.swingHigh, t2, HTF1.swingHigh - 20 * point);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);

   // HTF1 Low
   name = "ICC_HTF1_SL";
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, HTF1.swingLow + 20 * point, t2, HTF1.swingLow);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
  }

//+------------------------------------------------------------------+
//| AUTO-CONFIGURE per timeframe                                     |
//+------------------------------------------------------------------+
void AutoConfigure()
  {
   ENUM_TIMEFRAMES tf = _Period;

   if(!AutoSettings)
     {
      SwingLookback=SwingLookback_In; CorrectionMinPct=CorrMinPct_In;
      CorrectionMaxPct=CorrMaxPct_In; RR_Ratio=RR_Ratio_In;
      SL_Buffer_Points=SL_Buffer_In;
      TrailingStart_Pts=TrailingStart_In; TrailingStep_Pts=TrailingStep_In;
      BreakEvenAt_Pts=BreakEvenAt_In; BreakEvenProfit=BreakEvenProfit_In;
      ActiveProfile="MANUAL";
      ConfigureMTF(); return;
     }

   if(tf==PERIOD_M5)
     { SwingLookback=3;CorrectionMinPct=25;CorrectionMaxPct=65;RR_Ratio=1.2;
       SL_Buffer_Points=20;TrailingStart_Pts=80;TrailingStep_Pts=40;
       BreakEvenAt_Pts=60;BreakEvenProfit=5;ActiveProfile="M5 SCALP"; }
   else if(tf==PERIOD_M15)
     { SwingLookback=3;CorrectionMinPct=30;CorrectionMaxPct=70;RR_Ratio=1.5;
       SL_Buffer_Points=30;TrailingStart_Pts=120;TrailingStep_Pts=60;
       BreakEvenAt_Pts=100;BreakEvenProfit=8;ActiveProfile="M15 SCALP"; }
   else if(tf==PERIOD_H1)
     { SwingLookback=5;CorrectionMinPct=30;CorrectionMaxPct=79;RR_Ratio=2.0;
       SL_Buffer_Points=50;TrailingStart_Pts=200;TrailingStep_Pts=100;
       BreakEvenAt_Pts=150;BreakEvenProfit=10;ActiveProfile="H1 INTRADAY"; }
   else if(tf==PERIOD_H4)
     { SwingLookback=7;CorrectionMinPct=38;CorrectionMaxPct=79;RR_Ratio=3.0;
       SL_Buffer_Points=100;TrailingStart_Pts=400;TrailingStep_Pts=200;
       BreakEvenAt_Pts=300;BreakEvenProfit=20;ActiveProfile="H4 SWING"; }
   else if(tf==PERIOD_D1)
     { SwingLookback=10;CorrectionMinPct=38;CorrectionMaxPct=79;RR_Ratio=3.5;
       SL_Buffer_Points=200;TrailingStart_Pts=800;TrailingStep_Pts=400;
       BreakEvenAt_Pts=600;BreakEvenProfit=50;ActiveProfile="D1 POSITION"; }
   else
     { SwingLookback=SwingLookback_In;CorrectionMinPct=CorrMinPct_In;
       CorrectionMaxPct=CorrMaxPct_In;RR_Ratio=RR_Ratio_In;
       SL_Buffer_Points=SL_Buffer_In;TrailingStart_Pts=TrailingStart_In;
       TrailingStep_Pts=TrailingStep_In;BreakEvenAt_Pts=BreakEvenAt_In;
       BreakEvenProfit=BreakEvenProfit_In;ActiveProfile="CUSTOM"; }

   Print("Profile: ", ActiveProfile, " | TF: ", EnumToString(tf));
   ConfigureMTF();
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   symInfo.Name(_Symbol); symInfo.Refresh();

   ArrayResize(swingHighs, 100); ArrayResize(swingLows, 100);
   ArrayResize(swingHighBars, 100); ArrayResize(swingLowBars, 100);

   lastTimeframe = _Period;
   AutoConfigure();
   EvaluateMTFConfluence();

   Print("ICC EA v3.1 (Backtest-Fixed) | ", ActiveProfile,
         " | MTF: ", UseMTF ? "ON" : "OFF",
         " | Method: ", EnumToString(HTF_Method));
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  { ObjectsDeleteAll(0, "ICC_"); Comment(""); }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   MonitorSLTP();
   ManagePositions();

   if(_Period != lastTimeframe)
     { lastTimeframe=_Period; ResetState(); AutoConfigure();
       EvaluateMTFConfluence(); }

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
//| MONITOR SL/TP                                                    |
//+------------------------------------------------------------------+
void MonitorSLTP()
  {
   symInfo.Refresh();
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber || posInfo.Symbol()!=_Symbol) continue;

      ulong ticket=posInfo.Ticket();
      double op=posInfo.PriceOpen(),sl=posInfo.StopLoss(),tp=posInfo.TakeProfit();
      double point=symInfo.Point();

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        {
         double bid=symInfo.Bid();
         if(tp>0 && bid>=tp)
           { if(trade.PositionClose(ticket))
               SendAlertForced("✅ BUY TP HIT | "+_Symbol+" | +"
                  +DoubleToString((bid-op)/point,0)+" pts"); }
         else if(sl>0 && bid<=sl)
           { if(trade.PositionClose(ticket))
               SendAlertForced("🛑 BUY SL HIT | "+_Symbol+" | -"
                  +DoubleToString((op-bid)/point,0)+" pts"); }
        }
      if(posInfo.PositionType()==POSITION_TYPE_SELL)
        {
         double ask=symInfo.Ask();
         if(tp>0 && ask<=tp)
           { if(trade.PositionClose(ticket))
               SendAlertForced("✅ SELL TP HIT | "+_Symbol+" | +"
                  +DoubleToString((op-ask)/point,0)+" pts"); }
         else if(sl>0 && ask>=sl)
           { if(trade.PositionClose(ticket))
               SendAlertForced("🛑 SELL SL HIT | "+_Symbol+" | -"
                  +DoubleToString((ask-op)/point,0)+" pts"); }
        }
     }
  }

//+------------------------------------------------------------------+
//| Reset state                                                      |
//+------------------------------------------------------------------+
void ResetState()
  {
   currentTrend=TREND_NONE;currentPhase=PHASE_NONE;previousTrend=TREND_NONE;
   swingHighCount=0;swingLowCount=0;
   indicationHigh=0;indicationLow=0;correctionHigh=0;correctionLow=0;
   lastSwingHigh=0;lastSwingLow=0;prevSwingHigh=0;prevSwingLow=0;
   buySignalFired=false;sellSignalFired=false;lastAlertBar=0;
   ObjectsDeleteAll(0,"ICC_");
  }

//+------------------------------------------------------------------+
//| Detect Swing Points                                              |
//+------------------------------------------------------------------+
void DetectSwingPoints()
  {
   int bars=Bars(_Symbol,_Period);
   if(bars<SwingLookback*2+1) return;

   double highs[],lows[];
   ArrayResize(highs,SwingLookback*2+1);ArrayResize(lows,SwingLookback*2+1);
   int checkBar=SwingLookback;

   if(CopyHigh(_Symbol,_Period,1,SwingLookback*2+1,highs)<=0) return;
   if(CopyLow(_Symbol,_Period,1,SwingLookback*2+1,lows)<=0)  return;

   bool isSH=true;
   for(int i=0;i<SwingLookback*2+1;i++)
     { if(i==checkBar)continue; if(highs[i]>=highs[checkBar]){isSH=false;break;} }
   if(isSH && swingHighCount<100)
      if(swingHighCount==0 || swingHighs[swingHighCount-1]!=highs[checkBar])
        { swingHighs[swingHighCount]=highs[checkBar];
          swingHighBars[swingHighCount]=checkBar+1; swingHighCount++;
          prevSwingHigh=lastSwingHigh; lastSwingHigh=highs[checkBar];
          if(ShowSwingPoints) DrawSwingPoint(true,highs[checkBar],checkBar+1); }

   bool isSL=true;
   for(int i=0;i<SwingLookback*2+1;i++)
     { if(i==checkBar)continue; if(lows[i]<=lows[checkBar]){isSL=false;break;} }
   if(isSL && swingLowCount<100)
      if(swingLowCount==0 || swingLows[swingLowCount-1]!=lows[checkBar])
        { swingLows[swingLowCount]=lows[checkBar];
          swingLowBars[swingLowCount]=checkBar+1; swingLowCount++;
          prevSwingLow=lastSwingLow; lastSwingLow=lows[checkBar];
          if(ShowSwingPoints) DrawSwingPoint(false,lows[checkBar],checkBar+1); }

   if(swingHighCount>50) TrimSwingArray(swingHighs,swingHighBars,swingHighCount);
   if(swingLowCount>50)  TrimSwingArray(swingLows,swingLowBars,swingLowCount);
  }

//+------------------------------------------------------------------+
//| Market Structure                                                 |
//+------------------------------------------------------------------+
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
//| ICC Phase Detection                                              |
//+------------------------------------------------------------------+
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
        { currentPhase=PHASE_INDICATION;indicationHigh=sh1;indicationLow=sl1;
          buySignalFired=false;
          SendAlert("ICC INDICATION (Bull): HH @ "+DoubleToString(indicationHigh,_Digits)); }

      if(currentPhase==PHASE_INDICATION && cc<indicationHigh)
        { double ms=indicationHigh-indicationLow;
          double pp=(ms>0)?((indicationHigh-cc)/ms)*100.0:0;
          if(pp>=CorrectionMinPct && pp<=CorrectionMaxPct)
            { currentPhase=PHASE_CORRECTION;correctionLow=cc;correctionHigh=indicationHigh;
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
        { currentPhase=PHASE_INDICATION;indicationLow=sl1;indicationHigh=sh1;
          sellSignalFired=false;
          SendAlert("ICC INDICATION (Bear): LL @ "+DoubleToString(indicationLow,_Digits)); }

      if(currentPhase==PHASE_INDICATION && cc>indicationLow)
        { double ms=indicationHigh-indicationLow;
          double pp=(ms>0)?((cc-indicationLow)/ms)*100.0:0;
          if(pp>=CorrectionMinPct && pp<=CorrectionMaxPct)
            { currentPhase=PHASE_CORRECTION;correctionHigh=cc;correctionLow=indicationLow;
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
//| Check Entry Signals — with MTF gate + debug logging              |
//+------------------------------------------------------------------+
void CheckEntrySignals()
  {
   if(currentPhase!=PHASE_CONTINUATION) return;

   int currentBar=Bars(_Symbol,_Period);
   if(currentBar==lastAlertBar) return;
   if(CountOpenTrades()>=MaxOpenTrades) return;

   double ask=symInfo.Ask(),bid=symInfo.Bid(),point=symInfo.Point();

   // BULLISH
   if(currentTrend==TREND_BULLISH && !buySignalFired)
     {
      if(UseMTF && !mtfConfluenceBull)
        {
         if(!AllowCounterTrend)
           {
            if(HTF_Debug)
               Print("🚫 BUY BLOCKED: Entry=BULL but MTF not aligned | ", mtfStatusMsg);
            SendAlert("🚫 BUY BLOCKED — " + mtfStatusMsg);
            buySignalFired=true; currentPhase=PHASE_NONE; return;
           }
        }

      double slPrice=correctionLow-SL_Buffer_Points*point;
      double slDist=ask-slPrice;
      double tpPrice=ask+slDist*RR_Ratio;

      if(UseMTF && mtfConfluenceBull && HTF2.isValid && HTF2.trend==TREND_BULLISH)
         tpPrice=ask+slDist*RR_Ratio*1.25;

      double lots=CalculateLotSize(slDist);
      if(lots>0)
        {
         string confTag = UseMTF ? (HTF2.isValid && HTF2.trend==TREND_BULLISH ?
                          "FULL CONFLUENCE" : "HTF1 ALIGNED") : "MTF OFF";

         if(trade.Buy(lots,_Symbol,ask,slPrice,tpPrice,"ICC Buy "+ActiveProfile))
           {
            string msg=StringFormat("🟢 BUY | %s | %s\nEntry: %s | SL: %s | TP: %s\n%s | %s",
               _Symbol, ActiveProfile,
               DoubleToString(ask,_Digits), DoubleToString(slPrice,_Digits),
               DoubleToString(tpPrice,_Digits), confTag, mtfStatusMsg);
            SendAlertForced(msg);
            buySignalFired=true; lastAlertBar=currentBar; currentPhase=PHASE_NONE;
           }
        }
     }

   // BEARISH
   if(currentTrend==TREND_BEARISH && !sellSignalFired)
     {
      if(UseMTF && !mtfConfluenceBear)
        {
         if(!AllowCounterTrend)
           {
            if(HTF_Debug)
               Print("🚫 SELL BLOCKED: Entry=BEAR but MTF not aligned | ", mtfStatusMsg);
            SendAlert("🚫 SELL BLOCKED — " + mtfStatusMsg);
            sellSignalFired=true; currentPhase=PHASE_NONE; return;
           }
        }

      double slPrice=correctionHigh+SL_Buffer_Points*point;
      double slDist=slPrice-bid;
      double tpPrice=bid-slDist*RR_Ratio;

      if(UseMTF && mtfConfluenceBear && HTF2.isValid && HTF2.trend==TREND_BEARISH)
         tpPrice=bid-slDist*RR_Ratio*1.25;

      double lots=CalculateLotSize(slDist);
      if(lots>0)
        {
         string confTag = UseMTF ? (HTF2.isValid && HTF2.trend==TREND_BEARISH ?
                          "FULL CONFLUENCE" : "HTF1 ALIGNED") : "MTF OFF";

         if(trade.Sell(lots,_Symbol,bid,slPrice,tpPrice,"ICC Sell "+ActiveProfile))
           {
            string msg=StringFormat("🔴 SELL | %s | %s\nEntry: %s | SL: %s | TP: %s\n%s | %s",
               _Symbol, ActiveProfile,
               DoubleToString(bid,_Digits), DoubleToString(slPrice,_Digits),
               DoubleToString(tpPrice,_Digits), confTag, mtfStatusMsg);
            SendAlertForced(msg);
            sellSignalFired=true; lastAlertBar=currentBar; currentPhase=PHASE_NONE;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Position Management                                              |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber || posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(),sl=posInfo.StopLoss(),tp=posInfo.TakeProfit();
      double point=symInfo.Point(); ulong ticket=posInfo.Ticket();

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        { double bid=symInfo.Bid(),pp=(bid-op)/point;
          if(UseBreakEven && pp>=BreakEvenAt_Pts)
            { double ns=op+BreakEvenProfit*point;
              if(sl<ns) trade.PositionModify(ticket,ns,tp); }
          if(UseTrailingStop && pp>=TrailingStart_Pts)
            { double ts=bid-TrailingStep_Pts*point;
              if(ts>sl) trade.PositionModify(ticket,ts,tp); }
          if(currentTrend==TREND_BEARISH && previousTrend==TREND_BULLISH)
            SendAlert("⚠️ EXIT WARN BUY: Structure→BEAR"); }

      if(posInfo.PositionType()==POSITION_TYPE_SELL)
        { double ask=symInfo.Ask(),pp=(op-ask)/point;
          if(UseBreakEven && pp>=BreakEvenAt_Pts)
            { double ns=op-BreakEvenProfit*point;
              if(sl>ns||sl==0) trade.PositionModify(ticket,ns,tp); }
          if(UseTrailingStop && pp>=TrailingStart_Pts)
            { double ts=ask+TrailingStep_Pts*point;
              if(ts<sl||sl==0) trade.PositionModify(ticket,ts,tp); }
          if(currentTrend==TREND_BULLISH && previousTrend==TREND_BEARISH)
            SendAlert("⚠️ EXIT WARN SELL: Structure→BULL"); }
     }
  }

//+------------------------------------------------------------------+
//| Utility Functions                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDist)
  { if(FixedLots>0) return NormalizeLots(FixedLots);
    if(slDist<=0) return 0;
    double bal=AccountInfoDouble(ACCOUNT_BALANCE);
    double risk=bal*RiskPercent/100.0;
    double tv=symInfo.TickValue(),ts=symInfo.TickSize();
    if(tv<=0||ts<=0) return symInfo.LotsMin();
    return NormalizeLots(risk/((slDist/ts)*tv)); }

double NormalizeLots(double lots)
  { double mn=symInfo.LotsMin(),mx=symInfo.LotsMax(),st=symInfo.LotsStep();
    lots=MathMax(lots,mn);lots=MathMin(lots,mx);
    lots=MathFloor(lots/st)*st; return NormalizeDouble(lots,2); }

int CountOpenTrades()
  { int c=0; for(int i=PositionsTotal()-1;i>=0;i--)
      if(posInfo.SelectByIndex(i))
        if(posInfo.Magic()==MagicNumber && posInfo.Symbol()==_Symbol) c++;
    return c; }

bool IsNewBar()
  { static datetime lt=0; datetime ct=iTime(_Symbol,_Period,0);
    if(ct!=lt){lt=ct;return true;} return false; }

bool IsWithinSession()
  { MqlDateTime dt; TimeCurrent(dt);
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
    ObjectDelete(0,n); ObjectCreate(0,n,OBJ_ARROW,0,t,price);
    ObjectSetInteger(0,n,OBJPROP_ARROWCODE,isH?234:233);
    ObjectSetInteger(0,n,OBJPROP_COLOR,isH?BearColor:BullColor);
    ObjectSetInteger(0,n,OBJPROP_WIDTH,2); }

void TrimSwingArray(double &a[],int &b[],int &c)
  { int k=25; for(int i=0;i<k;i++){a[i]=a[c-k+i];b[i]=b[c-k+i];} c=k; }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   string tStr="NONE";
   if(currentTrend==TREND_BULLISH) tStr="BULLISH ▲";
   if(currentTrend==TREND_BEARISH) tStr="BEARISH ▼";
   string pStr="Scanning...";
   switch(currentPhase)
     { case PHASE_INDICATION:pStr="1. INDICATION";break;
       case PHASE_CORRECTION:pStr="2. CORRECTION";break;
       case PHASE_CONTINUATION:pStr="3. CONTINUATION";break; }

   string mtfBull=mtfConfluenceBull?"YES":"NO";
   string mtfBear=mtfConfluenceBear?"YES":"NO";

   string quality="---";
   if(currentTrend==TREND_BULLISH && mtfConfluenceBull)
      quality=HTF2.isValid&&HTF2.trend==TREND_BULLISH?"A+ FULL CONF":"A HTF1";
   else if(currentTrend==TREND_BEARISH && mtfConfluenceBear)
      quality=HTF2.isValid&&HTF2.trend==TREND_BEARISH?"A+ FULL CONF":"A HTF1";
   else if(currentTrend!=TREND_NONE)
      quality="B/C NO CONF";

   string d="";
   d+="╔════════════════════════════════════════════╗\n";
   d+="║     ICC STRATEGY EA v3.1 (BT-Fixed)       ║\n";
   d+="╠════════════════════════════════════════════╣\n";
   d+="║ Profile:  "+ActiveProfile+"\n";
   d+="║ Trend:    "+tStr+"\n";
   d+="║ Phase:    "+pStr+"\n";
   d+="╠═══ MTF CONFLUENCE ═════════════════════════╣\n";
   if(UseMTF)
     {
      d+="║ HTF1: "+HTF1.trendLabel+" ["+HTF1.methodUsed+"]\n";
      if(HTF2.isValid)
         d+="║ HTF2: "+HTF2.trendLabel+" ["+HTF2.methodUsed+"]\n";
      d+="║ Bull: "+mtfBull+" | Bear: "+mtfBear+"\n";
      d+="║ Signal: "+quality+"\n";
     }
   else d+="║ MTF: DISABLED\n";
   d+="╠═══ SETTINGS ═══════════════════════════════╣\n";
   d+="║ RR: "+DoubleToString(RR_Ratio,1)+" | SL: "+IntegerToString(SL_Buffer_Points)+"\n";
   d+="║ Trades: "+IntegerToString(CountOpenTrades())+"/"+IntegerToString(MaxOpenTrades)+"\n";
   d+="╚════════════════════════════════════════════╝";
   Comment(d);
  }
//+------------------------------------------------------------------+
