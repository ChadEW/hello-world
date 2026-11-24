//+------------------------------------------------------------------+
//|                                     ICC_TradesBySci_EA_v3_3_9.mq5 |
//|   EXPERT ADVISOR v3.3.9 — Sci-style Indication -> Correction ->   |
//|   Continuation (ICC) pullback entries.                           |
//|                                                                  |
//|   v3.3.10 EXIT LABELS (Pine v3.3.9 parity) — 2026-08-05.         |
//|   ADDITIVE VISUAL. Prior builds executed closes (SL / TP /       |
//|   trailing at the broker, plus opposite-signal CloseAllThisEA)   |
//|   but only the opposite-signal close produced a visible cue      |
//|   (TriggerFlash); SL/TP/trailing exits closed SILENTLY. This     |
//|   build draws a persistent on-chart label at EVERY closed trade  |
//|   via a new OnTradeTransaction() handler: on each out/inout deal |
//|   (this EA's magic+symbol) it reads DEAL_PRICE / DEAL_TIME /     |
//|   DEAL_PROFIT / DEAL_REASON and drops an arrow+text tag ("SL" /  |
//|   "TP" / "TRAIL/BE" / "OPP-CLOSE") coloured green (win) or red   |
//|   (loss). A g_closedTrades counter is surfaced on the dashboard  |
//|   ("Closed" + last-exit reason). New input group "Exit Labels    |
//|   (v3.3.10)": InpShowExitLabels, InpExitLblShowProfit,           |
//|   InpExitLblWinColor, InpExitLblLossColor, InpExitArrowSize.     |
//|   Helper DrawExitLabel(); prefix EXIT_PFX cleaned in OnDeinit.   |
//|   NO change to the MSE engine, ICC state machine, MM, trailing/  |
//|   BE, S/R, structural-TP, ATR-auto, or FVG-relax behaviour.      |
//|   Mirrors Pine strategy v3.3.9 1:1 (twin +1 version offset).     |
//|                                                                  |
//|   v3.3.9 FVG CONTAINMENT RELAXATION (Pine v3.3.8 parity) —       |
//|   2026-08-04. Fixes the "IND + COR print but no CONTINUATION"    |
//|   symptom. The phase-2 -> continuation gate demanded that the    |
//|   single, ever-deepening WorkTF correction extreme (g_corrExtreme)|
//|   sit EXACTLY inside a still-ACTIVE same-side FVG. That point-in- |
//|   gap test failed routinely: (a) g_corrExtreme is a WorkTF price  |
//|   but FVGs are detected on the structure TF (TF mismatch), (b) the|
//|   gap is often already retired (fillPct>=InpFVGFillInvalidate) by |
//|   arrival, (c) the running MathMin/MathMax pushes g_corrExtreme   |
//|   past the gap edge. Result: IND+COR then a silent ICC_Reset.     |
//|   FIX (opt-in, additive): new input group "SMC: FVG Containment   |
//|   Relaxation (v3.3.9)" -> InpRelaxFVGContain. When ON, the        |
//|   continuation accepts a correction extreme NEAR an active same-  |
//|   side FVG (tolerance, fixed pips or x ATR) AND/OR whose discount/|
//|   premium BAND overlaps an active gap (InpUseFVGband). OFF        |
//|   (default) reproduces the EXACT v3.3.8 point-in-gap behaviour.   |
//|   Helper MSE_FVGContainOK() unifies both paths; NO change to the  |
//|   MSE engine, bias, sweep, displacement, OB gate, S/R, MM,        |
//|   trailing/BE, structural-TP, or ATR-auto behaviour. Mirrors      |
//|   Pine strategy v3.3.8 1:1 (twin +1 version offset: the EA        |
//|   received the structural-TP port one build later than Pine).    |
//|                                                                  |
//|   v3.3.8 STRUCTURAL TAKE-PROFIT ENGINE (Pine v2.2 parity) —      |
//|   2026-07-31. Ports the Pine strategy structural-TP logic        |
//|   (f_structTP / f_tp) into the EA so BOTH platforms share one    |
//|   identical take-profit engine. New input group "Take-Profit     |
//|   Mode (v2.2 parity)": InpTPMode (Fixed RR / Structural),        |
//|   InpTPLookback, InpTPMinRR. PURELY ADDITIVE + two surgical      |
//|   edits inside ExecuteBuy / ExecuteSell that route the target    |
//|   through ResolveTP(). Fixed-RR default reproduces the exact     |
//|   v3.3.7 behaviour. Structural mode targets the nearest un-      |
//|   broken S/R beyond entry (Sci: previous high / next liquidity   |
//|   pool), with a WorkTF swing-extreme fallback and a MinRR floor. |
//|   A broker-min-stop guard reverts an illegal (too-close)         |
//|   structural target to Fixed-RR so MT5 never rejects the order.  |
//|   NO change to the MSE engine, ICC state machine, money/trade    |
//|   management, trailing/BE, S/R engine, or ATR-auto behaviour.    |
//|                                                                  |
//|   v3.3.7 EMPTY-ARRAY GUARD PARITY (mirrors Pine v3.3.7) —        |
//|   2026-07-30. The Pine strategy twin crashed on bar 0 with       |
//|   "In 'array.get()'. Index 0 is out of bounds, array size is 0"  |
//|   because Pine's `for i = 0 to array.size(x)-1` counts DOWNWARD  |
//|   to -1 on an EMPTY array and executes array.get(x,0). MQL5's    |
//|   C-style `for(int i=0;i<ArraySize(a);i++)` does NOT share that  |
//|   flaw (0<0 is false -> body skipped), so the EA never threw the |
//|   identical error. To keep the two engines line-for-line at      |
//|   parity, this build adds the SAME empty-collection early-out    |
//|   guard to every FVG/OB iterator that maps 1:1 to a guarded Pine |
//|   function: MSE_NearestActiveFVG, MSE_InActiveFVG, the FVG fill  |
//|   loop (MSE_UpdateFVGFills) + draw loop (MSE_DrawFVGs),          |
//|   MSE_NearestUnmitigatedOB, MSE_InUnmitigatedOB, MSE_InActiveOB, |
//|   the OB mitigate loop (MSE_UpdateOBMitigation) + draw loop      |
//|   (MSE_DrawOBs), plus the FVG/OB existence scans. In MQL5 these  |
//|   are DEFENSIVE/parity guards, not a behaviour change. NO        |
//|   trading logic, thresholds, entry paths, MM, S/R, or ATR-auto   |
//|   behaviour is altered.                                          |
//|                                                                  |
//|   v3.3.6 ATR-AUTO PIP (self-tuning; opt-in) + v3.3.4 zero-trade  |
//|   fixes folded in; v3.3.3 transparency; v3.3.1 RE10008 history   |
//|   guards; v3.0 modular SMC market-structure engine (MSE_*);      |
//|   v2.1 soft-D1 HTF weight. All preserved unchanged.              |
//|                                                                  |
//|   Built for Chad Woodyard, July 2026.                            |
//+------------------------------------------------------------------+
#property copyright   "Chad Woodyard"
#property version     "3.40"
#property description "ICC TradesBySci EA v3.3.10 - adds on-chart EXIT LABELS at every closed trade (SL/TP/trail/opposite-signal) via OnTradeTransaction; additive/visual, no engine/MM/ICC/TP change. Retains v3.3.9 FVG containment relaxation, v3.3.8 structural-TP engine, v3.3.7 empty-array guard fix, v3.3.6 ATR-auto pip mode, v3.3.4 zero-trade fixes, cross-asset scaling. Mirrors Pine v3.3.9. All engine logic, MM, and inputs preserved."
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
//============================= ENUMS =================================
enum ENUM_SR_DUR      { SR_DAYS = 0, SR_SESSIONS = 1 };
enum ENUM_BRK_MODE    { BRK_GRAY = 0, BRK_DELETE = 1 };
enum ENUM_ASSET_CLASS { ASSET_FOREX=0, ASSET_METAL=1, ASSET_INDEX=2, ASSET_CRYPTO=3, ASSET_OTHER=4 };
enum ENUM_TP_MODE     { TP_FIXED_RR=0, TP_STRUCTURAL=1 }; // v3.3.8 structural-TP
enum ENUM_SL_METHOD
  {
   SL_STRUCTURAL = 0, // Structural anchor only
   SL_ATR        = 1, // ATR x multiplier
   SL_SMART      = 2  // MAX(structural, ATR, broker min) - recommended
  };
