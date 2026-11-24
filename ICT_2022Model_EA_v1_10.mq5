//+------------------------------------------------------------------+
//|                                         ICT_2022Model_EA_v1.mq5   |
//|            Pure ICT 2022 Mentorship Model (Michael J. Huddleston) |
//|                                                                  |
//|  STRICT ICT ONLY. No ICC correction/continuation logic, no       |
//|  moving averages, RSI, or any non-ICT indicators. Every rule is  |
//|  a documented Inner Circle Trader characteristic:                |
//|                                                                  |
//|   1. KILL ZONE time filter (London / NY AM / Silver Bullet)      |
//|   2. DAILY BIAS (HTF draw on liquidity, equilibrium of PD range) |
//|   3. LIQUIDITY SWEEP (raid of PDH/PDL or session high/low)       |
//|   4. MARKET STRUCTURE SHIFT via DISPLACEMENT (must leave an FVG) |
//|   5. FAIR VALUE GAP entry, refined to OTE 0.62-0.705-0.79        |
//|   6. STOP LOSS beyond the sweep wick (past the 100% fib)         |
//|   7. TARGET opposite liquidity (ERL) / standard-deviation projs  |
//+------------------------------------------------------------------+
#property copyright "ICT 2022 Model EA"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//==================================================================
//  INPUTS
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
//  STATE
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
//  INIT
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

   Log("ICT 2022 Model EA initialised. Symbol="+_Symbol+
       "  pip="+DoubleToString(g_pip,(int)g_digits)+
       "  ExecTF="+EnumToString((ENUM_TIMEFRAMES)Period())+
       "  MODE="+(InpDryRun ? "*** DRY-RUN (no live orders) ***" : "LIVE (real orders)"));
   if(InpDryRun)
      Log("DRY-RUN ACTIVE: setups will be detected, logged and drawn, but NO BuyLimit/SellLimit is sent to the broker.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "ICTDB_");
}

//==================================================================
//  MAIN
//==================================================================
void OnTick()
{
   // ---- New-bar gate on execution timeframe ----
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t == g_lastBarTime) { if(InpShowDashboard) DrawDashboard(); return; }
   g_lastBarTime = t;

   RollDailyCounters();

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

   // ---- State machine ----
   switch(g_state)
   {
      case ST_IDLE:  TryDetectSweep();          break;
      case ST_SWEPT: TryDetectMSS_FVG_Arm();    break;
      default: break;
   }

   if(InpShowDashboard) DrawDashboard();
}

//==================================================================
//  1. DAILY BIAS  (HTF draw on liquidity + PD equilibrium)
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
//  2. KILL ZONE TIME FILTER  (New York local time)
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
//  3. LIQUIDITY SWEEP  (raid of swing pool / PDH-PDL)
//==================================================================
void TryDetectSweep()
{
   // Reference liquidity pools built from bars BEFORE the just-closed bar[1]
   double poolHigh = iHigh(_Symbol, PERIOD_CURRENT,
                     iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpSwingLookback, 2));
   double poolLow  = iLow (_Symbol, PERIOD_CURRENT,
                     iLowest (_Symbol, PERIOD_CURRENT, MODE_LOW,  InpSwingLookback, 2));

   if(InpUsePDHPDL)
   {
      double pdh = iHigh(_Symbol, PERIOD_D1, 1);
      double pdl = iLow (_Symbol, PERIOD_D1, 1);
      if(pdh > poolHigh) poolHigh = pdh;
      if(pdl < poolLow || poolLow == 0) poolLow = pdl;
   }

   double hi1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double lo1 = iLow (_Symbol, PERIOD_CURRENT, 1);
   double cl1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double buf = InpSweepMinPips * g_pip;

   // BUY-SIDE raid (sweep of highs) -> failure -> look for SHORTS
   bool sweptHighs = (hi1 > poolHigh + buf) && (cl1 < poolHigh);
   // SELL-SIDE raid (sweep of lows) -> failure -> look for LONGS
   bool sweptLows  = (lo1 < poolLow - buf)  && (cl1 > poolLow);

   // Only accept the sweep that agrees with daily bias (or both if bias=0)
   if(sweptLows && (g_dailyBias >= 0))
   {
      g_setupDir  = 1;                 // long
      g_sweepWick = lo1;               // fib 100%
      g_state     = ST_SWEPT;
      g_setupBar  = 0;
      Log(StringFormat("SWEEP: sell-side liquidity raided @ %.5f (pool %.5f). Bias=%d -> seeking LONG.",
                       lo1, poolLow, g_dailyBias));
   }
   else if(sweptHighs && (g_dailyBias <= 0))
   {
      g_setupDir  = -1;                // short
      g_sweepWick = hi1;               // fib 100%
      g_state     = ST_SWEPT;
      g_setupBar  = 0;
      Log(StringFormat("SWEEP: buy-side liquidity raided @ %.5f (pool %.5f). Bias=%d -> seeking SHORT.",
                       hi1, poolHigh, g_dailyBias));
   }
}

