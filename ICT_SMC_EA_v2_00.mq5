//+------------------------------------------------------------------+
//|                                            ICT_SMC_EA_v2_00.mq5   |
//|   ICT 2022 Model + Trades-by-Sci Smart Money Structure Engine    |
//|                                                                  |
//|  v2.00 — MARKET STRUCTURE ENGINE REPLACEMENT                     |
//|  ----------------------------------------------------------------|
//|  This build PRESERVES, byte-for-byte in behaviour:               |
//|     • Dashboard mechanism (extended with new SMC fields)         |
//|     • Money management  (ComputeLot / NormalizeLot)              |
//|     • Trade management  (ArmSetup / ComputeTarget / ManageArmed) |
//|     • All existing inputs                                        |
//|     • The ICC workflow state machine (IDLE->SWEPT->ARMED)        |
//|                                                                  |
//|  It REPLACES ONLY the market-structure engine — the two former   |
//|  detection routines (TryDetectSweep + TryDetectMSS_FVG_Arm) —    |
//|  with a full Smart Money Concepts engine:                        |
//|     1. Protected swing detection (internal + external)          |
//|     2. Liquidity engine (BSL/SSL, equal H/L, sweep + reclaim)   |
//|     3. Fair Value Gaps (detect, draw, fill %, pullback req.)    |
//|     4. Institutional displacement scoring (ATR/body/close/wick) |
//|     5. Dual market structure (external=direction,internal=entry)|
//|     6. Order / mitigation blocks (Trades-by-Sci enhancement)    |
//+------------------------------------------------------------------+
#property copyright "ICT 2022 Model EA + SMC Structure Engine"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//==================================================================
//  INPUTS  (ALL ORIGINAL INPUTS PRESERVED VERBATIM)
//==================================================================
input group "===== General ====="
input ulong    InpMagic            = 20220001;   // Magic number
input double   InpRiskPercent       = 1.0;         // Risk per trade (% of equity)
input bool     InpUseFixedLot       = false;       // Use fixed lot instead of % risk
input double   InpFixedLot          = 0.10;        // Fixed lot size
input int      InpMaxTradesPerDay   = 2;           // Max entries per day (ICT: 1-2 A+ setups)
input bool     InpDryRun            = true;        // DRY-RUN: detect+log+draw only, NO real orders sent
input bool     InpVerboseLog        = true;        // Diagnostic logging to Experts tab

input group "===== Timezone (broker -> New York) ====="
// ICT kill zones are defined in New York local time (EST/EDT).
// Enter the offset in hours FROM New York TO your broker server time.
// Example: broker = GMT+2 (EET), New York = GMT-5 (EST) -> offset = +7.
input int      InpBrokerToNYOffset  = 7;           // Broker hours ahead of New York
input bool     InpAutoDST           = true;        // Auto -1h during US DST (Mar-Nov)

input group "===== Kill Zones (New York local time, 24h) ====="
input bool     InpTradeLondonKZ     = true;        // London Open KZ 02:00-05:00 NY
input bool     InpTradeNYAMKZ       = true;        // New York AM KZ 08:30-11:00 NY
input bool     InpTradeSilverBullet = true;        // Silver Bullet 10:00-11:00 NY (subset of NY AM)
input int      InpLondonStartH      = 2;           // London KZ start hour
input int      InpLondonStartM      = 0;
input int      InpLondonEndH        = 5;
input int      InpLondonEndM        = 0;
input int      InpNYAMStartH        = 8;           // NY AM KZ start hour (8:30 indices)
input int      InpNYAMStartM        = 30;
input int      InpNYAMEndH          = 11;
input int      InpNYAMEndM          = 0;

input group "===== Daily Bias (HTF) ====="
input bool     InpUseAutoBias       = true;        // Auto bias from D1 structure + PD equilibrium
input int      InpManualBias        = 0;           // Manual bias if auto off: 1=long,-1=short,0=both

input group "===== Liquidity Sweep ====="
input int      InpSwingLookback     = 12;          // Bars to define local swing high/low pool
input bool     InpUsePDHPDL         = true;        // Also use Previous Day High/Low as liquidity
input double   InpSweepMinPips      = 1.0;         // Min penetration beyond level to count as raid

input group "===== Displacement / MSS / FVG ====="
input int      InpMSSLookback       = 6;           // Bars to define the structure point MSS must break
input double   InpMinDisplacePips   = 8.0;         // Min displacement candle range (pips)
input double   InpMinFVGPips        = 1.0;         // Min Fair Value Gap size (pips)
input int      InpSetupExpiryBars   = 12;          // Cancel setup if not filled within N bars

input group "===== OTE / Entry (ICT Fibonacci) ====="
// Anchored: sweep wick = 1.0 (100%), displacement extreme = 0.0 (0%)
input double   InpOTE_Start         = 0.62;        // OTE zone start
input double   InpOTE_Optimal       = 0.705;       // OTE sweet spot (mean threshold)
input double   InpOTE_End           = 0.79;        // OTE zone end
input bool     InpEntryAtOptimal    = true;        // Limit at 0.705 (else fill anywhere in 0.62-0.79 zone)
input bool     InpRequireFVGoverlap = true;        // OTE level must sit inside the displacement FVG

input group "===== Stops & Targets ====="
input double   InpStopBufferPips    = 2.0;         // Extra buffer beyond sweep wick for SL
input int      InpTargetMode        = 0;           // 0=Opposite liquidity(ERL), 1=RR multiple, 2=Std-Dev
input double   InpRRMultiple        = 3.0;         // RR target if mode=1 (ICT default ~1:3)
input double   InpStdDevProjection  = -2.0;        // Std-dev target if mode=2 (-0.27,-0.62,-1,-2)

input group "===== Dashboard ====="
input bool     InpShowDashboard     = true;        // On-chart status panel

//==================================================================
//  NEW INPUTS  — SMC MARKET STRUCTURE ENGINE (all thresholds tunable)
//==================================================================
input group "===== SMC: Protected Swings / Structure ====="
input int      InpIntSwingStrength  = 2;           // Fractal strength for INTERNAL swings (bars each side)
input int      InpExtSwingStrength  = 4;           // Fractal strength for EXTERNAL swings (bars each side)
input int      InpStructLookback    = 300;         // Bars scanned to locate protected swings
input bool     InpBOSUseClose       = true;        // BOS requires BODY CLOSE beyond swing (else wick)
input bool     InpExtTrendControlsDir  = true;     // EXTERNAL trend gates trade DIRECTION
input bool     InpIntTrendControlsEntry= true;     // INTERNAL BOS gates ENTRY trigger

input group "===== SMC: Liquidity Engine ====="
input int      InpLiqLookback       = 120;         // Bars scanned for liquidity pools / equal levels
input double   InpEqualLevelTolPips = 2.0;         // Tolerance for equal highs / equal lows (pips)
input bool     InpRequireReclaim    = true;        // Require liquidity RECLAIM after the sweep
input int      InpReclaimBars       = 3;           // Bars allowed for the reclaim to complete

input group "===== SMC: Fair Value Gaps ====="
input bool     InpDrawFVG           = true;        // Draw detected FVGs on the chart
input int      InpFVGScanBars       = 120;         // Bars scanned each update for new FVGs
input int      InpMaxTrackedFVG     = 30;          // Max FVGs held in memory (oldest dropped)
input double   InpFVGFillInvalidate = 100.0;       // Fill percent at which an FVG is retired (0..100)
input bool     InpRequireFVGpullback= true;        // Entry MUST pull back into an active FVG
input color    InpFVGBullColor      = clrTeal;     // Bullish FVG fill colour
input color    InpFVGBearColor      = clrMaroon;   // Bearish FVG fill colour

input group "===== SMC: Institutional Displacement ====="
input int      InpDispATRPeriod     = 14;          // ATR period for displacement normalisation
input double   InpDispATRMult       = 1.5;         // Range >= ATR*mult scores full ATR points
input double   InpDispMinBodyPct    = 0.50;        // Min body/range for a clean displacement
input double   InpDispMinCloseStr   = 0.60;        // Min closing strength (close near extreme)
input double   InpDispMaxWickRatio  = 1.00;        // Max opposing-wick/body ratio tolerated
input double   InpDispMinScore      = 60.0;        // Reject displacements scoring below this (0..100)