enum ENUM_ICC_PHASE   { PH_NONE=0, PH_INDICATION=1, PH_CORRECTION=2 };
//============================= INPUTS ================================
input group "=== Entry Paths (turn either on/off) ==="
input bool   UseICCPullback    = true;          // Sci Indication->Correction->Continuation pullback
input bool   UseCascadeEntries = false;         // v1 breakout path (OFF by default; buys the breakout)
input bool   UseRetestEntries  = true;          // Retest-confirmation entries
input bool   CloseOnOpposite   = true;          // Close open trade on opposite signal
input group "=== Bias / Filter (Sci: HTF sets bias, LTF entry) ==="
input bool   BiasLoose         = true;          // single BOS sets trend (HH w/o LL = bull)
input bool   UseD1Filter       = true;          // let D1 influence HTF bias as a SOFT weight
input double D1Weight          = 0.5;           // D1 weight vs H4 (0=ignore D1, 1.0=~old hard veto, >1 D1 dominates)
input double HTF_MinConviction = 0.5;           // Min net HTF score (same side as H4) required to trade
input bool   StrictAlign       = false;         // v1 lockstep 4-TF gate (leave OFF for Sci style)
input group "=== ICC Pullback Tuning ==="
input double CorrRetraceMin    = 0.500;         // Min pullback into discount/premium (fib of impulse)
input double CorrRetraceMax    = 0.900;         // Max pullback before setup invalidates (fib)
input int    ICC_ExpiryBars    = 30;            // Bars to complete Correction+Continuation, else reset
input group "=== Timeframe Cascade (Sci D1->H4->H1->M15) ==="
input ENUM_TIMEFRAMES BiasTF   = PERIOD_D1;     // Top bias TF
input ENUM_TIMEFRAMES MidTF    = PERIOD_H4;     // Mid / primary Indication TF
input ENUM_TIMEFRAMES WorkTF   = PERIOD_H1;     // Working TF (swing anchor)
input ENUM_TIMEFRAMES TrigTF   = PERIOD_M15;    // Trigger TF (entry timing)
input int    CascadeSwingLen   = 5;             // Pivot length per-TF for cascade
input group "=== Stop Loss / Sizing ==="
input ENUM_SL_METHOD SL_Method = SL_SMART;      // SL method
input double ATR_Multiplier    = 1.5;           // ATR multiplier
input int    ATR_Period        = 14;            // ATR period
input double BrokerStopCushion = 1.2;           // Safety multiple over broker min
input bool   AutoScaleByAsset  = true;          // Scale buffers for metal/index/crypto
input int    SL_Buffer_Points  = 50;            // Extra structural buffer (points)
input double RR_Ratio          = 2.0;           // TP reward : risk
input double RiskPercent       = 0.5;           // % balance risked per trade
input double FixedLots         = 0.0;           // >0 overrides risk-% sizing
input int    MaxOpenTrades     = 1;             // Max concurrent trades (this EA/symbol)
input bool   ShowDiagnostics   = true;          // Print broker diagnostics on init
input group "=== Take-Profit Mode (v2.2 parity) ==="
input ENUM_TP_MODE InpTPMode     = TP_FIXED_RR; // TP target: Fixed RR, or Structural (nearest un-broken S/R beyond entry)
input int          InpTPLookback = 200;         // Structural: WorkTF bars scanned for the fallback swing target
input double       InpTPMinRR    = 1.0;         // Structural: reject/floor targets below this reward:risk
input group "=== Trailing Stop ==="
input bool   UseTrailingStop   = true;
input int    TrailingStart_Pts = 200;
input int    TrailingStep_Pts  = 100;
input group "=== Break Even ==="
input bool   UseBreakEven      = true;
input int    BreakEvenAt_Pts   = 150;
input int    BreakEvenProfit   = 10;
input group "=== Session Filter ==="
input bool   UseSessionFilter  = false;
input int    SessionStartHour  = 13;            // 09:30 NY ~ 13:30 UTC
input int    SessionEndHour    = 20;            // 16:00 NY ~ 20:00 UTC
input group "=== Support / Resistance (body-close levels) ==="
input bool         SR_Show      = true;         // Run body-close S/R engine
input int          SR_MinTouch  = 3;            // Min body closes to confirm a level
input double       SR_TolPips   = 10.0;         // Zone tolerance (pips)
input ENUM_SR_DUR  SR_DurMode   = SR_DAYS;      // Level duration unit
input int          SR_DurN      = 3;            // Level duration (days or sessions)
input color        SR_ColRes    = clrOrange;    // Resistance color
input color        SR_ColSup    = clrTeal;      // Support color
// v3.3.3: S/R + broken-level colours render TRANSPARENT (shaded). One
// alpha controls all of them via ColorToARGB in DrawLevel/GrayOutLevel.
input int          SR_FillAlpha = 60;           // Colour transparency (0=fully transparent .. 255=opaque)
input bool         SR_UseZone   = true;         // Draw as shaded zone vs line
input bool         SR_ShowCnt   = true;         // Show touch-count label
input int          SR_RefLen    = 20;           // Reference SMA length (S/R classifier)
input group "=== Broken-Level Behavior ==="
input ENUM_BRK_MODE BrkMode     = BRK_GRAY;     // Gray Out (needed for retests) or Delete
input double        BrkBufPips   = 2.0;         // Break buffer beyond level (pips)
input color         BrkColor     = clrDimGray;  // Grayed-out color (transparent via SR_FillAlpha)
input group "=== Retest-Confirmation Entry ==="
input double RetestConfBufPips  = 1.0;          // Rejection confirmation buffer (pips)
input int    RetestArmBars      = 5;            // Arm window (bars) after a retest
input bool   RetestSepBar       = true;         // Require a separate confirmation bar
input double RetestSLbufPips    = 3.0;          // Retest SL buffer beyond level (pips)
input group "=== Visuals: Swings + Dashboard ==="
input bool   ShowSwings         = true;
input int    SwingLen           = 5;
input int    MaxSwings          = 6;
input color  ColHigh            = clrDodgerBlue;
input color  ColLow             = clrCrimson;
input bool   ShowDashboard      = true;
input group "=== Entry / Exit Flashing Dialog ==="
input bool   FlashOn            = true;
input int    FlashSeconds       = 6;
input int    FlashMs            = 400;
input ENUM_BASE_CORNER FlashCorner = CORNER_LEFT_UPPER;
input int    FlashX             = 220;
input int    FlashY             = 30;
input bool   ShowFlashPrices    = true;
input color  ColBuy             = clrLime;
input color  ColSell            = clrRed;
input color  ColExit            = clrOrange;
input color  ColRBuy            = clrLime;
input color  ColRSell           = clrRed;
input group "=== Alerts ==="
input bool   AlertPopup         = true;
input bool   AlertPush          = false;
input bool   AlertEmail         = false;
input bool   AlertSound         = false;
input string AlertSoundFile     = "alert.wav";
input group "=== EA Settings ==="
input ulong  MagicNumber        = 20260717;
input int    Slippage           = 30;
input string TradeComment       = "ICC-Sci-EA-v2.1";
input bool   DebugLog           = false;        // Print SL/lot skip reasons
input bool   VerboseLog         = true;         // Print bias/phase/signals every bar
//====================================================================
//  NEW INPUTS — SMC MARKET STRUCTURE ENGINE (v3.0). Every threshold
//  is configurable. All requirement toggles default ON (new behaviour);
//  turn them OFF to reproduce the v2.1 raw-pivot workflow exactly.
//====================================================================
input group "=== SMC: Structure TF & Protected Swings ==="
input ENUM_TIMEFRAMES InpMSE_TF   = PERIOD_CURRENT; // Structure TF for the SMC engine (PERIOD_CURRENT = chart)
input int    InpIntSwingStrength   = 2;          // Internal swing fractal strength (bars each side)
input int    InpExtSwingStrength   = 4;          // External swing fractal strength (bars each side)
input int    InpStructLookback     = 300;        // Bars scanned to locate protected swings
input bool   InpBOSUseClose        = true;       // BOS requires a BODY close beyond the protected swing (else wick)
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
input double InpFVGFillInvalidate  = 100.0;      // Fill % at which an FVG is retired (0..100)
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
input bool   InpRequireOB          = false;      // v3.3.4: OB is CONFLUENCE, not a hard 2nd container atop the FVG. Gate corrected to "active OB" - safe to re-enable.
input int    InpOBScanBack         = 8;          // Bars searched back from a displacement for the OB
input int    InpMaxTrackedOB       = 40;         // Max order blocks held in memory
input bool   InpOBMitigateOnClose  = true;       // OB invalidated on a BODY close through it (else wick)
input bool   InpDrawOB             = true;       // Draw order blocks on the chart
input color  InpOBBullColor        = clrDarkGreen;// Bullish OB colour
input color  InpOBBearColor        = clrDarkRed; // Bearish OB colour
//====================================================================
//  v3.3.6 ATR-AUTO PIP INPUTS (self-tuning; opt-in). When ON, the pip-
//  scaled STRUCTURE + ENTRY-BUFFER thresholds are derived live from a
//  fraction of ATR(InpATRautoLen) instead of the fixed *Pips inputs, so
//  they self-size per symbol/TF (no manual pip tuning). OFF (default) =
//  exact v3.3.4 fixed-pip behaviour. Mirrors the Pine v3.3.6 twin.
//====================================================================
input group "=== ATR-Auto Pip (self-tuning) ==="
input bool   InpUseATRauto    = false;   // Derive pip-scaled thresholds from ATR (ignore fixed *Pips)
input int    InpATRautoLen    = 14;      // ATR length for auto pip
input double InpFracSRtol      = 0.35;    // S/R zone tol (x ATR)
input double InpFracFVG        = 0.20;    // Min FVG size (x ATR)
input double InpFracSweep      = 0.15;    // Min sweep penetration (x ATR)
input double InpFracEqual      = 0.15;    // Equal H/L tol (x ATR)
input double InpFracSLbuf      = 0.30;    // ICC/Retest SL buffer (x ATR)
input double InpFracConf       = 0.10;    // Retest confirm buffer (x ATR)
input double InpFracBrk        = 0.10;    // Break buffer (x ATR)
//====================================================================
//  v3.3.9 FVG CONTAINMENT RELAXATION (opt-in; fixes IND+COR-but-no-
//  CONTINUATION). OFF (default) = exact v3.3.8 point-in-gap containment.
//  ON = accept a correction extreme NEAR an active same-side FVG
//  (tolerance) and/or whose discount/premium BAND overlaps an active gap.
//  Mirrors the Pine v3.3.8 twin.
//====================================================================
input group "=== SMC: FVG Containment Relaxation (v3.3.9) ==="
input bool   InpRelaxFVGContain   = false;  // Relax the continuation active-FVG containment test
input double InpFVGContainTolPips = 5.0;    // Containment tolerance (pips) - inside if within this of a gap edge
input double InpFVGContainFrac    = 0.25;   // Containment tolerance (x ATR) when ATR-auto ON
input bool   InpUseFVGband         = true;   // Also accept when the discount/premium BAND overlaps an active gap
//====================================================================
//  v3.3.10 EXIT LABELS (opt-in visual; Pine v3.3.9 parity). Draw a
//  persistent arrow+text tag at every CLOSED trade so SL/TP/trailing/
//  opposite-signal exits are visible on the chart, not just in the MT5
//  History tab. Purely visual - no trading/MM/engine change.
//====================================================================
input group "=== Exit Labels (v3.3.10) ==="
input bool   InpShowExitLabels     = true;        // Draw a label at each closed trade (SL/TP/trail/opp-close)
input bool   InpExitLblShowProfit  = true;        // Include net profit on the exit label
input color  InpExitLblWinColor    = clrTeal;     // Winning-exit label colour
input color  InpExitLblLossColor   = clrMaroon;   // Losing-exit label colour
input int    InpExitArrowSize      = 2;           // Exit arrow width (1..5)
//============================ GLOBALS ================================
CTrade        trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;
double g_pip=0, g_tol=0, g_brkBuf=0, g_confBuf=0, g_slBuf=0;
// v3.3.6 ATR-auto pip state + per-bar effective structure distances
int    g_atrAuto=INVALID_HANDLE;   // dedicated ATR handle (InpATRautoLen) on chart TF
double g_atrAutoVal=0.0;           // last good ATR value (0 = not ready -> fixed fallback)
double g_equalTol=0.0, g_sweepMin=0.0, g_fvgMin=0.0; // effective equal-level / sweep / FVG price distances
double g_fvgContainTol=0.0;                          // v3.3.9 effective FVG containment tolerance (ATR-auto or fixed)
int    g_sessCount=0, g_lastDayKey=-1;
int    g_barCount=0;
int    atrHandle=INVALID_HANDLE;
int    g_maHandle=INVALID_HANDLE;
int    g_uid=0;
ENUM_ASSET_CLASS AssetClass=ASSET_FOREX;
string AssetClassLabel="FOREX";
int    SLBufPts_Runtime=0;
int    TrailStart_Runtime=0, TrailStep_Runtime=0, BEat_Runtime=0, BEprofit_Runtime=0;
string PFX    = "ICCsciEA21_";
string SR_PFX = "ICCsciEA21_SR_";
string SW_PFX = "ICCsciEA21_SW_";
string g_swingNames[];
struct SwingCache { double lastHi, prevHi, lastLo, prevLo; };
SwingCache cD1, cH4, cH1, cM15;
int  biasD1=0, biasH4=0, biasH1=0, biasM15=0;
bool alignBull=false, alignBear=false;
double wkLastHi=0, wkLastLo=0;
// ---- cascade continuation edge detection (v1 path) ----
bool prevBuyCont=false, prevSellCont=false;
// ---- ICC pullback state machine ----
int      g_iccPhase = PH_NONE;
int      g_iccDir   = 0;      // +1 bull setup, -1 bear setup
double   g_indLevel = 0.0;    // swing broken during Indication (impulse origin)
double   g_indExtreme = 0.0;  // furthest extreme reached during impulse
double   g_corrExtreme = 0.0; // pullback extreme during Correction (SL anchor)
int      g_iccStartBar = 0;   // bar the Indication fired (for expiry)
bool     iccBuySig=false, iccSellSig=false;
double   iccSigSL=0.0;
// ---- v3.3.8 structural-TP readout state ----
double g_lastTP=0.0;         // last resolved TP price (for dashboard / diagnostics)
bool   g_lastTPstruct=false; // was the last TP a structural target (true) or fixed-RR (false)?
// ---- v3.0 SMC market-structure engine state ----------------------
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
string   FVG_PFX="ICCsciEA30_FVG_";
string   OB_PFX ="ICCsciEA30_OB_";
// ---- v3.3.10 exit-label state ----
string   EXIT_PFX="ICCsciEA310_EXIT_";  // chart-object prefix for exit tags
int      g_exitLblUID=0;                // unique id for each exit label pair
int      g_closedTrades=0;              // running count of closed trades (this EA)
string   g_lastExitReason="-";          // last exit reason (SL/TP/TRAIL-BE/OPP-CLOSE) for dashboard
// ---- S/R cluster storage ----
double   sr_price[];    int      sr_count[];
datetime sr_birthTime[]; int     sr_birthSes[];
datetime sr_birthBar[];  bool    sr_isRes[];
bool     sr_drawn[];     bool    sr_broken[];
bool     sr_retested[];  bool    sr_armed[];
int      sr_armBar[];    string  sr_name[];
// ---- retest-confirmation outputs ----
bool   retestBuySig=false, retestSellSig=false;
double retestSigLevel=0;
bool   srRetestThisBar=false, srRetestIsRes=false;
datetime lastAlertTime=0;
// ---- flashing dialog state ----
string FLASH_NAME="ICCsciEA21_FLASH";
bool   g_flashActive=false;
int    g_flashTicks=0;
bool   g_flashPhase=false;
string g_flashMsg="";
color  g_flashBase=clrLime;
bool   g_flashHasPx=false;
double g_flashEntry=0, g_flashSL=0, g_flashTP=0;
//+==================================================================+
//|                 ASSET CLASS + SCALING                            |
//+==================================================================+
ENUM_ASSET_CLASS DetectAssetClass()
  {
   string sym=_Symbol; StringToUpper(sym);
   if(StringFind(sym,"XAU")>=0||StringFind(sym,"GOLD")>=0||StringFind(sym,"XAG")>=0||
      StringFind(sym,"SILVER")>=0||StringFind(sym,"XPT")>=0||StringFind(sym,"XPD")>=0)
     { AssetClassLabel="METAL"; return ASSET_METAL; }
   if(StringFind(sym,"BTC")>=0||StringFind(sym,"ETH")>=0||StringFind(sym,"XRP")>=0||
      StringFind(sym,"LTC")>=0||StringFind(sym,"BCH")>=0||StringFind(sym,"SOL")>=0||
      StringFind(sym,"DOGE")>=0||StringFind(sym,"ADA")>=0)
     { AssetClassLabel="CRYPTO"; return ASSET_CRYPTO; }
   if(StringFind(sym,"US30")>=0||StringFind(sym,"US500")>=0||StringFind(sym,"NAS")>=0||
      StringFind(sym,"SPX")>=0||StringFind(sym,"DJ")>=0||StringFind(sym,"DAX")>=0||
      StringFind(sym,"FTSE")>=0||StringFind(sym,"NIK")>=0||StringFind(sym,"HK50")>=0||
      StringFind(sym,"AUS200")>=0||StringFind(sym,"GER")>=0||StringFind(sym,"UK100")>=0)
     { AssetClassLabel="INDEX"; return ASSET_INDEX; }
   if(StringLen(sym)>=6){ AssetClassLabel="FOREX"; return ASSET_FOREX; }
   AssetClassLabel="OTHER"; return ASSET_OTHER;
  }
