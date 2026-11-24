//+------------------------------------------------------------------+
//|                                           ICC_Strategy_EA_v3.mq5 |
//|            ICC - Indication, Correction, Continuation v3.0       |
//|     Auto-TF Settings + Auto SL/TP + Multi-Timeframe Confluence   |
//+------------------------------------------------------------------+
#property copyright   "ICC Strategy EA v3.0"
#property link        ""
#property version     "3.00"
#property description "ICC (Indication, Correction, Continuation) Strategy EA v3.0"
#property description "Auto-timeframe | Auto SL/TP | MTF Confluence Filter"

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
   MTF_AUTO      = 0,  // Auto-select HTF based on entry TF
   MTF_DUAL      = 1,  // Use two higher timeframes
   MTF_MANUAL    = 2   // Manually specify HTF
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== Multi-Timeframe Confluence ==="
input bool           UseMTF            = true;         // Enable MTF confluence filter
input ENUM_MTF_MODE  MTF_Mode          = MTF_AUTO;     // MTF selection mode
input ENUM_TIMEFRAMES ManualHTF1       = PERIOD_H4;    // Manual HTF 1 (if MTF_MANUAL)
input ENUM_TIMEFRAMES ManualHTF2       = PERIOD_D1;    // Manual HTF 2 (if MTF_MANUAL/MTF_DUAL)
input bool           RequireBothHTF    = false;        // Require BOTH HTFs aligned (dual mode)
input int            HTF_SwingLookback = 7;            // HTF swing detection lookback
input bool           AllowCounterTrend = false;        // Allow trades against HTF trend
input int            HTF_CheckBars     = 100;          // HTF bars to analyze for structure

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
input bool     ShowHTFZones       = true;        // Draw HTF S/R zones on chart
input color    BullColor          = clrDodgerBlue;
input color    BearColor          = clrOrangeRed;
input color    CorrColor          = clrGold;
input color    HTF_BullZone       = clrMediumSeaGreen;  // HTF bullish zone color
input color    HTF_BearZone       = clrCrimson;         // HTF bearish zone color

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
   string            trendLabel;
   bool              isValid;
  };

SMTFData  HTF1;                  // Primary higher timeframe
SMTFData  HTF2;                  // Secondary higher timeframe (dual mode)
bool      mtfConfluenceBull;     // HTF supports bullish entry
bool      mtfConfluenceBear;     // HTF supports bearish entry
string    mtfStatusMsg;          // Dashboard message

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

//+------------------------------------------------------------------+
//| AUTO-SELECT Higher Timeframe based on entry TF                   |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetAutoHTF1(ENUM_TIMEFRAMES entryTF)
  {
   // Maps: Entry TF → Immediate higher TF for trend confirmation
   if(entryTF == PERIOD_M5)   return PERIOD_M15;
   if(entryTF == PERIOD_M15)  return PERIOD_H1;
   if(entryTF == PERIOD_H1)   return PERIOD_H4;
   if(entryTF == PERIOD_H4)   return PERIOD_D1;
   if(entryTF == PERIOD_D1)   return PERIOD_W1;
   // Fallback
   return PERIOD_H4;
  }

ENUM_TIMEFRAMES GetAutoHTF2(ENUM_TIMEFRAMES entryTF)
  {
   // Maps: Entry TF → Structural/macro TF for bias confirmation
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
      mtfConfluenceBull = true;  // No filter = always pass
      mtfConfluenceBear = true;
      mtfStatusMsg = "MTF: DISABLED";
      return;
     }

   switch(MTF_Mode)
     {
      case MTF_AUTO:
         HTF1.timeframe = GetAutoHTF1(_Period);
         HTF2.timeframe = GetAutoHTF2(_Period);
         HTF1.isValid = true;
         HTF2.isValid = true;
         break;

      case MTF_DUAL:
         HTF1.timeframe = GetAutoHTF1(_Period);
         HTF2.timeframe = ManualHTF2;
         HTF1.isValid = true;
         HTF2.isValid = true;
         break;

      case MTF_MANUAL:
         HTF1.timeframe = ManualHTF1;
         HTF2.timeframe = ManualHTF2;
         HTF1.isValid = true;
         HTF2.isValid = true;
         break;
     }

   // Validate: HTF must be larger than entry TF
   if(HTF1.timeframe <= _Period)
     {
      Print("⚠ HTF1 (", EnumToString(HTF1.timeframe), ") <= Entry TF. Auto-correcting...");
      HTF1.timeframe = GetAutoHTF1(_Period);
     }
   if(HTF2.isValid && HTF2.timeframe <= _Period)
     {
      Print("⚠ HTF2 (", EnumToString(HTF2.timeframe), ") <= Entry TF. Auto-correcting...");
      HTF2.timeframe = GetAutoHTF2(_Period);
     }

   Print("═══ MTF CONFLUENCE CONFIG ═══");
   Print("Entry TF:  ", EnumToString(_Period));
   Print("HTF 1:     ", EnumToString(HTF1.timeframe));
   if(HTF2.isValid)
      Print("HTF 2:     ", EnumToString(HTF2.timeframe));
   Print("Mode:      ", EnumToString(MTF_Mode));
   Print("Both Req:  ", RequireBothHTF ? "YES" : "NO");
   Print("═════════════════════════════");
  }