input group "===== SMC: Order / Mitigation Blocks ====="
input bool     InpUseOrderBlocks    = true;        // Enable order-block detection & requirement
input bool     InpRequireOBoverlap  = true;        // Entry MUST sit inside an unmitigated OB
input int      InpOBScanBack        = 8;           // Bars searched back from displacement for the OB
input int      InpMaxTrackedOB      = 30;          // Max order blocks held in memory
input bool     InpOBMitigateOnClose = true;        // OB invalidated on BODY close through (else wick)
input bool     InpDrawOB            = true;        // Draw order blocks on the chart
input color    InpOBBullColor       = clrDarkGreen;// Bullish OB colour
input color    InpOBBearColor       = clrDarkRed;  // Bearish OB colour

//==================================================================
//  STATE  (ORIGINAL STATE PRESERVED)
//==================================================================
enum ICT_STATE { ST_IDLE, ST_SWEPT, ST_ARMED };

ICT_STATE g_state          = ST_IDLE;
int       g_dailyBias      = 0;      // 1 long, -1 short
datetime  g_lastBarTime    = 0;
datetime  g_dayStamp       = 0;
int       g_tradesToday     = 0;

// Sweep / setup memory
int       g_setupDir        = 0;     // intended trade direction after sweep (opposite to raid)
double    g_sweepWick       = 0.0;   // extreme of the sweep (fib 100%)
double    g_dispExtreme     = 0.0;   // displacement extreme (fib 0%)
double    g_fvgTop          = 0.0;
double    g_fvgBot          = 0.0;
int       g_setupBar        = 0;     // bar index (count) when MSS confirmed
datetime  g_setupTime       = 0;
double    g_oteEntry        = 0.0;
double    g_oteSL           = 0.0;
double    g_oteTP           = 0.0;

double    g_pip             = 0.0;   // pip size in price
long      g_digits          = 0;

//==================================================================
//  NEW STATE  — SMC ENGINE
//==================================================================
// --- Structure / protected swings ---
double    g_extProtHigh     = 0.0;   // external protected high (BSL reference)
double    g_extProtLow      = 0.0;   // external protected low  (SSL reference)
datetime  g_extProtHighTime = 0;
datetime  g_extProtLowTime  = 0;
int       g_extTrend        = 0;     // 1 up / -1 down / 0 none (controls DIRECTION)
double    g_intProtHigh     = 0.0;   // internal protected high
double    g_intProtLow      = 0.0;   // internal protected low
int       g_intTrend        = 0;     // 1 up / -1 down / 0 none (controls ENTRY)

// --- Liquidity ---
string    g_liqStatus       = "none";// human-readable liquidity state for dashboard
double    g_sweptLevel      = 0.0;   // the liquidity level that was raided
int       g_sweptSide       = 0;     // 1 = buy-side swept, -1 = sell-side swept

// --- Displacement ---
double    g_lastDispScore   = 0.0;   // most recent displacement score (dashboard)

// --- ATR handle ---
int       g_atrHandle       = INVALID_HANDLE;
double    g_atr             = 0.0;

// --- Fair Value Gaps ---
struct SFVG
{
   double   top;        // upper edge
   double   bot;        // lower edge
   datetime time;       // middle-candle time (unique key)
   int      dir;        // 1 bullish / -1 bearish
   double   fillPct;    // max fill percentage seen (0..100)
   bool     active;     // still tradable
   string   obj;        // chart object name
};
SFVG      g_fvg[];

// --- Order / Mitigation Blocks ---
struct SOB
{
   double   top;
   double   bot;
   datetime time;
   int      dir;        // 1 bullish OB / -1 bearish OB
   bool     mitigated;  // price has returned into the block
   bool     active;     // not invalidated by an opposing close-through
   string   obj;
};
SOB       g_ob[];

//==================================================================
//  INIT   (original + ATR handle)
//==================================================================
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(20);

   g_digits = (long)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   // pip = 10 points on 5/3-digit symbols, else 1 point
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_pip = (g_digits == 5 || g_digits == 3) ? point * 10.0 : point;

   // NEW: ATR handle for displacement normalisation
   g_atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpDispATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
      Log("WARNING: ATR handle failed to initialise; displacement ATR score will be 0.");

   Log("ICT+SMC EA v2.00 initialised. Symbol="+_Symbol+
       "  pip="+DoubleToString(g_pip,(int)g_digits)+
       "  ExecTF="+EnumToString((ENUM_TIMEFRAMES)Period())+
       "  MODE="+(InpDryRun ? "*** DRY-RUN (no live orders) ***" : "LIVE (real orders)"));
   if(InpDryRun)
      Log("DRY-RUN ACTIVE: setups will be detected, logged and drawn, but NO BuyLimit/SellLimit is sent to the broker.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   // Original dashboard cleanup + NEW FVG/OB object cleanup
   ObjectsDeleteAll(0, "ICTDB_");
   ObjectsDeleteAll(0, "ICTFVG_");
   ObjectsDeleteAll(0, "ICTOB_");
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
}

//==================================================================
//  MAIN   (original flow + one new call: MSE_Update)
//==================================================================
void OnTick()
{
   // ---- New-bar gate on execution timeframe ----
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == g_lastBarTime) { if(InpShowDashboard) DrawDashboard(); return; }
   g_lastBarTime = t;

   RollDailyCounters();

   // ---- NEW: refresh the Smart Money structure engine every bar ----
   MSE_Update();

   // ---- 1. Daily bias (must exist first) ----
   g_dailyBias = InpUseAutoBias ? ComputeDailyBias() : InpManualBias;

   // ---- Manage / expire existing setup ----
   if(g_state == ST_ARMED)
   {
      ManageArmed();
      if(InpShowDashboard) DrawDashboard();
      return;
   }

   // ---- 2. Kill zone hard filter ----
   if(!InKillZone())
   {
      if(g_state != ST_IDLE) { Log("Outside kill zone -> setup reset."); ResetSetup(); }
      if(InpShowDashboard) DrawDashboard();
      return;
   }

   // ---- Position cap ----
   if(HasOpenPosition() || g_tradesToday >= InpMaxTradesPerDay)
   {
      if(InpShowDashboard) DrawDashboard();
      return;
   }

   // ---- State machine (ICC workflow — UNCHANGED skeleton) ----
   switch(g_state)
   {
      case ST_IDLE:  TryDetectSweep();          break;   // INDICATION
      case ST_SWEPT: TryDetectMSS_FVG_Arm();    break;   // CORRECTION -> arm CONTINUATION
      default: break;
   }

   if(InpShowDashboard) DrawDashboard();
}

//==================================================================
//  1. DAILY BIAS  (HTF draw on liquidity + PD equilibrium) — UNCHANGED
//==================================================================
int ComputeDailyBias()
{
   // Previous day range
   double pdh = iHigh(_Symbol, PERIOD_D1, 1);
   double pdl = iLow (_Symbol, PERIOD_D1, 1);
   if(pdh <= 0 || pdl <= 0) return 0;
   double eq  = (pdh + pdl) / 2.0;                 // equilibrium (50%)
   double px  = iClose(_Symbol, PERIOD_CURRENT, 1);

   // D1 structure: previous 3 daily candles for HH/HL vs LH/LL
   double h1=iHigh(_Symbol,PERIOD_D1,1), h2=iHigh(_Symbol,PERIOD_D1,2);
   double l1=iLow (_Symbol,PERIOD_D1,1), l2=iLow (_Symbol,PERIOD_D1,2);

   int structBias = 0;
   if(h1 > h2 && l1 > l2)      structBias =  1;    // higher high & higher low
   else if(h1 < h2 && l1 < l2) structBias = -1;    // lower high & lower low

   // Premium/discount: below equilibrium = discount (favour longs), above = premium
   int pdBias = (px < eq) ? 1 : (px > eq ? -1 : 0);

   // Bias confirmed only when HTF structure and PD position agree.
   if(structBias != 0 && structBias == pdBias) return structBias;

   // If structure clear but price at other extreme, defer to structure (draw on liquidity)
   if(structBias != 0) return structBias;
   return 0;                                       // no clean bias -> stand aside
}