void ApplyAssetClassScaling()
  {
   SLBufPts_Runtime  = SL_Buffer_Points;
   TrailStart_Runtime= TrailingStart_Pts;
   TrailStep_Runtime = TrailingStep_Pts;
   BEat_Runtime      = BreakEvenAt_Pts;
   BEprofit_Runtime  = BreakEvenProfit;
   if(!AutoScaleByAsset) return;
   int mult=1;
   switch(AssetClass)
     {
      case ASSET_METAL:  mult=30;  break;
      case ASSET_INDEX:  mult=20;  break;
      case ASSET_CRYPTO: mult=300; break;
      default: return;
     }
   SLBufPts_Runtime  *= mult;
   TrailStart_Runtime*= mult;
   TrailStep_Runtime *= mult;
   BEat_Runtime      *= mult;
   BEprofit_Runtime  *= mult;
   PrintFormat("ASSET SCALING [%s]: SL_Buffer %d -> %d | Trail %d/%d",
               AssetClassLabel, SL_Buffer_Points, SLBufPts_Runtime,
               TrailStart_Runtime, TrailStep_Runtime);
  }
//+==================================================================+
//|                 v3.3.6 ATR-AUTO PIP DISTANCES                    |
//+==================================================================+
//--- Return a PRICE DISTANCE: fraction*ATR when ATR-auto is ON and the
//    ATR value is ready, else the fixed pips*g_pip (v3.3.4 behaviour).
//    Warmup / bad ATR (g_atrAutoVal<=0) transparently falls back to fixed.
double PipDist(double fixedPips,double atrFrac)
  {
   return (InpUseATRauto && g_atrAutoVal>0.0) ? atrFrac*g_atrAutoVal : fixedPips*g_pip;
  }
//--- Recompute every pip-scaled STRUCTURE/entry-buffer distance. Called
//    once in OnInit (seed) and at the top of each new bar in OnTick so
//    ATR-auto tracks live volatility. When ATR-auto is OFF these collapse
//    to the exact v3.3.4 constants.
void RefreshEffectiveDistances()
  {
   if(g_atrAuto!=INVALID_HANDLE)
     {
      double a[]; ArraySetAsSeries(a,true);
      if(CopyBuffer(g_atrAuto,0,1,1,a)==1 && a[0]>0.0) g_atrAutoVal=a[0];
     }
   g_tol      = PipDist(SR_TolPips,           InpFracSRtol);
   g_brkBuf   = PipDist(BrkBufPips,           InpFracBrk);
   g_confBuf  = PipDist(RetestConfBufPips,    InpFracConf);
   g_slBuf    = PipDist(RetestSLbufPips,      InpFracSLbuf);   // ICC + retest signal SL buffer
   g_equalTol = PipDist(InpEqualLevelTolPips, InpFracEqual);
   g_sweepMin = PipDist(InpSweepMinPips,      InpFracSweep);
   g_fvgMin   = PipDist(InpMinFVGPips,        InpFracFVG);
   g_fvgContainTol = PipDist(InpFVGContainTolPips, InpFVGContainFrac); // v3.3.9 FVG containment tolerance
  }
//+==================================================================+
//|                 SMART STOP CALCULATIONS                          |
//+==================================================================+
double GetMinStopDistance()
  {
   long stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spread  = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)*point;
   double minDist = MathMax((double)stopsLvl,(double)freezeLvl)*point;
   minDist = MathMax(minDist, spread*3.0);
   minDist = MathMax(minDist, point*10.0);
   return minDist;
  }
double GetATRStopDistance()
  {
   if(atrHandle==INVALID_HANDLE) return GetMinStopDistance()*2;
   double atr[]; ArraySetAsSeries(atr,true);
   if(CopyBuffer(atrHandle,0,1,1,atr)<1) return GetMinStopDistance()*2;
   if(atr[0]<=0) return GetMinStopDistance()*2;
   return atr[0]*ATR_Multiplier;
  }
double CalculateSLDistance(double structuralDist)
  {
   double point   = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double bufStop = SLBufPts_Runtime*point + structuralDist;
   double minStop = GetMinStopDistance();
   double atrStop = GetATRStopDistance();
   double finalDist;
   switch(SL_Method)
     {
      case SL_STRUCTURAL: finalDist=bufStop; break;
      case SL_ATR:        finalDist=atrStop; break;
      case SL_SMART:
      default:            finalDist=MathMax(MathMax(bufStop,atrStop), minStop*BrokerStopCushion); break;
     }
   finalDist = MathMax(finalDist, minStop*BrokerStopCushion);
   return finalDist;
  }
void PrintBrokerDiagnostics()
  {
   if(!ShowDiagnostics) return;
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   digits = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   spread   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   Print("==============================================================");
   Print("       ICC TradesBySci EA v3.3.10 - BROKER DIAGNOSTICS         ");
   Print("==============================================================");
   Print(" Symbol:       ", _Symbol, "  Asset: ", AssetClassLabel);
   Print(" Chart TF:     ", EnumToString((ENUM_TIMEFRAMES)_Period));
   Print(" Cascade:      ", EnumToString(BiasTF), " -> ", EnumToString(MidTF),
                            " -> ", EnumToString(WorkTF), " -> ", EnumToString(TrigTF));
   Print(" Entry paths:  ICC=", (UseICCPullback?"ON":"OFF"),
                       "  Cascade=", (UseCascadeEntries?"ON":"OFF"),
                       "  Retest=", (UseRetestEntries?"ON":"OFF"));
   Print(" Bias mode:    ", (BiasLoose?"LOOSE (single BOS)":"STRICT (HH+HL)"),
                       "  D1 filter=", (UseD1Filter?"SOFT":"OFF"),
                       "  D1wt=", DoubleToString(D1Weight,2),
                       "  MinConv=", DoubleToString(HTF_MinConviction,2),
                       "  StrictAlign=", (StrictAlign?"ON":"OFF"));
   Print(" Stops Level:  ", stopsLvl, " pts   Spread: ", spread, " pts");
   Print(" SL Method:    ", EnumToString(SL_Method), "   RR: ", DoubleToString(RR_Ratio,1));
   Print(" TP Mode:      ", (InpTPMode==TP_STRUCTURAL?"STRUCTURAL":"FIXED_RR"),
                       "   MinRR: ", DoubleToString(InpTPMinRR,2),
                       "   Lookback: ", IntegerToString(InpTPLookback));
   Print(" FVG Contain:  ", (InpRelaxFVGContain?"RELAX":"STRICT"),
                       "   Tol: ", DoubleToString(g_fvgContainTol,(int)digits),
                       "   Band: ", (InpUseFVGband?"ON":"OFF"));
   Print(" Min SafeStop: ", DoubleToString(GetMinStopDistance(),(int)digits),
         " | x Cushion: ", DoubleToString(GetMinStopDistance()*BrokerStopCushion,(int)digits));
   // Tester data-availability guard (root cause #4 in Appendix H)
   double m15c = iClose(_Symbol,TrigTF,1);
   double h1h  = iHigh(_Symbol,WorkTF,1);
   if(m15c<=0 || h1h<=0)
      Print(" *** WARNING: ", EnumToString(TrigTF), "/", EnumToString(WorkTF),
            " data not available. If backtesting, set modeling to 'Every tick'. ***");
   Print("==============================================================");
  }
//+==================================================================+
//|                 CASCADE BIAS ENGINE (loosened)                   |
//+==================================================================+
bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid=iHigh(_Symbol,tf,shift);
   if(mid==0) return false;
   for(int i=1;i<=L;i++)
     {
      if(iHigh(_Symbol,tf,shift-i)>=mid) return false;
      if(iHigh(_Symbol,tf,shift+i)> mid) return false;
     }
   return true;
  }
bool IsPivotLowTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid=iLow(_Symbol,tf,shift);
   if(mid==0) return false;
   for(int i=1;i<=L;i++)
     {
      if(iLow(_Symbol,tf,shift-i)<=mid) return false;
      if(iLow(_Symbol,tf,shift+i)< mid) return false;
     }
   return true;
  }
void RefreshSwingsTF(ENUM_TIMEFRAMES tf, SwingCache &c)
  {
   c.lastHi=c.prevHi=c.lastLo=c.prevLo=0;
   int bars=Bars(_Symbol,tf);
   int fh=0,fl=0;
   for(int shift=CascadeSwingLen+1; shift<bars-CascadeSwingLen-1 && (fh<2||fl<2); shift++)
     {
      if(fh<2 && IsPivotHighTF(tf,shift,CascadeSwingLen))
        { double px=iHigh(_Symbol,tf,shift); if(fh==0) c.lastHi=px; else c.prevHi=px; fh++; }
      if(fl<2 && IsPivotLowTF(tf,shift,CascadeSwingLen))
        { double px=iLow(_Symbol,tf,shift);  if(fl==0) c.lastLo=px; else c.prevLo=px; fl++; }
     }
  }
//--- v2 loosened bias: a single break of structure sets a trend -----
int BiasOf(const SwingCache &c)
  {
   if(c.lastHi==0||c.prevHi==0||c.lastLo==0||c.prevLo==0) return 0;
   bool hh = c.lastHi>c.prevHi;   // higher high
   bool hl = c.lastLo>c.prevLo;   // higher low
   bool lh = c.lastHi<c.prevHi;   // lower high
   bool ll = c.lastLo<c.prevLo;   // lower low
   if(BiasLoose)
     {
      // one BOS in a direction, no confirmed break the other way
      if(hh && !ll) return  1;    // made a higher high, did NOT make a lower low
      if(ll && !hh) return -1;    // made a lower low, did NOT make a higher high
      return 0;
     }
   // strict (v1 behavior)
   if(hh && hl) return  1;
   if(lh && ll) return -1;
   return 0;
  }
void EvaluateCascade()
  {
   RefreshSwingsTF(BiasTF,cD1);
   RefreshSwingsTF(MidTF, cH4);
   RefreshSwingsTF(WorkTF,cH1);
   RefreshSwingsTF(TrigTF,cM15);
   biasD1=BiasOf(cD1); biasH4=BiasOf(cH4); biasH1=BiasOf(cH1); biasM15=BiasOf(cM15);
   wkLastHi=cH1.lastHi; wkLastLo=cH1.lastLo;
   if(StrictAlign)
     {
      alignBull=(biasD1==1 && biasH4==1 && biasH1==1 && biasM15==1);
      alignBear=(biasD1==-1&& biasH4==-1&& biasH1==-1&& biasM15==-1);
     }
   else
     {
      alignBull=(biasH1==1 && biasM15==1);
      alignBear=(biasH1==-1&& biasM15==-1);
     }
  }
//--- v2.1: HTF bias as a SOFT-WEIGHTED score --------------------------
//  H4 LEADS the direction; D1 nudges conviction up/down via D1Weight.
//  score = biasH4 + biasD1 * D1Weight        (only when UseD1Filter)
//  A direction is returned only if the score stays on H4's side by at
//  least HTF_MinConviction; otherwise 0 (no trade).
//  D1Weight=1.0 + HTF_MinConviction=0.5 reproduces the old hard veto.
double HTFscore()
  {
   if(!UseD1Filter) return (double)biasH4;
   return (double)biasH4 + (double)biasD1 * D1Weight;
  }