//+------------------------------------------------------------------+
//| Analyze HTF market structure (swing-based trend detection)       |
//+------------------------------------------------------------------+
void AnalyzeHTF(SMTFData &htf)
  {
   if(!htf.isValid) return;

   int bars = Bars(_Symbol, htf.timeframe);
   if(bars < HTF_CheckBars) { htf.trend = TREND_NONE; htf.trendLabel = "INSUF DATA"; return; }

   // Find last 4 swing points on HTF
   double shArr[4], slArr[4];
   int shCount = 0, slCount = 0;
   int lookback = HTF_SwingLookback;

   double htfHighs[], htfLows[];
   int copyBars = MathMin(HTF_CheckBars, bars);
   if(CopyHigh(_Symbol, htf.timeframe, 1, copyBars, htfHighs) <= 0) return;
   if(CopyLow (_Symbol, htf.timeframe, 1, copyBars, htfLows)  <= 0) return;

   // Scan for swing highs
   for(int b = lookback; b < copyBars - lookback && shCount < 4; b++)
     {
      bool isSH = true;
      for(int k = 1; k <= lookback; k++)
        {
         if(htfHighs[b - k] >= htfHighs[b] || htfHighs[b + k] >= htfHighs[b])
           { isSH = false; break; }
        }
      if(isSH) { shArr[shCount] = htfHighs[b]; shCount++; }
     }

   // Scan for swing lows
   for(int b = lookback; b < copyBars - lookback && slCount < 4; b++)
     {
      bool isSL = true;
      for(int k = 1; k <= lookback; k++)
        {
         if(htfLows[b - k] <= htfLows[b] || htfLows[b + k] <= htfLows[b])
           { isSL = false; break; }
        }
      if(isSL) { slArr[slCount] = htfLows[b]; slCount++; }
     }

   if(shCount < 2 || slCount < 2)
     { htf.trend = TREND_NONE; htf.trendLabel = "FORMING"; return; }

   // Most recent swings (arrays filled oldest → newest due to scan direction)
   htf.swingHigh     = shArr[shCount - 1];
   htf.prevSwingHigh = shArr[shCount - 2];
   htf.swingLow      = slArr[slCount - 1];
   htf.prevSwingLow  = slArr[slCount - 2];

   bool hh = htf.swingHigh > htf.prevSwingHigh;
   bool hl = htf.swingLow  > htf.prevSwingLow;
   bool ll = htf.swingLow  < htf.prevSwingLow;
   bool lh = htf.swingHigh < htf.prevSwingHigh;

   if(hh && hl)
     { htf.trend = TREND_BULLISH; htf.trendLabel = "BULLISH ▲"; }
   else if(ll && lh)
     { htf.trend = TREND_BEARISH; htf.trendLabel = "BEARISH ▼"; }
   else if(hh && !hl)
     { htf.trend = TREND_BULLISH; htf.trendLabel = "BULL (HH)"; }
   else if(ll && !lh)
     { htf.trend = TREND_BEARISH; htf.trendLabel = "BEAR (LL)"; }
   else
     { htf.trend = TREND_NONE; htf.trendLabel = "RANGING ↔"; }
  }

//+------------------------------------------------------------------+
//| Evaluate MTF confluence — are higher TFs aligned for trade?      |
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

   // Analyze both HTFs
   AnalyzeHTF(HTF1);
   if(HTF2.isValid) AnalyzeHTF(HTF2);

   bool htf1Bull = (HTF1.trend == TREND_BULLISH);
   bool htf1Bear = (HTF1.trend == TREND_BEARISH);
   bool htf2Bull = !HTF2.isValid || (HTF2.trend == TREND_BULLISH);
   bool htf2Bear = !HTF2.isValid || (HTF2.trend == TREND_BEARISH);

   if(RequireBothHTF && HTF2.isValid)
     {
      // Strict: BOTH must agree
      mtfConfluenceBull = htf1Bull && htf2Bull;
      mtfConfluenceBear = htf1Bear && htf2Bear;
     }
   else
     {
      // Standard: HTF1 must align, HTF2 is bonus confirmation
      mtfConfluenceBull = htf1Bull;
      mtfConfluenceBear = htf1Bear;
     }

   // Build status message
   mtfStatusMsg = "HTF1(" + EnumToString(HTF1.timeframe) + "): " + HTF1.trendLabel;
   if(HTF2.isValid)
      mtfStatusMsg += " | HTF2(" + EnumToString(HTF2.timeframe) + "): " + HTF2.trendLabel;

   // Draw HTF S/R zones on entry chart
   if(ShowHTFZones)
      DrawHTFZones();
  }