//==================================================================
//  2. KILL ZONE TIME FILTER  (New York local time) — UNCHANGED
//==================================================================
bool InKillZone()
{
   MqlDateTime ny;
   TimeToStruct(NewYorkTime(), ny);
   int cur = ny.hour * 60 + ny.min;

   // Silver Bullet 10:00-11:00 (subset inside NY AM)
   if(InpTradeSilverBullet)
   {
      int sbS = 10*60, sbE = 11*60;
      if(cur >= sbS && cur < sbE) return true;
   }
   if(InpTradeLondonKZ)
   {
      int s = InpLondonStartH*60 + InpLondonStartM;
      int e = InpLondonEndH*60   + InpLondonEndM;
      if(cur >= s && cur < e) return true;
   }
   if(InpTradeNYAMKZ)
   {
      int s = InpNYAMStartH*60 + InpNYAMStartM;
      int e = InpNYAMEndH*60   + InpNYAMEndM;
      if(cur >= s && cur < e) return true;
   }
   return false;
}

datetime NewYorkTime()
{
   int off = InpBrokerToNYOffset;                  // broker hours ahead of NY
   if(InpAutoDST && IsUS_DST(TimeCurrent())) off -= 1;
   return TimeCurrent() - off * 3600;
}

// Rough US DST: 2nd Sunday March -> 1st Sunday November
bool IsUS_DST(datetime srv)
{
   MqlDateTime d; TimeToStruct(srv, d);
   int m = d.mon;
   if(m > 3 && m < 11) return true;
   if(m < 3 || m > 11) return false;
   // March: DST after 2nd Sunday; November: before 1st Sunday (approx by day-of-month)
   if(m == 3)  return (d.day >= 8 && d.day <= 14) ? (d.day_of_week >= 0) : (d.day > 14);
   if(m == 11) return (d.day < 7);
   return false;
}

//==================================================================
//==================================================================
//   NEW SMART MONEY STRUCTURE ENGINE (MSE_*)                       
//   Replaces the former TryDetectSweep body-logic + MSS detection. 
//   Everything below is modular; each concern is its own function. 
//==================================================================
//==================================================================

//------------------------------------------------------------------
//  MSE_Update — master per-bar refresh. Called once each new bar.
//  Order matters: structure -> liquidity tag -> FVGs -> OBs -> draw.
//------------------------------------------------------------------
void MSE_Update()
{
   // Refresh ATR used by the displacement scorer
   double atrBuf[];
   if(g_atrHandle != INVALID_HANDLE && CopyBuffer(g_atrHandle, 0, 1, 1, atrBuf) == 1)
      g_atr = atrBuf[0];

   MSE_UpdateStructure();     // protected swings + internal/external trend
   MSE_UpdateFVGs();          // detect / age / fill-track / draw FVGs
   if(InpUseOrderBlocks)
      MSE_UpdateOrderBlocks();// detect / mitigate / draw order blocks
}

//==================================================================
//  PROTECTED SWING DETECTION  (internal + external fractals)
//==================================================================

// Strict fractal high: high[shift] greater than 'strength' bars each side.
bool IsFractalHigh(int shift, int strength)
{
   double h = iHigh(_Symbol, PERIOD_CURRENT, shift);
   for(int k = 1; k <= strength; k++)
   {
      if(iHigh(_Symbol, PERIOD_CURRENT, shift + k) >= h) return false; // left side (older)
      if(iHigh(_Symbol, PERIOD_CURRENT, shift - k) >= h) return false; // right side (newer)
   }
   return true;
}

// Strict fractal low: low[shift] lower than 'strength' bars each side.
bool IsFractalLow(int shift, int strength)
{
   double l = iLow(_Symbol, PERIOD_CURRENT, shift);
   for(int k = 1; k <= strength; k++)
   {
      if(iLow(_Symbol, PERIOD_CURRENT, shift + k) <= l) return false;
      if(iLow(_Symbol, PERIOD_CURRENT, shift - k) <= l) return false;
   }
   return true;
}

// Locate the most-recent confirmed swing high & low for a given fractal
// strength. These are, by definition, the PROTECTED swings — the levels
// whose break constitutes a Break Of Structure (BOS).
void FindProtectedSwings(int strength, double &protHigh, double &protLow,
                         datetime &protHighTime, datetime &protLowTime)
{
   protHigh = 0.0; protLow = 0.0; protHighTime = 0; protLowTime = 0;
   int maxBars = MathMin(InpStructLookback, Bars(_Symbol, PERIOD_CURRENT) - (strength + 2));
   bool haveH = false, haveL = false;

   // A fractal is only confirmed once 'strength' newer bars exist, so we
   // start scanning at shift = strength + 1 and walk back into history.
   for(int s = strength + 1; s <= maxBars && !(haveH && haveL); s++)
   {
      if(!haveH && IsFractalHigh(s, strength))
      {
         protHigh     = iHigh(_Symbol, PERIOD_CURRENT, s);
         protHighTime = iTime(_Symbol, PERIOD_CURRENT, s);
         haveH = true;
      }
      if(!haveL && IsFractalLow(s, strength))
      {
         protLow     = iLow(_Symbol, PERIOD_CURRENT, s);
         protLowTime = iTime(_Symbol, PERIOD_CURRENT, s);
         haveL = true;
      }
   }
}

//==================================================================
//  DUAL MARKET STRUCTURE  (external trend + internal trend via BOS)
//==================================================================

// Generic BOS-driven trend updater for one structural scale.
// BOS is only ever measured against a PROTECTED swing (per spec).
void UpdateTrendScale(int strength,
                      double &protHigh, double &protLow,
                      datetime &protHighTime, datetime &protLowTime,
                      int &trend)
{
   FindProtectedSwings(strength, protHigh, protLow, protHighTime, protLowTime);

   double c1  = iClose(_Symbol, PERIOD_CURRENT, 1);
   double bH  = InpBOSUseClose ? c1 : iHigh(_Symbol, PERIOD_CURRENT, 1);
   double bL  = InpBOSUseClose ? c1 : iLow (_Symbol, PERIOD_CURRENT, 1);

   // Break of the protected high => bullish BOS; protected low => bearish BOS.
   if(protHigh > 0.0 && bH > protHigh)      trend = 1;
   else if(protLow > 0.0 && bL < protLow)   trend = -1;
   // else: trend persists (no fresh protected-swing break this bar)
}

// Refresh both structural scales. External governs DIRECTION, internal ENTRY.
void MSE_UpdateStructure()
{
   UpdateTrendScale(InpExtSwingStrength,
                    g_extProtHigh, g_extProtLow,
                    g_extProtHighTime, g_extProtLowTime,
                    g_extTrend);

   datetime intHT = 0, intLT = 0;                        // internal swing times (not shown on panel)
   UpdateTrendScale(InpIntSwingStrength,
                    g_intProtHigh, g_intProtLow,
                    intHT, intLT,
                    g_intTrend);
}

//==================================================================
//  LIQUIDITY ENGINE  (BSL / SSL, equal highs & lows, sweep, reclaim)
//==================================================================

// Detect an equal-highs cluster among recent fractal highs (BSL magnet).
// Returns true and the averaged level when two highs sit within tolerance.
bool DetectEqualHighs(double &level)
{
   double tol = InpEqualLevelTolPips * g_pip;
   double first = 0.0; bool haveFirst = false;
   int str = InpExtSwingStrength;
   for(int s = str + 1; s <= InpLiqLookback; s++)
   {
      if(!IsFractalHigh(s, str)) continue;
      double h = iHigh(_Symbol, PERIOD_CURRENT, s);
      if(!haveFirst) { first = h; haveFirst = true; continue; }
      if(MathAbs(h - first) <= tol) { level = (h + first) / 2.0; return true; }
      first = h; // slide reference to the newer high
   }
   return false;
}