int HTFbias()
  {
   if(biasH4==0) return 0;               // H4 must lead; flat H4 = no bias
   if(!UseD1Filter) return biasH4;       // D1 ignored -> pure H4
   double sc = HTFscore();
   if(biasH4==1  && sc >=  HTF_MinConviction) return  1;
   if(biasH4==-1 && sc <= -HTF_MinConviction) return -1;
   return 0;                             // D1 opposition dragged conviction below threshold
  }
//+==================================================================+
//|==================================================================|
//|   v3.0 SMART MONEY STRUCTURE ENGINE (MSE_*)                      |
//|   Replaces the raw multi-TF pivot detection that fed the ICC     |
//|   engine. Fully modular; each concern is its own function and    |
//|   operates on the configurable structure TF (g_mseTF).           |
//|   v3.3.1: RE10008-parity history guards added (see header).      |
//|   v3.3.7: empty-array parity guards added to FVG/OB iterators.   |
//|==================================================================|
//+==================================================================+
//--- Strict fractal high on the structure TF: greater than 'strength'
//    bars on each side. Only confirmed once 'strength' newer bars exist.
bool MSE_IsFractalHigh(int shift,int strength)
  {
   int bars=Bars(_Symbol,g_mseTF);
   if(shift<=strength || shift+strength>=bars) return false;
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
   int bars=Bars(_Symbol,g_mseTF);
   if(shift<=strength || shift+strength>=bars) return false;
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
   if(bars < strength*2 + 2) return;
   int maxBars=MathMin(InpStructLookback,bars-1-strength);
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
   // else: trend persists (no fresh protected-swing break this bar)
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
//--- Equal-highs cluster among recent fractal highs (BSL magnet).
bool MSE_DetectEqualHighs(double &level)
  {
   double tol=g_equalTol, first=0.0; bool haveFirst=false; // v3.3.6 ATR-auto
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
//--- Equal-lows cluster among recent fractal lows (SSL magnet).
bool MSE_DetectEqualLows(double &level)
  {
   double tol=g_equalTol, first=0.0; bool haveFirst=false; // v3.3.6 ATR-auto
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
//--- Buy-side liquidity = highest of protected high, equal-highs, pool, PDH.
double MSE_BuildBSL()
  {
   double lvl=g_extProtHigh;
   double eqH; if(MSE_DetectEqualHighs(eqH)) lvl=MathMax(lvl,eqH);
   int hi=iHighest(_Symbol,g_mseTF,MODE_HIGH,SwingLen*2,2);
   if(hi>=0) lvl=MathMax(lvl,iHigh(_Symbol,g_mseTF,hi));
   return lvl;
  }
//--- Sell-side liquidity = lowest of protected low, equal-lows, pool, PDL.
double MSE_BuildSSL()
  {
   double lvl=(g_extProtLow>0.0)? g_extProtLow : DBL_MAX;
   double eqL; if(MSE_DetectEqualLows(eqL)) lvl=MathMin(lvl,eqL);
   int lo=iLowest(_Symbol,g_mseTF,MODE_LOW,SwingLen*2,2);
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
   double buf=g_sweepMin; // v3.3.6 ATR-auto
   if(dir==1)
     {
      if(g_ssl>0.0 && (lo1<g_ssl-buf) && (cl1>g_ssl)){ sweepWick=lo1; sweptLevel=g_ssl; return true; }
     }
   else if(dir==-1)
     {
      if(g_bsl>0.0 && (hi1>g_bsl+buf) && (cl1<g_bsl)){ sweepWick=hi1; sweptLevel=g_bsl; return true; }
     }
   return false;
  }
//--- Reclaim: within InpReclaimBars a close returns through the swept level.
bool MSE_ReclaimConfirmed(int dir,double lvl)
  {
   if(!InpRequireReclaim) return true;
   for(int s=1;s<=InpReclaimBars;s++)
     {
      double c=iClose(_Symbol,g_mseTF,s);
      if(dir==1  && c>lvl) return true;   // reclaimed above swept low
      if(dir==-1 && c<lvl) return true;   // reclaimed below swept high
     }
   return false;
  }
//--- Refresh liquidity levels, run sweep+reclaim, maintain valid windows.
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
   bool dirOk=(dir==1)?(c>o):(c<o);          // correct directionality is mandatory
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
   double score =sBody+sClose+sWick+sATR;
   g_lastDispScore=MathMin(score,100.0);
   return g_lastDispScore;
  }
//==================================================================
//  FAIR VALUE GAP ENGINE  (detect all, draw, track fill %, retire)
//==================================================================
bool MSE_FVGExists(datetime midTime)
  {
   if(ArraySize(g_fvg)==0) return false; // v3.3.7 empty-array guard (Pine parity)
   for(int i=0;i<ArraySize(g_fvg);i++) if(g_fvg[i].time==midTime) return true;
   return false;
  }
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
   int bars=Bars(_Symbol,g_mseTF);
   if(bars<4) return;
   int maxBars=MathMin(InpFVGScanBars,bars-4);
   for(int s=1;s<=maxBars;s++)
     {
      // Bullish FVG: low[s] > high[s+2] (gap across middle candle s+1)
      double lowNear=iLow (_Symbol,g_mseTF,s);
      double highFar=iHigh(_Symbol,g_mseTF,s+2);
      if((lowNear-highFar)>=g_fvgMin) // v3.3.6 ATR-auto (was /g_pip>=InpMinFVGPips)
         MSE_AddFVG(lowNear,highFar,iTime(_Symbol,g_mseTF,s+1),1);
      // Bearish FVG: high[s] < low[s+2]
      double highNear=iHigh(_Symbol,g_mseTF,s);
      double lowFar  =iLow (_Symbol,g_mseTF,s+2);
      if((lowFar-highNear)>=g_fvgMin) // v3.3.6 ATR-auto (was /g_pip>=InpMinFVGPips)
         MSE_AddFVG(lowFar,highNear,iTime(_Symbol,g_mseTF,s+1),-1); // top=lowFar,bot=highNear
     }
  }
void MSE_UpdateFVGFills()
  {
   if(ArraySize(g_fvg)==0) return; // v3.3.7 empty-array guard (mirrors Pine FVG fill loop)
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
   if(ArraySize(g_fvg)==0) return; // v3.3.7 empty-array guard (mirrors Pine FVG draw loop)
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
//--- Nearest active FVG in the trade direction (bullish for longs).
int MSE_NearestActiveFVG(int tradeDir)
  {
   int best=-1; double bestD=DBL_MAX; double px=iClose(_Symbol,g_mseTF,1);
   if(ArraySize(g_fvg)==0) return best; // v3.3.7 empty-array guard (mirrors Pine nearestFVG)
   for(int i=0;i<ArraySize(g_fvg);i++)
     {
      if(!g_fvg[i].active || g_fvg[i].dir!=tradeDir) continue;
      double mid=(g_fvg[i].top+g_fvg[i].bot)/2.0, d=MathAbs(px-mid);
      if(d<bestD){ bestD=d; best=i; }
     }
   return best;
  }
//--- Is a given price inside an active FVG in the trade direction?
bool MSE_InActiveFVG(int tradeDir,double price)
  {
   if(ArraySize(g_fvg)==0) return false; // v3.3.7 empty-array guard (mirrors Pine inActiveFVG)
   for(int i=0;i<ArraySize(g_fvg);i++)
     {
      if(!g_fvg[i].active || g_fvg[i].dir!=tradeDir) continue;
      if(price<=g_fvg[i].top && price>=g_fvg[i].bot) return true;
     }
   return false;
  }
//--- v3.3.9: price counts as "inside" if within `tol` of an active same-side
//    FVG edge (absorbs WorkTF-vs-structureTF mismatch + g_corrExtreme drift).
bool MSE_InActiveFVGtol(int tradeDir,double price,double tol)
  {
   if(ArraySize(g_fvg)==0) return false; // empty-array guard (Pine parity)
   for(int i=0;i<ArraySize(g_fvg);i++)
     {
      if(!g_fvg[i].active || g_fvg[i].dir!=tradeDir) continue;
      if(price<=g_fvg[i].top+tol && price>=g_fvg[i].bot-tol) return true;
     }
   return false;
  }
//--- v3.3.9: does the price band [lo..hi] overlap ANY active same-side FVG?
//    Interval-overlap test: lo <= gapTop and hi >= gapBot.
bool MSE_BandOverlapsFVG(int tradeDir,double lo,double hi)
  {
   if(ArraySize(g_fvg)==0) return false; // empty-array guard (Pine parity)
   for(int i=0;i<ArraySize(g_fvg);i++)
     {
      if(!g_fvg[i].active || g_fvg[i].dir!=tradeDir) continue;
      if(lo<=g_fvg[i].top && hi>=g_fvg[i].bot) return true;
     }
   return false;
  }
//--- v3.3.9: unified continuation FVG-containment gate. Relax OFF => EXACT
//    v3.3.8 point-in-gap. Relax ON => point-in-gap OR near-edge tolerance OR
//    (optional) discount/premium band overlap. `bandFrom` is the shallow edge
//    of the pullback band (disc for longs, prem for shorts); `price` is the
//    correction extreme (g_corrExtreme).
bool MSE_FVGContainOK(int tradeDir,double price,double bandFrom)
  {
   if(MSE_InActiveFVG(tradeDir,price)) return true;   // exact v3.3.8 behaviour
   if(!InpRelaxFVGContain) return false;
   if(MSE_InActiveFVGtol(tradeDir,price,g_fvgContainTol)) return true;
   if(InpUseFVGband)
     {
      double lo=MathMin(price,bandFrom);
      double hi=MathMax(price,bandFrom);
      if(MSE_BandOverlapsFVG(tradeDir,lo,hi)) return true;
     }
   return false;
  }
//==================================================================
//  ORDER / MITIGATION BLOCK ENGINE  (Trades-by-Sci enhancement)
//  Bullish OB = last down-close candle before an up displacement;
//  bearish OB = last up-close candle before a down displacement.
//==================================================================
bool MSE_OBExists(datetime tm)
  {
   if(ArraySize(g_ob)==0) return false; // v3.3.7 empty-array guard (Pine parity)
   for(int i=0;i<ArraySize(g_ob);i++) if(g_ob[i].time==tm) return true;
   return false;
  }
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
   int bars=Bars(_Symbol,g_mseTF);
   if(bars<(InpOBScanBack+4)) return;
   int maxBars=MathMin(InpFVGScanBars,bars-(InpOBScanBack+3));
   for(int s=1;s<=maxBars;s++)
     {
      if(MSE_ScoreDisplacement(s,1)>=InpDispMinScore)   // bullish displacement -> bullish OB behind it
         for(int k=s+1;k<=s+InpOBScanBack;k++)
            if(iClose(_Symbol,g_mseTF,k)<iOpen(_Symbol,g_mseTF,k))
              { MSE_AddOB(iHigh(_Symbol,g_mseTF,k),iLow(_Symbol,g_mseTF,k),iTime(_Symbol,g_mseTF,k),1); break; }
      if(MSE_ScoreDisplacement(s,-1)>=InpDispMinScore)  // bearish displacement -> bearish OB behind it
         for(int k=s+1;k<=s+InpOBScanBack;k++)
            if(iClose(_Symbol,g_mseTF,k)>iOpen(_Symbol,g_mseTF,k))
              { MSE_AddOB(iHigh(_Symbol,g_mseTF,k),iLow(_Symbol,g_mseTF,k),iTime(_Symbol,g_mseTF,k),-1); break; }
     }
  }
void MSE_UpdateOBMitigation()
  {
   if(ArraySize(g_ob)==0) return; // v3.3.7 empty-array guard (mirrors Pine OB mitigate/draw loop)
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
   if(ArraySize(g_ob)==0) return; // v3.3.7 empty-array guard (mirrors Pine OB draw loop)
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
//--- Nearest UNMITIGATED, active OB in the trade direction.
int MSE_NearestUnmitigatedOB(int tradeDir)
  {
   int best=-1; double bestD=DBL_MAX; double px=iClose(_Symbol,g_mseTF,1);
   if(ArraySize(g_ob)==0) return best; // v3.3.7 empty-array guard (mirrors Pine nearestOB)
   for(int i=0;i<ArraySize(g_ob);i++)
     {
      if(!g_ob[i].active || g_ob[i].mitigated || g_ob[i].dir!=tradeDir) continue;
      double mid=(g_ob[i].top+g_ob[i].bot)/2.0, d=MathAbs(px-mid);
      if(d<bestD){ bestD=d; best=i; }
     }
   return best;
  }
//--- Is a given price inside an unmitigated OB in the trade direction?
bool MSE_InUnmitigatedOB(int tradeDir,double price)
  {
   if(ArraySize(g_ob)==0) return false; // v3.3.7 empty-array guard (mirrors Pine inUnmitigatedOB)
   for(int i=0;i<ArraySize(g_ob);i++)
     {
      if(!g_ob[i].active || g_ob[i].mitigated || g_ob[i].dir!=tradeDir) continue;
      if(price<=g_ob[i].top && price>=g_ob[i].bot) return true;
     }
   return false;
  }
//--- (v3.3.4 ZERO-TRADE FIX) Is price inside an ACTIVE (unviolated) OB?
//    A Continuation entry REQUIRES price to RETURN into the OB (that return
//    IS the mitigation). MSE_UpdateOBMitigation flags mitigated=true on first
//    overlap and runs (via MSE_Update) BEFORE ICC_Update, so InUnmitigatedOB
//    rejected the very OB the correction just tapped -> self-defeating gate
//    that blocked every ICC entry. Correct test: inside an OB that has NOT
//    been VIOLATED (closed through). 'active' already means unviolated; we
//    simply drop the '!mitigated' clause.
bool MSE_InActiveOB(int tradeDir,double price)
  {
   if(ArraySize(g_ob)==0) return false; // v3.3.7 empty-array guard (mirrors Pine inActiveOB)
   for(int i=0;i<ArraySize(g_ob);i++)
     {
      if(!g_ob[i].active || g_ob[i].dir!=tradeDir) continue;   // allow mitigated (=returned-to)
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
   if(Bars(_Symbol,g_mseTF) < 5) return;
   double a[]; ArraySetAsSeries(a,true);
   if(g_mseATR!=INVALID_HANDLE && CopyBuffer(g_mseATR,0,1,1,a)==1) g_mseATRval=a[0];
   MSE_UpdateStructure();
   MSE_UpdateLiquidity();
   MSE_UpdateFVGs();
   if(InpUseOrderBlocks) MSE_UpdateOrderBlocks();
   // Feed protected internal swings to the ICC break anchors (BOS-on-protected).
   if(InpIntTrendControlsEnt)
     {
      if(g_intProtHigh>0.0) wkLastHi=g_intProtHigh;
      if(g_intProtLow >0.0) wkLastLo=g_intProtLow;
     }
  }
//+==================================================================+
//|        ICC PULLBACK ENGINE  (Indication -> Correction ->         |
//|        Continuation)  — the genuine Sci-style entry.             |
//+==================================================================+
void ICC_Reset()
  {
   g_iccPhase=PH_NONE; g_iccDir=0;
   g_indLevel=0; g_indExtreme=0; g_corrExtreme=0; g_iccStartBar=0;
  }
void ICC_Update()
  {
   iccBuySig=false; iccSellSig=false; iccSigSL=0;
   if(!UseICCPullback) return;
   int    htf   = HTFbias();
   double m15c1 = iClose(_Symbol,TrigTF,1);   // just-closed M15 close
   double m15h2 = iHigh (_Symbol,TrigTF,2);   // prior M15 high (minor swing)
   double m15l2 = iLow  (_Symbol,TrigTF,2);   // prior M15 low  (minor swing)
   double wkH1  = iHigh (_Symbol,WorkTF,1);   // last closed H1 high
   double wkL1  = iLow  (_Symbol,WorkTF,1);   // last closed H1 low
   if(m15c1<=0 || wkH1<=0 || wkL1<=0) return; // data guard (tester modeling)
   // Bias flip cancels an in-progress setup facing the wrong way
   if(g_iccPhase!=PH_NONE && g_iccDir!=0 && htf!=0 && htf!=g_iccDir)
      ICC_Reset();
   // Expiry: setup must complete inside the window
   if(g_iccPhase!=PH_NONE && (g_barCount-g_iccStartBar)>ICC_ExpiryBars)
      ICC_Reset();
   //================= BULLISH branch =================
   if(htf==1)
     {
      if(g_iccPhase==PH_NONE)
        {
         // INDICATION (v3.0): break of a PROTECTED internal swing (wkLastHi now
         // carries the protected swing), gated by external trend + a confirmed
         // liquidity sweep+reclaim + an institutional displacement (reject weak).
         bool extOK   = (!InpExtTrendControlsDir) || g_extTrend>=0;         // external not bearish
         bool sweepOK = (!InpRequireSweep)        || g_sweepConfLong>0;      // SSL swept+reclaimed
         bool dispOK  = (!InpRejectWeakBreaks)    || (MSE_ScoreDisplacement(1,1)>=InpDispMinScore);
         if(wkLastHi>0 && m15c1>wkLastHi && extOK && sweepOK && dispOK)
           {
            g_iccPhase   = PH_INDICATION;
            g_iccDir     = 1;
            g_indLevel   = wkLastHi;      // impulse origin (broken protected swing)
            g_indExtreme = MathMax(wkH1,m15c1);
            g_corrExtreme= wkL1;
            g_iccStartBar= g_barCount;
           }
        }
      else if(g_iccPhase==PH_INDICATION && g_iccDir==1)
        {
         if(wkH1>g_indExtreme) g_indExtreme=wkH1;       // extend impulse high
         double leg = g_indExtreme-g_indLevel;
         if(leg>0)
           {
            double disc = g_indExtreme - leg*CorrRetraceMin;  // discount threshold
            double inval= g_indExtreme - leg*CorrRetraceMax;  // too-deep threshold
            if(wkL1<=inval)                    // pulled back too far -> invalidate
               ICC_Reset();
            else if(wkL1<=disc)                // reached discount -> Correction
              {
               g_iccPhase   = PH_CORRECTION;
               g_corrExtreme= wkL1;
              }
           }
        }
      else if(g_iccPhase==PH_CORRECTION && g_iccDir==1)
        {
         if(wkL1<g_corrExtreme) g_corrExtreme=wkL1;     // track pullback low
         double leg  = g_indExtreme-g_indLevel;
         double inval= (leg>0)? g_indExtreme-leg*CorrRetraceMax : 0;
         double disc = (leg>0)? g_indExtreme-leg*CorrRetraceMin : g_corrExtreme; // v3.3.9 shallow edge of discount band
         if(leg>0 && wkL1<=inval)                       // deep break -> invalidate
           { ICC_Reset(); }
         else
           {
            // CONTINUATION (v3.0): resume up ONLY if the correction pulled into an
            // active bullish FVG and (optionally) an unmitigated bullish order block.
            // v3.3.9: containment via MSE_FVGContainOK (strict point-in-gap, or
            // relaxed tolerance/band overlap when InpRelaxFVGContain is ON).
            bool fvgOK = (!InpRequireFVGpullback) || MSE_FVGContainOK(1,g_corrExtreme,disc);
            bool obOK  = (!InpRequireOB) || !InpUseOrderBlocks || MSE_InActiveOB(1,g_corrExtreme); // v3.3.4: active (unviolated) OB, not "unmitigated"
            if(m15h2>0 && m15c1>m15h2 && fvgOK && obOK)
              {
               iccBuySig=true;
               iccSigSL = g_corrExtreme - g_slBuf;      // SL below correction low
               ICC_Reset();
              }
           }
        }
     }
   //================= BEARISH branch =================
   else if(htf==-1)
     {
      if(g_iccPhase==PH_NONE)
        {
         // INDICATION (v3.0): break of a PROTECTED internal swing low, gated by
         // external trend + a confirmed BSL sweep+reclaim + institutional displacement.
         bool extOK   = (!InpExtTrendControlsDir) || g_extTrend<=0;         // external not bullish
         bool sweepOK = (!InpRequireSweep)        || g_sweepConfShort>0;     // BSL swept+reclaimed
         bool dispOK  = (!InpRejectWeakBreaks)    || (MSE_ScoreDisplacement(1,-1)>=InpDispMinScore);
         if(wkLastLo>0 && m15c1<wkLastLo && extOK && sweepOK && dispOK)      // INDICATION: BOS down
           {
            g_iccPhase   = PH_INDICATION;
            g_iccDir     = -1;
            g_indLevel   = wkLastLo;      // broken protected support
            g_indExtreme = MathMin(wkL1,m15c1);
            g_corrExtreme= wkH1;
            g_iccStartBar= g_barCount;
           }
        }
      else if(g_iccPhase==PH_INDICATION && g_iccDir==-1)
        {
         if(wkL1<g_indExtreme) g_indExtreme=wkL1;       // extend impulse low
         double leg = g_indLevel-g_indExtreme;
         if(leg>0)
           {
            double prem = g_indExtreme + leg*CorrRetraceMin;  // premium threshold
            double inval= g_indExtreme + leg*CorrRetraceMax;
            if(wkH1>=inval)
               ICC_Reset();
            else if(wkH1>=prem)
              {
               g_iccPhase   = PH_CORRECTION;
               g_corrExtreme= wkH1;
              }
           }
        }
      else if(g_iccPhase==PH_CORRECTION && g_iccDir==-1)
        {
         if(wkH1>g_corrExtreme) g_corrExtreme=wkH1;     // track pullback high
         double leg  = g_indLevel-g_indExtreme;
         double inval= (leg>0)? g_indExtreme+leg*CorrRetraceMax : 0;
         double prem = (leg>0)? g_indExtreme+leg*CorrRetraceMin : g_corrExtreme; // v3.3.9 shallow edge of premium band
         if(leg>0 && wkH1>=inval)
           { ICC_Reset(); }
         else
           {
            // CONTINUATION (v3.0): resume down ONLY if the correction pulled into an
            // active bearish FVG and (optionally) an unmitigated bearish order block.
            // v3.3.9: containment via MSE_FVGContainOK (strict point-in-gap, or
            // relaxed tolerance/band overlap when InpRelaxFVGContain is ON).
            bool fvgOK = (!InpRequireFVGpullback) || MSE_FVGContainOK(-1,g_corrExtreme,prem);
            bool obOK  = (!InpRequireOB) || !InpUseOrderBlocks || MSE_InActiveOB(-1,g_corrExtreme); // v3.3.4: active (unviolated) OB, not "unmitigated"
            if(m15l2>0 && m15c1<m15l2 && fvgOK && obOK)
              {
               iccSellSig=true;
               iccSigSL = g_corrExtreme + g_slBuf;      // SL above correction high
               ICC_Reset();
              }
           }
        }
     }
   else // htf flat: don't start new setups (let existing expire/flip handle itself)
     {
      if(g_iccPhase==PH_NONE) ICC_Reset();
     }
  }
//+==================================================================+
//|                 SCI SWING RAYS (visual)                          |
//+==================================================================+
void MakeSwing(datetime t, double px, color col)
  {
   string nm=SW_PFX+IntegerToString(g_uid++);
   ObjectCreate(0,nm,OBJ_TREND,0,t,px,TimeCurrent(),px);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,col);
   ObjectSetInteger(0,nm,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,true);
   int n=ArraySize(g_swingNames); ArrayResize(g_swingNames,n+1); g_swingNames[n]=nm;
   while(ArraySize(g_swingNames)>MaxSwings*2)
     {
      ObjectDelete(0,g_swingNames[0]);
      for(int i=0;i<ArraySize(g_swingNames)-1;i++) g_swingNames[i]=g_swingNames[i+1];
      ArrayResize(g_swingNames,ArraySize(g_swingNames)-1);
     }
  }
void ProcessSwing()
  {
   if(!ShowSwings) return;
   int need=SwingLen*2+2;
   double hi[],lo[]; datetime tm[];
   ArraySetAsSeries(hi,true); ArraySetAsSeries(lo,true); ArraySetAsSeries(tm,true);
   if(CopyHigh(_Symbol,_Period,0,need,hi)<need) return;
   if(CopyLow (_Symbol,_Period,0,need,lo)<need) return;
   if(CopyTime(_Symbol,_Period,0,need,tm)<need) return;
   int c=SwingLen;
   bool isHigh=true,isLow=true;
   for(int k=1;k<=SwingLen;k++)
     {
      if(hi[c]<=hi[c+k]||hi[c]<=hi[c-k]) isHigh=false;
      if(lo[c]>=lo[c+k]||lo[c]>=lo[c-k]) isLow =false;
     }
   if(isHigh) MakeSwing(tm[c],hi[c],ColHigh);
   if(isLow)  MakeSwing(tm[c],lo[c],ColLow);
  }
//+==================================================================+
//|                 BODY-CLOSE S/R ENGINE                            |
//+==================================================================+
double RefSMA()
  {
   if(g_maHandle==INVALID_HANDLE) return SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double buf[]; ArraySetAsSeries(buf,true);
   if(CopyBuffer(g_maHandle,0,1,1,buf)==1) return buf[0];
   return SymbolInfoDouble(_Symbol,SYMBOL_BID);
  }
void SR_CheckBroken(double c)
  {
   for(int i=ArraySize(sr_price)-1;i>=0;i--)
     {
      if(!sr_drawn[i]||sr_broken[i]) continue;
      double lvl=sr_price[i];
      bool brokeUp  =( sr_isRes[i] && c>lvl+g_brkBuf);
      bool brokeDown=(!sr_isRes[i] && c<lvl-g_brkBuf);
      if(brokeUp||brokeDown)
        {
         if(BrkMode==BRK_DELETE){ DeleteLevelObjects(i); RemoveAt(i); }
         else                   { sr_broken[i]=true; GrayOutLevel(i); }
        }
     }
  }
void SR_CheckRetest(double barHigh, double barLow, double barClose)
  {
   srRetestThisBar=false;
   if(BrkMode!=BRK_GRAY) return;
   for(int i=ArraySize(sr_price)-1;i>=0;i--)
     {
      if(!sr_broken[i]||sr_retested[i]) continue;
      double lvl=sr_price[i];
      bool retRes=( sr_isRes[i] && barLow <=lvl+g_brkBuf && barClose>=lvl-g_brkBuf);
      bool retSup=(!sr_isRes[i] && barHigh>=lvl-g_brkBuf && barClose<=lvl+g_brkBuf);
      if(retRes||retSup)
        {
         sr_retested[i]=true; sr_armed[i]=true; sr_armBar[i]=g_barCount;
         srRetestThisBar=true; srRetestIsRes=sr_isRes[i];
        }
     }
  }
void SR_CheckConfirm(double c)
  {
   retestBuySig=false; retestSellSig=false; retestSigLevel=0;
   if(!UseRetestEntries) return;
   for(int i=ArraySize(sr_price)-1;i>=0;i--)
     {
      if(!sr_armed[i]) continue;
      double lvl=sr_price[i];
      int    age=g_barCount-sr_armBar[i];
      if(age>RetestArmBars){ sr_armed[i]=false; continue; }
      bool canCheck = RetestSepBar ? (age>=1) : (age>=0);
      if(!canCheck) continue;
      bool confBuy =( sr_isRes[i] && c>lvl+g_confBuf);
      bool confSell=(!sr_isRes[i] && c<lvl-g_confBuf);
      if(confBuy)  { sr_armed[i]=false; retestBuySig=true;  retestSigLevel=lvl; }
      else if(confSell){ sr_armed[i]=false; retestSellSig=true; retestSigLevel=lvl; }
     }
  }
void GrayOutLevel(int i)
  {
   string nm=sr_name[i];
   // v3.3.3 TRANSPARENCY: grayed-out broken level uses the same SR_FillAlpha
   // so it stays a consistent transparent shade with the active levels.
   if(SR_UseZone && ObjectFind(0,nm+"_box")>=0)
     { ObjectSetInteger(0,nm+"_box",OBJPROP_COLOR,ColorToARGB(BrkColor,(uchar)SR_FillAlpha)); ObjectSetInteger(0,nm+"_box",OBJPROP_STYLE,STYLE_DOT); }
   if(!SR_UseZone && ObjectFind(0,nm+"_ln")>=0)
     { ObjectSetInteger(0,nm+"_ln",OBJPROP_COLOR,ColorToARGB(BrkColor,(uchar)SR_FillAlpha)); ObjectSetInteger(0,nm+"_ln",OBJPROP_STYLE,STYLE_DASH); }
   if(SR_ShowCnt && ObjectFind(0,nm+"_lb")>=0)
     { ObjectSetInteger(0,nm+"_lb",OBJPROP_COLOR,ColorToARGB(BrkColor,(uchar)SR_FillAlpha));
       ObjectSetString(0,nm+"_lb",OBJPROP_TEXT,"x "+(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i])); }
  }
void ProcessBar(double c, datetime t)
  {
   MqlDateTime mt; TimeToStruct(t,mt);
   int dayKey=mt.year*10000+mt.mon*100+mt.day;
   if(dayKey!=g_lastDayKey){ g_sessCount++; g_lastDayKey=dayKey; }
   bool matched=false;
   for(int i=0;i<ArraySize(sr_price);i++)
     {
      if(sr_broken[i]) continue;
      if(MathAbs(c-sr_price[i])<=g_tol)
        {
         int nc=sr_count[i]+1;
         sr_price[i]=(sr_price[i]*sr_count[i]+c)/nc;
         sr_count[i]=nc; matched=true;
         if(nc==SR_MinTouch && !sr_drawn[i]){ sr_drawn[i]=true; sr_isRes[i]=(sr_price[i]>=RefSMA()); DrawLevel(i); }
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
      if(!sr_drawn[i]||sr_broken[i]) continue;
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
      // v3.3.3 TRANSPARENCY: SR_FillAlpha sets the ARGB alpha so the FILLED
      // zone renders as a transparent shade (price action reads through it).
      ObjectSetInteger(0,on,OBJPROP_COLOR,ColorToARGB(col,(uchar)SR_FillAlpha));
      ObjectSetInteger(0,on,OBJPROP_FILL,true);
      ObjectSetInteger(0,on,OBJPROP_BACK,true);
     }
   else
     {
      string on=nm+"_ln";
      ObjectCreate(0,on,OBJ_TREND,0,t1,p,t2,p);
      ObjectSetInteger(0,on,OBJPROP_COLOR,ColorToARGB(col,(uchar)SR_FillAlpha)); // v3.3.3 TRANSPARENCY
      ObjectSetInteger(0,on,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,on,OBJPROP_RAY_RIGHT,false);
     }
   if(SR_ShowCnt)
     {
      string lb=nm+"_lb";
      ObjectCreate(0,lb,OBJ_TEXT,0,t2,p);
      ObjectSetString(0,lb,OBJPROP_TEXT,(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i]));
      ObjectSetInteger(0,lb,OBJPROP_COLOR,ColorToARGB(col,(uchar)SR_FillAlpha)); // v3.3.3 TRANSPARENCY
      ObjectSetInteger(0,lb,OBJPROP_ANCHOR,sr_isRes[i]?ANCHOR_LOWER:ANCHOR_UPPER);
      ObjectSetInteger(0,lb,OBJPROP_FONTSIZE,8);
     }
  }
void UpdateLabel(int i)
  {
   string lb=sr_name[i]+"_lb";
   if(ObjectFind(0,lb)>=0) ObjectSetString(0,lb,OBJPROP_TEXT,(sr_isRes[i]?"R x":"S x")+IntegerToString(sr_count[i]));
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
int ActiveSRCount()
  { int cnt=0; for(int i=0;i<ArraySize(sr_drawn);i++) if(sr_drawn[i]&&!sr_broken[i]) cnt++; return cnt; }
int ArmedCount()
  { int cnt=0; for(int i=0;i<ArraySize(sr_armed);i++) if(sr_armed[i]) cnt++; return cnt; }
//+==================================================================+
//|                 FLASHING DIALOG BOX                              |
//+==================================================================+
void SetLabel(string nm,int corner,int x,int y,string txt,color col,int fsize,string font)
  {
   if(ObjectFind(0,nm)<0) ObjectCreate(0,nm,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,nm,OBJPROP_CORNER,corner);
   ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,nm,OBJPROP_TEXT,txt);
   ObjectSetString (0,nm,OBJPROP_FONT,font);
   ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,fsize);
   ObjectSetInteger(0,nm,OBJPROP_COLOR,col);
  }