//+------------------------------------------------------------------+
//| Draw HTF support/resistance zones on entry-TF chart              |
//+------------------------------------------------------------------+
void DrawHTFZones()
  {
   if(!HTF1.isValid) return;
   double point = symInfo.Point();

   // HTF1 Swing High zone
   DrawHTFRect("ICC_HTF1_SH", HTF1.swingHigh, HTF1.swingHigh - 20 * point,
               HTF1.trend == TREND_BULLISH ? HTF_BullZone : HTF_BearZone,
               EnumToString(HTF1.timeframe) + " SH: " + DoubleToString(HTF1.swingHigh, _Digits));

   // HTF1 Swing Low zone
   DrawHTFRect("ICC_HTF1_SL", HTF1.swingLow + 20 * point, HTF1.swingLow,
               HTF1.trend == TREND_BEARISH ? HTF_BearZone : HTF_BullZone,
               EnumToString(HTF1.timeframe) + " SL: " + DoubleToString(HTF1.swingLow, _Digits));

   if(!HTF2.isValid) return;

   // HTF2 Swing High zone
   DrawHTFRect("ICC_HTF2_SH", HTF2.swingHigh, HTF2.swingHigh - 30 * point,
               HTF2.trend == TREND_BULLISH ? HTF_BullZone : HTF_BearZone,
               EnumToString(HTF2.timeframe) + " SH: " + DoubleToString(HTF2.swingHigh, _Digits));

   // HTF2 Swing Low zone
   DrawHTFRect("ICC_HTF2_SL", HTF2.swingLow + 30 * point, HTF2.swingLow,
               HTF2.trend == TREND_BEARISH ? HTF_BearZone : HTF_BullZone,
               EnumToString(HTF2.timeframe) + " SL: " + DoubleToString(HTF2.swingLow, _Digits));
  }

//+------------------------------------------------------------------+
//| Draw a horizontal zone rectangle                                 |
//+------------------------------------------------------------------+
void DrawHTFRect(string name, double priceTop, double priceBot, color clr, string tooltip)
  {
   datetime t1 = iTime(_Symbol, _Period, Bars(_Symbol, _Period) - 1);
   datetime t2 = iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period) * 20;

   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, priceTop, t2, priceBot);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, tooltip);

   // Label
   string lblName = name + "_LBL";
   ObjectDelete(0, lblName);
   ObjectCreate(0, lblName, OBJ_TEXT, 0, t2, (priceTop + priceBot) / 2.0);
   ObjectSetString (0, lblName, OBJPROP_TEXT, tooltip);
   ObjectSetInteger(0, lblName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, lblName, OBJPROP_FONTSIZE, 7);
  }

//+------------------------------------------------------------------+
//| AUTO-CONFIGURE per timeframe                                     |
//+------------------------------------------------------------------+
void AutoConfigure()
  {
   ENUM_TIMEFRAMES tf = _Period;

   if(!AutoSettings)
     {
      SwingLookback    = SwingLookback_In;
      CorrectionMinPct = CorrMinPct_In;
      CorrectionMaxPct = CorrMaxPct_In;
      RR_Ratio         = RR_Ratio_In;
      SL_Buffer_Points = SL_Buffer_In;
      TrailingStart_Pts= TrailingStart_In;
      TrailingStep_Pts = TrailingStep_In;
      BreakEvenAt_Pts  = BreakEvenAt_In;
      BreakEvenProfit  = BreakEvenProfit_In;
      ActiveProfile    = "MANUAL";
      ConfigureMTF();
      return;
     }

   if(tf == PERIOD_M5)
     {
      SwingLookback=3; CorrectionMinPct=25.0; CorrectionMaxPct=65.0;
      RR_Ratio=1.2; SL_Buffer_Points=20;
      TrailingStart_Pts=80; TrailingStep_Pts=40;
      BreakEvenAt_Pts=60; BreakEvenProfit=5;
      ActiveProfile="M5 SCALP";
     }
   else if(tf == PERIOD_M15)
     {
      SwingLookback=3; CorrectionMinPct=30.0; CorrectionMaxPct=70.0;
      RR_Ratio=1.5; SL_Buffer_Points=30;
      TrailingStart_Pts=120; TrailingStep_Pts=60;
      BreakEvenAt_Pts=100; BreakEvenProfit=8;
      ActiveProfile="M15 SCALP";
     }
   else if(tf == PERIOD_H1)
     {
      SwingLookback=5; CorrectionMinPct=30.0; CorrectionMaxPct=79.0;
      RR_Ratio=2.0; SL_Buffer_Points=50;
      TrailingStart_Pts=200; TrailingStep_Pts=100;
      BreakEvenAt_Pts=150; BreakEvenProfit=10;
      ActiveProfile="H1 INTRADAY";
     }
   else if(tf == PERIOD_H4)
     {
      SwingLookback=7; CorrectionMinPct=38.0; CorrectionMaxPct=79.0;
      RR_Ratio=3.0; SL_Buffer_Points=100;
      TrailingStart_Pts=400; TrailingStep_Pts=200;
      BreakEvenAt_Pts=300; BreakEvenProfit=20;
      ActiveProfile="H4 SWING";
     }
   else if(tf == PERIOD_D1)
     {
      SwingLookback=10; CorrectionMinPct=38.0; CorrectionMaxPct=79.0;
      RR_Ratio=3.5; SL_Buffer_Points=200;
      TrailingStart_Pts=800; TrailingStep_Pts=400;
      BreakEvenAt_Pts=600; BreakEvenProfit=50;
      ActiveProfile="D1 POSITION";
     }
   else
     {
      SwingLookback=SwingLookback_In; CorrectionMinPct=CorrMinPct_In;
      CorrectionMaxPct=CorrMaxPct_In; RR_Ratio=RR_Ratio_In;
      SL_Buffer_Points=SL_Buffer_In;
      TrailingStart_Pts=TrailingStart_In; TrailingStep_Pts=TrailingStep_In;
      BreakEvenAt_Pts=BreakEvenAt_In; BreakEvenProfit=BreakEvenProfit_In;
      ActiveProfile="CUSTOM (" + EnumToString(tf) + ")";
     }

   Print("═══ ICC AUTO-CONFIG ═══");
   Print("Profile: ", ActiveProfile, " | TF: ", EnumToString(tf));
   Print("Swing: ", SwingLookback, " | Corr: ", CorrectionMinPct, "-", CorrectionMaxPct,
         "% | RR: ", RR_Ratio, " | SL: ", SL_Buffer_Points, " pts");

   // Configure MTF after TF settings
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

   symInfo.Name(_Symbol);
   symInfo.Refresh();

   ArrayResize(swingHighs, 100);
   ArrayResize(swingLows, 100);
   ArrayResize(swingHighBars, 100);
   ArrayResize(swingLowBars, 100);

   lastTimeframe = _Period;
   AutoConfigure();

   // Initial MTF scan
   EvaluateMTFConfluence();

   Print("ICC Strategy EA v3.0 initialized | Profile: ", ActiveProfile,
         " | MTF: ", UseMTF ? "ON" : "OFF");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "ICC_");
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   // SL/TP monitor — every tick
   MonitorSLTP();
   ManagePositions();

   // Timeframe change detection
   if(_Period != lastTimeframe)
     {
      Print("⚙ TF changed: ", EnumToString(lastTimeframe), " → ", EnumToString(_Period));
      lastTimeframe = _Period;
      ResetState();
      AutoConfigure();
      EvaluateMTFConfluence();
      SendAlert("⚙ ICC reconfigured → " + ActiveProfile +
                " | HTF1: " + EnumToString(HTF1.timeframe));
     }

   // New bar processing
   if(!IsNewBar()) return;

   symInfo.Refresh();

   if(UseSessionFilter && !IsWithinSession()) return;

   // Refresh MTF analysis every new bar
   EvaluateMTFConfluence();

   // Entry TF analysis
   DetectSwingPoints();
   DetermineMarketStructure();
   IdentifyICCPhases();
   CheckEntrySignals();

   if(ShowDashboard) UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| MONITOR SL/TP — auto-close on every tick                         |