// Detect an equal-lows cluster among recent fractal lows (SSL magnet).
bool DetectEqualLows(double &level)
{
   double tol = InpEqualLevelTolPips * g_pip;
   double first = 0.0; bool haveFirst = false;
   int str = InpExtSwingStrength;
   for(int s = str + 1; s <= InpLiqLookback; s++)
   {
      if(!IsFractalLow(s, str)) continue;
      double l = iLow(_Symbol, PERIOD_CURRENT, s);
      if(!haveFirst) { first = l; haveFirst = true; continue; }
      if(MathAbs(l - first) <= tol) { level = (l + first) / 2.0; return true; }
      first = l;
   }
   return false;
}

// Build the buy-side liquidity level (BSL) = highest of protected high,
// equal-highs magnet, local swing pool and (optionally) PDH.
double BuildBuySideLiquidity()
{
   double lvl = g_extProtHigh;
   double eqH; if(DetectEqualHighs(eqH)) lvl = MathMax(lvl, eqH);
   double pool = iHigh(_Symbol, PERIOD_CURRENT,
                 iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSwingLookback, 2));
   lvl = MathMax(lvl, pool);
   if(InpUsePDHPDL) lvl = MathMax(lvl, iHigh(_Symbol, PERIOD_D1, 1));
   return lvl;
}

// Build the sell-side liquidity level (SSL) = lowest of protected low,
// equal-lows magnet, local swing pool and (optionally) PDL.
double BuildSellSideLiquidity()
{
   double lvl = (g_extProtLow > 0.0) ? g_extProtLow : DBL_MAX;
   double eqL; if(DetectEqualLows(eqL)) lvl = MathMin(lvl, eqL);
   double pool = iLow(_Symbol, PERIOD_CURRENT,
                 iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpSwingLookback, 2));
   lvl = MathMin(lvl, pool);
   if(InpUsePDHPDL) lvl = MathMin(lvl, iLow(_Symbol, PERIOD_D1, 1));
   if(lvl == DBL_MAX) lvl = pool;
   return lvl;
}

// A liquidity sweep = wick trades beyond the pool by >= InpSweepMinPips
// and the candle CLOSES back on the origin side (failure/rejection).
// dir = +1 tests a SELL-SIDE sweep (raid of lows -> look LONG),
// dir = -1 tests a BUY-SIDE sweep (raid of highs -> look SHORT).
bool DetectSweep(int dir, double &sweepWick, double &sweptLevel)
{
   double hi1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double lo1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double cl1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double buf = InpSweepMinPips * g_pip;

   if(dir == 1)   // sell-side raid
   {
      double ssl = BuildSellSideLiquidity();
      if(ssl > 0.0 && (lo1 < ssl - buf) && (cl1 > ssl))
      {
         sweepWick   = lo1;
         sweptLevel  = ssl;
         return true;
      }
   }
   else if(dir == -1)   // buy-side raid
   {
      double bsl = BuildBuySideLiquidity();
      if(bsl > 0.0 && (hi1 > bsl + buf) && (cl1 < bsl))
      {
         sweepWick   = hi1;
         sweptLevel  = bsl;
         return true;
      }
   }
   return false;
}

// Reclaim confirmation: after a sweep, price must trade back through the
// swept level within InpReclaimBars (close beyond the reclaim reference),
// confirming smart-money absorption before we permit a continuation.
bool ReclaimConfirmed(int dir, double sweptLevel)
{
   if(!InpRequireReclaim) return true;
   for(int s = 1; s <= InpReclaimBars; s++)
   {
      double c = iClose(_Symbol, PERIOD_CURRENT, s);
      if(dir == 1  && c > sweptLevel) return true;  // reclaimed above swept low
      if(dir == -1 && c < sweptLevel) return true;  // reclaimed below swept high
   }
   return false;
}

//==================================================================
//  INSTITUTIONAL DISPLACEMENT SCORING
//  Blends ATR expansion, body %, closing strength and wick ratio
//  into a single 0..100 score. Weak breaks are rejected downstream.
//==================================================================
double ScoreDisplacement(int shift, int dir)
{
   double o = iOpen (_Symbol, PERIOD_CURRENT, shift);
   double c = iClose(_Symbol, PERIOD_CURRENT, shift);
   double h = iHigh (_Symbol, PERIOD_CURRENT, shift);
   double l = iLow  (_Symbol, PERIOD_CURRENT, shift);

   double range = h - l;
   if(range <= 0.0) return 0.0;

   // Correct directionality is mandatory (a bull displacement must close up).
   bool dirOk = (dir == 1) ? (c > o) : (c < o);
   if(!dirOk) return 0.0;

   double body     = MathAbs(c - o);
   double bodyPct  = body / range;                                   // 0..1
   double closeStr = (dir == 1) ? (c - l) / range : (h - c) / range; // 0..1 (near extreme = strong)
   double oppWick  = (dir == 1) ? (h - c) : (c - l);                 // wick beyond the close
   double wickRat  = (body > 0.0) ? oppWick / body : 999.0;          // lower is better
   double atrFac   = (g_atr > 0.0) ? range / g_atr : 0.0;            // ATR expansion factor

   // Weighted components (sum to 100). Each is clamped to its target.
   double sBody  = MathMin(bodyPct  / MathMax(InpDispMinBodyPct , 0.01), 1.0) * 30.0;
   double sClose = MathMin(closeStr / MathMax(InpDispMinCloseStr, 0.01), 1.0) * 25.0;
   double sWick  = MathMin(InpDispMaxWickRatio / MathMax(wickRat, 0.0001), 1.0) * 15.0;
   double sATR   = MathMin(atrFac   / MathMax(InpDispATRMult   , 0.01), 1.0) * 30.0;

   double score = sBody + sClose + sWick + sATR;
   return MathMin(score, 100.0);
}

//==================================================================
//  FAIR VALUE GAP ENGINE  (detect all, draw, track fill %, retire)
//==================================================================

// Does an FVG with this middle-candle time already exist?
bool FVGExists(datetime midTime)
{
   for(int i = 0; i < ArraySize(g_fvg); i++)
      if(g_fvg[i].time == midTime) return true;
   return false;
}

// Append an FVG, dropping the oldest if we exceed the tracking cap.
void AddFVG(double top, double bot, datetime midTime, int dir)
{
   if(FVGExists(midTime)) return;
   int n = ArraySize(g_fvg);
   if(n >= InpMaxTrackedFVG)
   {
      if(g_fvg[0].obj != "") ObjectDelete(0, g_fvg[0].obj);
      ArrayRemove(g_fvg, 0, 1);
      n = ArraySize(g_fvg);
   }
   ArrayResize(g_fvg, n + 1);
   g_fvg[n].top     = top;
   g_fvg[n].bot     = bot;
   g_fvg[n].time    = midTime;
   g_fvg[n].dir     = dir;
   g_fvg[n].fillPct = 0.0;
   g_fvg[n].active  = true;
   g_fvg[n].obj     = "ICTFVG_" + IntegerToString((int)midTime);
}

// Scan the recent window for 3-candle imbalances and register new ones.
void ScanForFVGs()
{
   int maxBars = MathMin(InpFVGScanBars, Bars(_Symbol, PERIOD_CURRENT) - 4);
   for(int s = 1; s <= maxBars; s++)
   {
      // Bullish FVG: low[s] > high[s+2]  (gap across the middle candle s+1)
      double lowNear  = iLow (_Symbol, PERIOD_CURRENT, s);
      double highFar  = iHigh(_Symbol, PERIOD_CURRENT, s + 2);
      if((lowNear - highFar) / g_pip >= InpMinFVGPips)
      {
         datetime midT = iTime(_Symbol, PERIOD_CURRENT, s + 1);
         AddFVG(lowNear, highFar, midT, 1);
      }
      // Bearish FVG: high[s] < low[s+2]
      double highNear = iHigh(_Symbol, PERIOD_CURRENT, s);
      double lowFar   = iLow (_Symbol, PERIOD_CURRENT, s + 2);
      if((lowFar - highNear) / g_pip >= InpMinFVGPips)
      {
         datetime midT = iTime(_Symbol, PERIOD_CURRENT, s + 1);
         AddFVG(highNear, lowFar, midT, -1); // top=lowFar, bot=highNear
      }
   }
}