void DrawFlashBox(bool on)
  {
   int boxH=g_flashHasPx?92:40;
   string bg=FLASH_NAME+"_bg";
   if(ObjectFind(0,bg)<0) ObjectCreate(0,bg,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,bg,OBJPROP_CORNER,FlashCorner);
   ObjectSetInteger(0,bg,OBJPROP_XDISTANCE,FlashX);
   ObjectSetInteger(0,bg,OBJPROP_YDISTANCE,FlashY);
   ObjectSetInteger(0,bg,OBJPROP_XSIZE,180);
   ObjectSetInteger(0,bg,OBJPROP_YSIZE,boxH);
   ObjectSetInteger(0,bg,OBJPROP_BGCOLOR,on?g_flashBase:clrBlack);
   ObjectSetInteger(0,bg,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,bg,OBJPROP_COLOR,g_flashBase);
   ObjectSetInteger(0,bg,OBJPROP_WIDTH,2);
   ObjectSetInteger(0,bg,OBJPROP_BACK,false);
   SetLabel(FLASH_NAME,FlashCorner,FlashX+12,FlashY+11,g_flashMsg,on?clrWhite:g_flashBase,12,"Arial Black");
   if(g_flashHasPx)
     {
      SetLabel(FLASH_NAME+"_e", FlashCorner,FlashX+12,FlashY+34,"E:  "+DoubleToString(g_flashEntry,_Digits),clrWhite,9,"Consolas");
      SetLabel(FLASH_NAME+"_sl",FlashCorner,FlashX+12,FlashY+53,"SL: "+DoubleToString(g_flashSL,_Digits),clrTomato,9,"Consolas");
      SetLabel(FLASH_NAME+"_tp",FlashCorner,FlashX+12,FlashY+72,"TP: "+DoubleToString(g_flashTP,_Digits),clrLime,9,"Consolas");
     }
   else
     { ObjectDelete(0,FLASH_NAME+"_e"); ObjectDelete(0,FLASH_NAME+"_sl"); ObjectDelete(0,FLASH_NAME+"_tp"); }
  }