//==================================================================
//  4. MARKET STRUCTURE SHIFT (displacement) + 5. FAIR VALUE GAP
//==================================================================
void TryDetectMSS_FVG_Arm()
{
   g_setupBar++;
   if(g_setupBar > InpSetupExpiryBars)
   {
      Log("MSS/FVG not confirmed within expiry window -> reset.");
      ResetSetup();
      return;
   }

   // Structure point the displacement must break (short-term swing)
   double structHigh = iHigh(_Symbol, PERIOD_CURRENT,
                       iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, InpMSSLookback, 1));
   double structLow  = iLow (_Symbol, PERIOD_CURRENT,
                       iLowest (_Symbol, PERIOD_CURRENT, MODE_LOW,  InpMSSLookback, 1));

   double o1 = iOpen (_Symbol, PERIOD_CURRENT, 1);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double h1 = iHigh (_Symbol, PERIOD_CURRENT, 1);
   double l1 = iLow  (_Symbol, PERIOD_CURRENT, 1);
   double range1 = (h1 - l1) / g_pip;

   bool displaced = (range1 >= InpMinDisplacePips);

   if(g_setupDir == 1)   // LONG: need bullish MSS + bullish FVG
   {
      bool mssUp = (c1 > structHigh) && (c1 > o1) && displaced;
      if(!mssUp) return;

      // Bullish FVG (3-candle imbalance): low[1] > high[3]
      double lowMid   = iLow (_Symbol, PERIOD_CURRENT, 1);
      double highBack = iHigh(_Symbol, PERIOD_CURRENT, 3);
      double gap = (lowMid - highBack) / g_pip;
      if(gap < InpMinFVGPips) { Log("Bullish MSS but no valid FVG -> waiting."); return; }

      g_fvgBot     = highBack;         // FVG lower edge
      g_fvgTop     = lowMid;           // FVG upper edge
      g_dispExtreme= h1;               // fib 0%
      ArmSetup();
   }
   else if(g_setupDir == -1)  // SHORT: need bearish MSS + bearish FVG
   {
      bool mssDown = (c1 < structLow) && (c1 < o1) && displaced;
      if(!mssDown) return;

      // Bearish FVG: high[1] < low[3]
      double highMid = iHigh(_Symbol, PERIOD_CURRENT, 1);
      double lowBack = iLow (_Symbol, PERIOD_CURRENT, 3);
      double gap = (lowBack - highMid) / g_pip;
      if(gap < InpMinFVGPips) { Log("Bearish MSS but no valid FVG -> waiting."); return; }

      g_fvgTop     = lowBack;          // FVG upper edge
      g_fvgBot     = highMid;          // FVG lower edge
      g_dispExtreme= l1;               // fib 0%
      ArmSetup();
   }
}

//==================================================================
//  6. OTE ENTRY + STOP + TARGET  (arm limit order)
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
//  MANAGE ARMED SETUP
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
//  MONEY MANAGEMENT
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
//  HELPERS
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
//  DASHBOARD
//==================================================================
void DrawDashboard()
{
   string biasTxt  = g_dailyBias==1 ? "BULLISH" : g_dailyBias==-1 ? "BEARISH" : "NONE";
   string stateTxt = g_state==ST_IDLE ? "IDLE (await sweep)" :
                     g_state==ST_SWEPT? "SWEPT (await MSS+FVG)" : "ARMED (OTE limit set)";
   string kzTxt    = InKillZone() ? "IN KILL ZONE" : "outside KZ";

   MqlDateTime ny; TimeToStruct(NewYorkTime(), ny);
   string nyTxt = StringFormat("%02d:%02d NY", ny.hour, ny.min);

   string lines[8];
   lines[0] = InpDryRun ? "ICT 2022 MODEL EA  [DRY-RUN]" : "ICT 2022 MODEL EA  [LIVE]";
   lines[1] = "NY time: "+nyTxt+"  ["+kzTxt+"]";
   lines[2] = "Daily bias: "+biasTxt;
   lines[3] = "State: "+stateTxt;
   lines[4] = "Trades today: "+IntegerToString(g_tradesToday)+"/"+IntegerToString(InpMaxTradesPerDay);
   lines[5] = g_state>=ST_SWEPT ? "Sweep wick: "+DoubleToString(g_sweepWick,(int)g_digits) : "";
   lines[6] = g_state==ST_ARMED ? StringFormat("OTE %.5f  SL %.5f  TP %.5f",g_oteEntry,g_oteSL,g_oteTP) : "";
   lines[7] = g_state==ST_ARMED ? "FVG ["+DoubleToString(g_fvgBot,(int)g_digits)+" - "+DoubleToString(g_fvgTop,(int)g_digits)+"]" : "";

   int y = 20;
   for(int i=0;i<8;i++)
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
      ObjectSetInteger(0,name,OBJPROP_COLOR, i==0?clrGold : (i==2? (g_dailyBias==1?clrLime:g_dailyBias==-1?clrTomato:clrSilver):clrWhite));
      ObjectSetString (0,name,OBJPROP_TEXT,lines[i]);
      y += (i==0?20:16);
   }
   ChartRedraw();
}
//+------------------------------------------------------------------+