// Update fill percentage for every FVG from the last closed bar and retire
// any that have filled past the invalidation threshold.
void UpdateFVGFills()
{
   double hi1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double lo1 = iLow (_Symbol, PERIOD_CURRENT, 1);
   for(int i = 0; i < ArraySize(g_fvg); i++)
   {
      if(!g_fvg[i].active) continue;
      double span = g_fvg[i].top - g_fvg[i].bot;
      if(span <= 0.0) { g_fvg[i].active = false; continue; }

      double pct = g_fvg[i].fillPct;
      if(g_fvg[i].dir == 1)             // bullish: price fills DOWN from the top
      {
         if(lo1 < g_fvg[i].top)
         {
            double pen = g_fvg[i].top - MathMax(lo1, g_fvg[i].bot);
            pct = MathMax(pct, 100.0 * pen / span);
         }
      }
      else                             // bearish: price fills UP from the bottom
      {
         if(hi1 > g_fvg[i].bot)
         {
            double pen = MathMin(hi1, g_fvg[i].top) - g_fvg[i].bot;
            pct = MathMax(pct, 100.0 * pen / span);
         }
      }
      g_fvg[i].fillPct = pct;
      if(pct >= InpFVGFillInvalidate) g_fvg[i].active = false;
   }
}

// Draw / refresh FVG rectangles (right edge tracks the current bar).
void DrawFVGs()
{
   if(!InpDrawFVG) return;
   datetime tRight = iTime(_Symbol, PERIOD_CURRENT, 0);
   for(int i = 0; i < ArraySize(g_fvg); i++)
   {
      string nm = g_fvg[i].obj;
      if(!g_fvg[i].active)
      {
         if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
         continue;
      }
      color col = (g_fvg[i].dir == 1) ? InpFVGBullColor : InpFVGBearColor;
      if(ObjectFind(0, nm) < 0)
      {
         ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_fvg[i].time, g_fvg[i].top, tRight, g_fvg[i].bot);
         ObjectSetInteger(0, nm, OBJPROP_FILL, true);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
         ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
      }
      ObjectMove(0, nm, 0, g_fvg[i].time, g_fvg[i].top);
      ObjectMove(0, nm, 1, tRight,        g_fvg[i].bot);
   }
}

void MSE_UpdateFVGs()
{
   ScanForFVGs();
   UpdateFVGFills();
   DrawFVGs();
}

// Nearest ACTIVE FVG in the trade direction (bullish FVG for longs, bearish
// for shorts), chosen by proximity of its mid to current price. -1 if none.
int NearestActiveFVGIndex(int tradeDir)
{
   int    best = -1;
   double bestDist = DBL_MAX;
   double px = iClose(_Symbol, PERIOD_CURRENT, 1);
   int    wantDir = tradeDir; // long -> bullish FVG(1); short -> bearish FVG(-1)
   for(int i = 0; i < ArraySize(g_fvg); i++)
   {
      if(!g_fvg[i].active || g_fvg[i].dir != wantDir) continue;
      double mid = (g_fvg[i].top + g_fvg[i].bot) / 2.0;
      double d   = MathAbs(px - mid);
      if(d < bestDist) { bestDist = d; best = i; }
   }
   return best;
}

//==================================================================
//  ORDER / MITIGATION BLOCK ENGINE  (Trades-by-Sci enhancement)
//  A bullish OB = the last down-close candle before an up displacement;
//  a bearish OB = the last up-close candle before a down displacement.
//==================================================================

bool OBExists(datetime tm)
{
   for(int i = 0; i < ArraySize(g_ob); i++)
      if(g_ob[i].time == tm) return true;
   return false;
}

void AddOB(double top, double bot, datetime tm, int dir)
{
   if(OBExists(tm)) return;
   int n = ArraySize(g_ob);
   if(n >= InpMaxTrackedOB)
   {
      if(g_ob[0].obj != "") ObjectDelete(0, g_ob[0].obj);
      ArrayRemove(g_ob, 0, 1);
      n = ArraySize(g_ob);
   }
   ArrayResize(g_ob, n + 1);
   g_ob[n].top       = top;
   g_ob[n].bot       = bot;
   g_ob[n].time      = tm;
   g_ob[n].dir       = dir;
   g_ob[n].mitigated = false;
   g_ob[n].active    = true;
   g_ob[n].obj       = "ICTOB_" + IntegerToString((int)tm);
}

// Scan recent bars: when a candle scores as a valid displacement, register
// the originating order block (the last opposing-close candle before it).
void ScanForOrderBlocks()
{
   int maxBars = MathMin(InpFVGScanBars, Bars(_Symbol, PERIOD_CURRENT) - (InpOBScanBack + 3));
   for(int s = 1; s <= maxBars; s++)
   {
      // Bullish displacement at shift s -> hunt a bullish OB behind it
      if(ScoreDisplacement(s, 1) >= InpDispMinScore)
      {
         for(int k = s + 1; k <= s + InpOBScanBack; k++)
         {
            double o = iOpen(_Symbol, PERIOD_CURRENT, k);
            double c = iClose(_Symbol, PERIOD_CURRENT, k);
            if(c < o) // last down-close candle = bullish OB
            {
               AddOB(iHigh(_Symbol,PERIOD_CURRENT,k), iLow(_Symbol,PERIOD_CURRENT,k),
                     iTime(_Symbol,PERIOD_CURRENT,k), 1);
               break;
            }
         }
      }
      // Bearish displacement at shift s -> hunt a bearish OB behind it
      if(ScoreDisplacement(s, -1) >= InpDispMinScore)
      {
         for(int k = s + 1; k <= s + InpOBScanBack; k++)
         {
            double o = iOpen(_Symbol, PERIOD_CURRENT, k);
            double c = iClose(_Symbol, PERIOD_CURRENT, k);
            if(c > o) // last up-close candle = bearish OB
            {
               AddOB(iHigh(_Symbol,PERIOD_CURRENT,k), iLow(_Symbol,PERIOD_CURRENT,k),
                     iTime(_Symbol,PERIOD_CURRENT,k), -1);
               break;
            }
         }
      }
   }
}

// Flag mitigation (price returned into the block) and invalidation
// (opposing close straight through the block).
void UpdateOBMitigation()
{
   double hi1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double lo1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double cl1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   for(int i = 0; i < ArraySize(g_ob); i++)
   {
      if(!g_ob[i].active) continue;
      if(g_ob[i].dir == 1)   // bullish OB
      {
         if(lo1 <= g_ob[i].top && hi1 >= g_ob[i].bot) g_ob[i].mitigated = true; // touched
         double thru = InpOBMitigateOnClose ? cl1 : lo1;
         if(thru < g_ob[i].bot) g_ob[i].active = false; // invalidated
      }
      else                    // bearish OB
      {
         if(hi1 >= g_ob[i].bot && lo1 <= g_ob[i].top) g_ob[i].mitigated = true;
         double thru = InpOBMitigateOnClose ? cl1 : hi1;
         if(thru > g_ob[i].top) g_ob[i].active = false;
      }
   }
}