void ClearFlashBox()
  {
   ObjectDelete(0,FLASH_NAME);      ObjectDelete(0,FLASH_NAME+"_bg");
   ObjectDelete(0,FLASH_NAME+"_e"); ObjectDelete(0,FLASH_NAME+"_sl");
   ObjectDelete(0,FLASH_NAME+"_tp");
  }
void TriggerFlash(string msg,color base,bool hasPx,double e,double sl,double tp)
  {
   if(!FlashOn) return;
   g_flashActive=true; g_flashMsg=msg; g_flashBase=base; g_flashPhase=true;
   g_flashHasPx=(hasPx && ShowFlashPrices);
   g_flashEntry=e; g_flashSL=sl; g_flashTP=tp;
   g_flashTicks=(int)MathMax(2,(FlashSeconds*1000)/MathMax(50,FlashMs));
   DrawFlashBox(true);
   ChartRedraw();
  }
//+==================================================================+
//|                 ALERTS                                           |
//+==================================================================+
void DispatchAlert(string m)
  {
   Print("ICC-Sci-EA v3.3.10: ",m);
   if(AlertPopup) Alert(m);
   if(AlertPush)  SendNotification(m);
   if(AlertEmail) SendMail("ICC TradesBySci EA v3.3.10 - "+_Symbol,m);
   if(AlertSound) PlaySound(AlertSoundFile);
   lastAlertTime=TimeCurrent();
  }
//+==================================================================+
//|        v3.3.10 EXIT LABELS  (Pine v3.3.9 parity)                 |
//|  Draw a persistent arrow + text tag at a closed trade so SL/TP/  |
//|  trailing/opposite-signal exits are visible on the chart. Fed    |
//|  by OnTradeTransaction on each closing (out/inout) deal. Purely  |
//|  visual - no trading, MM, or engine state is touched.            |
//+==================================================================+
//--- Map an MT5 deal-close reason code to a short human tag.
string ExitReasonText(ENUM_DEAL_REASON r)
  {
   switch(r)
     {
      case DEAL_REASON_SL:     return "SL";        // stop-loss hit
      case DEAL_REASON_TP:     return "TP";        // take-profit hit
      case DEAL_REASON_SO:     return "STOP-OUT";  // margin stop-out
      case DEAL_REASON_CLIENT:
      case DEAL_REASON_MOBILE:
      case DEAL_REASON_WEB:
      case DEAL_REASON_EXPERT: return "OPP-CLOSE"; // EA/manual close (opposite signal or trail/BE modify-close)
      default:                 return "EXIT";
     }
  }