//+------------------------------------------------------------------+
void MonitorSLTP()
  {
   symInfo.Refresh();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))      continue;
      if(posInfo.Magic() != MagicNumber) continue;
      if(posInfo.Symbol() != _Symbol)    continue;

      ulong  ticket    = posInfo.Ticket();
      double openPrice = posInfo.PriceOpen();
      double sl        = posInfo.StopLoss();
      double tp        = posInfo.TakeProfit();
      double point     = symInfo.Point();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
         double bid = symInfo.Bid();
         if(tp > 0 && bid >= tp)
           {
            if(trade.PositionClose(ticket))
               SendAlertForced(StringFormat(
                  "✅ BUY TP HIT | %s %s\nEntry: %s → %s | +%.0f pts",
                  _Symbol, ActiveProfile,
                  DoubleToString(openPrice,_Digits), DoubleToString(bid,_Digits),
                  (bid-openPrice)/point));
           }
         else if(sl > 0 && bid <= sl)
           {
            if(trade.PositionClose(ticket))
               SendAlertForced(StringFormat(
                  "🛑 BUY SL HIT | %s %s\nEntry: %s → %s | -%.0f pts",
                  _Symbol, ActiveProfile,
                  DoubleToString(openPrice,_Digits), DoubleToString(bid,_Digits),
                  (openPrice-bid)/point));
           }
        }

      if(posInfo.PositionType() == POSITION_TYPE_SELL)
        {
         double ask = symInfo.Ask();
         if(tp > 0 && ask <= tp)
           {
            if(trade.PositionClose(ticket))
               SendAlertForced(StringFormat(
                  "✅ SELL TP HIT | %s %s\nEntry: %s → %s | +%.0f pts",
                  _Symbol, ActiveProfile,
                  DoubleToString(openPrice,_Digits), DoubleToString(ask,_Digits),
                  (openPrice-ask)/point));
           }
         else if(sl > 0 && ask >= sl)
           {
            if(trade.PositionClose(ticket))
               SendAlertForced(StringFormat(
                  "🛑 SELL SL HIT | %s %s\nEntry: %s → %s | -%.0f pts",
                  _Symbol, ActiveProfile,
                  DoubleToString(openPrice,_Digits), DoubleToString(ask,_Digits),
                  (ask-openPrice)/point));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Reset state on TF change                                         |
//+------------------------------------------------------------------+
void ResetState()
  {
   currentTrend=TREND_NONE; currentPhase=PHASE_NONE; previousTrend=TREND_NONE;
   swingHighCount=0; swingLowCount=0;
   indicationHigh=0; indicationLow=0;
   correctionHigh=0; correctionLow=0;
   lastSwingHigh=0; lastSwingLow=0;
   prevSwingHigh=0; prevSwingLow=0;
   buySignalFired=false; sellSignalFired=false;
   lastAlertBar=0;
   ObjectsDeleteAll(0, "ICC_");
  }

//+------------------------------------------------------------------+
//| Detect Swing Points (entry TF)                                   |
//+------------------------------------------------------------------+
void DetectSwingPoints()
  {
   int bars = Bars(_Symbol, _Period);
   if(bars < SwingLookback * 2 + 1) return;

   double highs[], lows[];
   ArrayResize(highs, SwingLookback*2+1);
   ArrayResize(lows,  SwingLookback*2+1);
   int checkBar = SwingLookback;

   if(CopyHigh(_Symbol,_Period,1,SwingLookback*2+1,highs)<=0) return;
   if(CopyLow (_Symbol,_Period,1,SwingLookback*2+1,lows) <=0) return;

   // Swing High
   bool isSH = true;
   for(int i=0; i<SwingLookback*2+1; i++)
     { if(i==checkBar) continue; if(highs[i]>=highs[checkBar]){isSH=false;break;} }
   if(isSH && swingHighCount<100)
      if(swingHighCount==0 || swingHighs[swingHighCount-1]!=highs[checkBar])
        {
         swingHighs[swingHighCount]=highs[checkBar];
         swingHighBars[swingHighCount]=checkBar+1;
         swingHighCount++;
         prevSwingHigh=lastSwingHigh; lastSwingHigh=highs[checkBar];
         if(ShowSwingPoints) DrawSwingPoint(true,highs[checkBar],checkBar+1);
        }

   // Swing Low
   bool isSL = true;
   for(int i=0; i<SwingLookback*2+1; i++)
     { if(i==checkBar) continue; if(lows[i]<=lows[checkBar]){isSL=false;break;} }
   if(isSL && swingLowCount<100)
      if(swingLowCount==0 || swingLows[swingLowCount-1]!=lows[checkBar])
        {
         swingLows[swingLowCount]=lows[checkBar];
         swingLowBars[swingLowCount]=checkBar+1;
         swingLowCount++;
         prevSwingLow=lastSwingLow; lastSwingLow=lows[checkBar];
         if(ShowSwingPoints) DrawSwingPoint(false,lows[checkBar],checkBar+1);
        }

   if(swingHighCount>50) TrimSwingArray(swingHighs,swingHighBars,swingHighCount);
   if(swingLowCount>50)  TrimSwingArray(swingLows, swingLowBars, swingLowCount);
  }

//+------------------------------------------------------------------+
//| Market Structure                                                 |
//+------------------------------------------------------------------+
void DetermineMarketStructure()
  {
   if(swingHighCount<2 || swingLowCount<2) return;
   previousTrend = currentTrend;
   double sh1=swingHighs[swingHighCount-1], sh2=swingHighs[swingHighCount-2];
   double sl1=swingLows[swingLowCount-1],   sl2=swingLows[swingLowCount-2];
   if(sh1>sh2 && sl1>sl2)      currentTrend=TREND_BULLISH;
   else if(sl1<sl2 && sh1<sh2) currentTrend=TREND_BEARISH;
  }

//+------------------------------------------------------------------+
//| ICC Phase Detection                                              |
//+------------------------------------------------------------------+
void IdentifyICCPhases()
  {
   if(swingHighCount<2 || swingLowCount<2) return;

   double close[];
   if(CopyClose(_Symbol,_Period,0,3,close)<3) return;
   double cc = close[2];

   // ═══ BULLISH ═══
   if(currentTrend==TREND_BULLISH)
     {
      double sh1=swingHighs[swingHighCount-1], sh2=swingHighs[swingHighCount-2];
      double sl1=swingLows[swingLowCount-1];

      if(sh1>sh2 && currentPhase!=PHASE_CORRECTION && currentPhase!=PHASE_CONTINUATION)
        {
         currentPhase=PHASE_INDICATION; indicationHigh=sh1; indicationLow=sl1;
         buySignalFired=false;
         if(ShowPhaseLabels) DrawPhaseLabel("Indication▲",indicationHigh,BullColor);
         SendAlert("ICC INDICATION (Bull): HH @ "+DoubleToString(indicationHigh,_Digits));
        }

      if(currentPhase==PHASE_INDICATION && cc<indicationHigh)
        {
         double ms=indicationHigh-indicationLow;
         double pp=((indicationHigh-cc)/ms)*100.0;
         if(pp>=CorrectionMinPct && pp<=CorrectionMaxPct)
           {
            currentPhase=PHASE_CORRECTION; correctionLow=cc; correctionHigh=indicationHigh;
            if(ShowPhaseLabels) DrawPhaseLabel("Correction▲",correctionLow,CorrColor);
            SendAlert("ICC CORRECTION (Bull): "+DoubleToString(pp,1)+"%");
           }
         if(currentPhase==PHASE_CORRECTION && cc<correctionLow)
           {
            double np=((indicationHigh-cc)/ms)*100.0;
            if(np<=CorrectionMaxPct) correctionLow=cc;
            else { currentPhase=PHASE_NONE; SendAlert("ICC INVALIDATED: Too deep"); }
           }
        }

      if(currentPhase==PHASE_CORRECTION)
        {
         double mid=indicationLow+(indicationHigh-indicationLow)*0.5;
         if(cc>mid && cc>correctionLow && close[2]>close[1])
           {
            currentPhase=PHASE_CONTINUATION;
            if(ShowPhaseLabels) DrawPhaseLabel("CONTINUATION▲",cc,BullColor);
           }
        }
     }

   // ═══ BEARISH ═══
   if(currentTrend==TREND_BEARISH)
     {
      double sl1=swingLows[swingLowCount-1], sl2=swingLows[swingLowCount-2];
      double sh1=swingHighs[swingHighCount-1];

      if(sl1<sl2 && currentPhase!=PHASE_CORRECTION && currentPhase!=PHASE_CONTINUATION)
        {
         currentPhase=PHASE_INDICATION; indicationLow=sl1; indicationHigh=sh1;
         sellSignalFired=false;
         if(ShowPhaseLabels) DrawPhaseLabel("Indication▼",indicationLow,BearColor);
         SendAlert("ICC INDICATION (Bear): LL @ "+DoubleToString(indicationLow,_Digits));
        }

      if(currentPhase==PHASE_INDICATION && cc>indicationLow)
        {
         double ms=indicationHigh-indicationLow;
         double pp=((cc-indicationLow)/ms)*100.0;
         if(pp>=CorrectionMinPct && pp<=CorrectionMaxPct)
           {
            currentPhase=PHASE_CORRECTION; correctionHigh=cc; correctionLow=indicationLow;
            if(ShowPhaseLabels) DrawPhaseLabel("Correction▼",correctionHigh,CorrColor);
            SendAlert("ICC CORRECTION (Bear): "+DoubleToString(pp,1)+"%");
           }
         if(currentPhase==PHASE_CORRECTION && cc>correctionHigh)
           {
            double np=((cc-indicationLow)/ms)*100.0;
            if(np<=CorrectionMaxPct) correctionHigh=cc;
            else { currentPhase=PHASE_NONE; SendAlert("ICC INVALIDATED: Too deep"); }
           }
        }

      if(currentPhase==PHASE_CORRECTION)
        {
         double mid=indicationLow+(indicationHigh-indicationLow)*0.5;
         if(cc<mid && cc<correctionHigh && close[2]<close[1])
           {
            currentPhase=PHASE_CONTINUATION;
            if(ShowPhaseLabels) DrawPhaseLabel("CONTINUATION▼",cc,BearColor);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check Entry Signals — with MTF confluence gate                   |
//+------------------------------------------------------------------+
void CheckEntrySignals()
  {
   if(currentPhase!=PHASE_CONTINUATION) return;

   int currentBar = Bars(_Symbol,_Period);
   if(currentBar==lastAlertBar) return;
   if(CountOpenTrades()>=MaxOpenTrades) return;

   double ask=symInfo.Ask(), bid=symInfo.Bid(), point=symInfo.Point();

   // ═══ BULLISH ENTRY ═══
   if(currentTrend==TREND_BULLISH && !buySignalFired)
     {
      // *** MTF CONFLUENCE CHECK ***
      if(UseMTF && !mtfConfluenceBull)
        {
         if(!AllowCounterTrend)
           {
            SendAlert("🚫 ICC BUY BLOCKED — HTF not bullish\n" + mtfStatusMsg);
            buySignalFired = true; // Prevent re-alerting same setup
            currentPhase = PHASE_NONE;
            return;
           }
         else
            SendAlert("⚠️ ICC BUY — Counter-trend! HTF bearish/ranging\n" + mtfStatusMsg);
        }

      double slPrice=correctionLow-SL_Buffer_Points*point;
      double slDist=ask-slPrice;
      double tpPrice=ask+slDist*RR_Ratio;

      // RR Boost: if both HTFs aligned, increase TP by 25%
      if(UseMTF && mtfConfluenceBull && HTF2.isValid && HTF2.trend==TREND_BULLISH)
        {
         tpPrice = ask + slDist * RR_Ratio * 1.25;
         Print("MTF BOOST: Both HTFs bullish — TP extended +25%");
        }

      double lots=CalculateLotSize(slDist);

      if(lots>0)
        {
         string confluenceTag = "";
         if(UseMTF)
           {
            if(mtfConfluenceBull && HTF2.isValid && HTF2.trend==TREND_BULLISH)
               confluenceTag = "🟢🟢 FULL CONFLUENCE";
            else if(mtfConfluenceBull)
               confluenceTag = "🟢 HTF1 ALIGNED";
            else
               confluenceTag = "⚠️ COUNTER-TREND";
           }

         string msg = StringFormat(
            "🟢 ICC BUY — TRADE OPENED\n"
            "Symbol: %s | %s\n"
            "Entry: %s | SL: %s (%.0f pts) | TP: %s\n"
            "RR: %.1f | Lots: %.2f | Risk: %.1f%%\n"
            "MTF: %s\n%s",
            _Symbol, ActiveProfile,
            DoubleToString(ask,_Digits),
            DoubleToString(slPrice,_Digits), slDist/point,
            DoubleToString(tpPrice,_Digits),
            (tpPrice-ask)/slDist, lots, RiskPercent,
            confluenceTag, mtfStatusMsg);

         if(trade.Buy(lots,_Symbol,ask,slPrice,tpPrice,"ICC Buy "+ActiveProfile))
           {
            SendAlertForced(msg);
            buySignalFired=true; lastAlertBar=currentBar; currentPhase=PHASE_NONE;
           }
         else
            Print("BUY FAILED: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
        }
     }

   // ═══ BEARISH ENTRY ═══
   if(currentTrend==TREND_BEARISH && !sellSignalFired)
     {
      // *** MTF CONFLUENCE CHECK ***
      if(UseMTF && !mtfConfluenceBear)
        {
         if(!AllowCounterTrend)
           {
            SendAlert("🚫 ICC SELL BLOCKED — HTF not bearish\n" + mtfStatusMsg);
            sellSignalFired = true;
            currentPhase = PHASE_NONE;
            return;
           }
         else
            SendAlert("⚠️ ICC SELL — Counter-trend! HTF bullish/ranging\n" + mtfStatusMsg);
        }

      double slPrice=correctionHigh+SL_Buffer_Points*point;
      double slDist=slPrice-bid;
      double tpPrice=bid-slDist*RR_Ratio;

      if(UseMTF && mtfConfluenceBear && HTF2.isValid && HTF2.trend==TREND_BEARISH)
        {
         tpPrice = bid - slDist * RR_Ratio * 1.25;
         Print("MTF BOOST: Both HTFs bearish — TP extended +25%");
        }

      double lots=CalculateLotSize(slDist);

      if(lots>0)
        {
         string confluenceTag = "";
         if(UseMTF)
           {
            if(mtfConfluenceBear && HTF2.isValid && HTF2.trend==TREND_BEARISH)
               confluenceTag = "🔴🔴 FULL CONFLUENCE";
            else if(mtfConfluenceBear)
               confluenceTag = "🔴 HTF1 ALIGNED";
            else
               confluenceTag = "⚠️ COUNTER-TREND";
           }

         string msg = StringFormat(
            "🔴 ICC SELL — TRADE OPENED\n"
            "Symbol: %s | %s\n"
            "Entry: %s | SL: %s (%.0f pts) | TP: %s\n"
            "RR: %.1f | Lots: %.2f | Risk: %.1f%%\n"
            "MTF: %s\n%s",
            _Symbol, ActiveProfile,
            DoubleToString(bid,_Digits),
            DoubleToString(slPrice,_Digits), slDist/point,
            DoubleToString(tpPrice,_Digits),
            (bid-tpPrice)/slDist, lots, RiskPercent,
            confluenceTag, mtfStatusMsg);

         if(trade.Sell(lots,_Symbol,bid,slPrice,tpPrice,"ICC Sell "+ActiveProfile))
           {
            SendAlertForced(msg);
            sellSignalFired=true; lastAlertBar=currentBar; currentPhase=PHASE_NONE;
           }
         else
            Print("SELL FAILED: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| Position Management — Trailing, Break-Even, Exit Warnings        |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(!posInfo.SelectByIndex(i))      continue;
      if(posInfo.Magic()!=MagicNumber)   continue;
      if(posInfo.Symbol()!=_Symbol)      continue;

      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss(), tp=posInfo.TakeProfit();
      double point=symInfo.Point();
      ulong ticket=posInfo.Ticket();

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        {
         double bid=symInfo.Bid(), pp=(bid-op)/point;
         if(UseBreakEven && pp>=BreakEvenAt_Pts)
           { double ns=op+BreakEvenProfit*point;
             if(sl<ns){trade.PositionModify(ticket,ns,tp);
               SendAlert("🔒 BUY BE → "+DoubleToString(ns,_Digits));} }
         if(UseTrailingStop && pp>=TrailingStart_Pts)
           { double ts=bid-TrailingStep_Pts*point;
             if(ts>sl) trade.PositionModify(ticket,ts,tp); }
         if(currentTrend==TREND_BEARISH && previousTrend==TREND_BULLISH)
            SendAlert("⚠️ EXIT WARN (BUY): Structure → BEARISH | "+mtfStatusMsg);
        }

      if(posInfo.PositionType()==POSITION_TYPE_SELL)
        {
         double ask=symInfo.Ask(), pp=(op-ask)/point;
         if(UseBreakEven && pp>=BreakEvenAt_Pts)
           { double ns=op-BreakEvenProfit*point;
             if(sl>ns||sl==0){trade.PositionModify(ticket,ns,tp);
               SendAlert("🔒 SELL BE → "+DoubleToString(ns,_Digits));} }
         if(UseTrailingStop && pp>=TrailingStart_Pts)
           { double ts=ask+TrailingStep_Pts*point;
             if(ts<sl||sl==0) trade.PositionModify(ticket,ts,tp); }
         if(currentTrend==TREND_BULLISH && previousTrend==TREND_BEARISH)
            SendAlert("⚠️ EXIT WARN (SELL): Structure → BULLISH | "+mtfStatusMsg);
        }
     }
  }

//+------------------------------------------------------------------+
//| Lot Size Calculation                                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDist)
  {
   if(FixedLots>0)    return NormalizeLots(FixedLots);
   if(slDist<=0)      return 0;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double risk=bal*RiskPercent/100.0;
   double tv=symInfo.TickValue(), ts=symInfo.TickSize();
   if(tv<=0||ts<=0) return symInfo.LotsMin();
   return NormalizeLots(risk/((slDist/ts)*tv));
  }

double NormalizeLots(double lots)
  {
   double mn=symInfo.LotsMin(), mx=symInfo.LotsMax(), st=symInfo.LotsStep();
   lots=MathMax(lots,mn); lots=MathMin(lots,mx);
   lots=MathFloor(lots/st)*st;
   return NormalizeDouble(lots,2);
  }

int CountOpenTrades()
  { int c=0;
    for(int i=PositionsTotal()-1;i>=0;i--)
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

//+------------------------------------------------------------------+
//| Alert Functions                                                  |
//+------------------------------------------------------------------+
void SendAlert(string m)
  { if(TimeCurrent()-lastAlertTime<60) return;
    DispatchAlert(m); lastAlertTime=TimeCurrent(); }

void SendAlertForced(string m)
  { DispatchAlert(m); lastAlertTime=TimeCurrent(); }

void DispatchAlert(string m)
  { Print("ICC: ",m);
    if(AlertPopup) Alert(m);
    if(AlertPush)  SendNotification(m);
    if(AlertEmail) SendMail("ICC - "+_Symbol,m);
    if(AlertSound) PlaySound(AlertSoundFile); }

//+------------------------------------------------------------------+
//| Drawing Functions                                                |
//+------------------------------------------------------------------+
void DrawSwingPoint(bool isH, double price, int shift)
  { datetime t=iTime(_Symbol,_Period,shift);
    string n="ICC_SW_"+(isH?"H_":"L_")+TimeToString(t);
    ObjectDelete(0,n);
    ObjectCreate(0,n,OBJ_ARROW,0,t,price);
    ObjectSetInteger(0,n,OBJPROP_ARROWCODE,isH?234:233);
    ObjectSetInteger(0,n,OBJPROP_COLOR,isH?BearColor:BullColor);
    ObjectSetInteger(0,n,OBJPROP_WIDTH,2); }

void DrawPhaseLabel(string text, double price, color clr)
  { datetime t=iTime(_Symbol,_Period,1);
    string n="ICC_PH_"+TimeToString(t)+"_"+text;
    ObjectDelete(0,n);
    ObjectCreate(0,n,OBJ_TEXT,0,t,price);
    ObjectSetString(0,n,OBJPROP_TEXT,text);
    ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
    ObjectSetInteger(0,n,OBJPROP_FONTSIZE,8); }

void TrimSwingArray(double &a[],int &b[],int &c)
  { int k=25; for(int i=0;i<k;i++){a[i]=a[c-k+i];b[i]=b[c-k+i];} c=k; }

//+------------------------------------------------------------------+
//| DASHBOARD — full status with MTF confluence                      |
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

   // MTF confluence status
   string mtfBull = mtfConfluenceBull ? "✅ YES" : "❌ NO";
   string mtfBear = mtfConfluenceBear ? "✅ YES" : "❌ NO";

   string d="";
   d+="╔════════════════════════════════════════════╗\n";
   d+="║         ICC STRATEGY EA  v3.0              ║\n";
   d+="║    Multi-Timeframe Confluence Edition      ║\n";
   d+="╠════════════════════════════════════════════╣\n";
   d+="║ Profile:     "+ActiveProfile+"\n";
   d+="║ Symbol:      "+_Symbol+" | "+EnumToString(_Period)+"\n";
   d+="║ Entry Trend: "+tStr+"\n";
   d+="║ Phase:       "+pStr+"\n";
   d+="╠═══ MULTI-TIMEFRAME CONFLUENCE ═════════════╣\n";

   if(UseMTF)
     {
      d+="║ HTF1 ("+EnumToString(HTF1.timeframe)+"): "+HTF1.trendLabel+"\n";
      if(HTF2.isValid)
         d+="║ HTF2 ("+EnumToString(HTF2.timeframe)+"): "+HTF2.trendLabel+"\n";
      d+="║ Bull Conf:   "+mtfBull+"\n";
      d+="║ Bear Conf:   "+mtfBear+"\n";
      d+="║ Mode:        "+EnumToString(MTF_Mode)+"\n";

      // Overall signal quality
      string quality = "---";
      if(currentTrend==TREND_BULLISH && mtfConfluenceBull)
        {
         if(HTF2.isValid && HTF2.trend==TREND_BULLISH)
            quality = "🟢🟢🟢 A+ SETUP (Full Confluence)";
         else
            quality = "🟢🟢 A SETUP (HTF1 Aligned)";
        }
      else if(currentTrend==TREND_BEARISH && mtfConfluenceBear)
        {
         if(HTF2.isValid && HTF2.trend==TREND_BEARISH)
            quality = "🔴🔴🔴 A+ SETUP (Full Confluence)";
         else
            quality = "🔴🔴 A SETUP (HTF1 Aligned)";
        }
      else if(currentTrend!=TREND_NONE)
         quality = "⚠️ B/C SETUP (No HTF Confluence)";

      d+="║ Signal:      "+quality+"\n";
     }
   else
      d+="║ MTF:         DISABLED\n";

   d+="╠═══ SWING & SETTINGS ═══════════════════════╣\n";
   d+="║ Swing H:     "+DoubleToString(lastSwingHigh,_Digits)+"\n";
   d+="║ Swing L:     "+DoubleToString(lastSwingLow,_Digits)+"\n";
   d+="║ Trades:      "+IntegerToString(CountOpenTrades())+" / "+
      IntegerToString(MaxOpenTrades)+"\n";
   d+="║ Lookback:    "+IntegerToString(SwingLookback)+" | Corr: "+
      DoubleToString(CorrectionMinPct,0)+"-"+DoubleToString(CorrectionMaxPct,0)+"%\n";
   d+="║ RR:          "+DoubleToString(RR_Ratio,1)+" | SL Buf: "+
      IntegerToString(SL_Buffer_Points)+" pts\n";
   d+="║ Trail:       "+IntegerToString(TrailingStart_Pts)+"/"+
      IntegerToString(TrailingStep_Pts)+" | BE: "+
      IntegerToString(BreakEvenAt_Pts)+"→+"+IntegerToString(BreakEvenProfit)+"\n";
   d+="╚════════════════════════════════════════════╝";

   Comment(d);
  }
//+------------------------------------------------------------------+