void DrawOBs()
{
   if(!InpDrawOB) return;
   datetime tRight = iTime(_Symbol, PERIOD_CURRENT, 0);
   for(int i = 0; i < ArraySize(g_ob); i++)
   {
      string nm = g_ob[i].obj;
      if(!g_ob[i].active)
      {
         if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
         continue;
      }
      color col = (g_ob[i].dir == 1) ? InpOBBullColor : InpOBBearColor;
      if(ObjectFind(0, nm) < 0)
      {
         ObjectCreate(0, nm, OBJ_RECTANGLE, 0, g_ob[i].time, g_ob[i].top, tRight, g_ob[i].bot);
         ObjectSetInteger(0, nm, OBJPROP_FILL, false);
         ObjectSetInteger(0, nm, OBJPROP_BACK, true);
         ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, nm, OBJPROP_COLOR, col);
         ObjectSetInteger(0, nm, OBJPROP_STYLE, g_ob[i].mitigated ? STYLE_DOT : STYLE_SOLID);
      }
      ObjectSetInteger(0, nm, OBJPROP_STYLE, g_ob[i].mitigated ? STYLE_DOT : STYLE_SOLID);
      ObjectMove(0, nm, 0, g_ob[i].time, g_ob[i].top);
      ObjectMove(0, nm, 1, tRight,       g_ob[i].bot);
   }
}

void MSE_UpdateOrderBlocks()
{
   ScanForOrderBlocks();
   UpdateOBMitigation();
   DrawOBs();
}

// Nearest UNMITIGATED, active OB in the trade direction. -1 if none.
int NearestUnmitigatedOBIndex(int tradeDir)
{
   int    best = -1;
   double bestDist = DBL_MAX;
   double px = iClose(_Symbol, PERIOD_CURRENT, 1);
   for(int i = 0; i < ArraySize(g_ob); i++)
   {
      if(!g_ob[i].active || g_ob[i].mitigated || g_ob[i].dir != tradeDir) continue;
      double mid = (g_ob[i].top + g_ob[i].bot) / 2.0;
      double d   = MathAbs(px - mid);
      if(d < bestDist) { bestDist = d; best = i; }
   }
   return best;
}

//==================================================================
//  CONTINUATION ENTRY ZONE BUILDER
//  Combines the required FVG and/or Order Block into a single zone that
//  the existing ArmSetup() will use verbatim (via g_fvgTop / g_fvgBot).
//  Returns false when a mandatory element is missing (setup rejected).
//==================================================================
bool BuildEntryZone(int tradeDir, double &zoneBot, double &zoneTop)
{
   bool haveFVG = false, haveOB = false;
   double fBot = 0, fTop = 0, oBot = 0, oTop = 0;

   int fi = NearestActiveFVGIndex(tradeDir);
   if(fi >= 0) { fBot = g_fvg[fi].bot; fTop = g_fvg[fi].top; haveFVG = true; }
   else if(InpRequireFVGpullback) { Log("Continuation rejected: no active FVG for pullback."); return false; }

   if(InpUseOrderBlocks && InpRequireOBoverlap)
   {
      int oi = NearestUnmitigatedOBIndex(tradeDir);
      if(oi >= 0) { oBot = g_ob[oi].bot; oTop = g_ob[oi].top; haveOB = true; }
      else { Log("Continuation rejected: no unmitigated Order Block."); return false; }
   }

   if(haveFVG && haveOB)
   {
      zoneBot = MathMax(fBot, oBot);
      zoneTop = MathMin(fTop, oTop);
      if(zoneBot >= zoneTop) { Log("Continuation rejected: FVG/OB do not overlap."); return false; }
   }
   else if(haveFVG) { zoneBot = fBot; zoneTop = fTop; }
   else if(haveOB)  { zoneBot = oBot; zoneTop = oTop; }
   else return false; // nothing mandated and nothing found -> let caller fall back

   return true;
}

//==================================================================
//==================================================================
//   ICC WORKFLOW HOOKS  (same function names & state machine role)  
//   Bodies now delegate to the new Smart Money engine above.        
//==================================================================
//==================================================================

//------------------------------------------------------------------
//  INDICATION  (ST_IDLE) — formerly a raw swing-pool sweep.
//  NOW: external trend gates direction; a liquidity sweep of BSL/SSL
//  (protected swing + equal H/L + pool + PDH/PDL) with reclaim
//  confirmation promotes the setup to ST_SWEPT.
//------------------------------------------------------------------
void TryDetectSweep()
{
   // Directional gate: external structure trend (per dual-structure spec),
   // still respecting the preserved daily-bias filter.
   int allowLong  = 1, allowShort = 1;
   if(InpExtTrendControlsDir && g_extTrend != 0)
   {
      allowLong  = (g_extTrend == 1)  ? 1 : 0;
      allowShort = (g_extTrend == -1) ? 1 : 0;
   }
   if(g_dailyBias > 0) allowShort = 0;   // daily bias veto (preserved intent)
   if(g_dailyBias < 0) allowLong  = 0;

   double wick = 0.0, level = 0.0;

   // LONG branch: sell-side liquidity raided -> reclaim -> seek longs
   if(allowLong && DetectSweep(1, wick, level) && ReclaimConfirmed(1, level))
   {
      g_setupDir   = 1;
      g_sweepWick  = wick;
      g_sweptLevel = level;
      g_sweptSide  = -1;                  // sell-side liquidity was taken
      g_liqStatus  = "SSL swept + reclaim";
      g_state      = ST_SWEPT;
      g_setupBar   = 0;
      Log(StringFormat("INDICATION: SSL raided @ %.5f (level %.5f), reclaim ok. ExtTrend=%d -> seek LONG.",
                       wick, level, g_extTrend));
      return;
   }

   // SHORT branch: buy-side liquidity raided -> reclaim -> seek shorts
   if(allowShort && DetectSweep(-1, wick, level) && ReclaimConfirmed(-1, level))
   {
      g_setupDir   = -1;
      g_sweepWick  = wick;
      g_sweptLevel = level;
      g_sweptSide  = 1;                   // buy-side liquidity was taken
      g_liqStatus  = "BSL swept + reclaim";
      g_state      = ST_SWEPT;
      g_setupBar   = 0;
      Log(StringFormat("INDICATION: BSL raided @ %.5f (level %.5f), reclaim ok. ExtTrend=%d -> seek SHORT.",
                       wick, level, g_extTrend));
      return;
   }

   g_liqStatus = "watching pools";
}

//------------------------------------------------------------------
//  CORRECTION  (ST_SWEPT) — formerly raw MSS + inline FVG.
//  NOW: requires a SCORED institutional displacement that breaks the
//  INTERNAL protected swing (internal BOS), aligned with external
//  trend, then builds the entry zone from active FVG (+/- unmitigated
//  OB) and hands off to the PRESERVED ArmSetup().
//------------------------------------------------------------------
void TryDetectMSS_FVG_Arm()
{
   g_setupBar++;
   if(g_setupBar > InpSetupExpiryBars)
   {
      Log("Correction not confirmed within expiry window -> reset.");
      ResetSetup();
      return;
   }

   // --- 1. Institutional displacement quality gate (reject weak breaks) ---
   double score = ScoreDisplacement(1, g_setupDir);
   g_lastDispScore = score;
   double range1 = (iHigh(_Symbol,PERIOD_CURRENT,1) - iLow(_Symbol,PERIOD_CURRENT,1)) / g_pip;
   if(score < InpDispMinScore || range1 < InpMinDisplacePips)
      return; // not institutional enough yet — keep waiting inside the window

   // --- 2. Internal BOS on the PROTECTED internal swing (dual structure) ---
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   bool intBOS = true;
   if(InpIntTrendControlsEntry)
   {
      if(g_setupDir == 1)
         intBOS = (g_intProtHigh > 0.0) && (c1 > g_intProtHigh); // bullish internal BOS
      else
         intBOS = (g_intProtLow  > 0.0) && (c1 < g_intProtLow);  // bearish internal BOS
   }
   if(!intBOS) { Log("Displacement ok but internal BOS not yet confirmed -> waiting."); return; }

   // --- 3. External trend must still agree with the setup direction ---
   if(InpExtTrendControlsDir && g_extTrend != 0 && g_extTrend != g_setupDir)
   {
      Log("External trend flipped against setup -> reset.");
      ResetSetup();
      return;
   }

   // --- 4. Displacement extreme = fib 0% anchor (preserved ArmSetup input) ---
   g_dispExtreme = (g_setupDir == 1) ? iHigh(_Symbol,PERIOD_CURRENT,1)
                                     : iLow (_Symbol,PERIOD_CURRENT,1);

   // --- 5. Build the entry zone from FVG (+/- OB). Fall back to the classic
   //        3-candle displacement FVG if the engine mandates nothing. ---
   double zBot = 0.0, zTop = 0.0;
   if(BuildEntryZone(g_setupDir, zBot, zTop))
   {
      g_fvgBot = zBot;
      g_fvgTop = zTop;
   }
   else
   {
      // Classic inline displacement FVG (original behaviour retained as fallback)
      if(g_setupDir == 1)
      {
         double lowMid   = iLow (_Symbol, PERIOD_CURRENT, 1);
         double highBack = iHigh(_Symbol, PERIOD_CURRENT, 3);
         if((lowMid - highBack) / g_pip < InpMinFVGPips) { Log("No valid displacement FVG -> waiting."); return; }
         g_fvgBot = highBack; g_fvgTop = lowMid;
      }
      else
      {
         double highMid = iHigh(_Symbol, PERIOD_CURRENT, 1);
         double lowBack = iLow (_Symbol, PERIOD_CURRENT, 3);
         if((lowBack - highMid) / g_pip < InpMinFVGPips) { Log("No valid displacement FVG -> waiting."); return; }
         g_fvgBot = highMid; g_fvgTop = lowBack;
      }
   }

   Log(StringFormat("CORRECTION confirmed: dir=%d dispScore=%.1f intBOS ok. Zone[%.5f-%.5f] -> arming.",
                    g_setupDir, score, g_fvgBot, g_fvgTop));

   // --- 6. Hand off to the PRESERVED continuation/entry engine ---
   ArmSetup();
}