//--- Draw the arrow + text pair for one closed trade.
//    wasLong = the CLOSED position was a BUY (its close is a SELL deal).
//    A long exit tag sits ABOVE the close price (arrow down), a short exit
//    tag sits BELOW it (arrow up), so it never hides the closing candle.
void DrawExitLabel(datetime tm,double price,bool wasLong,string reason,double profit)
  {
   if(!InpShowExitLabels) return;
   if(tm<=0 || price<=0.0) return;
   string base=EXIT_PFX+IntegerToString(g_exitLblUID++);
   bool   win=(profit>=0.0);
   color  col=win? InpExitLblWinColor : InpExitLblLossColor;
   // arrow object (Wingdings 233 up / 234 down)
   string an=base+"_ar";
   ObjectCreate(0,an,OBJ_ARROW,0,tm,price);
   ObjectSetInteger(0,an,OBJPROP_ARROWCODE,wasLong?234:233); // 234 down over a long exit, 233 up under a short exit
   ObjectSetInteger(0,an,OBJPROP_COLOR,col);
   ObjectSetInteger(0,an,OBJPROP_WIDTH,(int)MathMax(1,MathMin(5,InpExitArrowSize)));
   ObjectSetInteger(0,an,OBJPROP_ANCHOR,wasLong?ANCHOR_BOTTOM:ANCHOR_TOP);
   // text object with reason (+ optional net P&L)
   string tn=base+"_tx";
   string txt="x "+reason+(InpExitLblShowProfit? "  "+DoubleToString(profit,2) : "");
   ObjectCreate(0,tn,OBJ_TEXT,0,tm,price);
   ObjectSetString (0,tn,OBJPROP_TEXT,txt);
   ObjectSetInteger(0,tn,OBJPROP_COLOR,col);
   ObjectSetInteger(0,tn,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,tn,OBJPROP_ANCHOR,wasLong?ANCHOR_LOWER:ANCHOR_UPPER);
  }
//--- OnTradeTransaction: catch every CLOSING deal for this EA and tag it.
//    Runs off the trade stream (not per-bar) so SL/TP/trailing closes that
//    fire between bars are still captured. Filters by magic + symbol; only
//    DEAL_ENTRY_OUT / DEAL_ENTRY_INOUT (position-reducing) deals are labelled.
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult  &result)
  {
   if(!InpShowExitLabels) return;
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong dealTicket=trans.deal;
   if(dealTicket==0) return;
   if(!HistoryDealSelect(dealTicket)) return;
   // filter: this EA, this symbol, a CLOSING deal
   if((ulong)HistoryDealGetInteger(dealTicket,DEAL_MAGIC)!=MagicNumber) return;
   if(HistoryDealGetString(dealTicket,DEAL_SYMBOL)!=_Symbol) return;
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_INOUT) return;
   double   price =HistoryDealGetDouble (dealTicket,DEAL_PRICE);
   datetime tm    =(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);
   double   profit=HistoryDealGetDouble (dealTicket,DEAL_PROFIT)
                  +HistoryDealGetDouble (dealTicket,DEAL_SWAP)
                  +HistoryDealGetDouble (dealTicket,DEAL_COMMISSION);
   ENUM_DEAL_REASON drsn=(ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket,DEAL_REASON);
   // A closing deal's DEAL_TYPE is opposite the closed position: a SELL deal
   // (DEAL_TYPE_SELL) closes a LONG; a BUY deal closes a SHORT.
   ENUM_DEAL_TYPE dtype=(ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket,DEAL_TYPE);
   bool wasLong=(dtype==DEAL_TYPE_SELL);
   string reason=ExitReasonText(drsn);
   DrawExitLabel(tm,price,wasLong,reason,profit);
   g_closedTrades++;
   g_lastExitReason=reason;
  }
//+==================================================================+
//|                 POSITION / RISK MANAGEMENT                       |
//+==================================================================+
double NormalizeLots(double l)
  {
   double mn=symInfo.LotsMin(), mx=symInfo.LotsMax(), st=symInfo.LotsStep();
   l=MathMax(l,mn); l=MathMin(l,mx); l=MathFloor(l/st)*st;
   return NormalizeDouble(l,2);
  }
double CalculateLotSize(double sd)
  {
   if(FixedLots>0) return NormalizeLots(FixedLots);
   if(sd<=0) return 0;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double risk=bal*RiskPercent/100.0;
   double tv=symInfo.TickValue(), ts=symInfo.TickSize();
   if(tv<=0||ts<=0) return symInfo.LotsMin();
   return NormalizeLots(risk/((sd/ts)*tv));
  }
int CountOpenTrades()
  {
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     if(posInfo.SelectByIndex(i))
       if(posInfo.Magic()==MagicNumber && posInfo.Symbol()==_Symbol) c++;
   return c;
  }
int OpenTradeDir()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     if(posInfo.SelectByIndex(i))
       if(posInfo.Magic()==MagicNumber && posInfo.Symbol()==_Symbol)
         return (posInfo.PositionType()==POSITION_TYPE_BUY)?1:-1;
   return 0;
  }
void CloseAllThisEA(string reason)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      ulong tk=posInfo.Ticket();
      if(trade.PositionClose(tk))
        { TriggerFlash(reason,ColExit,false,0,0,0); DispatchAlert(reason+" | "+_Symbol); }
     }
  }
void ManagePositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss(), tp=posInfo.TakeProfit();
      double pt=symInfo.Point(); ulong tk=posInfo.Ticket();
      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        { double bid=symInfo.Bid(), pp=(bid-op)/pt;
          if(UseBreakEven && pp>=BEat_Runtime){ double ns=op+BEprofit_Runtime*pt; if(sl<ns) trade.PositionModify(tk,ns,tp); }
          if(UseTrailingStop && pp>=TrailStart_Runtime){ double ts=bid-TrailStep_Runtime*pt; if(ts>sl) trade.PositionModify(tk,ts,tp); } }
      if(posInfo.PositionType()==POSITION_TYPE_SELL)
        { double ask=symInfo.Ask(), pp=(op-ask)/pt;
          if(UseBreakEven && pp>=BEat_Runtime){ double ns=op-BEprofit_Runtime*pt; if(sl>ns||sl==0) trade.PositionModify(tk,ns,tp); }
          if(UseTrailingStop && pp>=TrailStart_Runtime){ double ts=ask+TrailStep_Runtime*pt; if(ts<sl||sl==0) trade.PositionModify(tk,ts,tp); } }
     }
  }
//+==================================================================+
//|        v3.3.8 STRUCTURAL TAKE-PROFIT  (Pine f_structTP / f_tp)    |
//|  Nearest un-broken body-close S/R level beyond entry; if none,    |
//|  fall back to the WorkTF swing high/low over InpTPLookback bars.  |
//|  Mirrors the Pine strategy target logic 1:1 (Sci: "target the     |
//|  previous high / next liquidity pool").                           |
//+==================================================================+
double StructuralTPTarget(int dir, double entryPx)
  {
   double best = 0.0;
   // 1) nearest DRAWN, UN-BROKEN S/R level beyond entry, in trade dir
   for(int i=0;i<ArraySize(sr_price);i++)
     {
      if(!sr_drawn[i] || sr_broken[i]) continue;
      double lvl = sr_price[i];
      if(dir>0 && lvl>entryPx)
         best = (best==0.0 || lvl<best) ? lvl : best;   // closest ABOVE for longs
      if(dir<0 && lvl<entryPx)
         best = (best==0.0 || lvl>best) ? lvl : best;   // closest BELOW for shorts
     }
   // 2) fallback: WorkTF swing extreme over the lookback (Pine tpHi/LoFallback)
   if(best==0.0)
     {
      if(dir>0)
        {
         int    hi=iHighest(_Symbol,WorkTF,MODE_HIGH,InpTPLookback,1);
         double hh=(hi>=0)? iHigh(_Symbol,WorkTF,hi):0.0;
         best=(hh>entryPx)? hh : 0.0;
        }
      else
        {
         int    lo=iLowest(_Symbol,WorkTF,MODE_LOW,InpTPLookback,1);
         double ll=(lo>=0)? iLow(_Symbol,WorkTF,lo):0.0;
         best=(ll>0.0 && ll<entryPx)? ll : 0.0;
        }
     }
   return best;
  }
//--- Resolve the final TP price. Returns the TP; sets usedStruct by ref.
//    Fixed-RR is the default target; a structural level REPLACES it only
//    when it exists AND clears both floors (min 10 points, and >= d*MinRR).
double ResolveTP(int dir, double entryPx, double d, bool &usedStruct)
  {
   usedStruct=false;
   double tpx = (dir>0)? entryPx + d*RR_Ratio : entryPx - d*RR_Ratio; // fixed-RR base
   if(InpTPMode==TP_STRUCTURAL)
     {
      double lvl=StructuralTPTarget(dir,entryPx);
      if(lvl>0.0)
        {
         double dist=(dir>0)? (lvl-entryPx) : (entryPx-lvl);
         if(dist>=_Point*10 && dist>=d*InpTPMinRR)   // Pine: mintick*10 AND d*tpMinRR
           {
            tpx=lvl;
            usedStruct=true;
           }
        }
     }
   return tpx;
  }