//==================================================================
//  6. OTE ENTRY + STOP + TARGET  (arm limit order) — UNCHANGED
//==================================================================
void ArmSetup()
{
   // OTE fib: 100% = sweep wick, 0% = displacement extreme
   double lo = MathMin(g_sweepWick, g_dispExtreme);
   double hi = MathMax(g_sweepWick, g_dispExtreme);
   double dist = hi - lo;
   if(dist <= 0) { ResetSetup(); return; }

   double fibOpt = InpOTE_Optimal;   // 0.705
   double entry, sl, tp;

   if(g_setupDir == 1)
   {
      // retrace DOWN from displacement high toward sweep low
      // level = dispHigh - fib*dist
      double zoneStart = g_dispExtreme - InpOTE_Start * dist; // 0.62
      double zoneEnd   = g_dispExtreme - InpOTE_End   * dist; // 0.79
      entry = InpEntryAtOptimal ? (g_dispExtreme - fibOpt * dist)
                                : (zoneStart + zoneEnd) / 2.0;

      // require OTE inside FVG if configured
      if(InpRequireFVGoverlap && !(entry <= g_fvgTop && entry >= g_fvgBot))
      {
         // snap entry into the FVG if OTE misses it slightly, else reject
         if(entry > g_fvgTop) entry = g_fvgTop;
         else if(entry < g_fvgBot) { Log("OTE below FVG -> reject setup."); ResetSetup(); return; }
      }

      sl = g_sweepWick - InpStopBufferPips * g_pip;   // below sweep wick
      tp = ComputeTarget(1, entry, sl, dist);
   }
   else
   {
      double zoneStart = g_dispExtreme + InpOTE_Start * dist;
      double zoneEnd   = g_dispExtreme + InpOTE_End   * dist;
      entry = InpEntryAtOptimal ? (g_dispExtreme + fibOpt * dist)
                                : (zoneStart + zoneEnd) / 2.0;

      if(InpRequireFVGoverlap && !(entry <= g_fvgTop && entry >= g_fvgBot))
      {
         if(entry < g_fvgBot) entry = g_fvgBot;
         else if(entry > g_fvgTop) { Log("OTE above FVG -> reject setup."); ResetSetup(); return; }
      }

      sl = g_sweepWick + InpStopBufferPips * g_pip;   // above sweep wick
      tp = ComputeTarget(-1, entry, sl, dist);
   }

   g_oteEntry = NormalizeDouble(entry, (int)g_digits);
   g_oteSL    = NormalizeDouble(sl,    (int)g_digits);
   g_oteTP    = NormalizeDouble(tp,    (int)g_digits);

   double lots = ComputeLot(g_oteEntry, g_oteSL);
   if(lots <= 0) { Log("Lot calc <= 0 -> reject."); ResetSetup(); return; }

   double rr = MathAbs(g_oteTP-g_oteEntry)/MathMax(MathAbs(g_oteEntry-g_oteSL),g_pip);

   bool ok;
   if(InpDryRun)
   {
      // --- DRY-RUN: do NOT touch the broker. Log the setup as if armed. ---
      ok = true;
      Log(StringFormat("[DRY-RUN] Would place %s OTE limit -> entry=%.5f SL=%.5f TP=%.5f lots=%.2f (RR~%.2f). NO order sent.",
          (g_setupDir==1?"LONG":"SHORT"), g_oteEntry, g_oteSL, g_oteTP, lots, rr));
   }
   else if(g_setupDir == 1)
      ok = trade.BuyLimit(lots, g_oteEntry, _Symbol, g_oteSL, g_oteTP, ORDER_TIME_GTC, 0, "ICT2022_OTE_Long");
   else
      ok = trade.SellLimit(lots, g_oteEntry, _Symbol, g_oteSL, g_oteTP, ORDER_TIME_GTC, 0, "ICT2022_OTE_Short");

   if(ok)
   {
      g_state    = ST_ARMED;
      g_setupTime= TimeCurrent();
      Log(StringFormat("ARMED %s OTE: entry=%.5f SL=%.5f TP=%.5f lots=%.2f (RR~%.2f)%s",
          (g_setupDir==1?"LONG":"SHORT"), g_oteEntry, g_oteSL, g_oteTP, lots, rr,
          (InpDryRun?"  [DRY-RUN virtual]":"")));
   }
   else
   {
      Log("Order placement FAILED: "+trade.ResultRetcodeDescription());
      ResetSetup();
   }
}

double ComputeTarget(int dir, double entry, double sl, double dist)
{
   double risk = MathAbs(entry - sl);

   if(InpTargetMode == 1)                 // RR multiple
      return dir==1 ? entry + InpRRMultiple*risk : entry - InpRRMultiple*risk;

   if(InpTargetMode == 2)                 // Std-dev projection of displacement leg
   {
      double proj = MathAbs(InpStdDevProjection) * dist;
      return dir==1 ? g_sweepWick + proj : g_sweepWick - proj; // measured from origin
   }

   // Mode 0: opposite liquidity (external range liquidity = ERL)
   if(dir == 1)
   {
      double oppo = iHigh(_Symbol, PERIOD_CURRENT,
                    iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSwingLookback*2, 1));
      double pdh = iHigh(_Symbol, PERIOD_D1, 1);
      double tgt = MathMax(oppo, pdh);
      if(tgt <= entry) tgt = entry + InpRRMultiple*risk;   // fallback
      return tgt;
   }
   else
   {
      double oppo = iLow(_Symbol, PERIOD_CURRENT,
                    iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, InpSwingLookback*2, 1));
      double pdl = iLow(_Symbol, PERIOD_D1, 1);
      double tgt = MathMin(oppo, pdl);
      if(tgt >= entry) tgt = entry - InpRRMultiple*risk;
      return tgt;
   }
}

//==================================================================
//  MANAGE ARMED SETUP — UNCHANGED
//==================================================================
void ManageArmed()
{
   // ---- DRY-RUN: simulate the fill (no broker position will ever exist) ----
   if(InpDryRun)
   {
      double hi1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double lo1 = iLow (_Symbol, PERIOD_CURRENT, 1);
      bool virtFilled = (g_setupDir == 1) ? (lo1 <= g_oteEntry)   // price traded down into long OTE
                                          : (hi1 >= g_oteEntry);  // price traded up into short OTE
      if(virtFilled)
      {
         g_tradesToday++;
         Log(StringFormat("[DRY-RUN] Virtual OTE FILLED %s @ %.5f (SL %.5f / TP %.5f). Trades today=%d. NO real position opened.",
             (g_setupDir==1?"LONG":"SHORT"), g_oteEntry, g_oteSL, g_oteTP, g_tradesToday));
         ResetSetup();          // clears direction/levels; engine free for next setup
         return;
      }
      // not yet filled -> fall through to the same expiry rules as live
   }
   else
   {
      // ---- LIVE: if limit filled a position exists, clear pending state ----
      if(HasOpenPosition())
      {
         if(g_state == ST_ARMED)
         {
            g_tradesToday++;
            Log("OTE limit FILLED -> position live. Trades today="+IntegerToString(g_tradesToday));
            DeletePendingOrders();
            g_state = ST_IDLE;   // engine free to look for next A+ setup (capped per day)
         }
         return;
      }
   }

   // Still pending: expire if kill zone ended or too much time passed
   string tag = InpDryRun ? "[DRY-RUN] " : "";
   if(!InKillZone())
   {
      Log(tag+"Kill zone ended before OTE fill -> cancel pending.");
      if(!InpDryRun) DeletePendingOrders();
      ResetSetup();
      return;
   }
   if(TimeCurrent() - g_setupTime > InpSetupExpiryBars * PeriodSeconds(PERIOD_CURRENT))
   {
      Log(tag+"OTE not filled within expiry -> cancel pending.");
      if(!InpDryRun) DeletePendingOrders();
      ResetSetup();
   }
}

//==================================================================
//  MONEY MANAGEMENT — UNCHANGED
//==================================================================
double ComputeLot(double entry, double sl)
{
   if(InpUseFixedLot) return NormalizeLot(InpFixedLot);

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPercent/100.0);
   double slPips     = MathAbs(entry - sl) / g_pip;
   if(slPips <= 0) return 0;

   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return 0;
   double valuePerPip = tickVal * (g_pip / tickSize);
   if(valuePerPip <= 0) return 0;

   double lots = riskMoney / (slPips * valuePerPip);
   return NormalizeLot(lots);
}

double NormalizeLot(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots/step)*step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//==================================================================
//  HELPERS — UNCHANGED (ResetSetup extended to clear new setup memory)
//==================================================================
bool HasOpenPosition()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)InpMagic)
         return true;
   }
   return false;
}

void DeletePendingOrders()
{
   for(int i = OrdersTotal()-1; i >= 0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == (long)InpMagic)
         trade.OrderDelete(tk);
   }
}

void ResetSetup()
{
   g_state       = ST_IDLE;
   g_setupDir    = 0;
   g_sweepWick   = 0;
   g_dispExtreme = 0;
   g_fvgTop = g_fvgBot = 0;
   g_setupBar    = 0;
   g_setupTime   = 0;
   g_oteEntry = g_oteSL = g_oteTP = 0;
   // NEW: clear liquidity setup memory
   g_sweptLevel  = 0;
   g_sweptSide   = 0;
}

void RollDailyCounters()
{
   datetime d = iTime(_Symbol, PERIOD_D1, 0);
   if(d != g_dayStamp)
   {
      g_dayStamp    = d;
      g_tradesToday = 0;
      Log("New trading day -> counters reset.");
   }
}

void Log(string msg)
{
   if(InpVerboseLog) Print("[ICT2022] ", msg);
}

//==================================================================
//  DASHBOARD — original mechanism preserved, EXTENDED with SMC rows
//==================================================================

// Helper: format the nearest active FVG in a direction for the panel.
string NearestFVGText(int tradeDir)
{
   int idx = NearestActiveFVGIndex(tradeDir);
   if(idx < 0) return "none";
   return DoubleToString(g_fvg[idx].bot,(int)g_digits)+" - "+
          DoubleToString(g_fvg[idx].top,(int)g_digits)+
          "  ("+DoubleToString(g_fvg[idx].fillPct,0)+"% filled)";
}

void DrawDashboard()
{
   string biasTxt  = g_dailyBias==1 ? "BULLISH" : g_dailyBias==-1 ? "BEARISH" : "NONE";
   string stateTxt = g_state==ST_IDLE ? "IDLE (await sweep)" :
                     g_state==ST_SWEPT? "SWEPT (await displacement)" : "ARMED (OTE limit set)";
   string kzTxt    = InKillZone() ? "IN KILL ZONE" : "outside KZ";
   string extTxt   = g_extTrend==1 ? "BULLISH" : g_extTrend==-1 ? "BEARISH" : "NONE";
   string intTxt   = g_intTrend==1 ? "BULLISH" : g_intTrend==-1 ? "BEARISH" : "NONE";

   MqlDateTime ny; TimeToStruct(NewYorkTime(), ny);
   string nyTxt = StringFormat("%02d:%02d NY", ny.hour, ny.min);

   // Extended panel: original rows + 8 new Smart-Money rows.
   string lines[17];
   lines[0]  = InpDryRun ? "ICT+SMC EA v2.00  [DRY-RUN]" : "ICT+SMC EA v2.00  [LIVE]";
   lines[1]  = "NY time: "+nyTxt+"  ["+kzTxt+"]";
   lines[2]  = "Daily bias: "+biasTxt;
   lines[3]  = "State: "+stateTxt;
   lines[4]  = "Trades today: "+IntegerToString(g_tradesToday)+"/"+IntegerToString(InpMaxTradesPerDay);
   // ---- NEW SMC rows ----
   lines[5]  = "External trend: "+extTxt;
   lines[6]  = "Internal trend: "+intTxt;
   lines[7]  = "Protected High: "+(g_extProtHigh>0?DoubleToString(g_extProtHigh,(int)g_digits):"-");
   lines[8]  = "Protected Low:  "+(g_extProtLow >0?DoubleToString(g_extProtLow ,(int)g_digits):"-");
   lines[9]  = "Liquidity: "+g_liqStatus;
   lines[10] = "Displacement score: "+DoubleToString(g_lastDispScore,0)+"/100";
   lines[11] = "Nearest Bull FVG: "+NearestFVGText(1);
   lines[12] = "Nearest Bear FVG: "+NearestFVGText(-1);
   // ---- original setup rows ----
   lines[13] = g_state>=ST_SWEPT ? "Sweep wick: "+DoubleToString(g_sweepWick,(int)g_digits) : "";
   lines[14] = g_state==ST_ARMED ? StringFormat("OTE %.5f  SL %.5f  TP %.5f",g_oteEntry,g_oteSL,g_oteTP) : "";
   lines[15] = g_state==ST_ARMED ? "Entry zone ["+DoubleToString(g_fvgBot,(int)g_digits)+" - "+DoubleToString(g_fvgTop,(int)g_digits)+"]" : "";
   lines[16] = "";

   int y = 20;
   for(int i=0;i<17;i++)
   {
      string name = "ICTDB_"+IntegerToString(i);
      if(lines[i]=="") { ObjectDelete(0,name); continue; }
      if(ObjectFind(0,name)<0)
      {
         ObjectCreate(0,name,OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,name,OBJPROP_XDISTANCE,12);
         ObjectSetInteger(0,name,OBJPROP_FONTSIZE, i==0?11:9);
      }
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      // colour: title gold; daily bias row tinted; external/internal trend tinted
      color c = clrWhite;
      if(i==0) c = clrGold;
      else if(i==2) c = (g_dailyBias==1?clrLime:g_dailyBias==-1?clrTomato:clrSilver);
      else if(i==5) c = (g_extTrend==1?clrLime:g_extTrend==-1?clrTomato:clrSilver);
      else if(i==6) c = (g_intTrend==1?clrLime:g_intTrend==-1?clrTomato:clrSilver);
      ObjectSetInteger(0,name,OBJPROP_COLOR, c);
      ObjectSetString (0,name,OBJPROP_TEXT,lines[i]);
      y += (i==0?20:16);
   }
   ChartRedraw();
}
//+------------------------------------------------------------------+