//+==================================================================+
//|                 ORDER EXECUTION                                  |
//+==================================================================+
void ExecuteBuy(double slAnchor, string tag, color boxCol)
  {
   double ask=symInfo.Ask();
   double minStop=GetMinStopDistance();
   double structDist=ask-slAnchor; if(structDist<0) structDist=0;
   double slDist=CalculateSLDistance(structDist);
   double slPrice=NormalizeDouble(ask-slDist,_Digits);
   if(ask-slPrice<minStop*BrokerStopCushion){ if(DebugLog) Print("BUY skip: SL too close"); return; }
   double slFinal=ask-slPrice;
   bool   tpStruct=false;
   double tpPrice=NormalizeDouble(ResolveTP(1,ask,slFinal,tpStruct),_Digits);
   // broker-min guard: a structural target closer than the min stop is illegal -> revert to RR
   if(tpStruct && (tpPrice-ask) < minStop*BrokerStopCushion)
     { tpPrice=NormalizeDouble(ask+slFinal*RR_Ratio,_Digits); tpStruct=false; }
   g_lastTP=tpPrice; g_lastTPstruct=tpStruct;
   double lots=CalculateLotSize(slFinal);
   if(lots<=0){ if(DebugLog) Print("BUY skip: lots<=0"); return; }
   if(trade.Buy(lots,_Symbol,ask,slPrice,tpPrice,TradeComment))
     {
      TriggerFlash(tag,boxCol,true,ask,slPrice,tpPrice);
      DispatchAlert(StringFormat("%s | %s | E:%s SL:%s TP:%s",
        tag,_Symbol,DoubleToString(ask,_Digits),DoubleToString(slPrice,_Digits),DoubleToString(tpPrice,_Digits)));
     }
   else
      PrintFormat("BUY FAILED [%d]: %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }
void ExecuteSell(double slAnchor, string tag, color boxCol)
  {
   double bid=symInfo.Bid();
   double minStop=GetMinStopDistance();
   double structDist=slAnchor-bid; if(structDist<0) structDist=0;
   double slDist=CalculateSLDistance(structDist);
   double slPrice=NormalizeDouble(bid+slDist,_Digits);
   if(slPrice-bid<minStop*BrokerStopCushion){ if(DebugLog) Print("SELL skip: SL too close"); return; }
   double slFinal=slPrice-bid;
   bool   tpStruct=false;
   double tpPrice=NormalizeDouble(ResolveTP(-1,bid,slFinal,tpStruct),_Digits);
   // broker-min guard: a structural target closer than the min stop is illegal -> revert to RR
   if(tpStruct && (bid-tpPrice) < minStop*BrokerStopCushion)
     { tpPrice=NormalizeDouble(bid-slFinal*RR_Ratio,_Digits); tpStruct=false; }
   g_lastTP=tpPrice; g_lastTPstruct=tpStruct;
   double lots=CalculateLotSize(slFinal);
   if(lots<=0){ if(DebugLog) Print("SELL skip: lots<=0"); return; }
   if(trade.Sell(lots,_Symbol,bid,slPrice,tpPrice,TradeComment))
     {
      TriggerFlash(tag,boxCol,true,bid,slPrice,tpPrice);
      DispatchAlert(StringFormat("%s | %s | E:%s SL:%s TP:%s",
        tag,_Symbol,DoubleToString(bid,_Digits),DoubleToString(slPrice,_Digits),DoubleToString(tpPrice,_Digits)));
     }
   else
      PrintFormat("SELL FAILED [%d]: %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
  }
//+==================================================================+
//|                 SIGNAL ROUTING                                   |
//+==================================================================+
bool IsWithinSession()
  {
   MqlDateTime dt; TimeCurrent(dt);
   if(SessionStartHour<SessionEndHour) return(dt.hour>=SessionStartHour && dt.hour<SessionEndHour);
   return(dt.hour>=SessionStartHour || dt.hour<SessionEndHour);
  }
bool IsNewBar()
  { static datetime lt=0; datetime ct=iTime(_Symbol,_Period,0); if(ct!=lt){ lt=ct; return true; } return false; }
string PhaseTxt(int p){ return p==PH_INDICATION?"IND":p==PH_CORRECTION?"COR":"---"; }
void TryEntries()
  {
   if(UseSessionFilter && !IsWithinSession())
     { if(VerboseLog) Print("[ICC] session filter: outside window, no entries"); return; }
   // --- v1 cascade continuation edges (optional) ---
   double trigClose=iClose(_Symbol,TrigTF,1);
   bool buyCont = UseCascadeEntries && alignBull && wkLastHi>0 && trigClose>wkLastHi;
   bool sellCont= UseCascadeEntries && alignBear && wkLastLo>0 && trigClose<wkLastLo;
   bool cascBuy  = buyCont  && !prevBuyCont;
   bool cascSell = sellCont && !prevSellCont;
   prevBuyCont=buyCont; prevSellCont=sellCont;
   bool buySig  = iccBuySig  || retestBuySig  || cascBuy;
   bool sellSig = iccSellSig || retestSellSig || cascSell;
   // --- verbose diagnostic line (root-cause visibility, Appendix H/I) ---
   if(VerboseLog)
      PrintFormat("[ICC] bar=%d bias D1/H4/H1/M15=%d/%d/%d/%d HTF=%d HTFsc=%.2f | phase=%s dir=%d ind=%.2f ext=%.2f corr=%.2f | sig ICC(b/s)=%d/%d RET(b/s)=%d/%d CASC(b/s)=%d/%d | SR act=%d armed=%d",
         g_barCount,biasD1,biasH4,biasH1,biasM15,HTFbias(),HTFscore(),
         PhaseTxt(g_iccPhase),g_iccDir,g_indLevel,g_indExtreme,g_corrExtreme,
         (int)iccBuySig,(int)iccSellSig,(int)retestBuySig,(int)retestSellSig,
         (int)cascBuy,(int)cascSell,ActiveSRCount(),ArmedCount());
   int dir=OpenTradeDir();
   if(CloseOnOpposite && dir==1 && sellSig){ CloseAllThisEA("EXIT LONG"); dir=0; }
   if(CloseOnOpposite && dir==-1 && buySig){ CloseAllThisEA("EXIT SHORT"); dir=0; }
   if(CountOpenTrades()>=MaxOpenTrades) return;
   if(dir!=0) return;
   // --- entries when flat: ICC pullback FIRST (highest quality), then retest, then cascade ---
   if(iccBuySig)
     { double anchor=(iccSigSL>0)? iccSigSL : wkLastLo; ExecuteBuy(anchor,"ICC BUY (continuation)",ColBuy); return; }
   if(iccSellSig)
     { double anchor=(iccSigSL>0)? iccSigSL : wkLastHi; ExecuteSell(anchor,"ICC SELL (continuation)",ColSell); return; }
   if(retestBuySig)
     { double anchor=retestSigLevel-g_slBuf; ExecuteBuy(anchor,"RETEST BUY",ColRBuy); return; }
   if(retestSellSig)
     { double anchor=retestSigLevel+g_slBuf; ExecuteSell(anchor,"RETEST SELL",ColRSell); return; }
   if(cascBuy)
     { ExecuteBuy(wkLastLo,"BUY ENTRY (breakout)",ColBuy); return; }
   if(cascSell)
     { ExecuteSell(wkLastHi,"SELL ENTRY (breakout)",ColSell); return; }
  }
//+==================================================================+
//|                 DASHBOARD                                        |
//+==================================================================+
void UpdateDashboard()
  {
   if(!ShowDashboard){ Comment(""); return; }
   string bD=biasD1==1?"^":biasD1==-1?"v":"-";
   string b4=biasH4==1?"^":biasH4==-1?"v":"-";
   string b1=biasH1==1?"^":biasH1==-1?"v":"-";
   string b5=biasM15==1?"^":biasM15==-1?"v":"-";
   string casc=alignBull?"^ ALIGNED LONG":alignBear?"v ALIGNED SHORT":"x NOT ALIGNED";
   int dir=OpenTradeDir();
   string pos=dir==1?"LONG":dir==-1?"SHORT":"flat";
   string d ="=== ICC TradesBySci EA v3.3.10 (SMC) ====\n";
   d+=" Cascade (D1 H4 H1 M15): "+bD+" "+b4+" "+b1+" "+b5+"\n";
   d+=" HTF filter: "+(HTFbias()==1?"^ BULL":HTFbias()==-1?"v BEAR":"- flat")+
      "  score="+DoubleToString(HTFscore(),2)+" (min "+DoubleToString(HTF_MinConviction,2)+")\n";
   d+=" ICC phase: "+PhaseTxt(g_iccPhase)+" (dir "+IntegerToString(g_iccDir)+")\n";
   d+=" Position: "+pos+"  ("+IntegerToString(CountOpenTrades())+"/"+IntegerToString(MaxOpenTrades)+")\n";
   d+=" S/R lvls: "+IntegerToString(ActiveSRCount())+"  | armed: "+IntegerToString(ArmedCount())+"\n";
   // ---- v3.0 SMC structure engine rows ----
   d+="--- SMC Structure Engine ----------------\n";
   d+=" External trend: "+MSE_TrendText(g_extTrend)+"   Internal trend: "+MSE_TrendText(g_intTrend)+"\n";
   d+=" Protected High: "+(g_extProtHigh>0?DoubleToString(g_extProtHigh,_Digits):"-")+"\n";
   d+=" Protected Low:  "+(g_extProtLow >0?DoubleToString(g_extProtLow ,_Digits):"-")+"\n";
   d+=" Liquidity: "+g_liqStatus+"\n";
   d+=" Displacement score: "+DoubleToString(g_lastDispScore,0)+"/100\n";
   d+=" Nearest Bull FVG: "+MSE_NearestFVGText(1)+"\n";
   d+=" Nearest Bear FVG: "+MSE_NearestFVGText(-1)+"\n";
   // v3.3.6: pip-mode readout (verify ATR-auto vs fixed + the live S/R tol used)
   d+=" Pip mode: "+(InpUseATRauto?"ATR-AUTO":"FIXED")+"  srTol="+DoubleToString(g_tol,_Digits)+"\n";
   // v3.3.8: structural-TP readout — mode + last resolved target ([s]=struct, [rr]=fixed)
   d+=" TP mode: "+(InpTPMode==TP_STRUCTURAL?"STRUCTURAL":"FIXED_RR");
   if(g_lastTP>0.0) d+="  last="+DoubleToString(g_lastTP,_Digits)+(g_lastTPstruct?" [s]":" [rr]");
   d+="\n";
   // v3.3.9: FVG-containment mode readout — RELAXED (tol/band) vs STRICT point-in-gap
   d+=" FVG contain: "+(InpRelaxFVGContain? ("RELAX tol="+DoubleToString(g_fvgContainTol,_Digits)+(InpUseFVGband?"+band":"")) : "STRICT")+"\n";
   // v3.3.10: exit-label readout — mode + closed-trade count + last exit reason
   d+=" Exit lbls: "+(InpShowExitLabels? ("ON"+(InpExitLblShowProfit?"+P&L":"")) : "OFF")+
      "  Closed="+IntegerToString(g_closedTrades)+"  last="+g_lastExitReason+"\n";
   d+="=========================================";
   Comment(d);
  }
//+==================================================================+
//|                 LIFECYCLE                                        |
//+==================================================================+
int OnInit()
  {
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);
   symInfo.Name(_Symbol); symInfo.Refresh();
   // v3.3.4 metal pip scaling: 2-digit XAU gave g_pip=_Point=0.01 -> S/R tol
   // 0.10 (ten cents) -> no clustering on gold. Treat metals like fractional FX.
   bool isMetalSym = (StringFind(_Symbol,"XAU")>=0 || StringFind(_Symbol,"XAG")>=0 ||
                      StringFind(_Symbol,"GOLD")>=0|| StringFind(_Symbol,"SILVER")>=0 ||
                      StringFind(_Symbol,"XPT")>=0 || StringFind(_Symbol,"XPD")>=0);
   g_pip     = _Point*(((_Digits==3||_Digits==5) || (_Digits<=2 && isMetalSym))?10:1);
   // v3.3.6 ATR-auto: dedicated ATR handle on the chart TF; RefreshEffectiveDistances()
   // seeds g_tol/g_brkBuf/g_confBuf/g_slBuf/g_equalTol/g_sweepMin/g_fvgMin (ATR or fixed).
   g_atrAuto = iATR(_Symbol,_Period,InpATRautoLen);
   if(g_atrAuto==INVALID_HANDLE) Print("WARNING: ATR-auto handle failed; using fixed pips.");
   RefreshEffectiveDistances();
   AssetClass=DetectAssetClass();
   ApplyAssetClassScaling();
   atrHandle=iATR(_Symbol,_Period,ATR_Period);
   if(atrHandle==INVALID_HANDLE) Print("WARNING: ATR handle failed; ATR SL will fallback.");
   g_maHandle=iMA(_Symbol,_Period,SR_RefLen,0,MODE_SMA,PRICE_CLOSE);
   if(g_maHandle==INVALID_HANDLE) Print("WARNING: SMA handle failed; S/R classifier will fallback.");
   // v3.0: dedicated ATR on the SMC structure TF for displacement scoring
   g_mseTF=(InpMSE_TF==PERIOD_CURRENT)? (ENUM_TIMEFRAMES)_Period : InpMSE_TF;
   g_mseATR=iATR(_Symbol,g_mseTF,InpDispATRPeriod);
   if(g_mseATR==INVALID_HANDLE) Print("WARNING: SMC ATR handle failed; displacement ATR score will be 0.");
   ICC_Reset();
   EvaluateCascade();
   MSE_Update();                 // prime protected swings / liquidity / FVGs / OBs
   PrintBrokerDiagnostics();
   if(FlashOn) EventSetMillisecondTimer(FlashMs);
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(g_maHandle!=INVALID_HANDLE) IndicatorRelease(g_maHandle);
   if(g_mseATR!=INVALID_HANDLE) IndicatorRelease(g_mseATR);   // v3.0
   if(g_atrAuto!=INVALID_HANDLE) IndicatorRelease(g_atrAuto); // v3.3.6 ATR-auto
   ObjectsDeleteAll(0,SR_PFX);
   ObjectsDeleteAll(0,SW_PFX);
   ObjectsDeleteAll(0,FVG_PFX);   // v3.0 FVG rectangles
   ObjectsDeleteAll(0,OB_PFX);    // v3.0 order-block rectangles
   ObjectsDeleteAll(0,EXIT_PFX);  // v3.3.10 exit-label tags
   ClearFlashBox();
   Comment("");
  }
void OnTimer()
  {
   if(!FlashOn) return;
   if(!g_flashActive) return;
   g_flashPhase=!g_flashPhase;
   DrawFlashBox(g_flashPhase);
   g_flashTicks--;
   if(g_flashTicks<=0){ g_flashActive=false; ClearFlashBox(); }
   ChartRedraw();
  }
void OnTick()
  {
   ManagePositions();
   if(!IsNewBar()) return;
   symInfo.Refresh();
   g_barCount++;
   RefreshEffectiveDistances();   // v3.3.6: recompute ATR-auto (or fixed) structure/buffer distances each bar
   double c    = iClose(_Symbol,_Period,1);
   datetime t  = iTime(_Symbol,_Period,1);
   double barHi= iHigh(_Symbol,_Period,1);
   double barLo= iLow (_Symbol,_Period,1);
   // 1) cascade bias (loosened) — preserved for the multi-TF dashboard + soft-D1 gate
   EvaluateCascade();
   // 1b) v3.0 SMC structure engine: protected swings, liquidity, FVGs, order
   //     blocks. Also overrides wkLastHi/wkLastLo with PROTECTED internal swings.
   MSE_Update();
   // 2) swing rays (visual)
   ProcessSwing();
   // 3) body-close S/R with broken + retest + confirmation
   if(SR_Show)
     {
      SR_CheckBroken(c);
      SR_CheckRetest(barHi,barLo,c);
      SR_CheckConfirm(c);
      ProcessBar(c,t);
      ExpireLevels(iTime(_Symbol,_Period,0));
      UpdateActiveLevels(iTime(_Symbol,_Period,0));
     }
   else { retestBuySig=false; retestSellSig=false; }
   // 4) ICC Indication->Correction->Continuation pullback engine
   ICC_Update();
   // 5) entry routing (real orders)
   TryEntries();
   // 6) dashboard
   UpdateDashboard();
  }
//+------------------------------------------------------------------+
