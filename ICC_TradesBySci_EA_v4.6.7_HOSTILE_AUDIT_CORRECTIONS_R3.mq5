// ICC_TradesBySci_EA_v4.6.6_PHASE5_TARGET_EXECUTION_MANAGEMENT_AUTHORITY
// Phase-5 input: accepted Phase-4 Continuation / Entry Authority candidate.
// Phase 1 retained: CM-01/02/03/04/05/28.
// Phase 2 retained: CM-06/07/08/09/10/11.
// Phase 3 retained: CM-12/13/14/15/16/17.
// Phase 4 retained: CM-18/19/20/21/22/23.
// Phase 5 ONLY: CM-24/25/26/27 — structural target, preserved Correction SL/monetary sizing,
// setup-owner position management, and explicit ICC-cycle lineage.
// Approved hierarchy remains: H1 setup/Indication -> M15 Correction -> H1 Continuation -> M15/M5 execution.
// No change to Indication, Correction, Continuation, LTF-entry authority or concurrency.
// No fixed-R target fallback and no pip-based profitability authority.
#property copyright   "Chad Woodyard"
#property version "4.67"
// DIAGNOSTICS_R2: evidence only; trading baseline is the supplied v4.6.7 R1.
#property description "ICC v4.6.6 Phase 5 structural targets + owner-TF management + cycle lineage"
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
enum ENUM_TREND_HEALTH{ TH_HEALTHY=0, TH_CAUTION=1, TH_REVERSAL=2 };
enum ENUM_ML_MODE
  {
   ML_OFF=0,
   ML_OBSERVE=1,
   ML_SHADOW=2,
   ML_FILTER=3,
   ML_FILTER_SIZE=4,
   ML_FULL=5
  };
// v4.4.0: learned 2R probability engine. No surrogate/static-source fallback.
// v4.3.6 SCI CORE FIDELITY: which ICC PHASE the liquidity-sweep requirement gates.
// The Working Document (s7, first bullet) states the public material places
// liquidity interaction INSIDE THE CORRECTION, so requiring it BEFORE the
// Indication reverses the documented ICC chronology (CORE-04 -> CORE-05 -> CORE-06).
enum ENUM_LIQ_PHASE { LIQ_OFF=0, LIQ_INDICATION=1, LIQ_CORRECTION=2 };
// RB 2-3: independent roles and state families. No chart timeframe authority.
enum I465 { I465_NONE, I465_DEVELOPING_LTF, I465_CONFIRMED_HTF };
enum C465 { C465_NONE, C465_DEVELOPING_LTF, C465_CLARIFIED_LTF, C465_CONFIRMED_HTF };
enum T465 { T465_NONE, T465_DEVELOPING_LTF, T465_CONFIRMED_HTF, T465_CONFIRMED_LTF };
// Existing numeric values stay stable; Phase 4 appends the baseline transcript entry path.
enum E465 { E465_NONE, E465_AGGRESSIVE_LTF, E465_HTF_CONFIRMED, E465_BASELINE_LTF };
enum V465 { V465_ACTIVE, V465_INVALIDATED };
input group "=== v4.6.5 Rulebook authority (legacy qualification inputs retired) ==="
// Legacy compatibility inputs are retained, but GSTF/H4 no longer vetoes a clear H1-owned Continuation/entry path.
input ENUM_TIMEFRAMES InpGSTF=PERIOD_H4; // legacy downstream compatibility authority; no longer Indication owner
input ENUM_TIMEFRAMES InpObservationTF=PERIOD_H1;
input ENUM_TIMEFRAMES InpEntryTF=PERIOD_M15;
input group "=== v4.6.6 Phase 5 structural roles (authority unchanged; target/management ownership added) ==="
input ENUM_TIMEFRAMES InpSetupStructureTF=PERIOD_H1; // explicit H1 day trade or H4; owns Indication; never auto-selected
input ENUM_TIMEFRAMES InpContextTF=PERIOD_H4; // explicit H4 or D1 longer-term context
input datetime InpTradeEnableTime=0; // broker/server time; 0 = first tick with complete context
input group "=== v4.6.5 retained qualification / telemetry ==="
input double InpRule3BodyRatio=0.80; // TELEMETRY/CONFLUENCE: legacy Rule-of-Three body threshold
input double InpRule3MaxWickRange=0.20; // TELEMETRY/CONFLUENCE: legacy Rule-of-Three wick threshold
input int InpHTFClosePolicy=1; // User decision: formal owning-GSTF close beyond protected level
input group "=== v4.6.5 Authorized liquidity engine ==="
input int InpADRDays=20; // ADR20 for equal-pool tolerance
input int InpLiquidityLookback=800; // bounded candidate scan
input int InpSessionPivotStrength=2; // exact session-level swing: two candles each side
input double InpEqualBodyTolFactor=0.50; // body-level tolerance = 50% of wick tolerance
input double InpEqualCloseRatioMaxDiff=0.40; // maximum close-position divergence
input int InpBrokerUTCWinterHours=2; // historical tester-safe broker server UTC offset (configure for broker)
input int InpBrokerUTCSummerHours=3; // historical tester-safe broker server UTC offset (configure for broker)
input double InpDispQualityNetADRMin=0.125; // raw displacement quality: 12.5% ADR20 net move
input double InpDispQualityMaxBodyOverlap=0.25; // clean progression: <=25% body overlap
input double InpDispQualityMaxOpenGap=0.25; // continuity: open within 25% avg range of prior close
struct S465Swings
  {
   double hi,prevHi,lo,prevLo;
   datetime hiT,prevHiT,loT,prevLoT,hiKnown,prevHiKnown,loKnown,prevLoKnown;
  };
// Authorized SD05 AOI ranking metadata. Ranking is lexicographic:
// GSTF authority > structural event (MSS>BOS>CHoCH/minor) > displacement quality
// > liquidity significance > OTE location > freshness > recency.
struct S465AOI
  {
   double high,low;
   datetime created;
   ENUM_TIMEFRAMES tf;
   int eventRank;          // 3=MSS, 2=BOS, 1=CHoCH/minor
   double dispScore;       // 0..10, ranks already-valid Rule-of-Three displacements only
   int liquidityRank;      // 2=external/GSTF structural liquidity, 1=internal, 0=unknown
   bool inOTE;
   int freshnessRank;      // 2=untouched, 1=partially mitigated; invalid candidates are excluded
   string eventType,liquidityClass;
  };

struct S465State
  {
   S465Swings governing;
   ENUM_TIMEFRAMES gstf,observationTF,entryTF,zoneTF,indTF;
   I465 indication; C465 correction; T465 continuation; E465 entry; V465 validity;
   int dir;
   datetime id,indStart,indEnd,corrStart,corrConfirmTime,contTime,sweepTime,shiftTime,aoiTouchTime;
   datetime lastIndBar,lastCorrBar,lastEntryBar,lastGSTFBar,lastZoneBar;
   double protectedHigh,protectedLow,keyLevel,boundary,zoneClose;
   double indHigh,indLow,corrHigh,corrLow,brokenLevel,oteLowAnchor,oteHighAnchor;
   // Phase 4 audit state: owning setup continuation and lower-TF execution evidence.
   double continuationLevel,entryEvidenceLevel;
   ENUM_TIMEFRAMES continuationTF,entryEvidenceTF;
   datetime continuationLevelTime,entryEvidenceTime;
   // Phase 5 CM-24/26/27: execution objective, owner-context and trend-cycle lineage.
   // These fields are observational/persistent metadata only; they do not authorize ICC stages.
   double structuralTarget,lineageSeedExtreme;
   ENUM_TIMEFRAMES structuralTargetTF;
   int structuralTargetSource; // 0=none, 1=active Indication extreme, 2=higher-context swing
   datetime parentSetupId,nextSetupId;
   datetime oteOriginTime,oteEndTime,oteBreakTime;
   double fvgHigh,fvgLow,fvgMid,fvgMitigation;
   double sweepLevel,sweepExtreme,reclaimClose;
   double sweepQuality,reclaimStrength,liquidityEventScore;
   double displacementQualityRaw,liqDispScore;
   int liquidityAuthorityRank,liqTierScore,liqPenScore,liqContextScore,liqTimingScore;
   string liquidityEventClass;
   int reclaimTimingScore,reclaimCloseScore,reclaimWickScore,reclaimFollowScore;
   datetime sweepLevelTime,sweepPenetrationTime;
   int sweepBarShift,reclaimBarShift; datetime reclaimTime; bool sweepDisplacement,sweepPendingDisplacement;
   double aoiHigh,aoiLow; datetime aoiCreated; ENUM_TIMEFRAMES aoiTF;
   int aoiEventRank,aoiLiquidityRank,aoiFreshnessRank; double aoiDispScore; bool aoiInOTE; string aoiEventType,aoiLiquidityClass,aoiRankReason;
   bool aoiValid,aoiTouched,aoiRankedWithOTE,sweepConfirmed,consumed,indContextLogged;
   double bodyRatio,upperBody,lowerBody,wickRange,retrace,lastObserved;
   string reason,liquidityType;
  };
S465State g465;
// Phase 5 CM-27: survives ICC_Reset() so one completed structural cycle can seed/link the next.
// It is never consulted to authorize Indication/Correction/Continuation/entry.
struct S466CycleLineage
  {
   datetime setupId,continuationTime;
   int dir;
   ENUM_TIMEFRAMES ownerTF;
   double indicationExtreme;
   bool ready;
  };
S466CycleLineage g466Cycle;
int g465Direction=0; // LEGACY context/diagnostic direction; it does not veto H1-owned Continuation or baseline entry
// Separate lifetime from ICC_Reset(): markup/history must survive legacy setup resets.
struct S466StructureRoles
  {
   ENUM_TIMEFRAMES setupTF,contextTF,entryTF;
   S465Swings h1Swings,h4Swings,setupSwings,contextSwings;
   int setupDirection,contextDirection,h1Direction,h4Direction;
   double activeH1High,activeH1Low;
   datetime activeH1HighTime,activeH1HighKnownTime,activeH1LowTime,activeH1LowKnownTime;
   datetime contextStart,historyFirst,tradeEnableTime;
   bool historyAvailable,contextReady,tradeEnabled;
   datetime activeH1HighSelectedTime,activeH1LowSelectedTime;
   bool activeH1HighCrossed,activeH1LowCrossed;
   datetime activeH1HighCrossTime,activeH1LowCrossTime;
   double preBreakH1High,preBreakH1Low;
   datetime preBreakH1HighTime,preBreakH1HighKnownTime,preBreakH1HighSelectedTime,preBreakH1HighCrossTime;
   datetime preBreakH1LowTime,preBreakH1LowKnownTime,preBreakH1LowSelectedTime,preBreakH1LowCrossTime;
   datetime scanStart,structureAsOf,lastH1Bar,lastH4Bar,lastD1Bar,lastCheckedHour,nextHistoryRetry;
   int expectedH1Bars,missingH1Bars;
   string historyStatus;
   // Phase 2 CM-08/11: explicit setup-owner boundaries and no-trade diagnostics.
   double activeSetupHigh,activeSetupLow;
   datetime activeSetupHighTime,activeSetupHighKnownTime,activeSetupLowTime,activeSetupLowKnownTime;
   bool noTradeZone;
   string noTradeReason;
   ENUM_TIMEFRAMES lastBreakTF;
   int lastBreakDir;
   double lastBreakLevel;
   datetime lastBreakLevelTime,lastBreakKnownTime,lastBreakTime;
   bool lastRule3Pass;
  };
S466StructureRoles g466;
string g466TraceFile="",g466LastTraceKey="";
datetime g465ClockG=0,g465ClockO=0,g465ClockE=0,g465LastUsedInd=0;
string g465TraceFile="";
double g465PendingSL=0;
S465State g465Pending;
bool g465PendingValid=false;
ulong g465PendingOrder=0;



//============================= INPUTS ================================
input group "=== Entry Path (Sci ICC only) ==="
input bool   UseICCPullback    = true;          // Sci Indication->Correction->Continuation pullback (the ONLY entry path)
input bool   CloseOnOpposite   = true;          // Close open trade on an opposite ICC continuation (structure flip)
input group "=== Bias / Filter (Sci: HTF sets bias, LTF entry) ==="
input bool   BiasLoose         = true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input bool   UseD1Filter       = true;          // let D1 influence HTF bias as a SOFT weight
input double D1Weight          = 0.5;           // D1 weight vs H4 (0=ignore D1, 1.0=~old hard veto, >1 D1 dominates)
input double HTF_MinConviction = 0.5;           // Min net HTF score (same side as H4) required to trade
// v4.2.4 A/B TOGGLE (previously-deferred judgment call (a)): the HTFbias
// conviction gate compares the net HTF score against HTF_MinConviction. With
// the default INCLUSIVE test (>=/<=), an opposing D1 that pulls the score to
// EXACTLY the threshold still PASSES: e.g. H4 up (g_extTrend=1) + opposing D1
// (biasD1=-1) with D1Weight=0.5 gives score = 1 + (-1)*0.5 = 0.5, and
// 0.5 >= 0.5 -> long allowed. The STRICT test (>/<) VETOES that boundary case,
// so a same-side H4 whose conviction is only just at the floor (because D1
// opposes) no longer trades. This is a genuine TRADING-LOGIC choice, not a bug:
// OFF (default) reproduces EXACT v4.2.3 behaviour; ON makes the EA more
// selective (fewer trades, removes the "H4 says go, D1 disagrees, conviction
// exactly at floor" setups). Kept as an input so it can be A/B-tested in the
// Strategy Tester with ONE variable changing and no recompile. Re-validate
// expectancy/trade-count/drawdown against the OFF baseline before committing.
input bool   InpHTFStrictBoundary = false; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input group "=== ICC Pullback Tuning ==="
input double CorrRetraceMin    = 0.500; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input double CorrRetraceMax    = 0.900; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    ICC_ExpiryBars    = 30; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
//====================================================================
//  v4.3.0 STRUCTURAL CORRECTION DEFINITION (previously-DEFERRED fidelity
//  item from the v4.1.0 audit). Trades-by-Sci defines a Correction
//  STRUCTURALLY -- a counter-trend leg that prints a confirmed LOWER HIGH
//  (in a bull setup) or HIGHER LOW (in a bear setup), which remains valid
//  for as long as the IMPULSE ORIGIN holds -- not by an arbitrary fib
//  percentage of the impulse leg.
//  OFF (default) = EXACT v4.2.9 behaviour: Correction confirms at the
//    CorrRetraceMin (0.50) discount/premium threshold and invalidates at
//    CorrRetraceMax (0.90) of the impulse leg (or the OTE band when ON).
//  ON = Sci-structural interpretation:
//    - CONFIRM  : a CONFIRMED counter-trend minor pivot (lower high for a
//                 bull / higher low for a bear) has formed on TrigTF beyond
//                 the InpStructCorrMinRetrace floor, using the SAME
//                 validated-neighbour-bar fractal test the cascade and the
//                 Continuation trigger already use.
//    - INVALIDATE: a BODY CLOSE back beyond g_indLevel -- the protected
//                 swing the Indication broke. If price reclaims the level
//                 it just broke, the BOS failed; that, not a fib depth, is
//                 the structural death of the setup.
//  A small retrace FLOOR is retained so a 1-tick pivot right at the impulse
//  extreme cannot be mistaken for a genuine correction.
//  TRADING-LOGIC change: alters which Corrections confirm and when setups
//  invalidate -> live signal generation. Re-validate on the tester with a
//  one-variable A/B against the OFF baseline.
//====================================================================
input bool   InpUseStructuralCorrection = false; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input double InpStructCorrMinRetrace    = 0.10; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input bool   InpStructCorrKeepMaxDepth  = false; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
//====================================================================
//  v4.3.6 SCI CORE FIDELITY CONTROLS  (Research & Methodology Working
//  Document -- "Mechanical ICC Core Rulebook" CORE-01..CORE-12, s4;
//  "High-Priority Fidelity Concerns", s7; "Core vs Enhancement", s8).
//  EVERY toggle here DEFAULTS TO THE LEGACY v4.3.5 BEHAVIOUR, so this
//  build is byte-identical out of the box. That is deliberate: the
//  Working Document s9 instructs "Do not immediately modify the
//  production trading logic. First build a diagnostic-only shadow
//  evaluator" -- so the corrections ship as A/B-testable switches, and
//  the SHADOW EVALUATOR (default ON, log-only) measures which CORE rule
//  actually rejects each candidate before any of them are adopted.
//====================================================================
input group "=== Sci Core Fidelity (v4.3.6 / Working Document) ==="
// s9 Layer A/B/C evaluator. Trading-NEUTRAL: reads state, sets none.
input bool InpSciCoreShadow      = true;   // Log the CORE-rule fidelity evaluator (diagnostic only; changes NO trade)
input int  InpSciShadowThrottle  = 0;      // Log at most 1 shadow line per N bars (0 = every qualifying bar)
// s7 bullet 1 + CORE-06: liquidity belongs in the CORRECTION, not before the Indication.
input ENUM_LIQ_PHASE InpLiquidityPhase = LIQ_INDICATION; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
// s7 bullet 5 + CORE-07/08: the continuation pivot must be the CORRECTION's own
// structural transition, not merely the latest qualifying pivot in a lookback.
input bool InpContTrigSinceCorrection = false; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
// s4 CORE-01: HH+HL / LH+LL only; otherwise NEUTRAL (consolidation) rather than a forced direction.
input bool InpNeutralOnConsolidation  = false; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int  InpConsolidationBars       = 12;    // MidTF bars without a fresh protected-swing BOS before declaring consolidation
// Unit correction: the Correction develops on WorkTF, but expiry counts CHART bars.
input bool InpExpiryInWorkTFBars      = false; // v4.6.5: retained legacy setting; no SCI CORE/execution authority

input group "=== Timeframe Cascade (Sci D1->H4->H1->M15) ==="
input ENUM_TIMEFRAMES BiasTF   = PERIOD_D1;     // Top bias TF
input ENUM_TIMEFRAMES MidTF    = PERIOD_H4;     // Mid / primary Indication TF
input ENUM_TIMEFRAMES WorkTF   = PERIOD_H1;     // Working TF (swing anchor)
input ENUM_TIMEFRAMES TrigTF   = PERIOD_M15;    // Trigger TF (entry timing)
input int    CascadeSwingLen   = 5;             // Pivot length per-TF for cascade
input group "=== Stop Loss / Sizing ==="
input ENUM_SL_METHOD SL_Method = SL_SMART; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input double ATR_Multiplier    = 1.5;           // ATR multiplier
input int    ATR_Period        = 14;            // ATR period
input double BrokerStopCushion = 1.2; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input bool   AutoScaleByAsset  = true;          // Scale buffers for metal/index/crypto
input int    SL_Buffer_Points  = 50; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input double RR_Ratio          = 2.0; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input double RiskPercent       = 0.5;           // % balance risked per trade
input double FixedLots         = 0.0;           // >0 overrides risk-% sizing
input int    MaxOpenTrades     = 1;             // Max concurrent trades (this EA/symbol)
input bool   ShowDiagnostics   = true;          // Print broker diagnostics on init
input group "=== Take-Profit Mode (v2.2 parity) ==="
input ENUM_TP_MODE InpTPMode     = TP_FIXED_RR; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int          InpTPLookback = 200;         // Structural: WorkTF bars scanned for the fallback swing target
input double       InpTPMinRR    = 1.0; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
//====================================================================
//  v4.5.0 FINDING 4 (HIGH, TAKE-PROFIT CRITERIA). InpTPMinRR defaulted
//  to 1.0, so a STRUCTURAL target only 1R away was accepted and became
//  the order's take-profit -- while the learned model, the v2/v4 dataset
//  labels and the whole "2R classifier" premise are built on a 2R target.
//  A model trained to predict P(reached 2R) was therefore allowed to size
//  and approve trades whose TP was exited at 1R, so the label and the
//  executed objective disagreed. InpMinTPRR is a HARD FLOOR applied to
//  EVERY resolved target (fixed-RR and structural alike): a target closer
//  than this is pushed out to the floor, never accepted as-is.
//====================================================================
input double       InpMinTPRR    = 2.0; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input group "=== Trailing Stop ==="
input bool   UseTrailingStop   = true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    TrailingStart_Pts = 200; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    TrailingStep_Pts  = 100; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input group "=== Break Even ==="
input bool   UseBreakEven      = true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    BreakEvenAt_Pts   = 150; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    BreakEvenProfit   = 10; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
//====================================================================
//  v3.5.0 LET WINNERS RUN (Sci runner). When ON, the trade is opened
//  with NO fixed take-profit (open-ended) and is ridden by a profit-
//  LOCK ratchet: once unrealised profit reaches RunnerArm points the
//  stop is pulled into profit (break-even + RunnerLock) and thereafter
//  only ever ratchets TIGHTER (trail behind peak by RunnerTrail points
//  and/or behind the last protected swing). Because the stop stays in
//  profit after arming, the position REMAINS OPEN AS LONG AS IT IS
//  PROFITABLE and closes only when price retraces into the locked floor
//  or an opposite ICC continuation flips structure (CloseOnOpposite).
//  Point inputs scale by asset class exactly like Trailing/Break-Even.
//====================================================================
input group "=== Let Winners Run (Sci runner) ==="
input bool   InpLetWinnersRun     = true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    InpRunnerArmPts      = 200; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    InpRunnerLockPts     = 40; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    InpRunnerTrailPts    = 150; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input bool   InpRunnerUseStructure= true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
//====================================================================
//  v3.6.0 EXIT ENGINE (R-multiple phased runner). Measures protection
//  in R (1R = |entry - initial SL|) so it self-scales to each setup and
//  to volatility (no arbitrary points). When ON it SUPERSEDES UseBreak-
//  Even / UseTrailingStop / the v3.5.0 point runner for the managed
//  position. Stages: PROTECT at +ProtectR (break-even), LOCK at +LockR,
//  ACTIVATE the STRUCTURE RUNNER at +ActivateR (structure-confirmed
//  trailing + progressive give-back floor + wide ATR emergency floor).
//  Master OFF = exact v3.5.0 management.
//====================================================================
input group "=== Exit Engine v3.6 (R-multiple runner) ==="
input bool   InpUseRexit           = false;  // Optional monetary R-stop experiment; default holds to owner structure/structural TP
input double InpProtectAtR         = 1.0;    // +R to move the stop to break-even (Phase 2 protect)
input double InpProtectLockR       = 0.0;    // R locked at protect (0 = pure break-even + buffer)
input double InpLockAtR            = 1.5;    // +R at which to lock meaningful profit (Phase 2b)
input double InpLockProfitR        = 0.5;    // R of profit locked from +LockR onward
input double InpActivateAtR        = 2.0;    // +R to activate the STRUCTURE RUNNER (Phase 3)
input double InpRunnerGiveBackR    = 2.0;    // Progressive floor beyond activation: lock (curR - this) in R
input bool   InpRunnerExternStruct = true;   // Runner trails behind PROTECTED EXTERNAL structure (primary)
input bool   InpRunnerInternStruct = true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input bool   InpRunnerATRFloor     = true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input double InpRunnerATRfloorMult = 3.0; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input bool   InpUsePartial         = false;  // Take an optional partial at +ActivateR (leave the rest running)
input double InpPartialPct         = 25.0;   // Percent of the position to close at the partial (0..100)
input bool   InpUseTrendHealth     = true;   // Trend-health governor (HEALTHY hold / CAUTION tighten / REVERSAL exit)
input bool   InpCloseOnConfirmedRev= true;   // Opposite ICC closes a runner ONLY with a confirmed external reversal
input group "=== Support / Resistance (structural-TP level map) ==="
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
input group "=== ICC Signal SL Buffer ==="
input double RetestSLbufPips    = 3.0;          // ICC continuation SL buffer beyond the correction extreme (pips)
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
input group "=== Alerts ==="
input bool   AlertPopup         = true;
input bool   AlertPush          = false;
input bool   AlertEmail         = false;
input bool   AlertSound         = false;
input string AlertSoundFile     = "alert.wav";
input group "=== EA Settings ==="
input ulong  MagicNumber        = 20260717;
input int    Slippage           = 30;
input string TradeComment       = "ICC-Sci-EA-v4.6.5";
input bool   DebugLog           = false;        // Print SL/lot skip reasons
input bool   VerboseLog         = true;         // Print bias/phase/signals every bar
//--- v4.6.1: the contract token is versioned WITH the feature set, not with the
//    EA. Bump it in lockstep with ANY change to the ML2RFeatures field order or
//    semantics in ML2RFeatures; leaving it stale is the one way to reopen the silent
//    stale-model hole this guard exists to close. The tensor SHAPE is not a
//    contract -- it was identical across the v4.5.0/v4.6.0 feature change.
#define ML2R_CONTRACT_TOKEN "icc_path_v2"
//    DECLARED HERE, ABOVE THE INPUT BLOCK, DELIBERATELY: the MQL5 preprocessor
//    is single-pass top-down, so a macro used as an `input` default must be
//    defined earlier in the file than that input. Declaring it beside
//    ML2R_FEATURE_COUNT (~line 830) reads better but does not compile.

input group "=== ML 2R Learned Model v4.4 ==="
input ENUM_ML_MODE InpMLMode=ML_OFF; // methodology validation default: no learned decision authority
input bool   InpMLModelEnabled=false;
input string InpMLModelFile="ICC_2R_v2.onnx";
// Model contract: one float tensor [1,28] -> one probability output [1,1].
//
// v4.6.1 BINDING CONTRACT GUARD.
// v4.6.0 changed the FEATURE SET but not the tensor SHAPE, which left a silent
// failure mode: a pre-v4.6.0 .onnx satisfies inputs==1, outputs==1 and [1,28],
// so it loads CLEANLY and then scores garbage, because slot i now carries a
// different quantity than it was trained on. Renaming the default file to _v2
// and printing a banner are ADVISORY ONLY -- neither can prevent the load, and
// a garbage-scoring gate is indistinguishable at runtime from a working one.
//
// The guard below binds the contract to the ONNX INPUT TENSOR NAME, which the
// trainer sets at export time and which is baked into the graph. Unlike a
// filename it cannot be defeated by renaming or copying the artifact.
//
//   skl2onnx : convert_sklearn(clf, initial_types=[("icc_path_v2",
//                                FloatTensorType([1,28]))])
//   torch    : torch.onnx.export(..., input_names=["icc_path_v2"])
//
// Models exported without an explicit name carry the framework default
// ("float_input" for skl2onnx, "input"/"onnx::Gemm_0" for torch) and are
// therefore REJECTED -- which is the intended behaviour, because an unnamed
// artifact cannot prove which feature set it was trained on.
input string InpMLContractToken=ML2R_CONTRACT_TOKEN;
// Fail-closed by default. Setting this false restores the v4.6.0 behaviour of
// loading any shape-compatible model, and is logged as a FAIL-OPEN warning on
// the same terms as the InpMLRequireModel=false warning in ML_Evaluate2R.
// InpMLAutonomous=true requires this to stay true (enforced in OnInit).
input bool   InpMLEnforceContract=true;
input bool   InpMLRequireModel=true;
input double InpML2RThreshold=0.60;
input double InpML2RHighThreshold=0.75;
input double InpMLLowRiskMult=0.50;
input double InpMLBaseRiskMult=1.00;
input double InpMLHighRiskMult=1.25;
//====================================================================
//  v4.5.0 AUTONOMOUS LEARNED-2R CONTROLS.
//
//  FINDING 2 (CRITICAL, TRADE-PATH): g_mlRunner was declared true, set
//  true at the top of ML_Evaluate2R, and NEVER ASSIGNED FALSE ANYWHERE in
//  the entire file. Both ExecuteBuy and ExecuteSell read
//      if((InpLetWinnersRun || InpUseRexit) && g_mlRunner){ tpPrice=0.0; }
//  and InpLetWinnersRun defaults TRUE -- so the condition was a tautology
//  and EVERY order was sent with tpPrice=0.0. The entire take-profit stack
//  (ResolveTP, StructuralTPTarget, RR_Ratio, InpTPMode, InpTPLookback,
//  InpTPMinRR) was unreachable dead code at default inputs, and the v4.0.4
//  comment claiming "if ML runner-selection was false at entry, a real TP
//  got attached" described behaviour that could not occur. FIX: the learned
//  probability now SELECTS the exit policy, which is the one genuinely
//  ML-driven trade decision the objective requires:
//      P(2R) >= InpMLRunnerMinP2R  -> RUNNER (no fixed TP; R-engine rides it)
//      P(2R) <  InpMLRunnerMinP2R  -> a real TP at >= InpMinTPRR is attached
//  Set InpMLRunnerByProb=false to reproduce v4.4.2 byte-identically.
//
//  FINDING 3 (CRITICAL, CONFIG TRAP): with a FILTERING mode selected and
//  InpMLModelEnabled=false, ML_Evaluate2R sets g_mlPass=false on EVERY
//  signal -- a total, permanent trade blockade whose only trace was a log
//  line. InpMLAutonomous makes the operating contract explicit and is
//  validated at OnInit (see the init banner) instead of failing silently.
//====================================================================
input bool   InpMLAutonomous    = false; // AUTONOMOUS: require a loaded model + fail-closed gate; refuse init if the ML config cannot trade
input bool   InpMLRunnerByProb  = true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
//====================================================================
//  v4.6.2 FINDING 4 (HIGH, TRADE PATH). InpMLRunnerByProb only takes
//  effect after a SUCCESSFUL inference. With the DEFAULT
//  InpMLModelEnabled=false -- or any failed OnnxRun, or a model
//  rejected by the v4.6.1 contract guard -- ML_Evaluate2R returns
//  with g_mlRunner still at its initial TRUE, so ExecuteBuy/Sell
//  force tpPrice=0.0 and EVERY trade is open-ended. The entire
//  take-profit stack, including the InpMinTPRR 2R hard floor added
//  by v4.5.0 Finding 4, is therefore dead code at default inputs.
//  This input decides the exit policy when NO probability exists:
//    false (default, CORRECTED) -> attach a real TP at >=InpMinTPRR.
//        The 2R objective is enforced by the engine rather than
//        delegated to a model that is not running.
//    true  (legacy v4.6.1)      -> ride open-ended, as before.
//  *** TRADING-AFFECTING at default inputs. Trades now carry a
//  *** broker-side TP whenever the model is off/unavailable. A/B it
//  *** against true per Master Spec s15.1 before committing.
//====================================================================
input bool   InpRunnerWhenNoInference = false; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input double InpMLRunnerMinP2R  = 0.75; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input double InpML2RLowThreshold= 0.00;  // >0: signals in [this .. InpML2RThreshold) TRADE at InpMLLowRiskMult instead of being vetoed (0 = legacy veto)
input bool   InpMLObserveWhenBusy=true;  // Evaluate + log the gate for signals that fire while a position is open (records only; places NO order)
input bool   InpMLLogInference=false;
input bool   InpMLExportCSV=true;
input string InpMLCSVFile="ICC_465_compat_v1.csv";
input group "=== ML v2 Trade Labeling (icc_ml_v2) ==="
input bool   InpMLv2Export  = true;                 // Write ONE finalized row per completed trade (true 2R label)
input string InpMLv2CSVFile = "ICC_465_compat_v2.csv"; // Separate one-row-per-trade dataset (train the 2R model on this)
input group "=== ML v4.0 Canonical Dataset ==="
input bool   InpMLv4Export = true;
input string InpMLv4CSVFile = "ICC_465_trades.csv";
input bool   InpICCGateDiagnostics = false; // logs ICC indication/continuation gate reasons; does not change trading logic
// v4.2.1 HARDENING (heartbeat): emit ONE low-noise "[ICC GATE] heartbeat" line
// every N processed bars, INDEPENDENT of InpICCGateDiagnostics, so an operator
// can always tell "the gate is alive and correctly quiet" apart from "the
// engine went dark / isn't running" -- the exact ambiguity behind the earlier
// "no [ICC GATE] appeared" episode. Purely a Print; it reads state and NEVER
// sets any ICC/gating/sizing/trading state, so backtest trade results are
// byte-identical with it on or off. 0 = disabled. On a ~30k-bar M15 run,
// N=50 adds ~600 lines, N=200 ~150.
input int    InpGateHeartbeatBars  = 50;    // [ICC GATE] heartbeat every N bars (0=off); trading-neutral, log-only
//====================================================================
//  NEW INPUTS — SMC MARKET STRUCTURE ENGINE (v3.0). Every threshold
//  is configurable. All requirement toggles default ON (new behaviour);
//  turn them OFF to reproduce the v2.1 raw-pivot workflow exactly.
//====================================================================
input group "=== SMC: Structure TF & Protected Swings ==="
// AUDIT FIX (v4.1.0 / Core-Engine Findings 1+2, CRITICAL): InpMSE_TF (a single
// structure timeframe shared by BOTH external and internal structure, default
// PERIOD_CURRENT = whatever the chart is attached to) is REMOVED. Previously,
// External and Internal structure differed ONLY by fractal strength (4 vs 2
// bars) on the IDENTICAL timeframe -- if this EA was attached to an M15 chart
// (a natural choice, since TrigTF=M15 is documented as "entry timing"), the
// Indication break level was drawn from M15 fractals, silently defeating the
// documented D1->H4->H1->M15 cascade and the WorkTF "swing anchor" role. Fix:
// External structure now ALWAYS computes on MidTF (H4, already documented as
// the "primary Indication TF"); Internal structure -- and the liquidity/FVG/
// order-block/displacement engines that feed the entry side -- now ALWAYS
// compute on WorkTF (H1, already documented as the "swing anchor"). This is
// not a new design choice; it corrects the code to match the roles the EA's
// OWN input comments already claimed for MidTF/WorkTF. As a direct consequence,
// the former "silent WorkTF override" (wkLastHi/wkLastLo being overwritten by
// internal-structure fractals) is no longer a bug: internal structure IS now
// genuinely WorkTF/H1-based, so feeding its protected swings into the ICC
// Indication anchor is the CORRECT, intended behaviour, not a contradiction.
input int    InpIntSwingStrength   = 2;          // Internal (WorkTF/H1) swing fractal strength (bars each side)
input int    InpExtSwingStrength   = 4;          // External (MidTF/H4) swing fractal strength (bars each side)
input int    InpStructLookback     = 300;        // Bars scanned to locate protected swings
input bool   InpBOSUseClose        = true;       // BOS requires a BODY close beyond the protected swing (else wick)
input bool   InpExtTrendControlsDir= true;       // External trend gates trade DIRECTION
input bool   InpIntTrendControlsEnt= true;       // Internal BOS gates the ENTRY (Indication) trigger
input group "=== ICC Continuation Trigger (v4.1.0) ==="
// AUDIT FIX (v4.1.0 / Core-Engine Finding 3): the Continuation trigger
// previously tested price against iHigh/iLow(TrigTF,2) -- a rolling, UN-
// CONFIRMED "2 bars ago" offset recomputed fresh every bar, with zero
// relationship to the correction's own structure. As the Correction phase
// persisted, this level slid forward arbitrarily, letting Continuation fire
// on stale noise or blocking a genuine one, purely based on what happened to
// sit 2 candles back. Fix: the trigger is now a genuine CONFIRMED minor-swing
// fractal pivot on TrigTF (M15), found by scanning backward for the nearest
// bar satisfying the existing IsPivotHighTF/IsPivotLowTF test (same validated-
// neighbor-bar guard used by the D1/H4/H1/M15 cascade) at InpMinorPivotStrength
// bars each side. Default strength=1 (fastest confirmation) matches M15's
// documented role as the "entry timing" TF and Sci's stated preference for
// simple, timely entries over added filtering.
input int    InpMinorPivotStrength  = 1;    // Confirmed minor-pivot fractal strength on TrigTF (bars each side)
input int    InpMinorPivotLookback  = 20;   // Bars scanned backward on TrigTF to find the confirmed minor pivot
input group "=== SMC: Liquidity Engine ==="
input bool   InpRequireSweep       = true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    InpLiqLookback        = 120;        // Bars scanned for liquidity pools / equal levels
input double InpEqualLevelTolPips  = 2.0;        // Tolerance for equal highs / equal lows (pips)
input bool   InpRequireReclaim     = true;       // Require price to RECLAIM the swept level
input int    InpReclaimBars        = 3;          // Bars allowed for the reclaim to complete
input int    InpSweepValidBars     = 8;          // Sweep stays valid to arm an Indication for N WorkTF/H1 bars (v4.2.7: now genuine H1 bars, not per-M15 tick)
input double InpSweepMinPips        = 1.0;        // Min penetration beyond the level to count as a raid
// AUDIT FIX (v4.2.1 / Finding A, CRITICAL): the sell-/buy-side liquidity pool
// used by the Indication sweep gate was built as the 120-bar RANGE EXTREME
// (iLowest/iHighest over InpLiqLookback, combined via MIN/MAX). Because a LONG
// setup also requires g_extTrend==1 (H4 up) and a SHORT requires g_extTrend==-1
// (H4 down), a same-side sweep of the 120-bar extreme is a deep counter-trend
// event that essentially never co-occurs with the required HTF alignment --
// producing ZERO Indications across a full 10-month XAUUSD backtest. When ON
// (default), the pool is the NEAREST internal liquidity price price would take
// out on a pullback (recent protected internal swing / equal-level cluster),
// which is the genuine ICC "sweep the pullback liquidity" magnet. Set OFF to
// reproduce the exact v4.2.0 range-extreme behaviour.
input bool   InpSweepNearestPool    = true;       // Sweep pool = nearest internal swing/equal-level (OFF = v4.2.0 120-bar extreme)
input group "=== SMC: Fair Value Gaps ==="
input bool   InpRequireFVGpullback = true; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
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
input bool   InpRequireOB          = false; // v4.6.5: retained legacy setting; no SCI CORE/execution authority
input int    InpOBScanBack         = 8;          // Bars searched back from a displacement for the OB
// AUDIT FIX (v4.5.0 / Finding 8, MEDIUM, CROSS-WIRE): MSE_ScanOBs() sized its scan
// depth with InpFVGScanBars -- an input documented and grouped under "SMC: Fair
// Value Gaps". Tuning the FVG scanner silently changed order-block detection range,
// which is the same class of defect as the v4.1.0 Finding 4 SwingLen/InpLiqLookback
// cross-wire. The OB engine now has its own depth input.
input int    InpOBScanBars         = 120;        // Bars scanned each update for new order blocks (was cross-wired to InpFVGScanBars)
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
input double InpFracSLbuf      = 0.30;    // ICC signal SL buffer (x ATR)
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
//====================================================================
//  v3.4.0 SCI KILL-ZONE SESSIONS (opt-in). Restrict NEW entries to the
//  ICT/Sci kill zones. Hours are BROKER-SERVER hours (adjust to your
//  broker GMT offset). OFF (default) = exact v3.3.10 all-hours flow.
//====================================================================
input group "=== Sci Kill-Zone Sessions (v3.4.0) ==="
input bool   InpUseKillzones  = false;  // Gate ALL entries to Sci kill zones (broker-server time)
input bool   InpKZ_London     = true;   // Enable London Open kill zone
input int    InpKZ_LonStart   = 7;      // London KZ start hour (broker time, 0-23)
input int    InpKZ_LonEnd     = 10;     // London KZ end hour (broker time, 0-23)
input bool   InpKZ_NYam       = true;   // Enable New York AM kill zone
input int    InpKZ_NYamStart  = 12;     // NY AM KZ start hour (broker time, 0-23)
input int    InpKZ_NYamEnd    = 15;     // NY AM KZ end hour (broker time, 0-23)
input bool   InpKZ_NYpm       = true;   // Enable New York PM kill zone
input int    InpKZ_NYpmStart  = 17;     // NY PM KZ start hour (broker time, 0-23)
input int    InpKZ_NYpmEnd    = 20;     // NY PM KZ end hour (broker time, 0-23)
//====================================================================
//  v3.4.0 SCI OTE ENTRY WINDOW (opt-in). When ON, the ICC Correction
//  must retrace into the 0.62-0.79 Optimal-Trade-Entry band before a
//  Continuation is allowed (Sci OTE entries). OFF (default) = the raw
//  CorrRetraceMin/Max band (exact v3.3.10 behaviour).
//====================================================================
input group "=== Sci OTE Entry Window (v3.4.0) ==="
input bool   InpUseOTE        = false;  // Require correction into the 0.62-0.79 OTE band before continuation
input double InpOTEmin        = 0.62;   // OTE shallow edge (min retrace of the impulse)
input double InpOTEmax        = 0.79;   // OTE deep edge (max retrace before invalidation)
//====================================================================
//  v3.9.3 ICC IMPULSE-MATURATION GUARD (opt-in; default OFF). Holds an
//  Indication impulse OPEN until it has developed for InpICCImpulseBars
//  bars OR its leg reaches InpICCMinLegATR x ATR, before the disc/inval
//  band is evaluated. Prevents a tiny first-bar leg from placing the
//  deep-invalidation threshold on the breakout price and resetting the
//  setup instantly. OFF reproduces the EXACT v3.9.2 ICC behaviour.
//====================================================================
input group "=== ICC Impulse Maturation (v3.9.3) ==="
input bool   InpUseImpulseMaturation = false; // Hold the impulse open until it matures (bars OR ATR leg) before disc/inval
input int    InpICCImpulseBars       = 2;     // Min bars since Indication before disc/inval arms (maturation by time)
input double InpICCMinLegATR         = 0.5;   // OR: min impulse leg as x ATR to mature instantly (0 = time-only)
//============================ GLOBALS ================================
CTrade        trade;
CPositionInfo posInfo;
CSymbolInfo   symInfo;
double g_pip=0, g_tol=0, g_brkBuf=0, g_slBuf=0;
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
// v3.5.0 Let-Winners-Run runtime (asset-class scaled, like Trailing/BE)
int    RunnerArm_Runtime=0, RunnerLock_Runtime=0, RunnerTrail_Runtime=0;
// v3.6.0 R-multiple exit-engine per-ticket registry (captures 1R = |entry-initial SL|)
ulong  g_rxTicket[];
ulong  g_rxIdentifier[];
double g_rxEntry[];
double g_rxRisk[];
bool   g_rxPartial[];
string PFX    = "ICCsciEA21_";
string SR_PFX = "ICCsciEA21_SR_";
string SW_PFX = "ICCsciEA21_SW_";
string g_swingNames[];
struct SwingCache { double lastHi, prevHi, lastLo, prevLo; };
SwingCache cD1, cH4, cH1, cM15;
int  biasD1=0, biasH4=0, biasH1=0, biasM15=0;
bool alignBull=false, alignBear=false;
double wkLastHi=0, wkLastLo=0;
// ---- ICC pullback state machine ----
int      g_iccPhase = PH_NONE;
int      g_iccDir   = 0;      // +1 bull setup, -1 bear setup
double   g_indLevel = 0.0;    // swing broken during Indication (impulse origin)
double   g_indExtreme = 0.0;  // furthest extreme reached during impulse
double   g_corrExtreme = 0.0; // pullback extreme during Correction (SL anchor)
int      g_iccStartBar = 0;   // bar the Indication fired (for expiry)
// AUDIT FIX (v4.3.1 / Finding A, CRITICAL): g_iccStartBar is a CHART-bar counter,
// so it cannot be used to bound a TrigTF pivot search. This wall-clock stamp of
// the Indication bar lets ICC_FindMinorPivot*Since() reject any pivot that formed
// BEFORE the impulse -- see the Finding A note on ICC_StructuralCorrectionOK().
datetime g_iccStartTime = 0;  // TIME the Indication fired (bounds the structural pivot search)
// v4.3.6 (Finding B / Working Document s7 bullet 5 + CORE-07/08): the CONTINUATION
// trigger must reference the CORRECTION's own structural transition. That requires a
// bound at the moment the Correction CONFIRMED, which the engine never recorded --
// g_iccStartTime marks the INDICATION, which is one phase too early.
datetime g_corrStartTime = 0;  // TIME the Correction confirmed (bounds the continuation pivot)
// v4.3.6 (Finding C / CORE-01): bars since the external protected structure last
// produced a genuine BOS. Used to declare NEUTRAL/consolidation instead of letting a
// stale one-off BOS persist as a permanent direction.
datetime g_extLastBOSTime = 0;
int      g_extBarsNoBOS   = 0;
bool     iccBuySig=false, iccSellSig=false;
double   iccSigSL=0.0;
// ---- v3.3.8 structural-TP readout state ----
double g_lastTP=0.0;         // last resolved TP price (for dashboard / diagnostics)
bool   g_lastTPstruct=false; // was the last TP a structural target (true) or fixed-RR (false)?
// ---- v3.0 SMC market-structure engine state ----------------------
// AUDIT FIX (v4.1.0 / Core-Engine Findings 1+2): g_mseTF (a single shared
// structure TF) is REPLACED by g_extTF (External structure -> MidTF/H4) and
// g_intTF (Internal structure + liquidity/FVG/OB/displacement -> WorkTF/H1).
// g_mseATR/g_mseATRval now measure ATR on g_intTF (H1) -- the same TF the
// liquidity, FVG, OB and displacement engines that consume it operate on.
int      g_mseATR = INVALID_HANDLE;   // ATR handle on the INTERNAL structure TF (g_intTF)
double   g_mseATRval = 0.0;
ENUM_TIMEFRAMES g_extTF = PERIOD_H4;   // External structure TF -- always MidTF (Sci: "primary Indication TF")
ENUM_TIMEFRAMES g_intTF = PERIOD_H1;   // Internal structure TF -- always WorkTF (Sci: "swing anchor"); also liquidity/FVG/OB/displacement
// dual structure
double   g_extProtHigh=0.0, g_extProtLow=0.0;   // external protected swings (direction)
double   g_intProtHigh=0.0, g_intProtLow=0.0;   // internal protected swings (entries)
int      g_extTrend=0, g_intTrend=0;            // 1 up / -1 down / 0 none
// liquidity
string   g_liqStatus="none";
double   g_bsl=0.0, g_ssl=0.0;                  // buy-/sell-side liquidity levels
int      g_sweepConfLong=0, g_sweepConfShort=0; // bars-remaining a sweep+reclaim stays valid
double   g_lastSweepLvl=0.0;
// v4.6.0 PATH FEATURES: the BAR the sweep was armed on, per side. The engine
// already tracks WHETHER a sweep is armed (g_sweepConf*) and for how much
// longer, but never WHEN it armed relative to the Indication -- so the tensor
// could not distinguish "raid then break" (LIQ_INDICATION chronology) from
// "break then raid inside the correction" (the CORE-06 chronology the Working
// Document s7 argues for). These stamps make that ordering measurable.
datetime g_sweepArmTimeLong=0, g_sweepArmTimeShort=0;
// AUDIT FIX (v4.2.7 / deferred item (b)): the sweep-validity counters above are
// measured in g_intTF (WorkTF/H1) bars -- the sweep is DETECTED on H1 -- but were
// decremented once per MSE_UpdateLiquidity() call, i.e. once per NEW CHART-TF bar
// (M15 in the documented cascade). So "InpSweepValidBars=8" really meant 8xM15
// (2 hours = ~2 H1 bars), not 8 H1 bars. g_lastLiqIntBarTime tracks the last H1
// bar time so the countdown now advances exactly once per new H1 bar.
datetime g_lastLiqIntBarTime=0;
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
// AUDIT FIX (v4.3.4 / Finding A, HIGH, RUNTIME REGRESSION introduced by v4.3.3):
// v4.3.3 gave MSE_AddFVG/MSE_AddOB a history back-fill loop, but BOTH functions
// REJECT a structure that is already dead (fill% >= InpFVGFillInvalidate, or an
// order block already closed through) by returning WITHOUT inserting it. A
// rejected structure is therefore absent from the store, so MSE_FVGExists /
// MSE_OBExists returns false for it on the NEXT bar too -- and the scanner
// re-detects it and re-runs the O(barsSince) back-fill loop AGAIN, every bar,
// forever. With InpFVGScanBars=120 that is sum(s-1) = 7,140 loop iterations per
// direction per bar (14,280 both ways, ~28,560 iHigh/iLow calls per bar), i.e.
// ~857 MILLION redundant history reads across a 30,000-bar M15 run.
// FIX: the deep historical scan only needs to run ONCE, at warm-up. After that,
// bars arrive one at a time, so the only gap/OB that can newly COMPLETE is at
// the shallow end of the series. These flags make the first scan deep and every
// later scan shallow (see MSE_ScanFVGs / MSE_ScanOBs), which removes the
// repeated back-fill entirely while detecting exactly the same structures.
bool     g_fvgScanPrimed=false;
bool     g_obScanPrimed =false;
// AUDIT FIX (v4.3.5 / Finding C, MEDIUM, TRADING-AFFECTING): v4.3.4 capped the
// post-warm-up scan at a HARDCODED 4 bars. That silently assumes at most ~4 g_intTF
// (WorkTF/H1) bars elapse between two MSE_Update() calls -- true only on the
// documented M15 chart. Attach the SAME EA to H4 or D1 (or lose bars to a terminal
// reconnect / tester history rebuild / symbol resync) and 6, 24 or more H1 bars pass
// per update, so every FVG and order block formed in that window is NEVER detected --
// permanently, because the shallow scan can never reach back that far again.
// g_lastScanIntBarTime records the g_intTF bar the last scan covered, so the depth is
// now the ACTUAL number of elapsed g_intTF bars (plus a small safety margin), which
// is self-correcting on any chart TF and after any gap in processing.
datetime g_lastScanIntBarTime=0;
//--- Bars of g_intTF that have printed since the previous scan, + safety margin.
//    Returns a large value if the tracker is unset (forces a deep scan).
int MSE_ScanDepthNeeded()
  {
   datetime cur=iTime(_Symbol,g_intTF,0);
   if(cur<=0 || g_lastScanIntBarTime<=0) return 1000000;      // unknown -> scan deep
   int prev=iBarShift(_Symbol,g_intTF,g_lastScanIntBarTime,false);
   if(prev<0) return 1000000;                                  // stamp fell out of history
   return prev+4;                                              // elapsed bars + margin
  }
// ---- v3.3.10 exit-label state ----
string   EXIT_PFX="ICCsciEA310_EXIT_";  // chart-object prefix for exit tags
int      g_exitLblUID=0;                // unique id for each exit label pair
int      g_closedTrades=0;              // running count of closed trades (this EA)
string   g_lastExitReason="-";          // last exit reason (SL/TP/TRAIL-BE/OPP-CLOSE) for dashboard
// AUDIT FIX (v4.0.4): staged BEFORE each trade.PositionClose()/PositionClosePartial()
// call so ExitReasonText() can report the REAL cause (OPP-CLOSE / TREND-REV / PARTIAL)
// instead of collapsing every EA-initiated close into "OPP-CLOSE".
// AUDIT FIX (v4.0.5 / F4): the single shared string above was a RACE CONDITION once
// MaxOpenTrades>1 -- closing two positions inside one ManagePositions() pass left only
// the LAST-staged tag standing (MQL5 only dispatches queued OnTradeTransaction events
// AFTER OnTick() returns), so an earlier deal's close reason could be silently
// overwritten by a later, unrelated close on a DIFFERENT ticket. Replaced with a
// ticket-keyed registry (RX_StageCloseTag / RX_ConsumeCloseTag below) so each closing
// deal reads back only its OWN staged reason, no matter how many positions close in
// the same tick.
ulong    g_pendingTagTicket[];
string   g_pendingTagText[];
//--- Stage a close-reason tag for a SPECIFIC ticket, immediately before the
//    trade.PositionClose()/PositionClosePartial() call that will close it.
void RX_StageCloseTag(ulong positionId,string tag)
  {
   for(int i=0;i<ArraySize(g_pendingTagTicket);i++)
      if(g_pendingTagTicket[i]==positionId){ g_pendingTagText[i]=tag; return; }
   int n=ArraySize(g_pendingTagTicket);
   ArrayResize(g_pendingTagTicket,n+1); ArrayResize(g_pendingTagText,n+1);
   g_pendingTagTicket[n]=positionId; g_pendingTagText[n]=tag;
  }
//--- Consume (read + remove) the staged tag for a ticket; "" if none was staged
//    (e.g. a manual close from the terminal, not initiated by this EA).
string RX_ConsumeCloseTag(ulong positionId)
  {
   for(int i=0;i<ArraySize(g_pendingTagTicket);i++)
     {
      if(g_pendingTagTicket[i]!=positionId) continue;
      string tag=g_pendingTagText[i];
      int n=ArraySize(g_pendingTagTicket);
      for(int j=i;j<n-1;j++){ g_pendingTagTicket[j]=g_pendingTagTicket[j+1]; g_pendingTagText[j]=g_pendingTagText[j+1]; }
      ArrayResize(g_pendingTagTicket,n-1); ArrayResize(g_pendingTagText,n-1);
      return tag;
     }
   return "";
  }
// ---- v3.4.0 Sci kill-zone / OTE state ----
bool     g_inKillzone=true;             // last kill-zone gate result (true when gate OFF)
string   g_kzActive="OFF";              // active kill-zone name for the dashboard
// ---- S/R cluster storage ----
double   sr_price[];    int      sr_count[];
datetime sr_birthTime[]; int     sr_birthSes[];
datetime sr_birthBar[];  bool    sr_isRes[];
bool     sr_drawn[];     bool    sr_broken[];
bool     sr_retested[];  bool    sr_armed[];
int      sr_armBar[];    string  sr_name[];
// ---- S/R retest visual state (level map only; no longer an entry path) ----
bool   srRetestThisBar=false, srRetestIsRes=false;
datetime lastAlertTime=0;
// ---- v3.7.0 ML runtime ----
long   g_mlOnnx=INVALID_HANDLE;
bool   g_mlModelReady=false;
bool   g_mlInferenceValid=false;
string g_mlModelVersion="NONE";
string g_mlInferenceError="";
double g_ml2RProb=0.0;
double g_mlRiskMult=1.0;
bool   g_mlPass=true,g_mlRunner=true;
int    g_mlDecision=0;
int    g_mlRegime=0,g_mlSession=0;
string g_mlRegimeTxt="RANGE";
//====================================================================
//  v4.4.2 ML GATE OBSERVABILITY  (Working Document v1.2 s9 "Layer D")
//  The Working Document records a MEASUREMENT BLIND SPOT: the SCI CORE
//  shadow evaluator grades Layers A/B/C inside ICC_Update(), but the
//  learned 2R gate executes LATER, in TryEntries(). A bar can therefore
//  be logged "CORE+ENH PASS" and still produce no trade, with nothing in
//  the [SCI CORE] line explaining the discrepancy.
//  ARCHITECTURAL NOTE (hostile-review correction to the Working Document):
//  the deferred fix was sketched as "add a Layer D to ICC_ShadowEvaluate".
//  That is NOT implementable, and the document should be corrected. The
//  shadow evaluator runs PER BAR, before ICC_Update() has produced a
//  signal; the ML verdict does not exist at that point in the tick. The
//  correct instrument is a SEPARATE PER-SIGNAL record, reconciled to the
//  shadow stream by timestamp -- which is what ML_LogGateVerdict() below
//  emits. These counters make the s14 "ML gate threshold" experiment
//  countable without parsing the whole Journal.
//  Trading-NEUTRAL: counters and Prints only.
//====================================================================
int g_mlGateEval=0;          // ML gate evaluations (one per routed ICC signal)
int g_mlGatePass=0;          // signals the gate allowed through
int g_mlGateBlock=0;         // signals the gate VETOED
int g_mlGateBlockNoModel=0;  // subset of blocks caused by an unusable model, not by a low score
bool g_mlGateFailOpenWarned=false;
// v3.8.0 feature snapshot, captured at the raw ICC signal
double g_mlOTEDepth=0.0,g_mlFVGMidDist=0.0,g_mlFVGMidDistATR=0.0,g_mlFVGSizeATR=0.0;
double g_mlRiskDistance=0.0,g_mlRiskDistanceATR=0.0,g_mlRiskDistancePips=0.0;
double g_mlSpreadPrice=0.0,g_mlSpreadPoints=0.0,g_mlTimeSin=0.0,g_mlTimeCos=0.0;
int g_mlHour=0,g_mlMinuteOfDay=0;
#define ML2R_FEATURE_COUNT 28
//====================================================================
//  v4.6.0 MODEL CONTRACT -- 28 features, CONTRACT ORDER as declared.
//  The COUNT is deliberately held flat. Appending the path features to
//  the existing 28 would have taken the vector to 32 against a labelled
//  sample in the low tens, making an already underdetermined fit worse;
//  the four weakest columns are therefore REPLACED, not supplemented.
//
//  DROPPED FROM THE TENSOR IN v4.6.0, with cause:
//    ext_trend        Collinear with `direction` BY CONSTRUCTION. A signal
//                     only reaches inference when HTFbias()!=0, and the
//                     Indication gate additionally requires extOK, so
//                     g_extTrend==dir on every routed signal. The column
//                     was a constant copy of slot 27.
//    icc_phase        CONSTANT. g_mlSigPhaseAtFire is latched inside the
//                     PH_CORRECTION continuation branch, so it has been
//                     PH_CORRECTION (2) on every inference ever run. A
//                     zero-variance column cannot inform a split.
//    correction_depth Clamped twin of ote_depth -- the redundancy was
//                     already recorded as a v4.4.1 modelling note. The
//                     GLOBAL is retained (g_mlCorrectionDepth) and the v4
//                     CSV column is untouched; only the TENSOR drops it,
//                     so the decision is reversible on evidence.
//    sweep_long +     Collapsed to ONE direction-relevant `sweep_age`.
//    sweep_short      Only the same-side counter can be non-zero for a
//                     given signal and slot 27 already carries the side,
//                     so the pair spent two slots encoding one number.
//
//  ADDED IN v4.6.0 -- all four are PATH-DEPENDENT, i.e. they describe the
//  ORDER and SHAPE of the setup's construction rather than a magnitude
//  measured at a single instant. See the calculators above ICC_Update().
//====================================================================
struct ML2RFeatures
  {
   float htf_score,int_trend,sweep_age,sweep_lead_bars,displacement;
   float fvg_active,ob_active,atr_pct,session,regime;
   float fvg_mid_dist_atr,ote_depth,fvg_size_atr,risk_distance_atr,spread_points;
   float time_sin,time_cos,impulse_age,impulse_leg_atr,impulse_concentration;
   float correction_age,corr_leg_count,corr_recovery_frac;
   float dist_ext_high_atr,dist_ext_low_atr;
   float dist_int_high_atr,dist_int_low_atr,direction;
  };
// ---- v3.9.0 icc_ml_v2 trade-life-cycle recorder (one finalized row per trade) ----
struct MLTradeV2
  {
   bool     used;
   ulong    posId;
   int      dir;
   datetime sigTime, entryTime, exitTime;
   double   entryPx, initSL, initRisk;
   double   mfe, mae;                 // price excursions (favourable / adverse)
   bool     r1,r2,r3,r5,r10;
   datetime t2rTime;
   double   exitPx, exitMoney;
   string   exitReason;
   // frozen signal-time features (captured at entry; no future leakage)
   double   fHTF; int fExt,fInt,fSweepL,fSweepS; double fDisp;
   int      fFVG,fOB; double fATR; int fSession,fRegime;
   double   fFVGdist,fFVGdistATR,fOTE,fFVGsizeATR;
   double   fRiskDist,fRiskDistATR,fRiskDistPips;
   double   fSpreadPx,fSpreadPts; int fHour,fMinOfDay; double fTsin,fTcos;
   double   fP2,fP3,fP5,fP10,fRiskMult; int fRunner;
   double fML2RProb,fMLRiskMult; int fMLDecision; string fMLModelVersion;
  };
MLTradeV2 g_mlv2[];

// AUDIT FIX (v4.0.5 / F5): all three ML datasets used a fixed, non-symbol-qualified
// filename with no locking, unsafe for a multi-symbol data-collection workflow --
// multiple chart instances (one per symbol) writing the SAME shared FILE_COMMON
// file with no coordination can interleave/duplicate header rows or clobber each
// other's appends. Each input filename is now resolved ONCE at OnInit into an
// effective, per-symbol/per-magic filename (root_SYMBOL.ext) stored here and used by every
// reader/writer below, so each symbol/instance gets its own file.
string g_mlv1FileEff="", g_mlv2FileEff="", g_mlv4FileEff="";
//--- Insert "_"+_Symbol before the file extension (or at the end if there is none).
string ML_BuildPerSymbolFilename(string fbase)
  {
   // AUDIT FIX (v4.3.3 / Finding G, LOW): StringFind() returns the FIRST dot, so a
   // filename containing any earlier dot (e.g. "ICC.v4_dataset.csv") was split in the
   // wrong place and produced "ICC_XAUUSD.v4_dataset.csv". Split on the LAST dot.
   int dot=StringFind(fbase,".",0);
   for(int d=dot+1; d>0; )
     { int nxt=StringFind(fbase,".",d); if(nxt<0) break; dot=nxt; d=nxt+1; }
   string root=(dot>=0)? StringSubstr(fbase,0,dot) : fbase;
   string ext =(dot>=0)? StringSubstr(fbase,dot)    : "";
   return root+"_"+_Symbol+"_"+IntegerToString((long)MagicNumber)+ext;
  }

// ---- v4.0 canonical ML dataset recorder ----
string g_mlRunId="";
ulong  g_mlTradeSeq=0;
int    g_mlIndStartBar=0, g_mlCorrStartBar=0;
double g_mlImpulseLegATR=0.0;
int    g_mlImpulseAgeBars=0, g_mlCorrectionAgeBars=0;
// AUDIT FIX (v4.0.5 / F7): g_mlIndStartBar/g_mlCorrStartBar were declared and reset in
// ICC_Reset() but NEVER assigned anywhere -- impulse_age_bars/correction_age_bars/
// impulse_leg_atr were permanently 0 in every exported row. Now stamped at the real
// Indication/Correction phase transitions inside ICC_Update() (see below), and
// g_mlSigPhaseAtFire captures the genuine ICC phase at the instant a Continuation
// fires -- BEFORE ICC_Reset() runs -- so ML_v4_RegisterEntry can read a real captured
// state instead of a hardcoded PH_CORRECTION literal.
int    g_mlSigPhaseAtFire=PH_NONE;
// AUDIT FIX (v4.4.1 / Finding A, CRITICAL, MODEL CONTRACT): feature 23
// (correction_depth) was computed LIVE inside ML_Build2RFeatures from
// g_indExtreme / g_indLevel / g_corrExtreme. But ICC_Update() calls ICC_Reset()
// INSIDE the continuation branch -- immediately after latching the other ML
// telemetry -- and ICC_Reset() zeroes all three of those globals. OnTick() then
// runs TryEntries() -> ML_Evaluate2R() -> ML_Build2RFeatures(), by which point
// impulseSpan==0.0, the guard fails, and corrDepth stayed 0.0 on EVERY inference.
// This is the same failure class as the v4.4.0 features 24-27 defect, and it was
// invisible to a CSV-only audit because ML_v4_RegisterEntry reads the LATCHED
// r.fCorrectionDepth=g_mlOTEDepth instead of recomputing. FIX: latch the value at
// continuation time, in both branches, exactly where g_mlImpulseLegATR and
// g_mlSigPhaseAtFire are already captured.
// SEMANTICS PRESERVED DELIBERATELY: this is the [0..1]-clamped retracement of the
// impulse leg -- the IDENTICAL formula the v4.4.0/v4.4.1 feature builder used, so
// the 28-feature model contract is unchanged. NOTE for modelling (NOT an EA fix):
// this makes feature 23 the clamped twin of feature 13 (ote_depth), and the v4 CSV
// already carries the same redundancy (r.fOTE and r.fCorrectionDepth both read
// g_mlOTEDepth). Whether to drop one is a preprocessing decision to be made on
// empirical evidence, not by silently redefining a column here.
double g_mlCorrectionDepth=0.0;
// AUDIT FIX (v4.5.0 / Finding 5, HIGH, MODEL CONTRACT): feature 05 (displacement)
// read g_lastDispScore, which is written ONLY by the MUTATING wrapper
// MSE_ScoreDisplacement(). That wrapper appears in exactly two places, both inside
// the Indication gate and both behind a SHORT-CIRCUITING ||:
//     bool dispOK = (!InpRejectWeakBreaks) || (MSE_ScoreDisplacement(1,1)>=...);
// With InpRejectWeakBreaks=false the left operand is true, the wrapper is never
// called, and every other call site uses the PURE MSE_ScoreDisplacementCalc (which
// by design does not write the global) -- so feature 05 AND the "disp" column in
// all three CSVs were a hard 0.0 for the entire run. The v4.4.1 header pinned this
// as a "dataset-generation precondition" rather than fixing it, which leaves a
// silent, operator-triggerable corruption of the model input vector.
// FIX: latch the Indication-bar displacement into a DEDICATED global using the PURE
// calculator, unconditionally, on the same lines that already gate the Indication.
// g_lastDispScore is left completely untouched, so the v4.0.4 Finding (4) /
// v4.0.5 F6 anti-clobber discipline is preserved exactly.
double g_mlDispAtIndication=0.0;
//====================================================================
//  v4.6.0 PATH-DEPENDENT FEATURE LATCHES.
//  Every one of these is computed in the CONTINUATION branch of
//  ICC_Update(), immediately BEFORE ICC_Reset() wipes g_indLevel /
//  g_indExtreme / g_corrExtreme / g_iccStartTime / g_corrStartTime.
//  This is the same discipline the v4.4.1 Finding A (correction_depth)
//  and v4.5.0 Finding 5 (displacement) fixes established: a feature
//  that reads ICC geometry from inside ML_Build2RFeatures is reading
//  zeros, because TryEntries() runs after the reset.
//====================================================================
// AUDIT FIX (v4.6.2 / Finding 10, LOW, MISLEADING SEMANTICS): this is the
// REMAINING validity countdown, so it DECREASES with age -- a HIGH value means a
// FRESH sweep and 0 means none armed. The name "sweep_age" reads as the opposite.
// Documented rather than renamed: the name is part of the v4.6.0 model contract
// and the CSV schema, and churning it again would invalidate a second artifact for
// no functional gain. Preprocessing should treat it as sweep FRESHNESS.
double g_mlSweepAge=0.0;              // 02: same-side sweep validity REMAINING at fire (high=fresh)
double g_mlSweepLeadBars=0.0;         // 03: signed bars, armed sweep -> Indication
double g_mlImpulseConcentration=0.0;  // 19: widest impulse bar / total leg
double g_mlCorrLegCount=0.0;          // 21: confirmed TrigTF pivots during the correction
double g_mlCorrRecovery=0.0;          // 22: recovery off the correction extreme at trigger
double g_mlDistExtHighATR=0.0,g_mlDistExtLowATR=0.0;
double g_mlDistIntHighATR=0.0,g_mlDistIntLowATR=0.0;

struct MLTradeV4
  {
   bool used;
   string runId,tradeId;
   ulong posId;
   ulong seq;
   int dir;
   datetime sigTime,entryTime,exitTime;
   double entryPx,initSL,initRisk;
   double mfe,mae;
   // v4.2.9 MONEY LAYER: excursions + initial risk expressed in ACCOUNT-CURRENCY
   // money, computed via MT5's OrderCalcProfit() (folds in contract size, tick
   // value/size, volume, and currency conversion) -- NOT a hand-rolled pips->$
   // conversion, which mis-scales on XAUUSD vs FX. mfe/maeMoney are stored as
   // positive magnitudes, mirroring the price-based mfe/mae above.
   double initRiskMoney, mfeMoney, maeMoney;
   bool r1,r2,r3,r5,r10;
   datetime t1rTime,t2rTime,t3rTime,t5rTime,t10rTime;
   double mfe30m,mfe1h,mfe2h,mfe4h,mfe8h,mfe24h;
   bool cp30m,cp1h,cp2h,cp4h,cp8h,cp24h;
   double exitPx,exitMoney;
   string exitReason;
   // frozen entry features
   double fHTF; int fExt,fInt,fSweepL,fSweepS; double fDisp;
   int fFVG,fOB; double fATR; int fSession,fRegime;
   double fFVGdist,fFVGdistATR,fOTE,fFVGsizeATR;
   double fRiskDist,fRiskDistATR,fRiskDistPips;
   double fSpreadPx,fSpreadPts; int fHour,fMinOfDay; double fTsin,fTcos;
   int fPhase,fImpulseAge,fCorrectionAge;
   double fImpulseLegATR,fCorrectionDepth;
   // v4.6.0 PATH FEATURES (schema 4.2.0). Frozen at entry from the same latches
   // the inference vector reads, so the dataset and the tensor cannot diverge --
   // which is the failure the v4.4.1 Finding A audit could NOT detect, because
   // that column was written from an independent calculation.
   double fSweepAge,fSweepLeadBars,fImpulseConcentration,fCorrLegCount,fCorrRecovery;
   double fDistExtHighATR,fDistExtLowATR,fDistIntHighATR,fDistIntLowATR;
   int fSymbolDigits; double fPoint,fTickSize,fTickValue,fContractSize;
   string fBroker,fAccountCurrency,fExecutionMode,fPeriod;
   string fDatasetVersion,fSchemaVersion,fModelVersion;
   double fP2,fP3,fP5,fP10,fRiskMult; int fRunner;
   double fML2RProb,fMLRiskMult; int fMLDecision; string fMLModelVersion;
   // exit structure state
   int xExtTrend,xIntTrend,xPhase;
   double xProtHigh,xProtLow,xATR;
   int xFVG,xOB;
   bool xStructureBreak,xOppositeSignal;
  };
MLTradeV4 g_mlv4[];
// pending signal snapshot, consumed at the entry deal (single-position flow)
bool     g_mlPendValid=false;
int      g_mlPendDir=0;
datetime g_mlPendSigTime=0;
double   g_pHTF=0; int g_pExt=0,g_pInt=0,g_pSweepL=0,g_pSweepS=0; double g_pDisp=0;
int      g_pFVG=0,g_pOB=0; double g_pATR=0; int g_pSession=0,g_pRegime=0;
double   g_pFVGdist=0,g_pFVGdistATR=0,g_pOTE=0,g_pFVGsizeATR=0;
double   g_pRiskDist=0,g_pRiskDistATR=0,g_pRiskDistPips=0;
double   g_pSpreadPx=0,g_pSpreadPts=0; int g_pHour=0,g_pMinOfDay=0; double g_pTsin=0,g_pTcos=0;
double   g_pP2=0,g_pP3=0,g_pP5=0,g_pP10=0,g_pRiskMult=1.0; int g_pRunner=1;
double g_pML2RProb=0.0,g_pMLRiskMult=1.0; int g_pMLDecision=0; string g_pMLModelVersion="NONE";
double   g_pInitSLguess=0;
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
   RunnerArm_Runtime  = InpRunnerArmPts;    // v3.5.0 runner (scaled below)
   RunnerLock_Runtime = InpRunnerLockPts;
   RunnerTrail_Runtime= InpRunnerTrailPts;
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
   RunnerArm_Runtime  *= mult;    // v3.5.0 runner scales with asset class too
   RunnerLock_Runtime *= mult;
   RunnerTrail_Runtime*= mult;
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
   g_slBuf    = PipDist(RetestSLbufPips,      InpFracSLbuf);   // ICC continuation signal SL buffer
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
// AUDIT FIX (v4.0.4): dedicated raw-ATR reader. Previously RX_ManageOne had to
// back-solve the raw ATR by dividing GetATRStopDistance() (which returns
// atr*ATR_Multiplier) back by ATR_Multiplier -- if a user set ATR_Multiplier
// very close to 0, that division silently collapsed the recovered "atr" to ~0,
// quietly disabling the wide ATR emergency floor with no warning. Both callers
// now read the same raw buffer directly through this single helper.
double GetRawATR()
  {
   if(atrHandle==INVALID_HANDLE) return 0.0;
   double atr[]; ArraySetAsSeries(atr,true);
   if(CopyBuffer(atrHandle,0,1,1,atr)<1) return 0.0;
   if(atr[0]<=0) return 0.0;
   return atr[0];
  }
double GetATRStopDistance()
  {
   double raw=GetRawATR();
   if(raw<=0.0) return GetMinStopDistance()*2;
   return raw*ATR_Multiplier;
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

// v4.6.5 RB 13,16; function mapping in CHANGE_REPORT.md.
void PrintBrokerDiagnostics()
  {
   if(!ShowDiagnostics) return;
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   digits = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   spread   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   Print("==============================================================");
   Print("       ICC TradesBySci EA v4.6.5 - BROKER DIAGNOSTICS         ");
   Print("==============================================================");
   Print(" Symbol:       ", _Symbol, "  Asset: ", AssetClassLabel);
   Print(" Chart TF:     ", EnumToString((ENUM_TIMEFRAMES)_Period));
   Print(" Cascade:      ", EnumToString(BiasTF), " -> ", EnumToString(MidTF),
                            " -> ", EnumToString(WorkTF), " -> ", EnumToString(TrigTF));
   // v4.1.0: External/Internal structure now genuinely separate timeframes
   // (Core-Engine Finding 1+2) -- printed so this is verifiable at a glance.
   Print(" SMC structure: External(dir)=", EnumToString(g_extTF), " strength=", IntegerToString(InpExtSwingStrength),
                       "  |  Internal(entry)+Liquidity/FVG/OB/Disp=", EnumToString(g_intTF), " strength=", IntegerToString(InpIntSwingStrength));
   Print(" Continuation trigger: confirmed minor pivot on ", EnumToString(TrigTF),
                       " strength=", IntegerToString(InpMinorPivotStrength),
                       " lookback=", IntegerToString(InpMinorPivotLookback), " bars");
   Print(" Entry path:   ICC pullback=", (UseICCPullback?"ON":"OFF"),
                       "   (Sci ICC is the ONLY entry path)");
   Print(" Bias mode:    ", (BiasLoose?"LOOSE (single BOS)":"STRICT (HH+HL)"),
                       "  D1 filter=", (UseD1Filter?"SOFT":"OFF"),
                       "  D1wt=", DoubleToString(D1Weight,2),
                       "  MinConv=", DoubleToString(HTF_MinConviction,2),
                       "  HTFboundary=", (InpHTFStrictBoundary?"STRICT (>/<)":"INCLUSIVE (>=/<=)"));
   Print(" Let winners run: ", (InpLetWinnersRun?"ON (no fixed TP; profit-lock ride)":"OFF (fixed TP cap)"),
                       "  arm=", IntegerToString(RunnerArm_Runtime),
                       "  lock=", IntegerToString(RunnerLock_Runtime),
                       "  trail=", IntegerToString(RunnerTrail_Runtime),
                       "  struct=", (InpRunnerUseStructure?"Y":"n"));
   Print(" Exit R-engine:", (InpUseRexit?"ON (supersedes BE/trail/point-runner)":"OFF (legacy v3.5.0)"),
                       "  protect=", DoubleToString(InpProtectAtR,1), "R",
                       "  lock=", DoubleToString(InpLockAtR,1), "R/+", DoubleToString(InpLockProfitR,1), "R",
                       "  activate=", DoubleToString(InpActivateAtR,1), "R",
                       "  giveback=", DoubleToString(InpRunnerGiveBackR,1), "R");
   Print("               struct ext=", (InpRunnerExternStruct?"Y":"n"), " int=", (InpRunnerInternStruct?"Y":"n"),
                       "  ATRfloor=", (InpRunnerATRFloor?DoubleToString(InpRunnerATRfloorMult,1)+"xATR":"off"),
                       "  health=", (InpUseTrendHealth?"Y":"n"), " confRev=", (InpCloseOnConfirmedRev?"Y":"n"),
                       "  partial=", (InpUsePartial?DoubleToString(InpPartialPct,0)+"%":"off"));
   Print(" Stops Level:  ", stopsLvl, " pts   Spread: ", spread, " pts");
   Print(" SL Method:    ", EnumToString(SL_Method), "   RR: ", DoubleToString(RR_Ratio,1));
   Print(" TP Mode:      ", (InpTPMode==TP_STRUCTURAL?"STRUCTURAL":"FIXED_RR"),
                       "   MinRR: ", DoubleToString(InpTPMinRR,2),
                       "   Lookback: ", IntegerToString(InpTPLookback));
   Print(" FVG Contain:  ", (InpRelaxFVGContain?"RELAX":"STRICT"),
                       "   Tol: ", DoubleToString(g_fvgContainTol,(int)digits),
                       "   Band: ", (InpUseFVGband?"ON":"OFF"));
   Print(" Kill-zones:   ", (InpUseKillzones?"ON":"OFF"),
                       "   Lon=", (InpKZ_London?"Y":"n"), IntegerToString(InpKZ_LonStart), "-", IntegerToString(InpKZ_LonEnd),
                       "  NYam=", (InpKZ_NYam?"Y":"n"), IntegerToString(InpKZ_NYamStart), "-", IntegerToString(InpKZ_NYamEnd),
                       "  NYpm=", (InpKZ_NYpm?"Y":"n"), IntegerToString(InpKZ_NYpmStart), "-", IntegerToString(InpKZ_NYpmEnd),
                       "  (broker time)");
   Print(" OTE window:   ", (InpUseOTE?"ON":"OFF"),
                       "   band ", DoubleToString(InpOTEmin,2), "-", DoubleToString(InpOTEmax,2));
   Print(" Correction def:", (InpUseStructuralCorrection?"STRUCTURAL (LH/HL + impulse-origin hold)":"FIB BAND (CorrRetraceMin..Max)"),
                       "   minRetrace=", DoubleToString(InpStructCorrMinRetrace,2),
                       "   keepMaxDepthCap=", (InpStructCorrKeepMaxDepth?"Y":"n"));
   Print(" ICC maturation:", (InpUseImpulseMaturation?"ON":"OFF"),
                       "   bars>=", IntegerToString(InpICCImpulseBars),
                       "   OR leg>=", DoubleToString(InpICCMinLegATR,2), "xATR");
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
// AUDIT FIX (v4.0.4): both functions previously validated only the CENTER bar
// (mid) against zero. If a neighbor bar's history wasn't yet synchronised for
// this TF (common right after EA attach, symbol/TF switch, or in the tester),
// iHigh/iLow silently return 0 for it -- and "0 >= mid" / "0 > mid" (etc.) is
// simply false, so a missing neighbor could never disqualify a pivot. That let
// a FALSE pivot (and therefore a false D1/H4/H1/M15 cascade bias) through on
// incomplete history. Every sampled neighbor is now validated >0 too (same
// class of guard already applied elsewhere for FVG/OB in v3.3.1/v3.3.7).
bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid=iHigh(_Symbol,tf,shift);
   if(mid<=0) return false;
   for(int i=1;i<=L;i++)
     {
      double hL=iHigh(_Symbol,tf,shift-i);
      double hR=iHigh(_Symbol,tf,shift+i);
      if(hL<=0.0 || hR<=0.0) return false;   // AUDIT FIX: incomplete history -> can't confirm a pivot
      if(hL>=mid) return false;
      if(hR> mid) return false;
     }
   return true;
  }
bool IsPivotLowTF(ENUM_TIMEFRAMES tf, int shift, int L)
  {
   double mid=iLow(_Symbol,tf,shift);
   if(mid<=0) return false;
   for(int i=1;i<=L;i++)
     {
      double lL=iLow(_Symbol,tf,shift-i);
      double lR=iLow(_Symbol,tf,shift+i);
      if(lL<=0.0 || lR<=0.0) return false;   // AUDIT FIX: incomplete history -> can't confirm a pivot
      if(lL<=mid) return false;
      if(lR< mid) return false;
     }
   return true;
  }

// v4.6.5 RB 4,7,19; Audit 8; function mapping in CHANGE_REPORT.md.
bool ICC_FindMinorPivotHigh(double &lvl)
  {
if(g465.corrStart<=0) return false;
   int limit=iBarShift(_Symbol,InpEntryTF,g465.corrStart,false);
   return ICC_FindMinorPivotHighSince(lvl,limit);
  }

// v4.6.5 RB 4,7,19; Audit 8; function mapping in CHANGE_REPORT.md.
bool ICC_FindMinorPivotLow(double &lvl)
  {
if(g465.corrStart<=0) return false;
   int limit=iBarShift(_Symbol,InpEntryTF,g465.corrStart,false);
   return ICC_FindMinorPivotLowSince(lvl,limit);
  }

// v4.6.5 RB 4,7,19; Audit 8; function mapping in CHANGE_REPORT.md.
bool ICC_FindMinorPivotHighSince(double &lvl,int maxShiftLimit)
  {
lvl=0.0;
   if(maxShiftLimit<1 || g465.corrStart<=0) return false;
   int strength=MathMax(1,InpMinorPivotStrength);
   int last=MathMin(maxShiftLimit,Bars(_Symbol,InpEntryTF)-strength-1);
   for(int s=strength+1;s<=last;s++)
     {
      if(iTime(_Symbol,InpEntryTF,s)<g465.corrStart) break;
      if(IsPivotHighTF(InpEntryTF,s,strength)) { lvl=iHigh(_Symbol,InpEntryTF,s); return true; }
     }
   return false;
  }

// v4.6.5 RB 4,7,19; Audit 8; function mapping in CHANGE_REPORT.md.
bool ICC_FindMinorPivotLowSince(double &lvl,int maxShiftLimit)
  {
lvl=0.0;
   if(maxShiftLimit<1 || g465.corrStart<=0) return false;
   int strength=MathMax(1,InpMinorPivotStrength);
   int last=MathMin(maxShiftLimit,Bars(_Symbol,InpEntryTF)-strength-1);
   for(int s=strength+1;s<=last;s++)
     {
      if(iTime(_Symbol,InpEntryTF,s)<g465.corrStart) break;
      if(IsPivotLowTF(InpEntryTF,s,strength)) { lvl=iLow(_Symbol,InpEntryTF,s); return true; }
     }
   return false;
  }
//--- TrigTF shift of the bar on which the Indication fired (-1 = unbounded /
//    not yet stamped). Used to reject pre-impulse pivots.
int ICC_IndicationShiftTrigTF()
  {
   if(g_iccStartTime<=0) return -1;
   int sh=iBarShift(_Symbol,TrigTF,g_iccStartTime,false);
   return (sh<0)? -1 : sh;
  }

// v4.6.5 RB 6-7,19; Audit 8; function mapping in CHANGE_REPORT.md.
bool ICC_StructuralCorrectionOK(int dir,double leg,double pullbackPx,double &bandEdge)
  {
bandEdge=0.0;
   if(dir!=g465.dir || g465.correction==C465_NONE || g465.corrStart<=0) return false;
   ENUM_TIMEFRAMES tf=(g465.correction==C465_CONFIRMED_HTF?g465.gstf:g465.entryTF);
   return ICC465_Correction(tf,dir,g465.corrStart,bandEdge);
  }

// v4.6.5 RB 9,21; Audit 3; function mapping in CHANGE_REPORT.md.
bool ICC_StructuralInvalidated(int dir,double m15c1)
  {
// Compatibility signature: supplied LTF price has NO zone authority.
   return ICC465_CheckInvalidation();
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

// v4.6.5 RB 4,19; Audit 3 BiasLoose; function mapping in CHANGE_REPORT.md.
int BiasOf(const SwingCache &c)
  {
if(c.lastHi<=0 || c.prevHi<=0 || c.lastLo<=0 || c.prevLo<=0) return 0;
   if(c.lastHi>c.prevHi && c.lastLo>c.prevLo) return 1;
   if(c.lastHi<c.prevHi && c.lastLo<c.prevLo) return -1;
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
   // Loose LTF alignment retained ONLY as a dashboard readout (the v1 lockstep
   // StrictAlign gate and the breakout path it fed were removed in v3.5.0).
   alignBull=(biasH1==1 && biasM15==1);
   alignBear=(biasH1==-1&& biasM15==-1);
  }
//--- v4.2.0: HTF direction is authoritative MSE External H4 structure.
//  H4 direction = g_extTrend, produced by protected-swing detection + BOS
//  on g_extTF (MidTF, normally H4). The legacy cascade biasH4 remains
//  intact for dashboard/secondary visibility but NO LONGER controls ICC HTF.
//  D1 is a soft conviction weight: same-direction D1 strengthens the H4
//  score, opposing D1 weakens it, and D1=0 leaves H4 unchanged.
//  HTF_MinConviction is applied to the resulting H4-led score.
double HTFscore()
  {
   const int h4Ext = g_extTrend;
   if(!UseD1Filter) return (double)h4Ext;
   return (double)h4Ext + (double)biasD1 * D1Weight;
  }

// v4.6.5 RB 1-4,19; Audit 4,8; function mapping in CHANGE_REPORT.md.
int HTFbias()
  {
return g465Direction;
  }
//+==================================================================+
//|==================================================================|
//|   v3.0 SMART MONEY STRUCTURE ENGINE (MSE_*)                      |
//|   Replaces the raw multi-TF pivot detection that fed the ICC     |
//|   engine. Fully modular; each concern is its own function.       |
//|   v4.1.0: operates on TWO structure timeframes -- External on    |
//|   g_extTF (MidTF/H4) and Internal + liquidity/FVG/OB/displacement|
//|   on g_intTF (WorkTF/H1) -- see the Core-Engine Finding 1+2 fix   |
//|   note in the file header for why this replaced a single shared  |
//|   structure TF (g_mseTF/InpMSE_TF, both removed).                 |
//|   v3.3.1: RE10008-parity history guards added (see header).      |
//|   v3.3.7: empty-array parity guards added to FVG/OB iterators.   |
//|==================================================================|
//+==================================================================+
//--- Strict fractal high on a given structure TF: greater than 'strength'
//    bars on each side. Only confirmed once 'strength' newer bars exist.
//    AUDIT FIX (v4.1.0 / Finding 1+2): now takes an explicit tf parameter
//    instead of always reading the single shared g_mseTF, so External (H4)
//    and Internal (H1) structure can never accidentally share a timeframe.
bool MSE_IsFractalHigh(int shift,int strength,ENUM_TIMEFRAMES tf)
  {
   int bars=Bars(_Symbol,tf);
   if(shift<=strength || shift+strength>=bars) return false;
   double h=iHigh(_Symbol,tf,shift);
   if(h<=0) return false;
   for(int k=1;k<=strength;k++)
     {
      if(iHigh(_Symbol,tf,shift+k)>=h) return false; // older side
      if(iHigh(_Symbol,tf,shift-k)>=h) return false; // newer side
     }
   return true;
  }
//--- Strict fractal low on a given structure TF.
bool MSE_IsFractalLow(int shift,int strength,ENUM_TIMEFRAMES tf)
  {
   int bars=Bars(_Symbol,tf);
   if(shift<=strength || shift+strength>=bars) return false;
   double l=iLow(_Symbol,tf,shift);
   if(l<=0) return false;
   for(int k=1;k<=strength;k++)
     {
      if(iLow(_Symbol,tf,shift+k)<=l) return false;
      if(iLow(_Symbol,tf,shift-k)<=l) return false;
     }
   return true;
  }
//--- Newest confirmed protected swing high & low for a given strength/TF.
//    These are, by definition, the PROTECTED swings whose break = BOS.
void MSE_FindProtected(int strength,double &protHigh,double &protLow,ENUM_TIMEFRAMES tf)
  {
   protHigh=0.0; protLow=0.0;
   int bars=Bars(_Symbol,tf);
   if(bars < strength*2 + 2) return;
   int maxBars=MathMin(InpStructLookback,bars-1-strength);
   bool haveH=false,haveL=false;
   for(int s=strength+1;s<=maxBars && !(haveH&&haveL);s++)
     {
      if(!haveH && MSE_IsFractalHigh(s,strength,tf)){ protHigh=iHigh(_Symbol,tf,s); haveH=true; }
      if(!haveL && MSE_IsFractalLow (s,strength,tf)){ protLow =iLow (_Symbol,tf,s); haveL=true; }
     }
  }
//--- Generic BOS-driven trend update for one structural scale.
//    BOS is only ever measured against a PROTECTED swing (per spec).
void MSE_UpdateTrendScale(int strength,double &protHigh,double &protLow,int &trend,ENUM_TIMEFRAMES tf,bool &bosNow)
  {
   // AUDIT FIX (v4.5.0 / Finding 6, MEDIUM, LOGIC): 'bosNow' reports whether a
   // genuine protected-swing BREAK occurred on this bar, independently of whether
   // the resulting trend DIFFERS from the previous one -- see MSE_UpdateStructure().
   bosNow=false;
   MSE_FindProtected(strength,protHigh,protLow,tf);
   double c1=iClose(_Symbol,tf,1);
   double bH=InpBOSUseClose? c1 : iHigh(_Symbol,tf,1);
   double bL=InpBOSUseClose? c1 : iLow (_Symbol,tf,1);
   if(protHigh>0.0 && bH>protHigh)     { trend=1;  bosNow=true; }  // bullish BOS on protected high
   else if(protLow>0.0 && bL<protLow)  { trend=-1; bosNow=true; }  // bearish BOS on protected low
   // else: trend persists (no fresh protected-swing break this bar)
  }
// AUDIT FIX (v4.3.6 / Finding C, HIGH, FIDELITY -- Working Document CORE-01):
// "Bullish = HH + HL. Bearish = LH + LL. If neither sequence is intact, classify the
// environment as NEUTRAL/CONSOLIDATING rather than forcing direction." The engine
// above violates BOTH halves of that rule:
//   (1) it sets a trend on a SINGLE break of one protected swing -- it never requires
//       the paired HH+HL / LH+LL sequence; and
//   (2) once set, "trend persists" FOREVER. There is no path back to 0. So after the
//       first BOS in a symbol's history the EA ALWAYS believes it has a direction,
//       and CONSOLIDATION -- which the public material says to avoid trading -- can
//       never be detected. HTFbias() then always returns +/-1, so the "no trade is
//       preferable to manufacturing a setup" discipline (Working Document s3, "How to
//       Stop Overtrading") is structurally unreachable.
// FIX (opt-in): after InpConsolidationBars MidTF bars with NO fresh protected-swing
// BOS in EITHER direction, declare the external structure NEUTRAL. That is the
// mechanical reading of "neither sequence is intact". Default OFF = legacy persist.
void MSE_ApplyConsolidationNeutral()
  {
   if(!InpNeutralOnConsolidation) return;
   datetime curExtBar=iTime(_Symbol,g_extTF,0);
   if(curExtBar<=0) return;
   if(curExtBar!=g_extLastBOSTime)
     {
      static datetime s_lastCounted=0;
      if(curExtBar!=s_lastCounted){ g_extBarsNoBOS++; s_lastCounted=curExtBar; }
     }
   if(g_extBarsNoBOS>=InpConsolidationBars && g_extTrend!=0)
     {
      if(VerboseLog)
         PrintFormat("[ICC CORE-01] CONSOLIDATION: %d %s bars with no protected-swing BOS -> external trend %d -> NEUTRAL (no forced direction)",
                     g_extBarsNoBOS,EnumToString(g_extTF),g_extTrend);
      g_extTrend=0;
     }
  }

// v4.6.5 RB 2-4,19; Audit 4; function mapping in CHANGE_REPORT.md.
void MSE_UpdateStructure()
  {
S465Swings ext,obs;
   ICC465_Swings(InpGSTF,InpExtSwingStrength,0,ext);
   ICC465_Swings(InpObservationTF,InpIntSwingStrength,0,obs);
   g465Direction=ICC465_Direction(ext);
   g_extTrend=g465Direction; g_intTrend=ICC465_Direction(obs);
   g_extProtHigh=ext.hi; g_extProtLow=ext.lo;
   g_intProtHigh=obs.hi; g_intProtLow=obs.lo;
  }
//==================================================================
//  LIQUIDITY ENGINE  (BSL/SSL, equal highs/lows, sweep, reclaim)
//==================================================================
//--- Equal-highs cluster among recent fractal highs (BSL magnet).
//    AUDIT FIX (v4.1.0 / Finding 1+2): now scans g_intTF (WorkTF/H1), the
//    entry-side structure timeframe, instead of the removed shared g_mseTF.
bool MSE_DetectEqualHighs(double &level)
  {
   double tol=g_equalTol, first=0.0; bool haveFirst=false; // v3.3.6 ATR-auto
   // AUDIT FIX (v4.2.6 / deferred item (c)): these equal-level (BSL/SSL magnet)
   // detectors scan g_intTF (WorkTF/H1 -- the INTERNAL, entry-side structure
   // timeframe) yet seeded the fractal test with InpExtSwingStrength (4), the
   // EXTERNAL/direction strength, while EVERY other H1 consumer (MSE_FindProtected
   // for g_intProtHigh/Low, the internal trend, the nearest-pool builders) uses
   // InpIntSwingStrength (2). That mismatch made equal-level clusters require a
   // 4-bar-each-side fractal on the same series where internal swings are 2-bar,
   // so the equal-highs/lows magnet was systematically STRICTER than -- and
   // structurally inconsistent with -- the protected swings feeding the sweep
   // pool right beside it. Fix: use InpIntSwingStrength, matching the timeframe
   // these functions actually operate on. NOTE: this CHANGES which equal-level
   // clusters are detected -> which sweep pools arm -> live signal generation;
   // re-validate on the tester (it generally makes the magnet slightly more
   // permissive, surfacing more genuine H1 equal-level pools).
   int str=InpIntSwingStrength;
   for(int s=str+1;s<=InpLiqLookback;s++)
     {
      if(!MSE_IsFractalHigh(s,str,g_intTF)) continue;
      double h=iHigh(_Symbol,g_intTF,s);
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
   // AUDIT FIX (v4.2.6 / deferred item (c)): these equal-level (BSL/SSL magnet)
   // detectors scan g_intTF (WorkTF/H1 -- the INTERNAL, entry-side structure
   // timeframe) yet seeded the fractal test with InpExtSwingStrength (4), the
   // EXTERNAL/direction strength, while EVERY other H1 consumer (MSE_FindProtected
   // for g_intProtHigh/Low, the internal trend, the nearest-pool builders) uses
   // InpIntSwingStrength (2). That mismatch made equal-level clusters require a
   // 4-bar-each-side fractal on the same series where internal swings are 2-bar,
   // so the equal-highs/lows magnet was systematically STRICTER than -- and
   // structurally inconsistent with -- the protected swings feeding the sweep
   // pool right beside it. Fix: use InpIntSwingStrength, matching the timeframe
   // these functions actually operate on. NOTE: this CHANGES which equal-level
   // clusters are detected -> which sweep pools arm -> live signal generation;
   // re-validate on the tester (it generally makes the magnet slightly more
   // permissive, surfacing more genuine H1 equal-level pools).
   int str=InpIntSwingStrength;
   for(int s=str+1;s<=InpLiqLookback;s++)
     {
      if(!MSE_IsFractalLow(s,str,g_intTF)) continue;
      double l=iLow(_Symbol,g_intTF,s);
      if(!haveFirst){ first=l; haveFirst=true; continue; }
      if(MathAbs(l-first)<=tol){ level=(l+first)/2.0; return true; }
      first=l;
     }
   return false;
  }
//--- Buy-side liquidity = highest of protected high, equal-highs, pool, PDH.
//    AUDIT FIX (v4.1.0 / Finding 4): the pool scan depth previously reused
//    SwingLen (documented under "Visuals: Swings + Dashboard", i.e. meant to
//    be COSMETIC swing-ray drawing only) as SwingLen*2 bars -- so adjusting a
//    purely visual input silently changed real liquidity-pool detection
//    range, while the input actually documented for this purpose
//    (InpLiqLookback) was ignored here. Fix: use InpLiqLookback, matching
//    MSE_DetectEqualHighs/Lows above and this function's own documented
//    liquidity-engine scope. Also now scans g_intTF (WorkTF/H1) instead of
//    the removed shared g_mseTF.
double MSE_BuildBSL()
  {
   // v4.2.1 (Finding A): nearest-pool mode uses the recent INTERNAL protected
   // high and/or equal-highs cluster (the first buy-side liquidity price would
   // take out on a counter-trend pullback), choosing the LOWER (nearer) of the
   // two. Falls back to the 120-bar high only if neither exists. OFF restores
   // the exact v4.2.0 range-extreme behaviour.
   if(InpSweepNearestPool)
     {
      double lvl=0.0;
      double eqH; if(MSE_DetectEqualHighs(eqH)) lvl=eqH;
      if(g_intProtHigh>0.0) lvl=(lvl>0.0)? MathMin(lvl,g_intProtHigh) : g_intProtHigh;
      if(lvl<=0.0){ int hi=iHighest(_Symbol,g_intTF,MODE_HIGH,InpLiqLookback,2); if(hi>=0) lvl=iHigh(_Symbol,g_intTF,hi); }
      return lvl;
     }
   double lvl=g_extProtHigh;
   double eqH; if(MSE_DetectEqualHighs(eqH)) lvl=MathMax(lvl,eqH);
   int hi=iHighest(_Symbol,g_intTF,MODE_HIGH,InpLiqLookback,2);
   if(hi>=0) lvl=MathMax(lvl,iHigh(_Symbol,g_intTF,hi));
   return lvl;
  }
//--- Sell-side liquidity = lowest of protected low, equal-lows, pool, PDL.
double MSE_BuildSSL()
  {
   // v4.2.1 (Finding A): nearest-pool mode uses the recent INTERNAL protected
   // low and/or equal-lows cluster, choosing the HIGHER (nearer) of the two.
   if(InpSweepNearestPool)
     {
      double lvl=0.0;
      double eqL; if(MSE_DetectEqualLows(eqL)) lvl=eqL;
      if(g_intProtLow>0.0) lvl=(lvl>0.0)? MathMax(lvl,g_intProtLow) : g_intProtLow;
      if(lvl<=0.0){ int lo=iLowest(_Symbol,g_intTF,MODE_LOW,InpLiqLookback,2); if(lo>=0) lvl=iLow(_Symbol,g_intTF,lo); }
      return lvl;
     }
   double lvl=(g_extProtLow>0.0)? g_extProtLow : DBL_MAX;
   double eqL; if(MSE_DetectEqualLows(eqL)) lvl=MathMin(lvl,eqL);
   int lo=iLowest(_Symbol,g_intTF,MODE_LOW,InpLiqLookback,2);
   if(lo>=0) lvl=MathMin(lvl,iLow(_Symbol,g_intTF,lo));
   if(lvl==DBL_MAX) lvl=0.0;
   return lvl;
  }
//--- Sweep = wick beyond the pool + close back on the origin side.
//    dir=+1 tests a SELL-SIDE sweep (raid of lows -> look LONG);
//    dir=-1 tests a BUY-SIDE  sweep (raid of highs -> look SHORT).
bool MSE_DetectSweep(int dir,double &sweepWick,double &sweptLevel)
  {
   double hi1=iHigh (_Symbol,g_intTF,1);
   double lo1=iLow  (_Symbol,g_intTF,1);
   double cl1=iClose(_Symbol,g_intTF,1);
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
      double c=iClose(_Symbol,g_intTF,s);
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
   // AUDIT FIX (v4.2.7 / deferred item (b)): decrement the sweep-validity window
   // ONCE PER NEW H1 (g_intTF) BAR, not once per MSE_UpdateLiquidity() call.
   // MSE_Update() runs on every new CHART-TF (M15) bar, so the old unconditional
   // "g_sweepConf--" burned the window ~4x too fast on an M15 chart (an H1 bar
   // spans 4 M15 bars). Now InpSweepValidBars is a genuine count of H1 bars the
   // sweep stays armed, matching the timeframe it is detected on. On the first
   // call (g_lastLiqIntBarTime==0) we prime the tracker without decrementing.
   datetime curIntBar=iTime(_Symbol,g_intTF,0);
   bool newIntBar=(curIntBar>0 && curIntBar!=g_lastLiqIntBarTime);
   if(newIntBar && g_lastLiqIntBarTime!=0)
     {
      if(g_sweepConfLong >0) g_sweepConfLong--;
      if(g_sweepConfShort>0) g_sweepConfShort--;
      // AUDIT FIX (v4.6.2 / Finding 2, HIGH, MODEL CONTRACT): clear the v4.6.0
      // event-order stamp the moment its window expires. Without this the stamp
      // outlived the sweep it described, and ICC_SweepLeadBars() -- which only
      // tested "armT>0" -- happily measured the distance to a raid that had
      // expired many setups ago, emitting it as a genuine early-raid reading.
      // Same defect CLASS as v4.4.1 Finding A: a feature that looks populated,
      // is never zero, and is silently describing the wrong event.
      if(g_sweepConfLong ==0) g_sweepArmTimeLong =0;
      if(g_sweepConfShort==0) g_sweepArmTimeShort=0;
     }
   if(curIntBar>0) g_lastLiqIntBarTime=curIntBar;
   double wick=0.0,lvl=0.0;
   // AUDIT FIX (v4.3.3 / Finding E, MEDIUM, TRADING-AFFECTING): MSE_DetectSweep and
   // MSE_ReclaimConfirmed both read g_intTF (H1) bar 1, but MSE_UpdateLiquidity runs
   // on every new CHART bar (M15) -- so the SAME H1 bar-1 sweep was re-detected up to
   // 4 times and each detection RESET the counter to InpSweepValidBars. Paired with
   // the v4.2.7 fix (decrement once per H1 bar), the countdown could be refreshed as
   // fast as it ticked down, so a sweep could stay armed far longer than the operator
   // configured -- silently widening the Indication window. Arm ONLY on a genuinely
   // new g_intTF bar; the decrement above already uses the same gate.
   bool armedNow=false;
   if(newIntBar)
     {
      if(MSE_DetectSweep(1,wick,lvl) && MSE_ReclaimConfirmed(1,lvl))
        { g_sweepConfLong=InpSweepValidBars; g_lastSweepLvl=lvl; g_liqStatus="SSL swept+reclaim"; armedNow=true;
          // AUDIT FIX (v4.6.2 / Finding 3, HIGH, MODEL CONTRACT): stamp the CLOSED
          // bar the sweep was DETECTED on (shift 1), not the still-forming bar 0.
          // MSE_DetectSweep/MSE_ReclaimConfirmed both read g_intTF shift 1, and
          // g_iccStartTime already follows the v4.3.3 Finding D closed-bar
          // convention -- so stamping bar 0 put the two ends of sweep_lead_bars on
          // DIFFERENT conventions and biased every reading by exactly one bar,
          // including flipping the sign of the "same bar" case the feature exists
          // to distinguish.
          g_sweepArmTimeLong=iTime(_Symbol,g_intTF,1); }
      else if(MSE_DetectSweep(-1,wick,lvl) && MSE_ReclaimConfirmed(-1,lvl))
        { g_sweepConfShort=InpSweepValidBars; g_lastSweepLvl=lvl; g_liqStatus="BSL swept+reclaim"; armedNow=true;
          // AUDIT FIX (v4.6.2 / Finding 3, HIGH): mirror of the long branch.
          g_sweepArmTimeShort=iTime(_Symbol,g_intTF,1); }
     }
   // preserve the original status precedence: a fresh sweep+reclaim reports itself,
   // otherwise fall through to the armed-countdown / idle readout.
   if(!armedNow)
     {
      if(g_sweepConfLong>0)       g_liqStatus="long armed ("+IntegerToString(g_sweepConfLong)+")";
      else if(g_sweepConfShort>0) g_liqStatus="short armed ("+IntegerToString(g_sweepConfShort)+")";
      else                        g_liqStatus="watching pools";
     }
  }
//==================================================================
//  INSTITUTIONAL DISPLACEMENT SCORING (ATR + body% + close + wick)
//  Blends four components into a single 0..100 score; weak breaks
//  are rejected upstream in the ICC Indication gate.
//==================================================================
// AUDIT FIX (v4.0.4): split the pure calculation from the "live" side effect.
// Previously this single function ALWAYS wrote its result into the shared
// global g_lastDispScore -- including when called purely for historical
// order-block detection (MSE_ScanOBs scans up to ~2xmaxBars bars/bar). The
// LAST such internal call (an old bar, arbitrary direction) silently
// clobbered the dashboard's "Displacement score" readout AND the "disp"
// feature exported into every ML CSV (v1/v2/v4) plus ML_Surrogate(), on any
// bar where the ICC engine itself didn't also freshly score bar 1 (i.e. most
// bars, since that only happens while hunting a brand-new Indication).
// MSE_ScoreDisplacementCalc() is the pure function (no side effect) used by
// bulk/historical scanning; MSE_ScoreDisplacement() is the thin wrapper that
// ALSO updates g_lastDispScore, reserved for genuine live signal-time calls
// (ICC_Update's dispOK gate, ICC_LogGateDiagnostics).
// AUDIT FIX (v4.1.0 / Finding 1+2): now reads g_intTF (WorkTF/H1) instead of
// the removed shared g_mseTF -- displacement feeds the entry side (Indication
// gate, ML surrogate), so it belongs on the Internal/entry structure TF.
double MSE_ScoreDisplacementCalc(int shift,int dir)
  {
   double o=iOpen (_Symbol,g_intTF,shift);
   double c=iClose(_Symbol,g_intTF,shift);
   double h=iHigh (_Symbol,g_intTF,shift);
   double l=iLow  (_Symbol,g_intTF,shift);
   double range=h-l;
   if(range<=0.0) return 0.0;
   bool dirOk=(dir==1)?(c>o):(c<o);          // correct directionality is mandatory
   if(!dirOk) return 0.0;
   double body    =MathAbs(c-o);
   double bodyPct =body/range;
   double closeStr=(dir==1)?(c-l)/range:(h-c)/range;
   double oppWick =(dir==1)?(h-c):(c-l);
   double wickRat =(body>0.0)? oppWick/body : 999.0;
   double atrNorm=g_mseATRval;
   // Historical scans must use the ATR belonging to the historical bar.
   if(shift>1 && g_mseATR!=INVALID_HANDLE)
     {
      double ah[]; ArraySetAsSeries(ah,true);
      if(CopyBuffer(g_mseATR,0,shift,1,ah)==1 && ah[0]>0.0) atrNorm=ah[0];
     }
   double atrFac  =(atrNorm>0.0)? range/atrNorm : 0.0;
   double sBody =MathMin(bodyPct /MathMax(InpDispMinBodyPct ,0.01),1.0)*30.0;
   double sClose=MathMin(closeStr/MathMax(InpDispMinCloseStr,0.01),1.0)*25.0;
   double sWick =MathMin(InpDispMaxWickRatio/MathMax(wickRat,0.0001),1.0)*15.0;
   double sATR  =MathMin(atrFac /MathMax(InpDispATRMult   ,0.01),1.0)*30.0;
   double score =sBody+sClose+sWick+sATR;
   return MathMin(score,100.0);
  }
double MSE_ScoreDisplacement(int shift,int dir)
  {
   g_lastDispScore=MSE_ScoreDisplacementCalc(shift,dir);
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
// AUDIT FIX (v4.3.1 / Finding F, MEDIUM, TRADING-AFFECTING): this evicted index 0
// on the assumption that index 0 is the oldest entry. It is not. MSE_ScanFVGs walks
// s=1 (NEWEST bar) upward to maxBars (oldest), so on the warm-up pass entries are
// appended NEWEST-FIRST -- index 0 is the most RECENTLY FORMED gap. With
// InpFVGScanBars(120) > InpMaxTrackedFVG(40) the store overflows on that very first
// scan, so the engine repeatedly discarded the freshest, most tradable gaps and kept
// the stalest ones -- directly degrading the FVG-containment gate the Continuation
// depends on. Fix: evict the genuinely oldest entry by TIMESTAMP, which is correct
// regardless of insertion order and needs no change to the scan direction.
void MSE_DropOldestFVG()
  {
   int n=ArraySize(g_fvg); if(n<=0) return;
   int oldest=0;
   for(int i=1;i<n;i++) if(g_fvg[i].time<g_fvg[oldest].time) oldest=i;
   if(g_fvg[oldest].obj!="") ObjectDelete(0,g_fvg[oldest].obj);
   for(int i=oldest;i<n-1;i++) g_fvg[i]=g_fvg[i+1];
   ArrayResize(g_fvg,n-1);
  }
// AUDIT FIX (v4.3.3 / Finding B, HIGH, TRADING-AFFECTING): STALE GAPS ENTERED THE
// STORE AS FRESH. MSE_ScanFVGs walks s=1..InpFVGScanBars (120) every bar, i.e. it
// detects gaps up to 120 WorkTF bars OLD -- but MSE_UpdateFVGFills only ever tests
// bar 1. So a gap that price traded clean through 90 bars ago was inserted with
// fillPct=0.0 and active=true and STAYED that way: the fill loop can only ever see
// bar 1 going forward, never the history the gap already lived through. Because
// MSE_FVGContainOK -> MSE_InActiveFVG is the Continuation's containment gate, the
// engine was approving (and rejecting) entries against long-dead gaps. FIX: when a
// gap is first inserted, back-fill its true fill percentage over every bar that has
// printed since it formed (shifts barsSince..1) and retire it immediately if it is
// already >= InpFVGFillInvalidate. 'barsSince' is the shift of the newest bar that
// existed when the gap completed; 0/negative means the gap is brand new.
void MSE_AddFVG(double top,double bot,datetime midTime,int dir,int barsSince=0)
  {
   if(MSE_FVGExists(midTime)) return;
   double span=top-bot;
   // AUDIT FIX (v4.3.4 / Finding F, LOW): the degenerate-span return sat AFTER the
   // back-fill loop, so a zero/negative-span gap still walked the whole history
   // before being discarded. Test it FIRST.
   if(span<=0.0) return;                               // degenerate gap: never track it
   double pct =0.0;
   if(span>0.0)
     {
      for(int b=barsSince;b>=1;b--)
        {
         double h=iHigh(_Symbol,g_intTF,b);
         double l=iLow (_Symbol,g_intTF,b);
         if(h<=0.0 || l<=0.0) continue;                // incomplete history -> skip bar
         double pen;
         if(dir==1) { if(l>=top) continue; pen=top-MathMax(l,bot); }
         else       { if(h<=bot) continue; pen=MathMin(h,top)-bot; }
         if(pen>0.0) pct=MathMax(pct,100.0*pen/span);
        }
     }
   if(pct>=InpFVGFillInvalidate) return;               // already retired before we saw it
   if(ArraySize(g_fvg)>=InpMaxTrackedFVG) MSE_DropOldestFVG();
   int n=ArraySize(g_fvg); ArrayResize(g_fvg,n+1);
   g_fvg[n].top=top; g_fvg[n].bot=bot; g_fvg[n].time=midTime; g_fvg[n].dir=dir;
   g_fvg[n].fillPct=pct; g_fvg[n].active=true;
   // AUDIT FIX (v4.3.3 / Finding F, LOW): the object name cast the 64-bit datetime
   // to int, which truncates past 2038-01-19 and can alias two gaps onto one chart
   // object name. IntegerToString() takes a long -- no cast needed.
   g_fvg[n].obj=FVG_PFX+IntegerToString((long)midTime);
  }
void MSE_ScanFVGs()
  {
   int bars=Bars(_Symbol,g_intTF);
   if(bars<4) return;
   int maxBars=MathMin(InpFVGScanBars,bars-4);
   // AUDIT FIX (v4.3.4 / Finding A, HIGH): run the DEEP historical scan only on the
   // first pass. Thereafter bars arrive one at a time, so the only gap that can
   // newly COMPLETE is at the shallow end (a gap spans bars s, s+1, s+2, so the
   // newest completable one is s=1); a small margin covers a skipped/rebuilt bar.
   // Everything already in the store keeps being maintained by MSE_UpdateFVGFills,
   // so no detection is lost -- this only stops re-walking history for structures
   // that were already evaluated and rejected. See the g_fvgScanPrimed note above.
   // v4.3.5 (Finding C): depth = bars actually elapsed since the last scan, not a
   // hardcoded 4. MathMin keeps it bounded by InpFVGScanBars / available history.
   if(g_fvgScanPrimed) maxBars=MathMin(maxBars,MSE_ScanDepthNeeded());
   else                g_fvgScanPrimed=true;
   for(int s=1;s<=maxBars;s++)
     {
      // Bullish FVG: low[s] > high[s+2] (gap across middle candle s+1)
      double lowNear=iLow (_Symbol,g_intTF,s);
      double highFar=iHigh(_Symbol,g_intTF,s+2);
      if((lowNear-highFar)>=g_fvgMin) // v3.3.6 ATR-auto (was /g_pip>=InpMinFVGPips)
         MSE_AddFVG(lowNear,highFar,iTime(_Symbol,g_intTF,s+1),1,s-1); // v4.3.3: back-fill fill% over bars s-1..1
      // Bearish FVG: high[s] < low[s+2]
      double highNear=iHigh(_Symbol,g_intTF,s);
      double lowFar  =iLow (_Symbol,g_intTF,s+2);
      if((lowFar-highNear)>=g_fvgMin) // v3.3.6 ATR-auto (was /g_pip>=InpMinFVGPips)
         MSE_AddFVG(lowFar,highNear,iTime(_Symbol,g_intTF,s+1),-1,s-1); // top=lowFar,bot=highNear; v4.3.3 back-fill
     }
  }
void MSE_UpdateFVGFills()
  {
   if(ArraySize(g_fvg)==0) return; // v3.3.7 empty-array guard (mirrors Pine FVG fill loop)
   double hi1=iHigh(_Symbol,g_intTF,1);
   double lo1=iLow (_Symbol,g_intTF,1);
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
   datetime tRight=iTime(_Symbol,g_intTF,0);
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
   int best=-1; double bestD=DBL_MAX; double px=iClose(_Symbol,g_intTF,1);
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
// AUDIT FIX (v4.3.1 / Finding F): identical eviction-order inversion in the order-
// block store (MSE_ScanOBs uses the same newest-first s=1..maxBars walk). Evict the
// genuinely oldest block by TIMESTAMP.
void MSE_DropOldestOB()
  {
   int n=ArraySize(g_ob); if(n<=0) return;
   int oldest=0;
   for(int i=1;i<n;i++) if(g_ob[i].time<g_ob[oldest].time) oldest=i;
   if(g_ob[oldest].obj!="") ObjectDelete(0,g_ob[oldest].obj);
   for(int i=oldest;i<n-1;i++) g_ob[i]=g_ob[i+1];
   ArrayResize(g_ob,n-1);
  }
// AUDIT FIX (v4.3.3 / Finding C, HIGH, TRADING-AFFECTING): identical staleness
// defect in the order-block store. MSE_ScanOBs walks the same s=1..maxBars history
// and can insert a block up to ~120 WorkTF bars old, but MSE_UpdateOBMitigation only
// ever inspects bar 1 -- so a block price had already CLOSED THROUGH long ago was
// inserted with mitigated=false, active=true and could never be corrected, because
// the violation that killed it is in the past the loop never revisits. MSE_InActiveOB
// is the Continuation's OB gate (and ML's ob_active feature), so both the entry
// decision and the dataset were reading blocks that no longer exist. FIX: replay the
// bars that have printed since the block formed and apply the SAME mitigation /
// violation rules used live; drop the block outright if it was already violated.
void MSE_AddOB(double top,double bot,datetime tm,int dir,int barsSince=0)
  {
   if(MSE_OBExists(tm)) return;
   bool mit=false;
   for(int b=barsSince;b>=1;b--)
     {
      double h=iHigh (_Symbol,g_intTF,b);
      double l=iLow  (_Symbol,g_intTF,b);
      double c=iClose(_Symbol,g_intTF,b);
      if(h<=0.0 || l<=0.0 || c<=0.0) continue;         // incomplete history -> skip bar
      if(dir==1)
        {
         if(l<=top && h>=bot) mit=true;                 // price returned into the block
         double thru=InpOBMitigateOnClose? c : l;
         if(thru<bot) return;                           // already VIOLATED -> never track it
        }
      else
        {
         if(h>=bot && l<=top) mit=true;
         double thru=InpOBMitigateOnClose? c : h;
         if(thru>top) return;                           // already VIOLATED -> never track it
        }
     }
   if(ArraySize(g_ob)>=InpMaxTrackedOB) MSE_DropOldestOB();
   int n=ArraySize(g_ob); ArrayResize(g_ob,n+1);
   g_ob[n].top=top; g_ob[n].bot=bot; g_ob[n].time=tm; g_ob[n].dir=dir;
   g_ob[n].mitigated=mit; g_ob[n].active=true;
   g_ob[n].obj=OB_PFX+IntegerToString((long)tm);        // v4.3.3 Finding F: no int truncation
  }
void MSE_ScanOBs()
  {
   int bars=Bars(_Symbol,g_intTF);
   if(bars<(InpOBScanBack+4)) return;
   int maxBars=MathMin(InpOBScanBars,bars-(InpOBScanBack+3)); // v4.5.0 Finding 8: own input, no longer the FVG input
   // AUDIT FIX (v4.3.4 / Finding A, HIGH): same deep-once/shallow-after treatment as
   // MSE_ScanFVGs. MSE_AddOB also REJECTS an already-violated block without storing
   // it, so without this the displacement scan + back-fill replayed the same dead
   // blocks every single bar. Tracked blocks stay maintained by MSE_UpdateOBMitigation.
   // v4.3.5 (Finding C): elapsed-bar depth, same rationale as MSE_ScanFVGs.
   if(g_obScanPrimed) maxBars=MathMin(maxBars,MSE_ScanDepthNeeded());
   else               g_obScanPrimed=true;
   for(int s=1;s<=maxBars;s++)
     {
      // AUDIT FIX (v4.0.4): use the pure Calc variant here -- this is a bulk
      // historical scan, not the live signal; it must NEVER touch g_lastDispScore.
      if(MSE_ScoreDisplacementCalc(s,1)>=InpDispMinScore)   // bullish displacement -> bullish OB behind it
         for(int k=s+1;k<=s+InpOBScanBack;k++)
            if(iClose(_Symbol,g_intTF,k)<iOpen(_Symbol,g_intTF,k))
              { MSE_AddOB(iHigh(_Symbol,g_intTF,k),iLow(_Symbol,g_intTF,k),iTime(_Symbol,g_intTF,k),1,k-1); break; } // v4.3.3 back-fill
      if(MSE_ScoreDisplacementCalc(s,-1)>=InpDispMinScore)  // bearish displacement -> bearish OB behind it
         for(int k=s+1;k<=s+InpOBScanBack;k++)
            if(iClose(_Symbol,g_intTF,k)>iOpen(_Symbol,g_intTF,k))
              { MSE_AddOB(iHigh(_Symbol,g_intTF,k),iLow(_Symbol,g_intTF,k),iTime(_Symbol,g_intTF,k),-1,k-1); break; } // v4.3.3 back-fill
     }
  }
void MSE_UpdateOBMitigation()
  {
   if(ArraySize(g_ob)==0) return; // v3.3.7 empty-array guard (mirrors Pine OB mitigate/draw loop)
   double hi1=iHigh (_Symbol,g_intTF,1);
   double lo1=iLow  (_Symbol,g_intTF,1);
   double cl1=iClose(_Symbol,g_intTF,1);
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
   datetime tRight=iTime(_Symbol,g_intTF,0);
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
   int best=-1; double bestD=DBL_MAX; double px=iClose(_Symbol,g_intTF,1);
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

// v4.6.5 RB 2,7,20; Audit 4,8; function mapping in CHANGE_REPORT.md.
void MSE_Update()
  {
   MSE_UpdateStructure();
   if(Bars(_Symbol,g_intTF) < 5 || Bars(_Symbol,g_extTF) < 5) return;
   double a[]; ArraySetAsSeries(a,true);
   if(g_mseATR!=INVALID_HANDLE && CopyBuffer(g_mseATR,0,1,1,a)==1) g_mseATRval=a[0];
   MSE_UpdateStructure();
   MSE_UpdateLiquidity();
   MSE_UpdateFVGs();
   if(InpUseOrderBlocks) MSE_UpdateOrderBlocks();
   // v4.3.5 (Finding C): stamp the g_intTF bar this pass covered, AFTER both scanners
   // have run, so the next pass can size its depth from real elapsed bars.
   { datetime curScanBar=iTime(_Symbol,g_intTF,0); if(curScanBar>0) g_lastScanIntBarTime=curScanBar; }
   // Feed protected internal swings to the ICC break anchors (BOS-on-protected).
   // AUDIT FIX (v4.1.0 / Finding 1): this is no longer a "silent override" of a
   // DIFFERENT documented WorkTF anchor -- g_intProtHigh/Low are now genuinely
   // computed ON WorkTF/H1 (see MSE_UpdateStructure -> g_intTF above), so
   // feeding them into wkLastHi/wkLastLo IS the correct, intended WorkTF
   // Indication anchor, not a contradiction of it.
   if(InpIntTrendControlsEnt)
     {
      if(g_intProtHigh>0.0) wkLastHi=g_intProtHigh;
      if(g_intProtLow >0.0) wkLastLo=g_intProtLow;
     }
  }

// v4.6.5 RB 1,5-6,12; Audit 3; function mapping in CHANGE_REPORT.md.
bool ICC_ImpulseMature(double leg)
  {
return true; // Magnitude and elapsed bars are observations only.
  }

// v4.6.5 RB 2-3,16; Audit 5; function mapping in CHANGE_REPORT.md.
void ICC_Reset()
  {
ZeroMemory(g465);
   g465.gstf=InpGSTF; g465.observationTF=InpObservationTF; g465.entryTF=InpEntryTF;
   g465.zoneTF=InpGSTF; g465.validity=V465_ACTIVE;
   g_iccPhase=PH_NONE; g_iccDir=0; g_indLevel=0; g_indExtreme=0; g_corrExtreme=0;
   g_iccStartTime=0; g_corrStartTime=0; g_iccStartBar=0;
   g_mlIndStartBar=0; g_mlCorrStartBar=0;
  }

// v4.6.5 RB 13,15; Audit 7-8; function mapping in CHANGE_REPORT.md.
void ICC_LogGateDiagnostics(int htf,double m15c1,double wkH1,double wkL1)
  {
ICC465_Log(g465.reason,"STATE");
  }

// v4.6.5 RB 1,12-13; Audit 8; function mapping in CHANGE_REPORT.md.
void ICC_ShadowEvaluate(int htf,double m15c1,double wkH1,double wkL1)
  {
// No duplicate legacy CORE definition. Shadow reads the authoritative state.
   ICC465_Log(g465.reason,"SHADOW_READ_ONLY");
  }

//+==================================================================+
//|  v4.6.0 PATH-DEPENDENT FEATURE CALCULATORS                       |
//|  PURE reads. No ICC, MSE, gating, sizing or ML state is mutated  |
//|  by any function below, so they are safe to call from inside the |
//|  continuation branch without disturbing the engine.              |
//|                                                                  |
//|  WHY THESE EXIST: the v4.5.0 tensor was 28 POINT-IN-TIME         |
//|  summaries. Aggregation destroys ORDER and SHAPE, so two setups  |
//|  with the same displacement, the same retracement percentage and |
//|  the same sweep distance -- but a different sequence of events   |
//|  and a different leg profile -- produced near-identical vectors. |
//|  The classifier had no column that could separate them. These    |
//|  four encode the ordering and shape by hand, which is the only   |
//|  regime that can be validated at the current labelled sample     |
//|  size (a sequence model is the v2 target, gated on a four-figure |
//|  labelled sample -- see CHANGELOG.md).                           |
//+==================================================================+

//--- Sentinel for "no liquidity sweep is armed on this side". Deliberately far
//    outside the legitimate signed-bar range so a tree split can isolate it and
//    it can never be confused with a genuine 0 (= sweep armed ON the Indication
//    bar, which is a real and meaningful case).
#define ML2R_NO_SWEEP -99.0

//--- EVENT ORDER. Signed g_intTF bars between the armed sweep and the
//    Indication bar:
//      > 0  the raid happened BEFORE the break      (LIQ_INDICATION chronology)
//      = 0  raid and break on the same g_intTF bar
//      < 0  the raid happened AFTER the break, i.e. INSIDE the correction
//           (the CORE-06 chronology the Working Document s7 bullet 1 argues is
//           the documented one)
//    Read at FIRE time, not at Indication time, so a correction-phase sweep is
//    captured too -- that is precisely the ordering distinction being measured.
double ICC_SweepLeadBars(int dir)
  {
   // AUDIT FIX (v4.6.2 / Finding 2, HIGH): require the same-side sweep to still be
   // ARMED, not merely to have a stamp. The stamp alone proves a raid happened at
   // some point in history; the counter is what proves it is still the raid this
   // setup is built on. Testing only "armT>0" made the sentinel unreachable in
   // practice and turned an expired sweep into a confident feature value.
   int      conf=(dir>0)? g_sweepConfLong    : g_sweepConfShort;
   datetime armT=(dir>0)? g_sweepArmTimeLong : g_sweepArmTimeShort;
   if(conf<=0) return ML2R_NO_SWEEP;                 // no LIVE sweep on this side
   if(armT<=0 || g_iccStartTime<=0) return ML2R_NO_SWEEP;
   int shArm=iBarShift(_Symbol,g_intTF,armT,false);
   int shInd=iBarShift(_Symbol,g_intTF,g_iccStartTime,false);
   if(shArm<0 || shInd<0) return ML2R_NO_SWEEP;   // stamp fell out of history -> no claim
   return (double)(shArm-shInd);                  // larger shift = older bar
  }

// v4.6.5 RB 2,13; Audit 7-8; function mapping in CHANGE_REPORT.md.
double ICC_ImpulseConcentration(double leg)
  {
   if(leg<=0.0 || g_iccStartTime<=0) return 0.0;
   int shInd=iBarShift(_Symbol,g465.indTF,g_iccStartTime,false);
   if(shInd<1) return 0.0;
   int shEnd=1;
   if(g_corrStartTime>0)
     { int sc=iBarShift(_Symbol,g465.indTF,g_corrStartTime,false); if(sc>=1) shEnd=sc+1; }
   // AUDIT FIX (v4.6.2 / Finding 5, MEDIUM, MODEL CONTRACT): when the Correction
   // confirms on the SAME g465.indTF bar as the Indication (common on an M15 chart
   // with an H1 internal TF -- four chart bars share one H1 bar), sc==shInd, so
   // shEnd became shInd+1 and the function returned a hard 0.0. That silently
   // reported "no concentration" for the fastest, most impulsive setups -- the
   // exact population the feature exists to identify. Clamp so the Indication bar
   // itself is always measured; it is by definition part of the impulse.
   if(shEnd>shInd) shEnd=shInd;
   if(shEnd<1)     shEnd=1;
   double widest=0.0;
   for(int sBar=shInd;sBar>=shEnd;sBar--)
     {
      double h=iHigh(_Symbol,g465.indTF,sBar), l=iLow(_Symbol,g465.indTF,sBar);
      if(h<=0.0 || l<=0.0) continue;              // incomplete history -> skip bar
      double rng=h-l; if(rng>widest) widest=rng;
     }
   return MathMax(0.0,MathMin(1.0,widest/leg));
  }

// v4.6.5 RB 2,13; Audit 7-8; function mapping in CHANGE_REPORT.md.
double ICC_CorrectionLegCount()
  {
   if(g_corrStartTime<=0) return 0.0;
   int cSh=iBarShift(_Symbol,InpEntryTF,g_corrStartTime,false);
   if(cSh<1) return 0.0;
   if(cSh>400) cSh=400;                           // hard bound; expiry makes this unreachable
   int strength=MathMax(1,InpMinorPivotStrength);
   int n=0;
   for(int sBar=strength+1;sBar<=cSh;sBar++)
     {
      if(IsPivotHighTF(InpEntryTF,sBar,strength))     n++;
      else if(IsPivotLowTF(InpEntryTF,sBar,strength)) n++;
     }
   return (double)n;
  }

//--- WHERE IN THE CORRECTION THE TRIGGER FIRED. Fraction of the correction leg
//    that price had already retraced, measured from the correction extreme back
//    toward the impulse extreme, at the instant the continuation confirmed.
//      ~0.1  fired almost straight off the extreme (tight, stop close, high R)
//      ~0.8  fired only after price had climbed most of the way back (the stop
//            still sits at the extreme, so the same setup is a much worse R)
//    ote_depth / correction_depth cannot express this -- they describe how DEEP
//    the pullback went, never how far it had UNWOUND when the trade was taken.
double ICC_CorrectionRecovery(int dir,double trigPx)
  {
   if(trigPx<=0.0) return 0.0;
   double span=(dir>0)? (g_indExtreme-g_corrExtreme) : (g_corrExtreme-g_indExtreme);
   if(span<=0.0) return 0.0;
   double moved=(dir>0)? (trigPx-g_corrExtreme) : (g_corrExtreme-trigPx);
   return MathMax(0.0,MathMin(1.0,moved/span));
  }

// v4.6.5 RB 1-9,17-21; Audit 4,8; function mapping in CHANGE_REPORT.md.
void ICC_Update()
  {
ICC465_Update();
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
// v3.5.0: SR_CheckConfirm() (the classic S/R retest-confirmation ENTRY emitter)
// was removed — retail horizontal-level retests are not the Sci SMC entry model.
// The S/R engine is retained only to map levels for the structural take-profit.
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
      // AUDIT FIX (v4.3.1 / Finding D, LOW, resource leak): RemoveAt() only shifts the
      // parallel arrays -- it does NOT delete the level's chart objects. Every other
      // eviction path (ExpireLevels, SR_CheckBroken/BRK_DELETE) correctly calls
      // DeleteLevelObjects() first. Here the level's name was discarded with the row,
      // so its _box/_ln/_lb objects were orphaned on the chart and could never be
      // deleted individually again (only the OnDeinit prefix sweep cleared them).
      if(ArraySize(sr_price)>60){ DeleteLevelObjects(0); RemoveAt(0); }
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
   Print("ICC-Sci-EA v4.6.2: ",m);
   if(AlertPopup) Alert(m);
   if(AlertPush)  SendNotification(m);
   if(AlertEmail) SendMail("ICC TradesBySci EA v4.6.2 - "+_Symbol,m);
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
//    AUDIT FIX (v4.0.5 / F4): stagedTag is now looked up by the CALLER via
//    RX_ConsumeCloseTag(posId) -- keyed to the specific ticket that closed --
//    instead of this function reading a single shared global. This eliminates
//    the cross-position race described in the v4.0.5 header (F4): closing two
//    positions in one ManagePositions() pass can no longer let one ticket's
//    tag bleed into another ticket's exit-reason label.
string ExitReasonText(ENUM_DEAL_REASON r,string stagedTag)
  {
   switch(r)
     {
      case DEAL_REASON_SL:     return "SL";        // stop-loss hit
      case DEAL_REASON_TP:     return "TP";        // take-profit hit
      case DEAL_REASON_SO:     return "STOP-OUT";  // margin stop-out
      case DEAL_REASON_CLIENT:
      case DEAL_REASON_MOBILE:
      case DEAL_REASON_WEB:
      case DEAL_REASON_EXPERT:
         // AUDIT FIX (v4.0.4): previously EVERY EA/manual close (trend-health
         // reversal exit, partial take, manual button, opposite-signal close)
         // collapsed to "OPP-CLOSE" here, which actively misleads the chart
         // labels and the dashboard's "last exit reason". A tag is now staged
         // at each real close call site (CloseAllThisEA, the R-engine's
         // trend-health reversal exit, the R-engine's partial take) immediately
         // before the trade.Position*() call, keyed to that ticket, and passed
         // in here by the caller; it falls back to the legacy "OPP-CLOSE" label
         // only when no tag was staged for THIS ticket (e.g. a manual close
         // from the terminal).
         return (stagedTag!="")? stagedTag : "OPP-CLOSE";
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
bool SelectPositionByIdentifier(ulong positionId)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==positionId) return true;
     }
   return false;
  }

// v4.6.5 RB 2,10,13,15; Audit 7-8; function mapping in CHANGE_REPORT.md.
// Diagnostic stop ledger is position-ID keyed, independent of the trading ledger.
struct S467DiagStop { ulong id; double sl; };
S467DiagStop g467DiagStops[];
int ICC467_DiagStopIndex(ulong id)
  {
   for(int i=0;i<ArraySize(g467DiagStops);i++) if(g467DiagStops[i].id==id) return i;
   return -1;
  }
void ICC467_DiagRememberSL(ulong id,double sl)
  {
   int i=ICC467_DiagStopIndex(id);
   if(i<0) { i=ArraySize(g467DiagStops); if(ArrayResize(g467DiagStops,i+1)!=i+1) return; g467DiagStops[i].id=id; }
   g467DiagStops[i].sl=sl;
  }
void ICC467_DiagForgetSL(ulong id)
  {
   int i=ICC467_DiagStopIndex(id);
   if(i<0) return;
   int n=ArraySize(g467DiagStops);
   for(int j=i;j<n-1;j++) g467DiagStops[j]=g467DiagStops[j+1];
   ArrayResize(g467DiagStops,n-1);
  }
void ICC467_DiagClosingDeal(ulong deal)
  {
   ENUM_DEAL_ENTRY kind=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   if(kind!=DEAL_ENTRY_OUT && kind!=DEAL_ENTRY_OUT_BY && kind!=DEAL_ENTRY_INOUT) return;
   ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   int i=ICC467_DiagStopIndex(id);
   double historySL=HistoryDealGetDouble(deal,DEAL_SL);
   double requested=i>=0?g467DiagStops[i].sl:ICC465_Get(id,"sl");
   string source=i>=0?"LAST_SUCCESSFUL_MODIFY":"INITIAL_REQUEST";
   if(i<0 && historySL>0 && historySL!=requested) { requested=historySL; source="DEAL_SL_FALLBACK"; }
   double fill=HistoryDealGetDouble(deal,DEAL_PRICE),volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
   ENUM_DEAL_TYPE dealType=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
   if(dealType!=DEAL_TYPE_BUY && dealType!=DEAL_TYPE_SELL) return;
   bool wasLong=dealType==DEAL_TYPE_SELL;
   double delta=0;
   // Signed gross execution difference: actual minus hypothetical SL fill, account currency.
   // Same closing volume and side; excludes fees/swap and is not an alternate exit policy.
   bool available=kind!=DEAL_ENTRY_INOUT &&
      HistoryDealGetInteger(deal,DEAL_REASON)==DEAL_REASON_SL && requested>0 &&
      OrderCalcProfit(wasLong?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,requested,fill,delta);
   MqlTick tick; ZeroMemory(tick);
   bool quoteOK=SymbolInfoTick(_Symbol,tick);
   bool quoteSameMs=quoteOK && tick.time_msc==HistoryDealGetInteger(deal,DEAL_TIME_MSC);
   PrintFormat("[ICC467 DIAG CLOSE_FILL] position=%I64u deal=%I64u setup=%I64d deal_time=%s deal_msc=%I64d side=%s requested_sl=%.8f sl_source=%s deal_sl=%.8f fill=%.8f volume=%.8f actual_minus_sl_money=%s currency=%s reason=%s Bid=%.8f Ask=%.8f spread_price=%.8f quote_msc=%I64d quote_ok=%d quote_same_ms=%d exit_side=%s",
      id,deal,(long)ICC465_Get(id,"setup"),TimeToString((datetime)HistoryDealGetInteger(deal,DEAL_TIME),TIME_DATE|TIME_SECONDS),
      HistoryDealGetInteger(deal,DEAL_TIME_MSC),wasLong?"BUY":"SELL",requested,source,historySL,fill,volume,
      available?DoubleToString(delta,8):"UNAVAILABLE",AccountInfoString(ACCOUNT_CURRENCY),
      EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(deal,DEAL_REASON)),tick.bid,tick.ask,tick.ask-tick.bid,tick.time_msc,(int)quoteOK,(int)quoteSameMs,wasLong?"Bid":"Ask");
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult  &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong dealTicket=trans.deal;
   if(dealTicket==0) return;
   if(!HistoryDealSelect(dealTicket)) return;
   // filter: this EA, this symbol
   if((ulong)HistoryDealGetInteger(dealTicket,DEAL_MAGIC)!=MagicNumber) return;
   if(HistoryDealGetString(dealTicket,DEAL_SYMBOL)!=_Symbol) return;
   ICC465_RecordDeal(dealTicket);
   ICC467_DiagClosingDeal(dealTicket);
   ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
   long     posId =HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);
   double   price =HistoryDealGetDouble (dealTicket,DEAL_PRICE);
   datetime tm    =(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);
   // v3.9.0 icc_ml_v2: register the trade on the ENTRY deal (freeze features + 1R)
   if(entry==DEAL_ENTRY_IN)
     {
      // AUDIT FIX (v4.2.3 / G1): the two registration calls were REORDERED so
      // ML_v4_RegisterEntry runs BEFORE ML_v2_RegisterEntry. ML_v4's own body
      // comment states "Do not consume the pending snapshot here; the legacy v2
      // recorder still needs it" -- i.e. the DESIGN intent is v4-first (reads
      // the g_mlPend* snapshot without consuming it), THEN v2 (reads it and
      // sets g_mlPendValid=false). The previous order was inverted: v2 cleared
      // g_mlPendValid first, so by the time v4 ran, its
      //   r.dir = g_mlPendValid ? g_mlPendDir : <fallback>
      // ALWAYS took the PositionGetInteger() fallback branch. That fallback
      // happens to be correct on a live entry deal, so trades were unaffected,
      // but the v4 dataset's dir/sigTime provenance no longer came from the
      // genuine staged signal -- a latent telemetry defect that would surface
      // the moment the fallback path ever disagreed (e.g. a not-yet-selectable
      // ticket). Restoring the documented order makes v4 read the real staged
      // dir + signal time. Telemetry/data-provenance only; no trade behaviour.
      // v4.3.1 (Finding C): pass THIS entry deal's own volume so the money layer is
      // never silently zeroed by a not-yet-selectable position.
      double entryVol=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
      ML_v4_RegisterEntry((ulong)posId,price,tm,entryVol);   // v4 FIRST: reads, does NOT consume
      ML_v2_RegisterEntry((ulong)posId,price,tm);   // v2 SECOND: reads, then consumes (g_mlPendValid=false)
      // AUDIT FIX (v4.2.5 / Finding 2, LOW, telemetry/defensive): the single-use
      // pending snapshot is normally cleared by ML_v2_RegisterEntry's
      // "g_mlPendValid=false". But that function early-returns when
      // InpMLv2Export=false, so with v4 export ON and v2 export OFF the flag was
      // NEVER reset -- a latent stale-provenance path where a later entry could
      // read a prior signal's staged dir/sigTime. Explicitly consume here so the
      // snapshot is single-use REGARDLESS of either export toggle. Idempotent
      // (already false in the normal path). Telemetry/data-provenance only.
      g_mlPendValid=false;
      return;
     }
   // otherwise handle CLOSING deals (labels + v1 EXIT row + v2 finalize)
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) return;
   double   profit=HistoryDealGetDouble (dealTicket,DEAL_PROFIT)
                  +HistoryDealGetDouble (dealTicket,DEAL_SWAP)
                  +HistoryDealGetDouble (dealTicket,DEAL_COMMISSION);
   ENUM_DEAL_REASON drsn=(ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket,DEAL_REASON);
   // A closing deal's DEAL_TYPE is opposite the closed position: a SELL deal
   // (DEAL_TYPE_SELL) closes a LONG; a BUY deal closes a SHORT.
   ENUM_DEAL_TYPE dtype=(ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket,DEAL_TYPE);
   bool wasLong=(dtype==DEAL_TYPE_SELL);
   // AUDIT FIX (v4.0.5 / F4): look up (and remove) the tag staged specifically for
   // THIS ticket, instead of reading/clearing one shared global -- see F4 in the
   // v4.0.5 header. Safe even if nothing was staged (returns "" -> falls back to
   // "OPP-CLOSE" inside ExitReasonText, same as before).
   string stagedTag=RX_ConsumeCloseTag((ulong)posId);
   string reason=ExitReasonText(drsn,stagedTag);
   // AUDIT FIX (v4.0.4): a partial close (InpUsePartial) is a DEAL_ENTRY_OUT deal on a
   // position that is STILL OPEN for its remainder. Previously this unconditionally drew
   // a "trade closed" arrow/label and incremented g_closedTrades on that partial fill,
   // falsely implying the whole trade was over. Only label/count on the deal that leaves
   // the position truly flat (mirrors the existing ML v2/v4 partial-close guard below).
   bool fullyClosed = !SelectPositionByIdentifier((ulong)posId);
   if(fullyClosed)
     {
      if(InpShowExitLabels) DrawExitLabel(tm,price,wasLong,reason,profit); // visual (gated)
      g_closedTrades++;
      g_lastExitReason=reason;
     }
   ML_Export("EXIT",wasLong?1:-1,profit);                    // v1 SIGNAL/EXIT stream
   ML_v2_OnExitDeal((ulong)posId,price,tm,profit,reason);    // v2 compatibility
   ML_v4_OnExitDeal((ulong)posId,price,tm,profit,reason);    // AUDIT FIX (v4.0.5 / F10): comment was mislabeled "v2 one-row-per-trade finalize" -- this IS the v4 one-row-per-trade finalize call
   if(fullyClosed) ICC467_DiagForgetSL((ulong)posId);
  }
//+==================================================================+
//|                 ML ENABLEMENT v3.7                              |
//+==================================================================+
int ML_CountActiveFVG(){ int n=0; for(int i=0;i<ArraySize(g_fvg);i++) if(g_fvg[i].active) n++; return n; }
int ML_CountActiveOB(){ int n=0; for(int i=0;i<ArraySize(g_ob);i++) if(g_ob[i].active) n++; return n; }
void ML_UpdateContext()
  {
   MqlDateTime dt; TimeCurrent(dt); int h=dt.hour;
   g_mlSession=InKillWindow(h,InpKZ_LonStart,InpKZ_LonEnd)?1:InKillWindow(h,InpKZ_NYamStart,InpKZ_NYamEnd)?2:InKillWindow(h,InpKZ_NYpmStart,InpKZ_NYpmEnd)?3:0;
   double atr=g_mseATRval;
   double span=(g_extProtHigh>0.0 && g_extProtLow>0.0)? MathAbs(g_extProtHigh-g_extProtLow):0.0;
   bool trend=(g_extTrend!=0 && g_intTrend==g_extTrend);
   bool expansion=(atr>0.0 && span>0.0 && span/atr>=3.0);
   g_mlRegime=trend?(expansion?3:2):(expansion?1:0);
   g_mlRegimeTxt=g_mlRegime==3?"TREND+EXP":g_mlRegime==2?"TREND":g_mlRegime==1?"RANGE+HIGHVOL":"RANGE";
  }
void ML_CaptureSignalFeatures(int dir)
  {
   // v3.9.1 FIX: symInfo is refreshed with Refresh() (specs) but never
   // RefreshRates() (quotes), so symInfo.Ask()/Bid() were 0 here and every
   // distance feature collapsed into a raw price magnitude. Source the entry
   // price directly via SymbolInfoDouble (this does NOT mutate the shared
   // symInfo consumed later by ExecuteBuy/ExecuteSell), with an iClose
   // fallback, so execution stays byte-for-byte identical.
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double mkt=iClose(_Symbol,_Period,0); if(mkt<=0.0) mkt=iClose(_Symbol,_Period,1);
   if(ask<=0.0) ask=mkt;
   if(bid<=0.0) bid=mkt;
   double entry=(dir>0)?ask:bid;
   if(entry<=0.0) entry=mkt;                 // final guard (tester warmup)
   double atr=g_mseATRval;
   int idx=MSE_NearestActiveFVG(dir);
   g_mlFVGMidDist=0.0; g_mlFVGMidDistATR=0.0; g_mlFVGSizeATR=0.0;
   if(idx>=0 && entry>0.0)
     {
      double mid=(g_fvg[idx].top+g_fvg[idx].bot)/2.0;
      double size=g_fvg[idx].top-g_fvg[idx].bot;
      g_mlFVGMidDist=MathAbs(entry-mid);
      if(atr>0.0){ g_mlFVGMidDistATR=g_mlFVGMidDist/atr; g_mlFVGSizeATR=size/atr; }
     }
   // AUDIT FIX (v4.0.4): previously this used the RAW ICC anchor distance
   // (|entry-iccSigSL|) alone. The REAL broker stop distance -- the one every
   // 1R..10R label in the v2/v4 ML datasets is actually measured against -- is
   // CalculateSLDistance(structDist): the larger of that anchor distance, the
   // ATR stop, and the broker-min cushion (default SL_Method=SL_SMART). Feeding
   // the classifier a "risk_distance" feature that doesn't match the basis of
   // its own labels can bias training. This mirrors the exact structDist/SL
   // formula ExecuteBuy/ExecuteSell use at execution time -- a feature-accuracy
   // fix only; no order/sizing/trading behaviour changes.
   double mlStructDist=(iccSigSL>0.0 && entry>0.0)? MathAbs(entry-iccSigSL) : 0.0;
   g_mlRiskDistance=(mlStructDist>0.0)? CalculateSLDistance(mlStructDist) : 0.0;
   // AUDIT FIX (v4.0.5 / F3): g_mlRiskDistance above comes from CalculateSLDistance()
   // -> GetATRStopDistance() -> GetRawATR() -> atrHandle (chart TF _Period, ATR_Period)
   // whenever SL_Method is SL_ATR/SL_SMART (the default). Normalizing it here by "atr"
   // (g_mseATRval) instead was a SEPARATE indicator handle -- g_mseATR ran on the SMC
   // structure TF (at the time: g_mseTF, which only equalled the chart TF when
   // InpMSE_TF=PERIOD_CURRENT) using InpDispATRPeriod, NOT ATR_Period. Whenever
   // InpMSE_TF != chart TF or ATR_Period != InpDispATRPeriod, "risk_distance_atr"
   // silently stopped meaning "risk expressed in units of the ATR that actually
   // sized that risk." Fix: use GetRawATR() -- the SAME raw ATR reader the SL engine
   // itself uses -- for this ONE feature only. (g_mlFVGMidDistATR/g_mlFVGSizeATR
   // above correctly keep using the structure-TF "atr"/g_mseATRval, since FVG
   // geometry genuinely lives there -- that normalization was NOT mismatched and is
   // left unchanged.) NOTE (v4.1.0): g_mseTF/InpMSE_TF referenced above were later
   // replaced by g_extTF (MidTF/H4) and g_intTF (WorkTF/H1) -- see Finding 1+2 in
   // the file header. g_mseATR/g_mseATRval now run on g_intTF; this fix's reasoning
   // and conclusion (use GetRawATR() for risk_distance_atr specifically) is unchanged.
   double rawAtrForRisk=GetRawATR();
   g_mlRiskDistanceATR=(rawAtrForRisk>0.0)?g_mlRiskDistance/rawAtrForRisk:0.0;
   g_mlRiskDistancePips=(g_pip>0.0)?g_mlRiskDistance/g_pip:0.0;
   g_mlSpreadPoints=(double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
   g_mlSpreadPrice=g_mlSpreadPoints*_Point;
   MqlDateTime dt; TimeCurrent(dt);
   g_mlHour=dt.hour; g_mlMinuteOfDay=dt.hour*60+dt.min;
   double ang=2.0*M_PI*(double)g_mlMinuteOfDay/1440.0;
   g_mlTimeSin=MathSin(ang); g_mlTimeCos=MathCos(ang);
  }
//+------------------------------------------------------------------+
//| v4.4.1 ML FEATURE PROVENANCE FIX                                |
//| Four protected-swing distance features were never populated by   |
//| the v4.4.0 learned-2R path. They are now captured at inference   |
//| time from the live H4/H1 protected structure, normalized by the  |
//| H1 structure ATR already used by the v4 dataset contract.       |
//| No ICC entry/exit/sizing rule is changed.                        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| v4.4.0 LEARNED 2R MODEL                                         |
//| ICC remains the setup generator; ML only evaluates valid setups. |
//+------------------------------------------------------------------+
// v4.4.1 ML FEATURE PROVENANCE / LEAKAGE HARDENING
// Build the 28 features ONLY from state that exists before the order is sent.
// The caller reaches this function only after ICC_Update() has produced a valid
// continuation and immediately before ExecuteBuy()/ExecuteSell().  No future
// trade outcome, post-entry bar, or bar-0 OHLC is used as a model feature.
bool ML_Build2RFeatures(int dir,ML2RFeatures &x)
  {
   // IMPORTANT: live Bid/Ask is intentional here. It is the information actually
   // available at the decision tick. iClose(...,0) is only a warm-up fallback;
   // MQL5 shift 0 is the still-forming/current bar, not a historical close.
   double entry=(dir>0?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
   if(entry<=0.0) entry=iClose(_Symbol,_Period,0);
   if(entry<=0.0) return false;

   // ATR for the chart-timeframe risk feature. GetRawATR() explicitly reads
   // buffer shift 1, i.e. the last fully closed chart bar.
   double rawAtr=GetRawATR();

   // v4.6.0: the v4.4.1 correction_depth recompute/fallback that stood here is
   // REMOVED, because correction_depth is no longer a tensor slot (it was the
   // clamped twin of ote_depth -- see the contract note on ML2RFeatures). The
   // g_mlCorrectionDepth LATCH in ICC_Update() is deliberately left in place:
   // it still populates engine state and keeps the column available to the v4
   // dataset, so reinstating it is a preprocessing decision made on evidence
   // rather than a code change made on assumption.
   //
   // EVERY path-dependent feature read below comes from a LATCH written in the
   // continuation branch BEFORE ICC_Reset(). None of them may be recomputed
   // here: by the time TryEntries() calls this function the ICC geometry is
   // already zeroed, which is exactly how the v4.4.1 Finding A defect survived
   // three releases and could not be seen in any CSV.

   // v4.4.0 defect: the four protected-swing distance globals were declared but
   // NEVER assigned by the learned-2R path, so features 24-27 were always zero.
   // Populate them HERE, immediately before inference, from the same protected
   // H4/H1 structures that are already feeding the live ICC engine.
   // The existing v4 CSV contract normalizes all four distances by the H1
   // internal-structure ATR (g_mseATRval). That convention is retained so the
   // feature ordering/semantics stay compatible with the v4 dataset.
   double structureAtr=g_mseATRval;
   g_mlDistExtHighATR=0.0; g_mlDistExtLowATR=0.0;
   g_mlDistIntHighATR=0.0; g_mlDistIntLowATR=0.0;
   if(structureAtr>0.0)
     {
      if(g_extProtHigh>0.0) g_mlDistExtHighATR=MathAbs(g_extProtHigh-entry)/structureAtr;
      if(g_extProtLow>0.0)  g_mlDistExtLowATR =MathAbs(entry-g_extProtLow)/structureAtr;
      if(g_intProtHigh>0.0) g_mlDistIntHighATR=MathAbs(g_intProtHigh-entry)/structureAtr;
      if(g_intProtLow>0.0)  g_mlDistIntLowATR =MathAbs(entry-g_intProtLow)/structureAtr;
     }

   // All assignments below are snapshots of state that exists NOW, before the
   // broker order is submitted. Do not move this function after ExecuteBuy/Sell.
   x.htf_score=(float)HTFscore(); x.int_trend=(float)g_intTrend;
   // 02/03 -- LIQUIDITY, now as AGE + ORDER rather than two side-specific counters.
   x.sweep_age=(float)g_mlSweepAge;
   x.sweep_lead_bars=(float)g_mlSweepLeadBars;
   // v4.5.0 Finding 5: read the Indication-bar latch, falling back to g_lastDispScore
   // only if no Indication has been latched yet (defensive; a no-op on the live path).
   double dispFeat=(g_mlDispAtIndication>0.0)? g_mlDispAtIndication : g_lastDispScore;
   x.displacement=(float)MathMax(0.0,MathMin(1.0,dispFeat/100.0));
   x.fvg_active=(float)ML_CountActiveFVG(); x.ob_active=(float)ML_CountActiveOB();
   x.atr_pct=(float)((rawAtr>0.0)?rawAtr/entry:0.0);
   x.session=(float)g_mlSession; x.regime=(float)g_mlRegime;
   x.fvg_mid_dist_atr=(float)g_mlFVGMidDistATR; x.ote_depth=(float)g_mlOTEDepth;
   x.fvg_size_atr=(float)g_mlFVGSizeATR; x.risk_distance_atr=(float)g_mlRiskDistanceATR;
   x.spread_points=(float)g_mlSpreadPoints; x.time_sin=(float)g_mlTimeSin; x.time_cos=(float)g_mlTimeCos;
   // 17/18/19 -- IMPULSE: age, magnitude, and now SHAPE.
   x.impulse_age=(float)g_mlImpulseAgeBars; x.impulse_leg_atr=(float)g_mlImpulseLegATR;
   x.impulse_concentration=(float)g_mlImpulseConcentration;
   // 20/21/22 -- CORRECTION: age, and now SHAPE + WHERE THE TRIGGER FIRED.
   x.correction_age=(float)g_mlCorrectionAgeBars;
   x.corr_leg_count=(float)g_mlCorrLegCount;
   x.corr_recovery_frac=(float)g_mlCorrRecovery;
   x.dist_ext_high_atr=(float)g_mlDistExtHighATR; x.dist_ext_low_atr=(float)g_mlDistExtLowATR;
   x.dist_int_high_atr=(float)g_mlDistIntHighATR; x.dist_int_low_atr=(float)g_mlDistIntLowATR;
   x.direction=(float)dir;
   return true;
  }

//+------------------------------------------------------------------+
//| v4.4.1 28-VALUE FEATURE DUMP (diagnostic only; sets NO state)     |
//| Prints the COMPLETE model input vector in CONTRACT ORDER, with    |
//| the same indices ML_Run2RInference writes into input_data[0][i].  |
//| WHY THIS EXISTS: before v4.4.1 the ONLY inference log was         |
//|   "[ML2R] dir=%d P2R=%.4f decision=%d risk=x%.2f model=%s"        |
//| which exposes NONE of the 28 features -- so a constant/zeroed     |
//| feature (v4.4.0 features 24-27, and feature 23 up to v4.4.1)      |
//| could reach the classifier with no way to observe it before       |
//| training. The v4 CSV cannot substitute for this: several v4       |
//| columns are written by ML_v4_RegisterEntry from a SEPARATE        |
//| calculation, so the CSV can look correct while the INFERENCE      |
//| vector is wrong. This is emitted on TWO lines to stay within      |
//| MQL5's PrintFormat argument limit and to keep the Journal         |
//| greppable: filter on "[ML2R FEAT]".                               |
//| Trading-NEUTRAL: reads the struct, mutates nothing.               |
//+------------------------------------------------------------------+
void ML_LogFeatureVector(int dir,const ML2RFeatures &f)
  {
   if(!InpMLLogInference) return;
   PrintFormat("[ML2R FEAT] t=%s dir=%d | 00 htf_score=%.6f 01 int_trend=%.6f 02 sweep_age=%.6f 03 sweep_lead_bars=%.6f 04 displacement=%.6f 05 fvg_active=%.6f 06 ob_active=%.6f 07 atr_pct=%.8f 08 session=%.6f 09 regime=%.6f 10 fvg_mid_dist_atr=%.6f 11 ote_depth=%.6f 12 fvg_size_atr=%.6f 13 risk_distance_atr=%.6f",
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),dir,
      f.htf_score,f.int_trend,f.sweep_age,f.sweep_lead_bars,f.displacement,
      f.fvg_active,f.ob_active,f.atr_pct,f.session,f.regime,
      f.fvg_mid_dist_atr,f.ote_depth,f.fvg_size_atr,f.risk_distance_atr);
   PrintFormat("[ML2R FEAT] t=%s dir=%d | 14 spread_points=%.6f 15 time_sin=%.6f 16 time_cos=%.6f 17 impulse_age=%.6f 18 impulse_leg_atr=%.6f 19 impulse_concentration=%.6f 20 correction_age=%.6f 21 corr_leg_count=%.6f 22 corr_recovery_frac=%.6f 23 dist_ext_high_atr=%.6f 24 dist_ext_low_atr=%.6f 25 dist_int_high_atr=%.6f 26 dist_int_low_atr=%.6f 27 direction=%.6f",
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),dir,
      f.spread_points,f.time_sin,f.time_cos,
      f.impulse_age,f.impulse_leg_atr,f.impulse_concentration,
      f.correction_age,f.corr_leg_count,f.corr_recovery_frac,
      f.dist_ext_high_atr,f.dist_ext_low_atr,f.dist_int_high_atr,f.dist_int_low_atr,
      f.direction);
  }

bool ML_Run2RInference(const ML2RFeatures &f,double &prob)
  {
   prob=0.0;
   if(!g_mlModelReady || g_mlOnnx==INVALID_HANDLE){ g_mlInferenceError="model_not_ready"; return false; }
   matrixf input_data(1,ML2R_FEATURE_COUNT);
   // v4.6.0 CONTRACT ORDER. These indices are the single source of truth for the
   // training preprocessor -- ML_LogFeatureVector below prints the SAME indices,
   // so the Journal dump and the tensor can never silently disagree.
   input_data[0][0]=f.htf_score; input_data[0][1]=f.int_trend; input_data[0][2]=f.sweep_age; input_data[0][3]=f.sweep_lead_bars;
   input_data[0][4]=f.displacement; input_data[0][5]=f.fvg_active; input_data[0][6]=f.ob_active; input_data[0][7]=f.atr_pct;
   input_data[0][8]=f.session; input_data[0][9]=f.regime; input_data[0][10]=f.fvg_mid_dist_atr; input_data[0][11]=f.ote_depth;
   input_data[0][12]=f.fvg_size_atr; input_data[0][13]=f.risk_distance_atr; input_data[0][14]=f.spread_points; input_data[0][15]=f.time_sin;
   input_data[0][16]=f.time_cos; input_data[0][17]=f.impulse_age; input_data[0][18]=f.impulse_leg_atr; input_data[0][19]=f.impulse_concentration;
   input_data[0][20]=f.correction_age; input_data[0][21]=f.corr_leg_count; input_data[0][22]=f.corr_recovery_frac;
   input_data[0][23]=f.dist_ext_high_atr; input_data[0][24]=f.dist_ext_low_atr; input_data[0][25]=f.dist_int_high_atr;
   input_data[0][26]=f.dist_int_low_atr; input_data[0][27]=f.direction;
   // AUDIT FIX (v4.5.0 / Finding 1, CRITICAL, RUNTIME): the receiving buffer was
   // declared "vectorf output(1)" -- a RANK-1 tensor of shape [1] -- while
   // ML_Load2RModel() had already pinned the model's output to the RANK-2 shape
   // {1,1} via OnnxSetOutputShape(). Under ONNX_NO_CONVERSION MQL5 does no
   // reshaping: the destination rank must match the declared output rank, so
   // OnnxRun() fails on EVERY call. The consequences were invisible by design:
   // ML_Run2RInference returns false, ML_Evaluate2R takes the failed-inference
   // branch, and with the default InpMLRequireModel=true every signal is vetoed
   // (fail-closed, zero trades) -- or, with it false, every signal trades
   // UNFILTERED while the operator believes a learned model is running. Either
   // way the model never actually scores a setup. FIX: receive into a matrixf of
   // the SAME {1,1} shape the output was pinned to.
   matrixf output(1,1);
   ResetLastError();
   if(!OnnxRun(g_mlOnnx,ONNX_NO_CONVERSION,input_data,output))
     { g_mlInferenceError=StringFormat("onnx_run_error_%d",GetLastError()); return false; }
   if(output.Rows()<1 || output.Cols()<1){ g_mlInferenceError="empty_output_tensor"; return false; }
   prob=(double)output[0][0];
   if(prob<0.0 || prob>1.0){ g_mlInferenceError="output_not_probability"; return false; }
   return true;
  }

void ML_Evaluate2R(int dir)
  {
   g_mlInferenceValid=false; g_mlInferenceError=""; g_ml2RProb=0.0; g_mlRiskMult=1.0;
   g_mlPass=true; g_mlDecision=0;
   // AUDIT FIX (v4.6.2 / Finding 4, HIGH, TRADE PATH): seed the exit policy for the
   // NO-INFERENCE case here, instead of unconditionally true. If the learned exit
   // policy is enabled but no probability exists, riding open-ended is the one
   // choice the model demonstrably did NOT make. Falling back to a real >=InpMinTPRR
   // target keeps the 2R objective enforceable; InpRunnerWhenNoInference=true
   // restores the legacy v4.6.1 behaviour.
   g_mlRunner=(!InpMLRunnerByProb) || InpRunnerWhenNoInference;
   ML_UpdateContext(); ML_CaptureSignalFeatures(dir);
   if(!InpMLModelEnabled)
     {
      g_mlModelVersion="DISABLED";
      // v4.4.1: with the model DISABLED the feature vector was never built at all,
      // so the 28 features could not be inspected on a plain OBSERVE run. When
      // InpMLLogInference is ON we now build and dump the vector anyway -- purely
      // to make feature provenance auditable WITHOUT requiring a trained ONNX file.
      // Diagnostic only: no inference is run, no gate/size decision is affected.
      if(InpMLLogInference)
        {
         ML2RFeatures fdbg;
         if(ML_Build2RFeatures(dir,fdbg)) ML_LogFeatureVector(dir,fdbg);
        }
      if(InpMLMode==ML_FILTER || InpMLMode==ML_FILTER_SIZE || InpMLMode==ML_FULL){ g_mlPass=false; g_mlDecision=-1; }
      return;
     }
   ML2RFeatures f;
   // v4.4.1: build FIRST, dump SECOND, infer THIRD. The previous
   // "!ML_Build2RFeatures(...) || !ML_Run2RInference(...)" short-circuit meant a
   // failed OnnxRun discarded the vector silently, which is exactly the case an
   // operator most needs to see.
   bool built=ML_Build2RFeatures(dir,f);
   if(built) ML_LogFeatureVector(dir,f);
   if(!built || !ML_Run2RInference(f,g_ml2RProb))
     {
      g_mlPass=(!InpMLRequireModel || InpMLMode==ML_OFF || InpMLMode==ML_OBSERVE || InpMLMode==ML_SHADOW);
      g_mlDecision=g_mlPass?0:-1;
      return;
     }
   g_mlInferenceValid=true;
   g_mlRiskMult=(g_ml2RProb>=InpML2RHighThreshold?InpMLHighRiskMult:(g_ml2RProb>=InpML2RThreshold?InpMLBaseRiskMult:InpMLLowRiskMult));
   if(InpMLMode==ML_FILTER || InpMLMode==ML_FILTER_SIZE || InpMLMode==ML_FULL)
     {
      // AUDIT FIX (v4.5.0 / Finding 10, LOW-MEDIUM, DEAD PARAMETER): InpMLLowRiskMult
      // was UNREACHABLE. It is only selected when P2R < InpML2RThreshold, but in every
      // FILTERING mode that same condition vetoes the trade outright, and in
      // OBSERVE/SHADOW the multiplier is never applied to sizing at all. The
      // "confidence sizing" tier the input documents therefore never executed once.
      // FIX (opt-in, default 0.00 = exact legacy veto): when InpML2RLowThreshold>0,
      // a signal scoring in [InpML2RLowThreshold .. InpML2RThreshold) is TAKEN at the
      // reduced multiplier instead of discarded, which is what a graded probability
      // is for. Below InpML2RLowThreshold it is still vetoed.
      bool lowBand=(InpML2RLowThreshold>0.0
                    && g_ml2RProb>=InpML2RLowThreshold
                    && g_ml2RProb< InpML2RThreshold);
      g_mlPass=(g_ml2RProb>=InpML2RThreshold) || lowBand;
      g_mlDecision=g_mlPass?1:-1;
     }
   else { g_mlPass=true; g_mlDecision=(g_ml2RProb>=InpML2RThreshold?1:0); }
   // AUDIT FIX (v4.5.0 / Finding 2, CRITICAL, TRADE-PATH): the learned probability
   // now selects the EXIT POLICY. This is the single decision in the EA that is
   // genuinely made by the model rather than merely filtered by it, and it is what
   // makes the 2R objective enforceable: a setup the model does NOT rate as a
   // high-probability 2R runner is given a real, broker-side take-profit at no less
   // than InpMinTPRR, instead of being handed to an open-ended runner by default.
   if(InpMLRunnerByProb) g_mlRunner=(g_ml2RProb>=InpMLRunnerMinP2R);
   if(InpMLLogInference)
      PrintFormat("[ML2R] dir=%d P2R=%.4f decision=%d risk=x%.2f model=%s",dir,g_ml2RProb,g_mlDecision,g_mlRiskMult,g_mlModelVersion);
  }

//+------------------------------------------------------------------+
//| v4.4.2 ML GATE VERDICT RECORD  (Working Document v1.2 s9 Layer D) |
//| Emitted ONCE per routed ICC signal, immediately after              |
//| ML_Evaluate2R() and BEFORE the pass/block branch, so the record    |
//| exists whether the setup trades or is vetoed.                      |
//|                                                                    |
//| WHY UNCONDITIONAL (no input gate, unlike InpMLLogInference):       |
//|   Before v4.4.2 a veto left almost no trace. The only block message |
//|   was gated behind VerboseLog, and the "[ML2R] dir/P2R/decision"    |
//|   line is (a) gated behind InpMLLogInference, which defaults FALSE, |
//|   and (b) printed ONLY on the inference-SUCCESS path -- so on a     |
//|   model failure, the case where a block is MOST suspicious, there   |
//|   was no [ML2R] line at all. A CORE-valid, enhancement-passing      |
//|   setup could therefore be discarded in complete silence while the  |
//|   shadow evaluator logged "CORE+ENH PASS" for the same bar.         |
//|                                                                    |
//| FLOOD RISK: none. Unlike ICC_ShadowEvaluate (per BAR, ~30k lines on |
//|   an M15 year), this fires only on a genuine routed ICC signal --   |
//|   the live engine produced 18 over 11 months. No throttle needed.   |
//|                                                                    |
//| Trading-NEUTRAL: reads state, increments diagnostic counters, and   |
//| Prints. It sets NO gating, sizing or ICC state, so backtest trade   |
//| results are byte-identical with or without it.                     |
//+------------------------------------------------------------------+
void ML_LogGateVerdict(int dir)
  {
   bool gating=(InpMLMode==ML_FILTER || InpMLMode==ML_FILTER_SIZE || InpMLMode==ML_FULL);
   g_mlGateEval++;
   if(g_mlPass) g_mlGatePass++;
   else       { g_mlGateBlock++; if(!g_mlInferenceValid) g_mlGateBlockNoModel++; }
   // FAIL-OPEN DETECTION (hostile finding, v4.4.2 Finding C). With
   // InpMLRequireModel=false the pass expression
   //   g_mlPass=(!InpMLRequireModel || mode==OFF/OBSERVE/SHADOW)
   // evaluates TRUE on a FAILED inference even in a FILTER mode. The gate
   // then silently degrades to pass-through: the operator believes a filter
   // is running, and every ICC signal trades unfiltered. Nothing anywhere
   // reported this. Warn ONCE per session; do NOT change the behaviour --
   // fail-open vs fail-closed is what InpMLRequireModel exists to select.
   if(gating && !g_mlInferenceValid && g_mlPass && !g_mlGateFailOpenWarned)
     {
      g_mlGateFailOpenWarned=true;
      PrintFormat("[ML2R GATE] *** FAIL-OPEN WARNING: mode=%s is a FILTERING mode but inference is UNAVAILABLE (err=%s) and InpMLRequireModel=false -> the gate is NOT filtering. Every ICC signal will trade unfiltered for the rest of this run. Set InpMLRequireModel=true to fail closed, or disable the filtering mode.",
                  EnumToString(InpMLMode),(g_mlInferenceError==""?"none":g_mlInferenceError));
     }
   // Verdict vocabulary deliberately MIRRORS the [SCI CORE] evaluator so the
   // two streams reconcile by timestamp. "<<<" marks the countable class the
   // Working Document s9 asks for: a setup the CORE model approved and the
   // learned enhancement then killed.
   string verdict;
   if(!gating)                     verdict="ML-N/A (non-gating mode; observation only)";
   else if(g_mlPass)               verdict="ML-PASS";
   else if(!g_mlInferenceValid)    verdict="ML-REJECT (model unavailable, fail-closed)  <<< CORE-VALID SETUP VETOED";
   else                            verdict="ML-REJECT (score below threshold)  <<< CORE-VALID SETUP VETOED";
   PrintFormat("[ML2R GATE] bar=%d t=%s dir=%d | mode=%s gating=%d modelEnabled=%d requireModel=%d | model=%s infValid=%d err=%s | P2R=%.4f thr=%.2f highThr=%.2f | riskMult=%.2f | phaseAtFire=%d | %s | totals eval=%d pass=%d block=%d (modelUnavail=%d)",
      g_barCount,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),dir,
      EnumToString(InpMLMode),(int)gating,(int)InpMLModelEnabled,(int)InpMLRequireModel,
      g_mlModelVersion,(int)g_mlInferenceValid,(g_mlInferenceError==""?"none":g_mlInferenceError),
      g_ml2RProb,InpML2RThreshold,InpML2RHighThreshold,
      g_mlRiskMult,g_mlSigPhaseAtFire,
      verdict,
      g_mlGateEval,g_mlGatePass,g_mlGateBlock,g_mlGateBlockNoModel);
  }

//--- v4.4.2: end-of-run rollup so the s14 ML-gate experiment can be read
//    off ONE line instead of counted out of the Journal. Log-only.
void ML_LogGateSummary()
  {
   if(g_mlGateEval<=0) return;
   double blockPct=100.0*(double)g_mlGateBlock/(double)g_mlGateEval;
   PrintFormat("[ML2R GATE] SESSION SUMMARY | mode=%s modelEnabled=%d model=%s | evaluations=%d pass=%d block=%d (%.1f%% of CORE-valid setups vetoed; %d of those from an unusable model) | InpML2RThreshold=%.2f",
      EnumToString(InpMLMode),(int)InpMLModelEnabled,g_mlModelVersion,
      g_mlGateEval,g_mlGatePass,g_mlGateBlock,blockPct,g_mlGateBlockNoModel,InpML2RThreshold);
   if(g_mlGateBlock>0)
      Print("[ML2R GATE] NOTE: every blocked signal above had already satisfied the ICC CORE sequence and every enabled enhancement gate. Per Working Document s8 the learned gate is an EA ENHANCEMENT -- adopt it only on out-of-sample monetary/R evidence, never on trade count.");
  }

bool ML_Load2RModel()
  {
   g_mlModelReady=false; g_mlOnnx=INVALID_HANDLE; g_mlModelVersion="NONE";
   if(!InpMLModelEnabled) return true;
   ResetLastError(); g_mlOnnx=OnnxCreate(InpMLModelFile,ONNX_COMMON_FOLDER);
   if(g_mlOnnx==INVALID_HANDLE){ PrintFormat("[ML2R] MODEL LOAD FAILED file=%s err=%d",InpMLModelFile,GetLastError()); return false; }
   long inputs=OnnxGetInputCount(g_mlOnnx), outputs=OnnxGetOutputCount(g_mlOnnx);
   if(inputs!=1 || outputs!=1){ PrintFormat("[ML2R] MODEL CONTRACT FAILED inputs=%I64d outputs=%I64d; expected 1/1",inputs,outputs); OnnxRelease(g_mlOnnx); g_mlOnnx=INVALID_HANDLE; return false; }

   //=================================================================
   // v4.6.1 BINDING CONTRACT GUARD -- runs BEFORE the shape calls, because
   // the shape is exactly what CANNOT discriminate here: a pre-v4.6.0 model
   // passes every shape assertion this function makes. Checked first so a
   // rejected artifact fails fast and never reaches inference.
   //=================================================================
   string gotName=OnnxGetInputName(g_mlOnnx,0);        // NULL on failure
   string wantName=ML2R_CONTRACT_TOKEN;
   bool   named   =(gotName!=NULL && StringLen(gotName)>0);
   // AUDIT FIX (v4.6.2 / Finding 6, MEDIUM, DOC/CODE DIVERGENCE): this comparison
   // is CASE-SENSITIVE (StringCompare's third argument is case_sensitive, and it is
   // true here). The v4.6.1 documentation described it as case-insensitive. The
   // CODE is right -- an ONNX graph input name is an exact identifier and a
   // case-folded match would accept an artifact that is not the one specified --
   // so the documentation is corrected to match the code, not the reverse.
   bool   tokenOK =(named && StringCompare(gotName,wantName,true)==0);

   // Advisory only, and deliberately separate from the decision above: a
   // filename proves nothing (it is trivially renamed) but a literal "v1" in
   // the path is worth surfacing even when the graph name checks out.
   // AUDIT FIX (v4.6.2 / Finding 8, LOW, FALSE POSITIVE): the v4.6.1 test matched
   // "v1" ANYWHERE in the string, so "ICC_2R_v10.onnx", "rev1.onnx" or a folder
   // named "v1.5" all tripped it. An advisory that fires on correct inputs trains
   // the operator to ignore it. Match the actual legacy artifact patterns instead.
   if(StringFind(InpMLModelFile,"_v1.")>=0 || StringFind(InpMLModelFile,"_v1_")>=0)
      PrintFormat("[ML2R] NOTE: InpMLModelFile=%s contains \"v1\". The filename is NOT the contract -- the input-tensor name is. Verify this artifact was retrained on the v4.6.0 PATH_v2 feature set.",InpMLModelFile);

   if(!tokenOK)
     {
      if(InpMLEnforceContract)
        {
         PrintFormat("[ML2R] *** MODEL CONTRACT REJECTED file=%s inputName=%s expected=%s",
                     InpMLModelFile,(named?gotName:"<unnamed/NULL>"),wantName);
         Print("[ML2R] *** The tensor SHAPE [1,",ML2R_FEATURE_COUNT,"] matched, so this model WOULD have loaded and scored -- silently, and wrongly. v4.6.0 replaced ext_trend/icc_phase/correction_depth/sweep_long+short with the path-dependent set, so slot i no longer carries what this artifact was trained on.");
         Print("[ML2R] *** FIX: retrain on a homogeneous schema-4.2.0 dataset and export with the contract name set --");
         Print("[ML2R] ***      skl2onnx: convert_sklearn(clf, initial_types=[(\"",wantName,"\", FloatTensorType([1,",ML2R_FEATURE_COUNT,"]))])");
         Print("[ML2R] ***      torch   : torch.onnx.export(..., input_names=[\"",wantName,"\"])");
         Print("[ML2R] *** Override with InpMLEnforceContract=false ONLY to reproduce a historical run. Never in autonomous mode.");
         OnnxRelease(g_mlOnnx); g_mlOnnx=INVALID_HANDLE; return false;
        }
      // Fail-open path: mirrors the InpMLRequireModel=false warning idiom in
      // ML_Evaluate2R. Loud, unconditional, and states the consequence rather
      // than merely noting the setting.
      PrintFormat("[ML2R] *** FAIL-OPEN WARNING: InpMLEnforceContract=false and the contract token does NOT match (inputName=%s expected=%s). This model is being accepted on SHAPE ALONE. If it predates v4.6.0 every probability it returns for the rest of this run is meaningless, and the gate will still look like it is working. Metrics from this run are NOT admissible as A/B evidence.",
                  (named?gotName:"<unnamed/NULL>"),wantName);
     }

   const ulong inputShape[]={1,ML2R_FEATURE_COUNT}; const ulong outputShape[]={1,1};
   if(!OnnxSetInputShape(g_mlOnnx,0,inputShape)){ PrintFormat("[ML2R] INPUT SHAPE FAILED err=%d",GetLastError()); OnnxRelease(g_mlOnnx); g_mlOnnx=INVALID_HANDLE; return false; }
   if(!OnnxSetOutputShape(g_mlOnnx,0,outputShape)){ PrintFormat("[ML2R] OUTPUT SHAPE FAILED err=%d",GetLastError()); OnnxRelease(g_mlOnnx); g_mlOnnx=INVALID_HANDLE; return false; }
   // v4.6.1: the version tag now reports what was VERIFIED, not a literal. This
   // string reaches the v4 dataset via ML_v4_ModelVersion(), so a run made under
   // an unverified override is self-identifying in the CSV afterwards -- the
   // provenance survives past the Journal being cleared.
   g_mlModelReady=true;
   g_mlModelVersion=tokenOK ? ("ICC_2R_"+wantName+"_VERIFIED")
                            : ("ICC_2R_UNVERIFIED("+(named?gotName:"unnamed")+")");
   PrintFormat("[ML2R] MODEL READY version=%s contract=%s features=%d file=%s",
               g_mlModelVersion,(tokenOK?"VERIFIED":"*** UNVERIFIED ***"),
               ML2R_FEATURE_COUNT,InpMLModelFile);
   return true;
  }

void ML_Export(string eventName,int dir,double resultMoney=0.0)
  {
   if(!InpMLExportCSV) return;
   int h=FileOpen(g_mlv1FileEff,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI,',');
   if(h==INVALID_HANDLE){ Print("ML CSV open failed: ",GetLastError()); return; }
   bool empty=(FileSize(h)==0); FileSeek(h,0,SEEK_END);
   if(empty)
     {
      // AUDIT FIX (v4.0.5 / F9): check the header write result -- previously
      // discarded, so a disk-full/permission failure here left a headerless
      // (or partially-headered) CSV with zero diagnostic trace.
      uint whdr=FileWrite(h,"schema","event","time","symbol","period","dir","htf_score","ext_trend","int_trend","sweep_long","sweep_short","disp","fvg_active","ob_active","atr","session","regime","p2r_prob","legacy_p3","legacy_p5","legacy_p10","legacy_forecast_dir","legacy_forecast_atr","fvg_mid_dist","fvg_mid_dist_atr","ote_depth","fvg_size_atr","risk_distance","risk_distance_atr","risk_distance_pips","spread_price","spread_points","hour","minute_of_day","time_sin","time_cos","symbol_id","risk_mult","runner","result_money");
      if(whdr==0) Print("[ML] WARNING: v1 CSV header write may have FAILED err=",GetLastError()," file=",g_mlv1FileEff);
     }
   uint wrow=FileWrite(h,"icc_ml_v1",eventName,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),dir,HTFscore(),g_extTrend,g_intTrend,g_sweepConfLong,g_sweepConfShort,g_lastDispScore,ML_CountActiveFVG(),ML_CountActiveOB(),g_mseATRval,g_mlSession,g_mlRegime,g_ml2RProb,0.0,0.0,0.0,0,0.0,g_mlFVGMidDist,g_mlFVGMidDistATR,g_mlOTEDepth,g_mlFVGSizeATR,g_mlRiskDistance,g_mlRiskDistanceATR,g_mlRiskDistancePips,g_mlSpreadPrice,g_mlSpreadPoints,g_mlHour,g_mlMinuteOfDay,g_mlTimeSin,g_mlTimeCos,_Symbol,g_mlRiskMult,(int)g_mlRunner,resultMoney);
   // AUDIT FIX (v4.0.5 / F9): FileWrite() returns bytes written (0/negative on
   // failure); previously never checked, so a dropped row had zero indication.
   if(wrow==0) Print("[ML] WARNING: v1 CSV row write may have FAILED err=",GetLastError()," event=",eventName," file=",g_mlv1FileEff);
   FileClose(h);   // FileClose() is void in MQL5 -- nothing to check here
  }
//+==================================================================+
//|   v3.8.1: CREATE CSV + HEADER AT STARTUP                        |
//|   Guarantees the dataset file exists and carries the correct     |
//|   header even if OBSERVE runs produce zero ICC signals, so the    |
//|   export path/permissions are verifiable. Header is written only  |
//|   when the file is empty; SIGNAL/EXIT rows still append later.    |
//|   NOTE: In the Strategy Tester, FILE_COMMON is redirected to the  |
//|   agent sandbox (…/Tester/Agent-*/MQL5/Files), NOT the live       |
//|   Terminal/Common/Files. On a live/demo chart it lands in Common. |
//+==================================================================+
void ML_EnsureCSVHeader()
  {
   if(!InpMLExportCSV) return;
   int h=FileOpen(g_mlv1FileEff,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI,',');
   if(h==INVALID_HANDLE)
     {
      Print("[ML] CSV create/verify FAILED err=",GetLastError()," file=",g_mlv1FileEff);
      return;
     }
   if(FileSize(h)==0)
      FileWrite(h,"schema","event","time","symbol","period","dir","htf_score","ext_trend","int_trend","sweep_long","sweep_short","disp","fvg_active","ob_active","atr","session","regime","p2r_prob","legacy_p3","legacy_p5","legacy_p10","legacy_forecast_dir","legacy_forecast_atr","fvg_mid_dist","fvg_mid_dist_atr","ote_depth","fvg_size_atr","risk_distance","risk_distance_atr","risk_distance_pips","spread_price","spread_points","hour","minute_of_day","time_sin","time_cos","symbol_id","risk_mult","runner","result_money");
   FileClose(h);
   Print("[ML] CSV ready -> Common\\Files\\",g_mlv1FileEff,
         "  (mode=",EnumToString(InpMLMode),
         ", export=",(InpMLExportCSV?"true":"false"),
         ")  NOTE: Strategy Tester redirects FILE_COMMON to the agent sandbox.");
  }
//+==================================================================+
//|   v3.9.0 icc_ml_v2 TRADE-LIFE-CYCLE RECORDER (true 2R label)     |
//|   Freezes signal-time features at entry, tracks MFE/MAE per open  |
//|   trade every tick, and writes ONE finalized row per completed    |
//|   trade carrying reached_1r..reached_10r + exit_r. Join-safe and   |
//|   leakage-free: the training target is derived only from post-     |
//|   entry excursion. Separate file from the v1 SIGNAL/EXIT stream.   |
//|   NOTE: FILE_COMMON is redirected to the tester agent sandbox      |
//|   during Strategy Tester runs (same as v3.8.1).                    |
//+==================================================================+
void ML_v2_StagePending(int dir)
  {
   // g_ml* feature globals were just populated by ML_Evaluate2R(dir)
   g_mlPendValid=true; g_mlPendDir=dir; g_mlPendSigTime=TimeCurrent();
   g_pHTF=HTFscore(); g_pExt=g_extTrend; g_pInt=g_intTrend;
   g_pSweepL=g_sweepConfLong; g_pSweepS=g_sweepConfShort; g_pDisp=g_mlDispAtIndication;
   g_pFVG=ML_CountActiveFVG(); g_pOB=ML_CountActiveOB(); g_pATR=g_mseATRval;
   g_pSession=g_mlSession; g_pRegime=g_mlRegime;
   g_pFVGdist=g_mlFVGMidDist; g_pFVGdistATR=g_mlFVGMidDistATR; g_pOTE=g_mlOTEDepth; g_pFVGsizeATR=g_mlFVGSizeATR;
   g_pRiskDist=g_mlRiskDistance; g_pRiskDistATR=g_mlRiskDistanceATR; g_pRiskDistPips=g_mlRiskDistancePips;
   g_pSpreadPx=g_mlSpreadPrice; g_pSpreadPts=g_mlSpreadPoints; g_pHour=g_mlHour; g_pMinOfDay=g_mlMinuteOfDay;
   g_pTsin=g_mlTimeSin; g_pTcos=g_mlTimeCos;
   g_pP2=g_ml2RProb; g_pP3=0.0; g_pP5=0.0; g_pP10=0.0; g_pRiskMult=g_mlRiskMult; g_pRunner=(g_mlRunner?1:0); g_pML2RProb=g_ml2RProb; g_pMLRiskMult=g_mlRiskMult; g_pMLDecision=g_mlDecision; g_pMLModelVersion=g_mlModelVersion;
   g_pInitSLguess=iccSigSL;
  }
int ML_v2_Find(ulong posId)
  { for(int i=0;i<ArraySize(g_mlv2);i++) if(g_mlv2[i].used && g_mlv2[i].posId==posId) return i; return -1; }
void ML_v2_EnsureHeader()
  {
   if(!InpMLv2Export) return;
   int h=FileOpen(g_mlv2FileEff,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI,',');
   if(h==INVALID_HANDLE){ Print("[MLv2] CSV create/verify FAILED err=",GetLastError()," file=",g_mlv2FileEff); return; }
   if(FileSize(h)==0)
     {
      // AUDIT FIX (v4.0.5 / F9): check the header write result.
      uint whdr=FileWrite(h,"schema","trade_id","dir","symbol","period","signal_time","entry_time","exit_time",
                "entry_price","initial_stop","initial_risk","initial_risk_pips",
                "mfe_price","mae_price","mfe_r","mae_r",
                "reached_1r","reached_2r","reached_3r","reached_5r","reached_10r",
                "time_to_2r_sec","exit_price","exit_r","exit_money","exit_reason",
                "htf_score","ext_trend","int_trend","sweep_long","sweep_short","disp","fvg_active","ob_active","atr","session","regime",
                "fvg_mid_dist","fvg_mid_dist_atr","ote_depth","fvg_size_atr","risk_distance","risk_distance_atr","risk_distance_pips",
                "spread_price","spread_points","hour","minute_of_day","time_sin","time_cos","symbol_id",
                "surrogate_p2","surrogate_p3","surrogate_p5","surrogate_p10","risk_mult","runner");
      if(whdr==0) Print("[MLv2] WARNING: CSV header write may have FAILED err=",GetLastError()," file=",g_mlv2FileEff);
     }
   FileClose(h);
   Print("[MLv2] one-row-per-trade dataset ready -> Common\\Files\\",g_mlv2FileEff,
         "  (tester redirects FILE_COMMON to the agent sandbox)");
  }
void ML_v2_RegisterEntry(ulong posId,double entryPx,datetime entryTime)
  {
   if(!InpMLv2Export) return;
   if(ML_v2_Find(posId)>=0) return;   // already registered
   int n=ArraySize(g_mlv2); ArrayResize(g_mlv2,n+1);
   MLTradeV2 r;
   r.used=true; r.posId=posId; r.entryPx=entryPx; r.entryTime=entryTime;
   double sl=0.0;
   if(SelectPositionByIdentifier(posId)) sl=PositionGetDouble(POSITION_SL);
   if(sl<=0.0) sl=g_pInitSLguess;
   r.initSL=sl;
   r.initRisk=(sl>0.0)? MathAbs(entryPx-sl) : (g_pRiskDist>0.0? g_pRiskDist : GetATRStopDistance());
   if(r.initRisk<=0.0) r.initRisk=GetATRStopDistance();
   r.dir = g_mlPendValid? g_mlPendDir : ((SelectPositionByIdentifier(posId) && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1);
   r.sigTime = g_mlPendValid? g_mlPendSigTime : entryTime;
   r.mfe=0.0; r.mae=0.0; r.r1=false; r.r2=false; r.r3=false; r.r5=false; r.r10=false; r.t2rTime=0;
   r.exitPx=0.0; r.exitMoney=0.0; r.exitTime=0; r.exitReason="-";
   // freeze features (or zero if the entry had no staged signal, e.g. manual)
   r.fHTF=0; r.fExt=0; r.fInt=0; r.fSweepL=0; r.fSweepS=0; r.fDisp=0;
   r.fFVG=0; r.fOB=0; r.fATR=0; r.fSession=0; r.fRegime=0;
   r.fFVGdist=0; r.fFVGdistATR=0; r.fOTE=0; r.fFVGsizeATR=0;
   r.fRiskDist=0; r.fRiskDistATR=0; r.fRiskDistPips=0;
   r.fSpreadPx=0; r.fSpreadPts=0; r.fHour=0; r.fMinOfDay=0; r.fTsin=0; r.fTcos=0;
   r.fP2=0; r.fP3=0; r.fP5=0; r.fP10=0; r.fRiskMult=1.0; r.fRunner=1;
   // AUDIT FIX (v4.5.0 / Finding 11, LOW, DATA INTEGRITY): these four MLTradeV2
   // members are DECLARED in the struct but were never assigned by this registrar.
   // MQL5 does not zero-initialise numeric struct members, so each new trade row
   // carried whatever bytes the reused array slot happened to hold. They are not in
   // the current v2 column list, which is exactly why it went unnoticed -- adding
   // them to the schema later would have silently emitted garbage.
   r.fML2RProb=0.0; r.fMLRiskMult=1.0; r.fMLDecision=0; r.fMLModelVersion="NONE";
   if(g_mlPendValid)
     {
      r.fHTF=g_pHTF; r.fExt=g_pExt; r.fInt=g_pInt; r.fSweepL=g_pSweepL; r.fSweepS=g_pSweepS; r.fDisp=g_pDisp;
      r.fFVG=g_pFVG; r.fOB=g_pOB; r.fATR=g_pATR; r.fSession=g_pSession; r.fRegime=g_pRegime;
      r.fFVGdist=g_pFVGdist; r.fFVGdistATR=g_pFVGdistATR; r.fOTE=g_pOTE; r.fFVGsizeATR=g_pFVGsizeATR;
      r.fRiskDist=g_pRiskDist; r.fRiskDistATR=g_pRiskDistATR; r.fRiskDistPips=g_pRiskDistPips;
      r.fSpreadPx=g_pSpreadPx; r.fSpreadPts=g_pSpreadPts; r.fHour=g_pHour; r.fMinOfDay=g_pMinOfDay; r.fTsin=g_pTsin; r.fTcos=g_pTcos;
      r.fP2=g_pP2; r.fP3=g_pP3; r.fP5=g_pP5; r.fP10=g_pP10; r.fRiskMult=g_pRiskMult; r.fRunner=g_pRunner;
     }
   g_mlv2[n]=r;
   g_mlPendValid=false; // consumed
  }
void ML_v2_TrackOpen()
  {
   if(!InpMLv2Export) return;
   for(int i=0;i<ArraySize(g_mlv2);i++)
     {
      if(!g_mlv2[i].used) continue;
      if(!SelectPositionByIdentifier(g_mlv2[i].posId)) continue; // closed -> finalized on the exit deal
      bool isLong=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double px = isLong? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(px<=0.0) continue;
      double fav = isLong? (px-g_mlv2[i].entryPx) : (g_mlv2[i].entryPx-px);
      double adv = -fav;
      if(fav>g_mlv2[i].mfe) g_mlv2[i].mfe=fav;
      if(adv>g_mlv2[i].mae) g_mlv2[i].mae=adv;
      double risk=g_mlv2[i].initRisk; if(risk<=0.0) continue;
      double mfeR=g_mlv2[i].mfe/risk;
      if(!g_mlv2[i].r1 && mfeR>=1.0)  g_mlv2[i].r1=true;
      if(!g_mlv2[i].r2 && mfeR>=2.0){ g_mlv2[i].r2=true; g_mlv2[i].t2rTime=TimeCurrent(); }
      if(!g_mlv2[i].r3 && mfeR>=3.0)  g_mlv2[i].r3=true;
      if(!g_mlv2[i].r5 && mfeR>=5.0)  g_mlv2[i].r5=true;
      if(!g_mlv2[i].r10&& mfeR>=10.0) g_mlv2[i].r10=true;
     }
  }
bool ML_v2_WriteRow(int i)
  {
   if(!InpMLv2Export) return false;
   ML_v2_EnsureHeader(); // guarantees file + header exist
   int h=FileOpen(g_mlv2FileEff,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI,',');
   if(h==INVALID_HANDLE){ Print("[MLv2] CSV open failed: ",GetLastError()); return false; }
   FileSeek(h,0,SEEK_END);
   double risk=g_mlv2[i].initRisk; if(risk<=0.0) risk=1.0;
   double mfeR=g_mlv2[i].mfe/risk, maeR=g_mlv2[i].mae/risk;
   double exitR=(g_mlv2[i].dir>0? (g_mlv2[i].exitPx-g_mlv2[i].entryPx) : (g_mlv2[i].entryPx-g_mlv2[i].exitPx))/risk;
   double riskPips=(g_pip>0.0? g_mlv2[i].initRisk/g_pip : 0.0);
   long t2r=(g_mlv2[i].t2rTime>0 && g_mlv2[i].entryTime>0)? (long)(g_mlv2[i].t2rTime-g_mlv2[i].entryTime) : -1;
   string tradeId=_Symbol+"_"+StringFormat("%I64u",g_mlv2[i].posId);
   uint wrow=FileWrite(h,"icc_ml_v2",tradeId,g_mlv2[i].dir,_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),
             TimeToString(g_mlv2[i].sigTime,TIME_DATE|TIME_SECONDS),TimeToString(g_mlv2[i].entryTime,TIME_DATE|TIME_SECONDS),TimeToString(g_mlv2[i].exitTime,TIME_DATE|TIME_SECONDS),
             g_mlv2[i].entryPx,g_mlv2[i].initSL,g_mlv2[i].initRisk,riskPips,
             g_mlv2[i].mfe,g_mlv2[i].mae,mfeR,maeR,
             (int)g_mlv2[i].r1,(int)g_mlv2[i].r2,(int)g_mlv2[i].r3,(int)g_mlv2[i].r5,(int)g_mlv2[i].r10,
             t2r,g_mlv2[i].exitPx,exitR,g_mlv2[i].exitMoney,g_mlv2[i].exitReason,
             g_mlv2[i].fHTF,g_mlv2[i].fExt,g_mlv2[i].fInt,g_mlv2[i].fSweepL,g_mlv2[i].fSweepS,g_mlv2[i].fDisp,g_mlv2[i].fFVG,g_mlv2[i].fOB,g_mlv2[i].fATR,g_mlv2[i].fSession,g_mlv2[i].fRegime,
             g_mlv2[i].fFVGdist,g_mlv2[i].fFVGdistATR,g_mlv2[i].fOTE,g_mlv2[i].fFVGsizeATR,g_mlv2[i].fRiskDist,g_mlv2[i].fRiskDistATR,g_mlv2[i].fRiskDistPips,
             g_mlv2[i].fSpreadPx,g_mlv2[i].fSpreadPts,g_mlv2[i].fHour,g_mlv2[i].fMinOfDay,g_mlv2[i].fTsin,g_mlv2[i].fTcos,_Symbol,
             g_mlv2[i].fP2,g_mlv2[i].fP3,g_mlv2[i].fP5,g_mlv2[i].fP10,g_mlv2[i].fRiskMult,g_mlv2[i].fRunner);
   // AUDIT FIX (v4.0.5 / F9): check the write result -- previously discarded, so a
   // disk-full/permission/agent-interrupt condition could silently drop a completed
   // trade's row with zero indication anywhere.
   if(wrow==0) Print("[MLv2] WARNING: CSV row write may have FAILED err=",GetLastError()," trade=",tradeId," file=",g_mlv2FileEff);
   FileClose(h);   // FileClose() is void in MQL5 -- nothing to check here
   return wrow!=0;
  }
void ML_v2_OnExitDeal(ulong posId,double exitPx,datetime exitTime,double money,string reason)
  {
   if(!InpMLv2Export) return;
   int idx=ML_v2_Find(posId); if(idx<0) return;
   g_mlv2[idx].exitMoney += money;
   g_mlv2[idx].exitPx     = exitPx;
   g_mlv2[idx].exitTime   = exitTime;
   g_mlv2[idx].exitReason = reason;
   // final excursion sample at the exit price
   double fav=(g_mlv2[idx].dir>0? (exitPx-g_mlv2[idx].entryPx) : (g_mlv2[idx].entryPx-exitPx));
   if(fav>g_mlv2[idx].mfe) g_mlv2[idx].mfe=fav;
   if(-fav>g_mlv2[idx].mae) g_mlv2[idx].mae=-fav;
   if(SelectPositionByIdentifier(posId)) return; // partial close -> wait for full close
   if(!ML_v2_WriteRow(idx)) return; // Keep the completed record for a later retry.
   int n=ArraySize(g_mlv2);
   for(int j=idx;j<n-1;j++) g_mlv2[j]=g_mlv2[j+1];
   ArrayResize(g_mlv2,n-1);
  }
//+==================================================================+
//|                 ML v4.0 CANONICAL DATA ENGINE                    |
//+==================================================================+
string ML_v4_ModelVersion(){ return g_mlModelReady?g_mlModelVersion:"NONE"; }
int ML_v4_Find(ulong posId)
  { for(int i=0;i<ArraySize(g_mlv4);i++) if(g_mlv4[i].used && g_mlv4[i].posId==posId) return i; return -1; }

string ML_v4_CsvField(string v)
  {
   StringReplace(v,"\"","\"\"");
   return "\""+v+"\"";
  }

// v4.6.5 RB 13,15; Audit 7-8; function mapping in CHANGE_REPORT.md.
void ML_v4_EnsureHeader()
  {
   if(!InpMLv4Export) return;
   int h=FileOpen(g_mlv4FileEff,FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI); // AUDIT FIX (v4.0.4): FILE_TXT added -- FileWriteString's documented behaviour branches on FILE_TXT/CSV/BIN; none was set before, unlike every other dataset in this EA
   if(h==INVALID_HANDLE){ Print("[MLv4] CSV create/verify FAILED err=",GetLastError()," file=",g_mlv4FileEff); return; }
   if(FileSize(h)==0)
     {
      string header="dataset_version,schema_version,run_id,trade_id,trade_seq,position_id,dir,symbol,period,digits,point,tick_size,tick_value,contract_size,broker,account_currency,execution_mode,signal_time,entry_time,exit_time,entry_price,initial_stop,initial_risk,initial_risk_pips,htf_score,ext_trend,int_trend,sweep_long,sweep_short,displacement,fvg_active,ob_active,atr,session,regime,fvg_mid_dist,fvg_mid_dist_atr,ote_depth,fvg_size_atr,risk_distance,risk_distance_atr,risk_distance_pips,spread_price,spread_points,hour,minute_of_day,time_sin,time_cos,icc_phase,impulse_age_bars,impulse_leg_atr,correction_age_bars,correction_depth,distance_to_external_high_atr,distance_to_external_low_atr,distance_to_internal_high_atr,distance_to_internal_low_atr,mfe_price,mae_price,mfe_r,mae_r,reached_1r,reached_2r,reached_3r,reached_5r,reached_10r,time_to_1r_sec,time_to_2r_sec,time_to_3r_sec,time_to_5r_sec,time_to_10r_sec,mfe_30m_r,mfe_1h_r,mfe_2h_r,mfe_4h_r,mfe_8h_r,mfe_24h_r,exit_price,exit_r,exit_money,exit_reason,exit_external_trend,exit_internal_trend,exit_protected_high,exit_protected_low,exit_structure_break,exit_opposite_signal,exit_fvg_active,exit_ob_active,exit_atr,model_version,ml_2r_prob,ml_decision,ml_risk_mult,initial_risk_money,mfe_money,mae_money,sweep_age,sweep_lead_bars,impulse_concentration,corr_leg_count,corr_recovery_frac,setup_id,gstf,observation_tf,entry_tf,zone_tf,entry_path,structural_anchor,ind_state,cor_state,cont_state,entry_reason\r\n";
      // AUDIT FIX (v4.0.5 / F9): FileWriteString() is VOID for FILE_TXT files (no
      // return value to check), so error detection uses the standard MQL5
      // ResetLastError()/GetLastError() pattern instead -- previously no check
      // of any kind was performed here.
      ResetLastError();
      FileWriteString(h,header);
      int werr=GetLastError();
      if(werr!=0) Print("[MLv4] WARNING: CSV header write may have FAILED err=",werr," file=",g_mlv4FileEff);
     }
   FileClose(h);
  }

double ML_v4_R(double px,double entry,double risk,int dir)
  { if(risk<=0.0) return 0.0; return (dir>0?(px-entry):(entry-px))/risk; }

void ML_v4_SnapshotCheckpoint(MLTradeV4 &r,double px,double risk,long ageSec)
  {
   double rr=ML_v4_R(px,r.entryPx,risk,r.dir);
   if(ageSec>=1800 && !r.cp30m){ r.mfe30m=MathMax(r.mfe,rr*risk); r.cp30m=true; }
   if(ageSec>=3600 && !r.cp1h){ r.mfe1h=MathMax(r.mfe,rr*risk); r.cp1h=true; }
   if(ageSec>=7200 && !r.cp2h){ r.mfe2h=MathMax(r.mfe,rr*risk); r.cp2h=true; }
   if(ageSec>=14400 && !r.cp4h){ r.mfe4h=MathMax(r.mfe,rr*risk); r.cp4h=true; }
   if(ageSec>=28800 && !r.cp8h){ r.mfe8h=MathMax(r.mfe,rr*risk); r.cp8h=true; }
   if(ageSec>=86400 && !r.cp24h){ r.mfe24h=MathMax(r.mfe,rr*risk); r.cp24h=true; }
  }

// v4.6.5 RB 13,15-16; Audit 7-8; function mapping in CHANGE_REPORT.md.
void ML_v4_RegisterEntry(ulong posId,double entryPx,datetime entryTime,double dealVolume=0.0)
  {
   if(!InpMLv4Export) return;
   int existing=ML_v4_Find(posId);
   if(existing>=0)
     {
      // A single entry order may generate multiple IN deals. Accumulate the
      // incremental money risk instead of retaining only the first fill.
      if(dealVolume>0.0 && g_mlv4[existing].initSL>0.0)
        {
         double addRiskMoney=0.0;
         if(OrderCalcProfit(g_mlv4[existing].dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,
                            _Symbol,dealVolume,entryPx,g_mlv4[existing].initSL,addRiskMoney))
            g_mlv4[existing].initRiskMoney+=MathAbs(addRiskMoney);
        }
      return;
     }
   int n=ArraySize(g_mlv4); ArrayResize(g_mlv4,n+1);
   MLTradeV4 r;
   r.used=true; r.posId=posId; r.seq=0; r.dir=g_mlPendValid?g_mlPendDir:((SelectPositionByIdentifier(posId) && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1);
   r.mfe=0.0; r.mae=0.0; r.r1=false; r.r2=false; r.r3=false; r.r5=false; r.r10=false;
   r.t1rTime=0; r.t2rTime=0; r.t3rTime=0; r.t5rTime=0; r.t10rTime=0;
   r.mfe30m=0.0; r.mfe1h=0.0; r.mfe2h=0.0; r.mfe4h=0.0; r.mfe8h=0.0; r.mfe24h=0.0;
   r.cp30m=false; r.cp1h=false; r.cp2h=false; r.cp4h=false; r.cp8h=false; r.cp24h=false;
   r.exitPx=0.0; r.exitMoney=0.0; r.exitTime=0; r.exitReason="-";
   // AUDIT FIX (v4.5.0 / Finding 11, LOW, DATA INTEGRITY): the ten exit-state members
   // are normally filled by ML_v4_OnExitDeal() before the row is written, but they are
   // never initialised here. Any path that writes a row without a completed exit deal
   // (a forced OnDeinit flush, a future partial-close schema change) would emit
   // uninitialised memory into ten dataset columns. Seed them explicitly.
   r.xExtTrend=0; r.xIntTrend=0; r.xPhase=PH_NONE;
   r.xProtHigh=0.0; r.xProtLow=0.0; r.xATR=0.0;
   r.xFVG=0; r.xOB=0; r.xStructureBreak=false; r.xOppositeSignal=false;
   // AUDIT FIX (v4.2.3 / G2): guard sigTime with g_mlPendValid, mirroring
   // ML_v2_RegisterEntry. Previously v4 read g_mlPendSigTime UNCONDITIONALLY,
   // so a manual / unstaged entry (no ICC signal) recorded a STALE prior-signal
   // timestamp instead of its own entry time. With G1's reorder v4 now sees a
   // valid pending for genuine EA entries; this guard covers the manual case.
   r.entryPx=entryPx; r.entryTime=entryTime; r.sigTime=(g_mlPendValid? g_mlPendSigTime : entryTime);
   r.seq=++g_mlTradeSeq; r.runId=g_mlRunId;
   r.tradeId=g_mlRunId+"_"+StringFormat("%06I64u",r.seq);
   r.initSL=(SelectPositionByIdentifier(posId)?PositionGetDouble(POSITION_SL):g_pInitSLguess);
   if(r.initSL<=0.0) r.initSL=g_pInitSLguess;   // v4.2.2 (F2): guard a 0/absent broker SL
   r.initRisk=MathAbs(r.entryPx-r.initSL);
   // AUDIT FIX (v4.2.2 / F2): the v4 recorder previously lacked the degenerate-
   // risk fallback that ML_v2_RegisterEntry already has. If POSITION_SL was
   // momentarily 0 (queried on the entry deal before the stop is visible) OR
   // the entry price coincided with the stop, r.initRisk became 0 -- and since
   // EVERY v4 label is risk-normalized, that silently corrupted the dataset:
   // ML_v4_TrackOpen()'s "if(risk<=0.0) continue;" skipped ALL reached_1r..10r
   // labeling, and ML_v4_WriteRow() forced a risk=1.0 sentinel, distorting
   // mfe_r/mae_r/exit_r and every mfe_*h_r checkpoint. Mirror the v2 fallback
   // so the true-2R basis is always sane.
   if(r.initRisk<=0.0) r.initRisk=(g_pRiskDist>0.0? g_pRiskDist : GetATRStopDistance());
   // v4.2.9 MONEY LAYER: initial risk in ACCOUNT CURRENCY via OrderCalcProfit()
   // (the loss the position would realize moving entry->initSL at this volume).
   // This is the ONLY correct way to get $ on XAUUSD -- it uses the broker's
   // contract size / tick value / tick size / currency conversion, never a
   // manual pips*$/pip. mfeMoney/maeMoney start at 0 and are tracked live in
   // ML_v4_TrackOpen(). $-at-1R/2R/.../10R is downstream-derivable as N*initRiskMoney.
   r.initRiskMoney=0.0; r.mfeMoney=0.0; r.maeMoney=0.0;
   // AUDIT FIX (v4.3.1 / Finding C, MEDIUM, telemetry): the volume came ONLY from
   // SelectPositionByIdentifier(posId). On the DEAL_ENTRY_IN transaction the position is
   // not always selectable yet, and on a partial//multi-deal fill POSITION_VOLUME is
   // the AGGREGATE, not this deal's. Either way initRiskMoney silently stayed 0, and
   // because ML_v4_OnExitDeal derives mfe/mae_money from initRiskMoney/initRisk, the
   // ENTIRE money layer for that trade collapsed to 0 with no diagnostic. Fix: prefer
   // the volume passed in from the entry deal itself (DEAL_VOLUME), falling back to
   // the position only if that is unavailable.
   double rvol=(dealVolume>0.0)? dealVolume
                               : (SelectPositionByIdentifier(posId)? PositionGetDouble(POSITION_VOLUME):0.0);
   if(rvol<=0.0)
      PrintFormat("[MLv4] WARNING: entry volume unavailable for pos=%I64u -> money layer will be 0 for this trade",posId);
   if(rvol>0.0 && r.initSL>0.0 && r.entryPx>0.0)
     {
      double rprof=0.0;
      if(OrderCalcProfit(r.dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,rvol,r.entryPx,r.initSL,rprof))
         r.initRiskMoney=MathAbs(rprof);
     }
   r.fHTF=g_pHTF; r.fExt=g_pExt; r.fInt=g_pInt; r.fSweepL=g_pSweepL; r.fSweepS=g_pSweepS; r.fDisp=g_pDisp;
   r.fFVG=g_pFVG; r.fOB=g_pOB; r.fATR=g_pATR; r.fSession=g_pSession; r.fRegime=g_pRegime;
   r.fFVGdist=g_pFVGdist; r.fFVGdistATR=g_pFVGdistATR; r.fOTE=g_pOTE; r.fFVGsizeATR=g_pFVGsizeATR;
   r.fRiskDist=g_pRiskDist; r.fRiskDistATR=g_pRiskDistATR; r.fRiskDistPips=g_pRiskDistPips;
   r.fSpreadPx=g_pSpreadPx; r.fSpreadPts=g_pSpreadPts; r.fHour=g_pHour; r.fMinOfDay=g_pMinOfDay; r.fTsin=g_pTsin; r.fTcos=g_pTcos;
   // AUDIT FIX (v4.0.5/F7): read the genuine phase captured at signal-fire time
   // (g_mlSigPhaseAtFire, stamped in ICC_Update() just before ICC_Reset() runs)
   // instead of a hardcoded PH_CORRECTION literal.
   r.fPhase=g_mlSigPhaseAtFire; r.fImpulseAge=g_mlImpulseAgeBars; r.fCorrectionAge=g_mlCorrectionAgeBars;
   r.fImpulseLegATR=g_mlImpulseLegATR; r.fCorrectionDepth=g_mlOTEDepth;
   r.fSweepAge=g_mlSweepAge; r.fSweepLeadBars=g_mlSweepLeadBars;
   r.fImpulseConcentration=g_mlImpulseConcentration;
   r.fCorrLegCount=g_mlCorrLegCount; r.fCorrRecovery=g_mlCorrRecovery;
   double atr=g_pATR; double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK),bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double px=(r.dir>0?ask:bid); if(px<=0.0) px=entryPx;
   // AUDIT FIX (v4.3.1 / Finding B, MEDIUM, data integrity): these four fields were
   // assigned ONLY inside the "if(atr>0.0)" block below, and even there only when the
   // matching protected swing was >0. MQL5 does NOT zero-initialise local struct
   // members, so on any entry where the structure-TF ATR was not yet ready (tester
   // warm-up, fresh attach) or a protected swing had not formed, ML_v4_WriteRow wrote
   // UNINITIALISED memory into distance_to_external/internal_high/low_atr. Explicitly
   // seed them to 0 first so the dataset can never carry garbage.
   r.fDistExtHighATR=0.0; r.fDistExtLowATR=0.0; r.fDistIntHighATR=0.0; r.fDistIntLowATR=0.0;
   if(atr>0.0)
     {
      if(g_extProtHigh>0.0) r.fDistExtHighATR=MathAbs(g_extProtHigh-px)/atr;
      if(g_extProtLow>0.0)  r.fDistExtLowATR =MathAbs(px-g_extProtLow)/atr;
      if(g_intProtHigh>0.0) r.fDistIntHighATR=MathAbs(g_intProtHigh-px)/atr;
      if(g_intProtLow>0.0)  r.fDistIntLowATR =MathAbs(px-g_intProtLow)/atr;
     }
   r.fSymbolDigits=_Digits; r.fPoint=_Point;
   r.fTickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   r.fTickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   r.fContractSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE);
   r.fBroker=AccountInfoString(ACCOUNT_COMPANY);
   r.fAccountCurrency=AccountInfoString(ACCOUNT_CURRENCY);
   r.fExecutionMode=IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE));
   r.fPeriod=EnumToString((ENUM_TIMEFRAMES)_Period);
   r.fDatasetVersion="ICC_ML_v465"; r.fSchemaVersion="4.6.5.1"; r.fModelVersion=ML_v4_ModelVersion();
   r.fP2=0.0; r.fP3=0.0; r.fP5=0.0; r.fP10=0.0;
   // AUDIT FIX (v4.6.2 / Finding 9, LOW, DEAD ASSIGNMENT): was hardcoded to 1 while
   // the genuine runner-vs-TP decision was already staged in g_pRunner. Currently
   // invisible because the v4 header carries no runner column -- which is precisely
   // what makes it dangerous: adding that column later would have silently emitted
   // a constant. Read the staged value.
   r.fRiskMult=g_pMLRiskMult; r.fRunner=g_pRunner;
   r.fML2RProb=g_pML2RProb; r.fMLRiskMult=g_pMLRiskMult; r.fMLDecision=g_pMLDecision; r.fMLModelVersion=g_pMLModelVersion;
   g_mlv4[n]=r;
   // Do not consume the pending snapshot here; the legacy v2 recorder
   // still needs it in the same entry transaction.
  }

void ML_v4_TrackOpen()
  {
   if(!InpMLv4Export) return;
   for(int i=0;i<ArraySize(g_mlv4);i++)
     {
      if(!g_mlv4[i].used) continue;
      if(!SelectPositionByIdentifier(g_mlv4[i].posId)) continue;
      bool isLong=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double px=isLong?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(px<=0.0) continue;
      double fav=isLong?(px-g_mlv4[i].entryPx):(g_mlv4[i].entryPx-px);
      double adv=-fav;
      if(fav>g_mlv4[i].mfe) g_mlv4[i].mfe=fav;
      if(adv>g_mlv4[i].mae) g_mlv4[i].mae=adv;
      // v4.2.9 MONEY LAYER: peak favourable/adverse UNREALIZED $ via OrderCalcProfit
      // at the live price (broker-accurate; captures "max unrealized profit before
      // exit ($)" and MAE-$). Stored as positive magnitudes like mfe/mae above.
      double volM=PositionGetDouble(POSITION_VOLUME);
      if(volM>0.0)
        {
         double favM=0.0;
         if(OrderCalcProfit(isLong?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volM,g_mlv4[i].entryPx,px,favM))
           {
            if(favM>g_mlv4[i].mfeMoney)  g_mlv4[i].mfeMoney=favM;
            if(-favM>g_mlv4[i].maeMoney) g_mlv4[i].maeMoney=-favM;
           }
        }
      double risk=g_mlv4[i].initRisk; if(risk<=0.0) continue;
      double mfeR=g_mlv4[i].mfe/risk;
      if(!g_mlv4[i].r1 && mfeR>=1.0){g_mlv4[i].r1=true;g_mlv4[i].t1rTime=TimeCurrent();}
      if(!g_mlv4[i].r2 && mfeR>=2.0){g_mlv4[i].r2=true;g_mlv4[i].t2rTime=TimeCurrent();}
      if(!g_mlv4[i].r3 && mfeR>=3.0){g_mlv4[i].r3=true;g_mlv4[i].t3rTime=TimeCurrent();}
      if(!g_mlv4[i].r5 && mfeR>=5.0){g_mlv4[i].r5=true;g_mlv4[i].t5rTime=TimeCurrent();}
      if(!g_mlv4[i].r10&&mfeR>=10.0){g_mlv4[i].r10=true;g_mlv4[i].t10rTime=TimeCurrent();}
      ML_v4_SnapshotCheckpoint(g_mlv4[i],px,risk,(long)(TimeCurrent()-g_mlv4[i].entryTime));
     }
  }

// v4.6.5 RB 13,15; Audit 7-8; function mapping in CHANGE_REPORT.md.
bool ML_v4_WriteRow(int i)
  {
   if(!InpMLv4Export) return false;
   ML_v4_EnsureHeader();
   int h=FileOpen(g_mlv4FileEff,FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI); // AUDIT FIX (v4.0.4): FILE_TXT added -- FileWriteString's documented behaviour branches on FILE_TXT/CSV/BIN; none was set before, unlike every other dataset in this EA
   if(h==INVALID_HANDLE){ Print("[MLv4] CSV open failed: ",GetLastError()); return false; }
   FileSeek(h,0,SEEK_END);

   // Do NOT alias g_mlv4[i] with a local reference. Some MQL5 builds reject
   // that form for a struct array element. Direct indexing also makes the
   // one-row/one-trade mapping explicit.
   double risk=g_mlv4[i].initRisk; if(risk<=0.0) risk=1.0;
   double mfeR=g_mlv4[i].mfe/risk, maeR=g_mlv4[i].mae/risk;
   long t1=(g_mlv4[i].t1rTime>0?(long)(g_mlv4[i].t1rTime-g_mlv4[i].entryTime):-1);
   long t2=(g_mlv4[i].t2rTime>0?(long)(g_mlv4[i].t2rTime-g_mlv4[i].entryTime):-1);
   long t3=(g_mlv4[i].t3rTime>0?(long)(g_mlv4[i].t3rTime-g_mlv4[i].entryTime):-1);
   long t5=(g_mlv4[i].t5rTime>0?(long)(g_mlv4[i].t5rTime-g_mlv4[i].entryTime):-1);
   long t10=(g_mlv4[i].t10rTime>0?(long)(g_mlv4[i].t10rTime-g_mlv4[i].entryTime):-1);
   double pips=(g_pip>0.0?g_mlv4[i].initRisk/g_pip:0.0);

   // MQL5 FileWrite() has a finite argument limit. Build the complete CSV
   // record as a string and write it once: exactly ONE complete trade row.
   string row="";
   row+=ML_v4_CsvField(g_mlv4[i].fDatasetVersion)+","+ML_v4_CsvField(g_mlv4[i].fSchemaVersion)+","+ML_v4_CsvField(g_mlv4[i].runId)+","+ML_v4_CsvField(g_mlv4[i].tradeId)+","+IntegerToString((long)g_mlv4[i].seq)+","+IntegerToString((long)g_mlv4[i].posId)+","+IntegerToString(g_mlv4[i].dir)+","+ML_v4_CsvField(_Symbol)+","+ML_v4_CsvField(g_mlv4[i].fPeriod)+",";
   row+=IntegerToString(g_mlv4[i].fSymbolDigits)+","+DoubleToString(g_mlv4[i].fPoint,12)+","+DoubleToString(g_mlv4[i].fTickSize,12)+","+DoubleToString(g_mlv4[i].fTickValue,12)+","+DoubleToString(g_mlv4[i].fContractSize,12)+","+ML_v4_CsvField(g_mlv4[i].fBroker)+","+ML_v4_CsvField(g_mlv4[i].fAccountCurrency)+","+ML_v4_CsvField(g_mlv4[i].fExecutionMode)+",";
   row+=ML_v4_CsvField(TimeToString(g_mlv4[i].sigTime,TIME_DATE|TIME_SECONDS))+","+ML_v4_CsvField(TimeToString(g_mlv4[i].entryTime,TIME_DATE|TIME_SECONDS))+","+ML_v4_CsvField(TimeToString(g_mlv4[i].exitTime,TIME_DATE|TIME_SECONDS))+",";
   row+=DoubleToString(g_mlv4[i].entryPx,_Digits)+","+DoubleToString(g_mlv4[i].initSL,_Digits)+","+DoubleToString(g_mlv4[i].initRisk,12)+","+DoubleToString(pips,6)+",";
   row+=DoubleToString(g_mlv4[i].fHTF,8)+","+IntegerToString(g_mlv4[i].fExt)+","+IntegerToString(g_mlv4[i].fInt)+","+IntegerToString(g_mlv4[i].fSweepL)+","+IntegerToString(g_mlv4[i].fSweepS)+","+DoubleToString(g_mlv4[i].fDisp,6)+",";
   row+=IntegerToString(g_mlv4[i].fFVG)+","+IntegerToString(g_mlv4[i].fOB)+","+DoubleToString(g_mlv4[i].fATR,12)+","+IntegerToString(g_mlv4[i].fSession)+","+IntegerToString(g_mlv4[i].fRegime)+",";
   row+=DoubleToString(g_mlv4[i].fFVGdist,12)+","+DoubleToString(g_mlv4[i].fFVGdistATR,8)+","+DoubleToString(g_mlv4[i].fOTE,8)+","+DoubleToString(g_mlv4[i].fFVGsizeATR,8)+",";
   row+=DoubleToString(g_mlv4[i].fRiskDist,12)+","+DoubleToString(g_mlv4[i].fRiskDistATR,8)+","+DoubleToString(g_mlv4[i].fRiskDistPips,6)+","+DoubleToString(g_mlv4[i].fSpreadPx,12)+","+DoubleToString(g_mlv4[i].fSpreadPts,4)+",";
   row+=IntegerToString(g_mlv4[i].fHour)+","+IntegerToString(g_mlv4[i].fMinOfDay)+","+DoubleToString(g_mlv4[i].fTsin,8)+","+DoubleToString(g_mlv4[i].fTcos,8)+",";
   row+=IntegerToString(g_mlv4[i].fPhase)+","+IntegerToString(g_mlv4[i].fImpulseAge)+","+DoubleToString(g_mlv4[i].fImpulseLegATR,8)+","+IntegerToString(g_mlv4[i].fCorrectionAge)+","+DoubleToString(g_mlv4[i].fCorrectionDepth,8)+",";
   row+=DoubleToString(g_mlv4[i].fDistExtHighATR,8)+","+DoubleToString(g_mlv4[i].fDistExtLowATR,8)+","+DoubleToString(g_mlv4[i].fDistIntHighATR,8)+","+DoubleToString(g_mlv4[i].fDistIntLowATR,8)+",";
   row+=DoubleToString(g_mlv4[i].mfe,12)+","+DoubleToString(g_mlv4[i].mae,12)+","+DoubleToString(mfeR,8)+","+DoubleToString(maeR,8)+",";
   row+=IntegerToString((int)g_mlv4[i].r1)+","+IntegerToString((int)g_mlv4[i].r2)+","+IntegerToString((int)g_mlv4[i].r3)+","+IntegerToString((int)g_mlv4[i].r5)+","+IntegerToString((int)g_mlv4[i].r10)+",";
   row+=IntegerToString(t1)+","+IntegerToString(t2)+","+IntegerToString(t3)+","+IntegerToString(t5)+","+IntegerToString(t10)+",";
   row+=DoubleToString(g_mlv4[i].mfe30m/risk,8)+","+DoubleToString(g_mlv4[i].mfe1h/risk,8)+","+DoubleToString(g_mlv4[i].mfe2h/risk,8)+","+DoubleToString(g_mlv4[i].mfe4h/risk,8)+","+DoubleToString(g_mlv4[i].mfe8h/risk,8)+","+DoubleToString(g_mlv4[i].mfe24h/risk,8)+",";
   row+=DoubleToString(g_mlv4[i].exitPx,_Digits)+","+ICC465_RealizedRText(g_mlv4[i].posId)+","+DoubleToString(ICC465_Get(g_mlv4[i].posId,"realized"),2)+","+ML_v4_CsvField(g_mlv4[i].exitReason)+",";
   row+=IntegerToString(g_mlv4[i].xExtTrend)+","+IntegerToString(g_mlv4[i].xIntTrend)+","+DoubleToString(g_mlv4[i].xProtHigh,_Digits)+","+DoubleToString(g_mlv4[i].xProtLow,_Digits)+",";
   row+=IntegerToString((int)g_mlv4[i].xStructureBreak)+","+IntegerToString((int)g_mlv4[i].xOppositeSignal)+","+IntegerToString(g_mlv4[i].xFVG)+","+IntegerToString(g_mlv4[i].xOB)+","+DoubleToString(g_mlv4[i].xATR,12)+","+ML_v4_CsvField(g_mlv4[i].fModelVersion)+","+DoubleToString(g_mlv4[i].fML2RProb,6)+","+IntegerToString(g_mlv4[i].fMLDecision)+","+DoubleToString(g_mlv4[i].fMLRiskMult,4)+",";
   // v4.2.9 MONEY LAYER (schema 4.0.2): appended AFTER model_version so every
   // pre-existing column index is preserved for already-merged v4 CSVs.
   row+=DoubleToString(g_mlv4[i].initRiskMoney,2)+","+DoubleToString(g_mlv4[i].mfeMoney,2)+","+DoubleToString(g_mlv4[i].maeMoney,2)+",";
   // v4.6.0 PATH FEATURES (schema 4.2.0): APPENDED last, exactly as the v4.2.9
   // money layer was, so every pre-existing column index stays stable for CSVs
   // already merged from earlier runs. Do NOT mix 4.1.0 and 4.2.0 rows in one
   // training frame -- the older rows have no value for these columns and an
   // imputed zero is indistinguishable from a genuine zero in three of them.
   row+=DoubleToString(g_mlv4[i].fSweepAge,4)+","+DoubleToString(g_mlv4[i].fSweepLeadBars,4)+","
       +DoubleToString(g_mlv4[i].fImpulseConcentration,8)+","+DoubleToString(g_mlv4[i].fCorrLegCount,4)+","
        +DoubleToString(g_mlv4[i].fCorrRecovery,8)+",";
   ulong metaId=g_mlv4[i].posId;
   row+=IntegerToString((long)ICC465_Get(metaId,"setup"))+","+IntegerToString((int)ICC465_Get(metaId,"gstf"))+","+
      IntegerToString((int)ICC465_Get(metaId,"obs"))+","+IntegerToString((int)ICC465_Get(metaId,"entrytf"))+","+
      IntegerToString((int)ICC465_Get(metaId,"zone"))+","+IntegerToString((int)ICC465_Get(metaId,"path"))+","+
      DoubleToString(ICC465_Get(metaId,"anchor"),_Digits)+","+IntegerToString((int)ICC465_Get(metaId,"ind"))+","+
      IntegerToString((int)ICC465_Get(metaId,"cor"))+","+IntegerToString((int)ICC465_Get(metaId,"cont"))+","+
      ((int)ICC465_Get(metaId,"path")==E465_BASELINE_LTF?"ENTRY_BASELINE_LTF":
       (int)ICC465_Get(metaId,"path")==E465_AGGRESSIVE_LTF?"ENTRY_AGGRESSIVE_LTF":
       (int)ICC465_Get(metaId,"path")==E465_HTF_CONFIRMED?"ENTRY_HTF_CONFIRMED":"ENTRY_NONE")+"\r\n";

   // AUDIT FIX (v4.0.5 / F9): FileWriteString() is VOID for FILE_TXT files, so error
   // detection uses ResetLastError()/GetLastError() -- previously no check of any
   // kind was performed, so a disk-full/permission/agent-interrupt condition could
   // silently drop a completed trade's row with zero indication anywhere.
   ResetLastError();
   FileWriteString(h,row);
   int werr=GetLastError();
   if(werr!=0) Print("[MLv4] WARNING: CSV row write may have FAILED err=",werr," trade=",g_mlv4[i].tradeId," file=",g_mlv4FileEff);
   FileClose(h);
   return werr==0;
  }

void ML_v4_OnExitDeal(ulong posId,double exitPx,datetime exitTime,double money,string reason)
  {
   if(!InpMLv4Export)return;
   int idx=ML_v4_Find(posId);if(idx<0)return;
   g_mlv4[idx].exitMoney+=money;g_mlv4[idx].exitPx=exitPx;g_mlv4[idx].exitTime=exitTime;g_mlv4[idx].exitReason=reason;
   double fav=(g_mlv4[idx].dir>0?(exitPx-g_mlv4[idx].entryPx):(g_mlv4[idx].entryPx-exitPx));
   if(fav>g_mlv4[idx].mfe)g_mlv4[idx].mfe=fav;if(-fav>g_mlv4[idx].mae)g_mlv4[idx].mae=-fav;
   // v4.2.9 MONEY LAYER: final excursion sample at the exit price. The position
   // may already be flat here, so instead of OrderCalcProfit (needs live volume)
   // we scale the price excursion by the linear $/price ratio initRiskMoney/
   // initRisk (money scales linearly with price distance at fixed volume).
   double rmPerPx=(g_mlv4[idx].initRisk>0.0? g_mlv4[idx].initRiskMoney/g_mlv4[idx].initRisk : 0.0);
   if(rmPerPx>0.0)
     {
      double favM=fav*rmPerPx;
      if(favM>g_mlv4[idx].mfeMoney)  g_mlv4[idx].mfeMoney=favM;
      if(-favM>g_mlv4[idx].maeMoney) g_mlv4[idx].maeMoney=-favM;
     }
   double risk=g_mlv4[idx].initRisk;if(risk>0.0)ML_v4_SnapshotCheckpoint(g_mlv4[idx],exitPx,risk,(long)(exitTime-g_mlv4[idx].entryTime));
   g_mlv4[idx].xExtTrend=g_extTrend;g_mlv4[idx].xIntTrend=g_intTrend;g_mlv4[idx].xPhase=g_iccPhase;
   g_mlv4[idx].xProtHigh=g_intProtHigh;g_mlv4[idx].xProtLow=g_intProtLow;g_mlv4[idx].xATR=g_mseATRval;
   g_mlv4[idx].xFVG=ML_CountActiveFVG();g_mlv4[idx].xOB=ML_CountActiveOB();
   g_mlv4[idx].xStructureBreak=(g_extTrend!=g_mlv4[idx].dir || g_intTrend!=g_mlv4[idx].dir);
   g_mlv4[idx].xOppositeSignal=((g_mlv4[idx].dir>0&&iccSellSig)||(g_mlv4[idx].dir<0&&iccBuySig));
   if(SelectPositionByIdentifier(posId))return;
   if(!ML_v4_WriteRow(idx)) return; // Keep the completed record for a later retry.
   int n=ArraySize(g_mlv4);for(int j=idx;j<n-1;j++)g_mlv4[j]=g_mlv4[j+1];ArrayResize(g_mlv4,n-1);
  }

void ICC467_RetryClosedDatasetRows()
  {
   // Retry once per minute to avoid a log flood while the file remains unavailable.
   static datetime lastAttempt=0;
   datetime now=TimeCurrent();
   if(lastAttempt>0 && now-lastAttempt<60) return;
   lastAttempt=now;
   for(int i=ArraySize(g_mlv2)-1;i>=0;i--)
     {
      if(g_mlv2[i].exitTime<=0 || SelectPositionByIdentifier(g_mlv2[i].posId)) continue;
      if(!ML_v2_WriteRow(i)) continue;
      for(int j=i;j<ArraySize(g_mlv2)-1;j++) g_mlv2[j]=g_mlv2[j+1];
      ArrayResize(g_mlv2,ArraySize(g_mlv2)-1);
     }
   for(int i=ArraySize(g_mlv4)-1;i>=0;i--)
     {
      if(g_mlv4[i].exitTime<=0 || SelectPositionByIdentifier(g_mlv4[i].posId)) continue;
      if(!ML_v4_WriteRow(i)) continue;
      for(int j=i;j<ArraySize(g_mlv4)-1;j++) g_mlv4[j]=g_mlv4[j+1];
      ArrayResize(g_mlv4,ArraySize(g_mlv4)-1);
     }
  }

//+==================================================================+
//|                 POSITION / RISK MANAGEMENT                       |
//+==================================================================+
double NormalizeLots(double l)
  {
   double mn=symInfo.LotsMin(), mx=symInfo.LotsMax(), st=symInfo.LotsStep();
   if(st<=0.0) st=mn>0.0? mn : 0.01;
   l=MathMax(l,mn); l=MathMin(l,mx); l=MathFloor(l/st)*st;
   // AUDIT FIX (v4.3.1 / Finding E, MEDIUM, sizing): the result was rounded to a
   // HARDCODED 2 decimals. On a broker with a 0.001 lot step that re-rounds the
   // step-aligned value straight back OFF the step (e.g. 0.125 -> 0.13), which can
   // exceed the intended risk and can be rejected as an invalid volume. Derive the
   // digit count from the broker's actual LotsStep instead.
   int lotDigits=0; double stp=st;
   while(lotDigits<8 && MathAbs(stp-MathRound(stp))>1e-9){ stp*=10.0; lotDigits++; }
   l=NormalizeDouble(l,lotDigits);
   // guard the rounding itself from stepping outside the broker's own bounds
   if(l<mn) l=mn;
   if(l>mx) l=mx;
   return l;
  }

// v4.6.5 RB 10,15; Audit 7-8; function mapping in CHANGE_REPORT.md.
double CalculateLotSize(double sd)
  {
// Compatibility caller supplies distance; new execution supplies exact side/prices.
   int dir=g465.dir;
   double entry=(dir>0?symInfo.Ask():symInfo.Bid());
   return ICC465_Lots(dir,entry,entry-dir*sd);
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
//--- v3.6.1 dual floating-P/L readout. Aggregates THIS EA's open positions and
//    returns unrealised money (account currency, incl. swap + commission) and a
//    volume-weighted pip figure, so the dashboard can judge results in $ (the
//    outcome that hits the account) AND pips (the chart behaviour the runner
//    reacts to). Read-only: touches no orders and changes no engine logic.
void FloatingPL(double &money,double &pips,int &nPos)
  {
   money=0.0; pips=0.0; nPos=0;
   double pipSz=(g_pip>0.0? g_pip : _Point);
   double wPips=0.0, wVol=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      nPos++;
      money += posInfo.Profit()+posInfo.Swap()+posInfo.Commission();
      double op=posInfo.PriceOpen();
      double cur=(posInfo.PositionType()==POSITION_TYPE_BUY)? symInfo.Bid() : symInfo.Ask();
      if(cur<=0.0) continue;   // v3.9.2 guard: skip a position with a stale/zero quote
      double dirSgn=(posInfo.PositionType()==POSITION_TYPE_BUY)? 1.0 : -1.0;
      double vol=posInfo.Volume();
      wPips += ((cur-op)*dirSgn/pipSz)*vol;   // volume-weighted so blended pips are fair
      wVol  += vol;
     }
   if(wVol>0.0) pips=wPips/wVol;
  }
void CloseAllThisEA(string reason)
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      ulong tk=posInfo.Ticket();
      ulong closeId=(ulong)posInfo.Identifier();
      RX_StageCloseTag(closeId,"OPP-CLOSE");
      bool closeOK=(trade.PositionClose(tk) && TradeResultSucceeded());
      if(closeOK)
        { TriggerFlash(reason,ColExit,false,0,0,0); DispatchAlert(reason+" | "+_Symbol); }
      else
        {
         RX_ConsumeCloseTag(closeId);
         PrintFormat("[EXIT] close FAILED #%I64u rc=%d (%s)",tk,trade.ResultRetcode(),trade.ResultRetcodeDescription());
        }
     }
  }
//====================================================================
//  v3.6.0 R-MULTIPLE EXIT ENGINE (helpers + per-position manager).
//  1R = |entry - initial SL|, captured ONCE per ticket. Stages, floor,
//  structure runner and trend-health as documented in the header. Every
//  stop candidate only ratchets in the favourable direction and is
//  clamped to the broker minimum stop distance, so modifies stay legal.
//====================================================================
int RX_Find(ulong tk)
  {
   if(PositionSelectByTicket(tk))
     {
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      for(int i=0;i<ArraySize(g_rxIdentifier);i++)
         if(g_rxIdentifier[i]==id) return i;
     }
   for(int i=0;i<ArraySize(g_rxTicket);i++) if(g_rxTicket[i]==tk) return i;
   return -1;
  }
// AUDIT FIX (v4.2.8 / CRITICAL, log-flood + broker spam): the 2026.03.19 tester
// journal showed position #12 (a short) firing tens of thousands of IDENTICAL
// "failed modify #12 ... sl:4854.32 -> sl:4854.32 [Invalid stops]" (retcode
// 10016) -- one per tick for ~50 minutes of a single stalled bar -- producing a
// 26 MB log. Root cause: the four raw trade.PositionModify() call sites (a) did
// not verify the new SL actually DIFFERS from the live SL, and (b) did not
// validate the SL against the broker STOPS + FREEZE distance, and (c) discarded
// the return value, so a rejected stop was re-sent every single tick forever.
// This wrapper fixes all three: it skips no-op modifies (new==current within a
// tick), rejects broker-illegal stops BEFORE sending, and -- crucially --
// remembers the last SL that FAILED for each ticket so an identical failing
// value is never re-attempted until price/level actually moves. Pure execution
// hardening: it changes NO entry/exit decision, only suppresses illegal/dupe
// PositionModify spam.
ulong  g_rxFailTicket[];
double g_rxFailSL[];
double RX_LastFailSL(ulong tk)
  { for(int i=0;i<ArraySize(g_rxFailTicket);i++) if(g_rxFailTicket[i]==tk) return g_rxFailSL[i]; return 0.0; }
void RX_SetFailSL(ulong tk,double sl)
  {
   for(int i=0;i<ArraySize(g_rxFailTicket);i++) if(g_rxFailTicket[i]==tk){ g_rxFailSL[i]=sl; return; }
   int n=ArraySize(g_rxFailTicket); ArrayResize(g_rxFailTicket,n+1); ArrayResize(g_rxFailSL,n+1);
   g_rxFailTicket[n]=tk; g_rxFailSL[n]=sl;
  }
void RX_ClearFailSL(ulong tk)
  {
   int n=ArraySize(g_rxFailTicket);
   for(int i=0;i<n;i++) if(g_rxFailTicket[i]==tk)
     { for(int j=i;j<n-1;j++){ g_rxFailTicket[j]=g_rxFailTicket[j+1]; g_rxFailSL[j]=g_rxFailSL[j+1]; }
       ArrayResize(g_rxFailTicket,n-1); ArrayResize(g_rxFailSL,n-1); return; }
  }

// v4.6.5 RB 10; Audit 7-8; function mapping in CHANGE_REPORT.md.
bool RX_SafeModify(ulong tk,bool isLong,double rawNewSL,double tp,double px)
  {
   double pt   = SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   double newSL= NormalizeDouble(rawNewSL,_Digits);
   if(newSL<=0.0 || px<=0.0) return false;
   if(!PositionSelectByTicket(tk)) { RX_ClearFailSL(tk); return false; }
   double curSL= PositionGetDouble(POSITION_SL);
   // (a) no-op guard: nothing meaningfully changed -> never touch the broker.
   if(curSL>0.0 && MathAbs(newSL-curSL) < pt*0.5) return false;
   // (b) broker STOPS + FREEZE legality (a SELL stop must sit far enough ABOVE
   //     price; a BUY stop far enough BELOW). GetMinStopDistance folds in
   //     stops-level, freeze-level, spread and a floor.
   double minDist = (double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   if(isLong)  { if(newSL > px-minDist) return false; }   // long SL must be below px by minDist
   else        { if(newSL < px+minDist) return false; }   // short SL must be above px by minDist
   // (c) anti-spam: don't re-send a value the broker already rejected until it
   //     genuinely changes.
   double lastFail=RX_LastFailSL(tk);
   if(lastFail>0.0 && MathAbs(newSL-lastFail) < pt*0.5) return false;
   if(trade.PositionModify(tk,newSL,tp) && TradeResultSucceeded())
     { RX_ClearFailSL(tk); return true; }
   // real failure: remember it (so we stop hammering) and log ONCE per new value.
   RX_SetFailSL(tk,newSL);
   PrintFormat("[RX] modify #%I64u skipped-after-fail sl=%.5f rc=%d (%s)",
               tk,newSL,trade.ResultRetcode(),trade.ResultRetcodeDescription());
   return false;
  }

//--- Drop registry rows whose ticket is no longer an open position.
void RX_Prune()
  {
   // AUDIT FIX (v4.3.4 / Finding E, LOW-MEDIUM, unbounded growth): the parallel
   // g_rxFailTicket/g_rxFailSL registry (v4.2.8 anti-spam) was only ever cleared
   // from inside RX_SafeModify, which is called for OPEN positions only. A ticket
   // whose last modify FAILED and then CLOSED left its row behind permanently, so
   // the arrays grew for the life of the run and every RX_LastFailSL/RX_SetFailSL
   // lookup -- both linear scans, on every managed tick -- got progressively
   // slower. Prune it here, on the same pass that prunes the position registry.
   for(int i=ArraySize(g_rxFailTicket)-1;i>=0;i--)
      if(!PositionSelectByTicket(g_rxFailTicket[i]))
        {
         int m=ArraySize(g_rxFailTicket);
         for(int j=i;j<m-1;j++){ g_rxFailTicket[j]=g_rxFailTicket[j+1]; g_rxFailSL[j]=g_rxFailSL[j+1]; }
         ArrayResize(g_rxFailTicket,m-1); ArrayResize(g_rxFailSL,m-1);
        }
   for(int i=ArraySize(g_rxTicket)-1;i>=0;i--)
     {
      if(SelectPositionByIdentifier(g_rxIdentifier[i]))
        {
         g_rxTicket[i]=(ulong)PositionGetInteger(POSITION_TICKET);
         continue;
        }
      int n=ArraySize(g_rxTicket);
      for(int j=i;j<n-1;j++)
        {
         g_rxTicket[j]=g_rxTicket[j+1]; g_rxIdentifier[j]=g_rxIdentifier[j+1];
         g_rxEntry[j]=g_rxEntry[j+1]; g_rxRisk[j]=g_rxRisk[j+1]; g_rxPartial[j]=g_rxPartial[j+1];
        }
      ArrayResize(g_rxTicket,n-1); ArrayResize(g_rxIdentifier,n-1);
      ArrayResize(g_rxEntry,n-1); ArrayResize(g_rxRisk,n-1); ArrayResize(g_rxPartial,n-1);
     }
  }

//--- Register a ticket the first time we see it and capture its 1R.
int RX_Ensure(ulong tk,double entry,double sl)
  {
   int idx=RX_Find(tk); if(idx>=0) return idx;
   double risk=(sl>0.0)? MathAbs(entry-sl) : GetATRStopDistance();
   if(risk<=0.0) risk=GetATRStopDistance();
   if(!PositionSelectByTicket(tk)) return -1;
   ulong identifier=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   int n=ArraySize(g_rxTicket);
   ArrayResize(g_rxTicket,n+1); ArrayResize(g_rxIdentifier,n+1);
   ArrayResize(g_rxEntry,n+1); ArrayResize(g_rxRisk,n+1); ArrayResize(g_rxPartial,n+1);
   g_rxTicket[n]=tk; g_rxIdentifier[n]=identifier;
   g_rxEntry[n]=entry; g_rxRisk[n]=risk; g_rxPartial[n]=false;
   return n;
  }

//--- Locked-profit R at the current open R (progressive floor ladder):
//    +ProtectR -> ProtectLockR (BE), +LockR -> LockProfitR, +ActivateR
//    onward -> (curR - GiveBackR). Sentinel -1e18 = nothing locked yet.
double RX_LockedR(double curR)
  {
   double f=-1e18;
   if(curR>=InpProtectAtR)  f=MathMax(f,InpProtectLockR);
   if(curR>=InpLockAtR)     f=MathMax(f,InpLockProfitR);
   if(curR>=InpActivateAtR) f=MathMax(f,curR-InpRunnerGiveBackR);
   return f;
  }

// v4.6.5 RB 2,10; Audit 8; function mapping in CHANGE_REPORT.md.
ENUM_TREND_HEALTH RX_Health(int dir)
  {
   ENUM_TIMEFRAMES tf=InpSetupStructureTF;
   int strength=(tf==PERIOD_H4?InpExtSwingStrength:InpIntSwingStrength);
   S465Swings sw; ICC465_Swings(tf,strength,0,sw);
   return ICC465_Direction(sw)==-dir?TH_REVERSAL:TH_HEALTHY;
  }
string RX_HealthTxt(ENUM_TREND_HEALTH h){ return h==TH_HEALTHY?"HEALTHY":h==TH_CAUTION?"CAUTION":"REVERSAL"; }

// v4.6.5 RB 10,13; Audit 7-8; function mapping in CHANGE_REPORT.md.
double RX_DashInfo(string &htxt)
  {
htxt="OWNER_TF";
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i) || posInfo.Magic()!=MagicNumber || posInfo.Symbol()!=_Symbol) continue;
      ulong id=(ulong)posInfo.Identifier();
      double risk=ICC465_Get(id,"risk");
      if(risk>0) return (posInfo.Profit()+posInfo.Swap()+ICC465_Get(id,"realized"))/risk;
     }
   htxt="R_UNAVAILABLE"; return 0;
  }

// v4.6.5 RB 2,9-10; Audit 8; function mapping in CHANGE_REPORT.md.
bool RX_ManageOne(double minStop)
  {
return ICC465_ManagePosition();
  }

// v4.6.5 RB 2,9-10; Audit 8; function mapping in CHANGE_REPORT.md.
void ManagePositions()
  {
RX_Prune();
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber || posInfo.Symbol()!=_Symbol) continue;
      RX_ManageOne(GetMinStopDistance());
     }
  }

// Phase 5 CM-24 helper: higher-context swing is a FALLBACK only when the
// active-cycle Indication extreme is already behind the executable entry.
int g467DiagTargetPivots=0,g467DiagTargetAhead=0,g467DiagTargetTaken=0;
double g467DiagContextTarget=0;
datetime g467DiagTargetTime=0,g467DiagTargetKnown=0;
string g467DiagTargetReason="NOT_EVALUATED";

void ICC467_DiagTarget(string stage,int dir,double entryPx,double target)
  {
   double extreme=dir>0?g465.indHigh:g465.indLow;
   PrintFormat("[ICC467 DIAG TARGET] stage=%s time=%s setup=%I64d owner=%s dir=%d ind_start=%s ind_end=%s frozen_extreme=%.8f entry=%.8f entry_side=%s extreme_ahead=%d context_tf=%s eligible_context_target=%.8f context_pivot_time=%s context_known_time=%s context_reason=%s pivots=%d ahead=%d taken=%d selected_source=%s selected_target=%.8f management=%s",
      stage,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),(long)g465.id,EnumToString(g465.indTF),dir,
      TimeToString(g465.indStart,TIME_DATE|TIME_SECONDS),TimeToString(g465.indEnd,TIME_DATE|TIME_SECONDS),extreme,entryPx,dir>0?"Ask":"Bid",
      (int)(extreme>0 && dir*(extreme-entryPx)>0),EnumToString(InpContextTF),g467DiagContextTarget,
      TimeToString(g467DiagTargetTime,TIME_DATE|TIME_SECONDS),TimeToString(g467DiagTargetKnown,TIME_DATE|TIME_SECONDS),
      g467DiagTargetReason,g467DiagTargetPivots,g467DiagTargetAhead,g467DiagTargetTaken,
      ICC466_TargetSourceText(g465.structuralTargetSource),target,target>0?"EXISTING_STRUCTURAL_TP":"EXISTING_TARGETLESS_RUNNER");
  }

double ICC466_ContextStructuralTarget(ENUM_TIMEFRAMES tf,int strength,int dir,double entryPx)
  {
   g467DiagTargetReason="INVALID_CONTEXT_TF_OR_STRENGTH";
   if(tf==PERIOD_CURRENT || strength<1) return 0;
   double best=0.0;
   int last=MathMin(InpTPLookback,Bars(_Symbol,tf)-strength-1);
   g467DiagTargetReason=last<strength+1?"NO_CONFIRMED_SEARCH_BARS":"NO_CONFIRMED_PIVOT";
   for(int s=strength+1;s<=last;s++)
     {
      bool pivot=(dir>0?IsPivotHighTF(tf,s,strength):IsPivotLowTF(tf,s,strength));
      if(!pivot) continue;
      g467DiagTargetPivots++;
      double p=(dir>0?iHigh(_Symbol,tf,s):iLow(_Symbol,tf,s));
      if(dir*(p-entryPx)<=0) continue;
      g467DiagTargetAhead++;
      bool taken=false;
      for(int k=s-1;k>=1;k--)
         if((dir>0 && iHigh(_Symbol,tf,k)>p) || (dir<0 && iLow(_Symbol,tf,k)<p)) { taken=true; break; }
      if(taken) g467DiagTargetTaken++;
      if(!taken && (best==0 || dir*(p-best)<0))
        {
         best=p;
         g467DiagTargetTime=iTime(_Symbol,tf,s);
         g467DiagTargetKnown=iTime(_Symbol,tf,s-strength-1);
        }
     }
   g467DiagContextTarget=best;
   if(best>0) g467DiagTargetReason="ELIGIBLE_UNTAKEN_PIVOT";
   else if(g467DiagTargetAhead>0) g467DiagTargetReason="ALL_AHEAD_PIVOTS_TAKEN";
   else if(g467DiagTargetPivots>0) g467DiagTargetReason="NO_PIVOT_AHEAD_OF_ENTRY";
   return best;
  }

// Phase 5 CM-24: the active Indication cycle owns the primary structural target.
// Buy -> frozen Indication/new-swing high. Sell -> frozen Indication/new-swing low.
// If execution occurs beyond that objective, only then may the explicit higher
// context timeframe provide a runner target. There is still no fixed-R fallback.
double StructuralTPTarget(int dir, double entryPx)
  {
   g467DiagTargetPivots=0; g467DiagTargetAhead=0; g467DiagTargetTaken=0;
   g467DiagContextTarget=0; g467DiagTargetTime=0; g467DiagTargetKnown=0;
   g467DiagTargetReason="NOT_EVALUATED_PRIMARY_EXTREME_AHEAD";
   g465.structuralTarget=0; g465.structuralTargetTF=PERIOD_CURRENT; g465.structuralTargetSource=0;
   double cycleTarget=(dir>0?g465.indHigh:g465.indLow);
   if(cycleTarget>0 && dir*(cycleTarget-entryPx)>0)
     {
      g465.structuralTarget=cycleTarget;
      g465.structuralTargetTF=g465.indTF;
      g465.structuralTargetSource=1;
      return cycleTarget;
     }

   ENUM_TIMEFRAMES contextTF=InpContextTF;
   int strength=InpExtSwingStrength;
   double contextTarget=ICC466_ContextStructuralTarget(contextTF,strength,dir,entryPx);
   if(contextTarget>0)
     {
      g465.structuralTarget=contextTarget;
      g465.structuralTargetTF=contextTF;
      g465.structuralTargetSource=2;
      return contextTarget;
     }
   return 0;
  }

// Phase 5 CM-24: structural geometry only; no fixed-R fallback or minimum-R floor.
double ResolveTP(int dir, double entryPx, double d, bool &usedStruct)
  {
   double target=StructuralTPTarget(dir,entryPx);
   usedStruct=(target>0);
   if(g465.structuralTargetSource==1) ICC465_Log("TP_ACTIVE_INDICATION_EXTREME","TARGET");
   else if(g465.structuralTargetSource==2) ICC465_Log("TP_HIGHER_CONTEXT_RUNNER_SWING","TARGET");
   else ICC465_Log("TP_NO_STRUCTURAL_TARGET_RUNNER","TARGET");
   ICC467_DiagTarget("RESOLVE",dir,entryPx,target);
   return target;
  }

// v4.6.5 RB 10,15; Audit 8; function mapping in CHANGE_REPORT.md.
void ExecuteBuy(double slAnchor, string tag, color boxCol)
  {
ICC465_Execute(1,slAnchor,tag,boxCol);
  }

// v4.6.5 RB 10,15; Audit 8; function mapping in CHANGE_REPORT.md.
void ExecuteSell(double slAnchor, string tag, color boxCol)
  {
ICC465_Execute(-1,slAnchor,tag,boxCol);
  }
//+==================================================================+
//|                 SIGNAL ROUTING                                   |
//+==================================================================+
//--- v3.4.0 Sci kill-zone gate. A window may wrap midnight (start>end).
bool InKillWindow(int h,int s,int e)
  { if(s<e) return (h>=s && h<e); return (h>=s || h<e); }
//--- True if kill-zones are OFF, or the current broker hour sits in an
//    enabled kill zone. Sets g_kzActive/g_inKillzone for the dashboard.
bool IsInKillzone()
  {
   if(!InpUseKillzones){ g_inKillzone=true; g_kzActive="OFF"; return true; }
   MqlDateTime dt; TimeCurrent(dt); int h=dt.hour;
   if(InpKZ_London && InKillWindow(h,InpKZ_LonStart ,InpKZ_LonEnd )){ g_kzActive="London"; g_inKillzone=true; return true; }
   if(InpKZ_NYam   && InKillWindow(h,InpKZ_NYamStart,InpKZ_NYamEnd)){ g_kzActive="NY-AM";  g_inKillzone=true; return true; }
   if(InpKZ_NYpm   && InKillWindow(h,InpKZ_NYpmStart,InpKZ_NYpmEnd)){ g_kzActive="NY-PM";  g_inKillzone=true; return true; }
   g_kzActive="outside"; g_inKillzone=false; return false;
  }
bool IsNewBar()
  { static datetime lt=0; datetime ct=iTime(_Symbol,_Period,0); if(ct!=lt){ lt=ct; return true; } return false; }
string PhaseTxt(int p){ return p==PH_INDICATION?"IND":p==PH_CORRECTION?"COR":"---"; }

// Phase 4 CM-23: route only the baseline sequenced ICC signal. Session/ML remain
// optional experiments outside SCI CORE; concurrency/risk policy remains unchanged.
void TryEntries()
  {
IsInKillzone(); // context refresh; optional experiment is separate from SCI CORE
   if(!iccBuySig && !iccSellSig) return;
   if(g465.entry!=E465_BASELINE_LTF)
     { ICC465_Log("EXEC_LEGACY_ENTRY_PATH_RETIRED","VETO"); return; }
   int dir=iccBuySig?1:-1;
   ML_Evaluate2R(dir); ML_LogGateVerdict(dir); ML_Export("SIGNAL",dir);
   if(InpUseKillzones && !g_inKillzone) { ICC465_Log("EXEC_SESSION_EXPERIMENT","VETO"); return; }
   if(!g_mlPass) { ICC465_Log("EXEC_ML_EXPERIMENT","VETO"); return; }
   if(CountOpenTrades()>=MaxOpenTrades || OpenTradeDir()!=0)
     { ICC465_Log("EXEC_POSITION_LIMIT","VETO"); return; }
   // Netting must not merge this setup with another strategy/manual exposure.
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && PositionSelect(_Symbol))
     { ICC465_Log("EXEC_NETTING_SYMBOL_BUSY","VETO"); return; }
   if(iccSigSL<=0 || g465.entry==E465_NONE || g465.validity!=V465_ACTIVE) return;
   ML_v2_StagePending(dir);
   if(dir>0) ExecuteBuy(iccSigSL,"ICC v4.6.5 BUY",ColBuy);
   else ExecuteSell(iccSigSL,"ICC v4.6.5 SELL",ColSell);
  }

// v4.6.5 RB 2-3,13,15; Audit 8; function mapping in CHANGE_REPORT.md.
void UpdateDashboard()
  {
if(!ShowDashboard) { Comment(""); return; }
   string h; double rr=RX_DashInfo(h);
   Comment("ICC TradesBySci v4.6.7 | H1 indication -> LTF correction/resumption\nsetup=",EnumToString(InpSetupStructureTF),
      " context=",EnumToString(InpContextTF)," entry=",EnumToString(InpEntryTF),
      "\n",g465.reason," | dir=",g465Direction,
      " active_high=",DoubleToString(g466.activeSetupHigh,_Digits)," active_low=",DoubleToString(g466.activeSetupLow,_Digits),
      " no_trade=",(g466.noTradeZone?"YES":"NO"),
      "\nind_break=",DoubleToString(g465.brokenLevel,_Digits)," corr_low=",DoubleToString(g465.corrLow,_Digits),
      " corr_high=",DoubleToString(g465.corrHigh,_Digits)," cont_level=",DoubleToString(g465.continuationLevel,_Digits),
      " LTF_evidence=",DoubleToString(g465.entryEvidenceLevel,_Digits),
      "\n",EnumToString(g465.indication)," / ",EnumToString(g465.correction),
      " / ",EnumToString(g465.continuation)," / ",EnumToString(g465.entry),
      "\nRisk currency=",AccountInfoString(ACCOUNT_CURRENCY)," R=",DoubleToString(rr,3)," ",h,
      "\nRule3 telemetry wick cutoff=",DoubleToString(InpRule3MaxWickRange,3)," (non-authoritative)");
  }
//+==================================================================+
//|                 LIFECYCLE                                        |
//+==================================================================+
//+------------------------------------------------------------------+
//| HOSTILE-AUDIT HARDENING                                          |
//+------------------------------------------------------------------+
bool TradeResultSucceeded()
  {
   uint rc=trade.ResultRetcode();
   return (rc==TRADE_RETCODE_DONE ||
           rc==TRADE_RETCODE_DONE_PARTIAL ||
           rc==TRADE_RETCODE_PLACED ||
           rc==TRADE_RETCODE_ORDER_CHANGED ||
           rc==TRADE_RETCODE_NO_CHANGES ||
           rc==TRADE_RETCODE_POSITION_CLOSED);
  }

// v4.6.5 RB 1-2,5,10,12,21; Audit 8; function mapping in CHANGE_REPORT.md.
bool ValidateInputs()
  {
if(MagicNumber==0 || Slippage<0 || MaxOpenTrades<1) return false;
   if(InpGSTF!=PERIOD_D1 && InpGSTF!=PERIOD_H4 && InpGSTF!=PERIOD_H1)
     { Print("SPECIFICATION DECISION REQUIRED: GSTF outside supplied D1/H4/H1 roles"); return false; }
   // Preserve Continuation/entry and later downstream authority during the Phase-3 Correction-only change.
   if(InpObservationTF==PERIOD_CURRENT || InpEntryTF==PERIOD_CURRENT ||
      PeriodSeconds(InpObservationTF)>=PeriodSeconds(InpGSTF) ||
      PeriodSeconds(InpEntryTF)>PeriodSeconds(InpObservationTF)) return false;
   if(InpEntryTF!=PERIOD_M15 && InpEntryTF!=PERIOD_M5) return false;
   if(InpSetupStructureTF!=PERIOD_H1 && InpSetupStructureTF!=PERIOD_H4) return false;
   if(InpContextTF!=PERIOD_H4 && InpContextTF!=PERIOD_D1) return false;
   if(InpTradeEnableTime<0) return false;
   // Phase 2 CM-06: telemetry thresholds are validated only as ratios; they no longer define trade authority.
   if(InpRule3BodyRatio<0.0 || InpRule3BodyRatio>1.0 ||
      InpRule3MaxWickRange<0.0 || InpRule3MaxWickRange>1.0) return false;
   if(InpHTFClosePolicy!=1) { Print("User-resolved GSTF close policy must be 1 (literal formal close beyond level)"); return false; }
   if(CascadeSwingLen<1 || InpExtSwingStrength<1 || InpIntSwingStrength<1 || InpMinorPivotStrength<1 ||
      InpStructLookback<10 || InpTPLookback<1) return false;
   if((RiskPercent<=0 && FixedLots<=0) || FixedLots<0) return false;
   if(ATR_Period<1 || InpATRautoLen<1 || InpDispATRPeriod<1 || SR_RefLen<1) return false;
   if(InpUseRexit && (InpProtectAtR<0 || InpProtectLockR<0 || InpLockAtR<0 || InpLockProfitR<0 || InpActivateAtR<0 || InpRunnerGiveBackR<0)) return false;
   if(InpUsePartial && (InpPartialPct<=0 || InpPartialPct>=100)) return false;
   if(InpMLMode!=ML_OFF && InpMLMode!=ML_OBSERVE && InpMLMode!=ML_SHADOW)
     { Print("SPECIFICATION DECISION REQUIRED: SD07 old PATH_v2 model not validated for v4.6.5; execution ML modes disabled"); return false; }
   if(InpMLAutonomous) return false;
   if(InpML2RThreshold<0 || InpML2RThreshold>1 || InpML2RHighThreshold<InpML2RThreshold || InpML2RHighThreshold>1) return false;
   if(InpMLModelEnabled && StringCompare(InpMLContractToken,ML2R_CONTRACT_TOKEN,true)!=0) return false;
   if(FlashOn && (FlashSeconds<1 || FlashMs<50)) return false;
   return true;
  }

bool RX_ClosePartial(ulong ticket,double volume)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   ENUM_ACCOUNT_MARGIN_MODE mode=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   bool basic=false;
   if(mode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      basic=trade.PositionClosePartial(ticket,volume);
   else if(type==POSITION_TYPE_BUY)
      basic=trade.Sell(volume,_Symbol,0.0,0.0,0.0,"ICC-PARTIAL");
   else
      basic=trade.Buy(volume,_Symbol,0.0,0.0,0.0,"ICC-PARTIAL");
   return basic && TradeResultSucceeded();
  }

// v4.6.5 RB 2-3,13,21; Audit 8; function mapping in CHANGE_REPORT.md.
int OnInit()
  {
   if(!ValidateInputs()) return INIT_PARAMETERS_INCORRECT;
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   // AUDIT FIX (v4.2.5 / Finding 1, MEDIUM-HIGH, TRADE-BLOCKING): the filling
   // mode was hardcoded to ORDER_FILLING_FOK with NO check of the symbol's
   // SYMBOL_FILLING_MODE bitmask. Many brokers -- very commonly XAUUSD ECN /
   // market-execution accounts -- support only IOC, not FOK, and reject EVERY
   // order with retcode 10030 "Unsupported filling mode", so the EA silently
   // places ZERO trades no matter how valid the signals are. (CTrade already
   // defaults to FOK, so the hardcoded line added no safety.) Fix: detect the
   // broker-supported mode and prefer FOK -> IOC -> RETURN. Execution-layer
   // only; no signal, sizing, or exit logic changed.
   int fillMask=(int)SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if(!trade.SetTypeFillingBySymbol(_Symbol))
     {
      PrintFormat("[INIT] FATAL: could not determine a broker-valid filling mode for %s (mask=%d).",
                  _Symbol,fillMask);
      return INIT_FAILED;
     }
   ENUM_ORDER_TYPE_FILLING fillMode=trade.RequestTypeFilling();
   PrintFormat("[INIT] Filling mode -> %s (broker mask=%d)",
      EnumToString(fillMode),fillMask);
   symInfo.Name(_Symbol); symInfo.Refresh();
    MqlDateTime runDt; TimeLocal(runDt);
    g_mlRunId=StringFormat("%04d%02d%02d_%02d%02d%02d_%s_%s_%I64u_%u",
      runDt.year,runDt.mon,runDt.day,runDt.hour,runDt.min,runDt.sec,_Symbol,
      EnumToString((ENUM_TIMEFRAMES)_Period),MagicNumber,(uint)GetTickCount());
   // v3.3.4 metal pip scaling: 2-digit XAU gave g_pip=_Point=0.01 -> S/R tol
   // 0.10 (ten cents) -> no clustering on gold. Treat metals like fractional FX.
   bool isMetalSym = (StringFind(_Symbol,"XAU")>=0 || StringFind(_Symbol,"XAG")>=0 ||
                      StringFind(_Symbol,"GOLD")>=0|| StringFind(_Symbol,"SILVER")>=0 ||
                      StringFind(_Symbol,"XPT")>=0 || StringFind(_Symbol,"XPD")>=0);
   g_pip     = _Point*(((_Digits==3||_Digits==5) || (_Digits<=2 && isMetalSym))?10:1);
   // v3.3.6 ATR-auto: dedicated ATR handle on the chart TF; RefreshEffectiveDistances()
   // seeds g_tol/g_brkBuf/g_slBuf/g_equalTol/g_sweepMin/g_fvgMin (ATR or fixed).
   g_atrAuto = iATR(_Symbol,_Period,InpATRautoLen);
   if(g_atrAuto==INVALID_HANDLE) Print("WARNING: ATR-auto handle failed; using fixed pips.");
   RefreshEffectiveDistances();
   AssetClass=DetectAssetClass();
   ApplyAssetClassScaling();
   atrHandle=iATR(_Symbol,_Period,ATR_Period);
   if(atrHandle==INVALID_HANDLE) Print("WARNING: ATR handle failed; ATR SL will fallback.");
   g_maHandle=iMA(_Symbol,_Period,SR_RefLen,0,MODE_SMA,PRICE_CLOSE);
   if(g_maHandle==INVALID_HANDLE) Print("WARNING: SMA handle failed; S/R classifier will fallback.");
   // AUDIT FIX (v4.1.0 / Finding 1+2): g_extTF/g_intTF replace the removed
   // single shared g_mseTF/InpMSE_TF -- assigned ONCE here from the EA's own
   // already-documented cascade inputs (MidTF="primary Indication TF" for
   // External; WorkTF="swing anchor" for Internal), instead of a separate,
   // independently-configurable structure-TF input that could silently
   // diverge from either. The displacement ATR handle now sits on g_intTF
   // (H1), the same TF the liquidity/FVG/OB/displacement engines operate on.
   ICC466_Init();
   g_extTF=InpGSTF;
   g_intTF=InpObservationTF;
   Print("[ICC465] Rulebook v1.1 controls. Explicit GSTF=",EnumToString(InpGSTF),
         " observation=",EnumToString(InpObservationTF)," entry=",EnumToString(InpEntryTF));
   Print("[ICC465] Legacy magnitude/FVG/OB/conviction/expiry gates and fixed-R TP are retired from SCI CORE.");
   Print("[ICC465] Phase 4: H1/H4 setup-owner Continuation is a post-Correction formal re-break; M15/M5 refines entry; liquidity/AOI/OTE are non-gating baseline confluence.");
   ICC465_SessionDiagnostics();
   Print("[ICC465] Automatic GSTF selection and round-number granularity remain SPECIFICATION DECISION REQUIRED; SD05 AOI ranking is RESOLVED by authorized lexicographic stack.");
   g_mseATR=iATR(_Symbol,g_intTF,InpDispATRPeriod);
   if(g_mseATR==INVALID_HANDLE) Print("WARNING: SMC ATR handle failed; displacement ATR score will be 0.");
   ICC_Reset();
   g465TraceFile="ICC467_state4_events_"+g_mlRunId+".csv";
   ICC465_Log("INIT_TRANSCRIPT_STATE4","INIT");
   EvaluateCascade();
   MSE_Update();                 // prime protected swings / liquidity / FVGs / OBs
   ICC466_UpdateStructure(); // prime retained structure roles for Phase-3 Correction authority
   ML_UpdateContext();
   // AUDIT FIX (v4.0.5 / F5): resolve each dataset's EFFECTIVE (per-symbol) filename
   // once, here, before any header/row is written -- see g_mlv1FileEff etc. above.
   g_mlv1FileEff=ML_BuildPerSymbolFilename(InpMLCSVFile);
   g_mlv2FileEff=ML_BuildPerSymbolFilename(InpMLv2CSVFile);
   g_mlv4FileEff=ML_BuildPerSymbolFilename(InpMLv4CSVFile);
   if(!ML_Load2RModel() && InpMLModelEnabled && InpMLRequireModel) return INIT_FAILED;
   //====================================================================
   // AUDIT FIX (v4.5.0 / Finding 3, CRITICAL, CONFIG TRAP + AUTONOMY CONTRACT).
   // ML_Evaluate2R contains this branch:
   //     if(!InpMLModelEnabled){ ... if(mode==FILTER/FILTER_SIZE/FULL){ g_mlPass=false; } return; }
   // so selecting a FILTERING mode while InpMLModelEnabled stays at its DEFAULT
   // FALSE vetoes 100% of signals, permanently, for the whole run -- a silent,
   // total trade blockade produced by a plausible two-input combination. Nothing
   // validated it at startup; the only evidence was a per-signal log line on a run
   // that, by construction, produces no trades to draw attention to itself.
   // Conversely InpMLRequireModel=false in a filtering mode degrades the gate to
   // pass-through (the v4.4.2 Finding C fail-open), which invalidates any s14 A/B
   // arm run in that state.
   // FIX: validate the combination ONCE, loudly, at init. InpMLAutonomous=true
   // makes the contract binding and REFUSES to start a configuration that cannot
   // trade, instead of discovering it after a 30,000-bar backtest returns zero deals.
   //====================================================================
   {
    bool mlGating=(InpMLMode==ML_FILTER || InpMLMode==ML_FILTER_SIZE || InpMLMode==ML_FULL);
    // v4.6.0: featureSet is printed UNCONDITIONALLY. The tensor SHAPE did not
    // change, so a stale ICC_2R_v1.onnx loads without error and scores garbage;
    // this line is the only startup evidence of which contract is in force.
    Print("[ML2R] feature-set -> PATH_v2 (28 slots). v4.6.0 REPLACED ext_trend/icc_phase/correction_depth/sweep_long+short with sweep_age, sweep_lead_bars, impulse_concentration, corr_leg_count, corr_recovery_frac. A model trained on the PRE-v4.6.0 vector is INVALID here -- retrain on a schema-4.2.0 dataset.");
    PrintFormat("[ML2R] init-contract -> featureSet=PATH_v2 features=%d token=%s enforce=%s modelVersion=%s | mode=%s gating=%s modelEnabled=%s modelReady=%s requireModel=%s autonomous=%s | runnerByProb=%s minP2R=%.2f | thr=%.2f lowThr=%.2f highThr=%.2f | minTPRR=%.2f",
       ML2R_FEATURE_COUNT,ML2R_CONTRACT_TOKEN,(InpMLEnforceContract?"YES":"*** NO ***"),g_mlModelVersion,
       EnumToString(InpMLMode),(mlGating?"YES":"no"),
       (InpMLModelEnabled?"YES":"no"),(g_mlModelReady?"YES":"no"),
       (InpMLRequireModel?"YES":"no"),(InpMLAutonomous?"YES":"no"),
       (InpMLRunnerByProb?"YES":"no"),InpMLRunnerMinP2R,
       InpML2RThreshold,InpML2RLowThreshold,InpML2RHighThreshold,InpMinTPRR);
    if(mlGating && !InpMLModelEnabled)
      {
       Print("[ML2R] *** FATAL CONFIG: a FILTERING mode is selected but InpMLModelEnabled=false.");
       Print("[ML2R] *** ML_Evaluate2R vetoes EVERY signal in this state -- the EA would run to completion and place ZERO trades.");
       Print("[ML2R] *** Enable the model (InpMLModelEnabled=true + a valid InpMLModelFile) or select ML_OBSERVE/ML_SHADOW.");
       if(InpMLAutonomous) return INIT_FAILED;
       Print("[ML2R] *** Continuing only because InpMLAutonomous=false. Expect zero trades.");
      }
    if(InpMLAutonomous)
      {
       if(!mlGating)
         { Print("[ML2R] *** FATAL CONFIG: InpMLAutonomous=true requires a gating mode (ML_FILTER / ML_FILTER_SIZE / ML_FULL)."); return INIT_FAILED; }
       if(!g_mlModelReady)
         { Print("[ML2R] *** FATAL CONFIG: InpMLAutonomous=true but no ONNX model is loaded -- an autonomous run may not fail open."); return INIT_FAILED; }
       if(!InpMLRequireModel)
         { Print("[ML2R] *** FATAL CONFIG: InpMLAutonomous=true requires InpMLRequireModel=true so a failed inference fails CLOSED."); return INIT_FAILED; }
       // v4.6.1: same reasoning one level up. InpMLRequireModel makes a FAILED
       // inference fail closed; InpMLEnforceContract is what stops a WRONG one
       // from ever being treated as successful. Autonomous sizing and exit
       // policy are driven by the probability, so an unverified model does not
       // merely filter badly -- it sizes and exits on a meaningless number.
       if(!InpMLEnforceContract)
         { Print("[ML2R] *** FATAL CONFIG: InpMLAutonomous=true requires InpMLEnforceContract=true. Autonomous mode sizes positions and selects the exit policy from the model probability; an unverified artifact would do both on a number with no meaning."); return INIT_FAILED; }
       if(InpMLRunnerByProb && InpMLRunnerMinP2R<InpML2RThreshold)
          PrintFormat("[ML2R] WARNING: InpMLRunnerMinP2R (%.2f) < InpML2RThreshold (%.2f) -- every passing signal becomes a runner, so no take-profit is ever attached.",
                      InpMLRunnerMinP2R,InpML2RThreshold);
       Print("[ML2R] AUTONOMOUS MODE ACTIVE: ICC generates setups, the learned 2R model gates them, sizes them and selects runner-vs-take-profit.");
      }
   }
   ML_EnsureCSVHeader();         // v3.8.1: header exists even with zero signals (OBSERVE verifiable)
   ML_v2_EnsureHeader();         // v3.9.0 compatibility dataset
   ML_v4_EnsureHeader();         // v4.0 canonical dataset header at startup
   PrintBrokerDiagnostics();
   if(FlashOn) EventSetMillisecondTimer(FlashMs);
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  {
   ML_LogGateSummary();   // v4.4.2: one-line rollup of the ML gate's veto rate
   EventKillTimer();
   if(g_mlOnnx!=INVALID_HANDLE) { OnnxRelease(g_mlOnnx); g_mlOnnx=INVALID_HANDLE; g_mlModelReady=false; }
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

// v4.6.5 RB 2-9,13; Audit 4,8; function mapping in CHANGE_REPORT.md.
void OnTick()
  {
symInfo.RefreshRates();
   ICC467_RetryClosedDatasetRows();
   ICC466_UpdateStructure(); // one scheduler call per tick; expensive scans only on structural clocks/retry
   ICC465_TrackLiveExtreme();
   ManagePositions();
   ML_v2_TrackOpen(); ML_v4_TrackOpen();
   // Separate role clocks: a D1 chart cannot delay an M5 entry/zone close.
   datetime g=iTime(_Symbol,InpGSTF,0), o=iTime(_Symbol,InpObservationTF,0), e=iTime(_Symbol,InpEntryTF,0);
   if(g<=0) return; // HTF path must not depend on subordinate history availability
   if(g==g465ClockG && o==g465ClockO && e==g465ClockE) return;
   g465ClockG=g; g465ClockO=o; g465ClockE=e;
   symInfo.Refresh(); g_barCount++;
   RefreshEffectiveDistances(); EvaluateCascade(); MSE_Update();
   // CM-28: warm-up can seed structure but cannot evaluate/fire a legacy setup.
   // ManagePositions above remains active for existing exposure.
   if(g466.tradeEnabled) { ICC_Update(); TryEntries(); }
   UpdateDashboard();
  }
//+------------------------------------------------------------------+

//==================== v4.6.6 PHASE 1 ONLY ============================
void ICC466_Init()
  {
   ZeroMemory(g466);
   ZeroMemory(g466Cycle); // EA-session reset only; ICC_Reset() intentionally does NOT clear cycle lineage.
   g466.setupTF=InpSetupStructureTF; g466.contextTF=InpContextTF; g466.entryTF=InpEntryTF;
   g466TraceFile="ICC466_phase1_structure_trace_"+g_mlRunId+".csv";
   g466LastTraceKey="";
   Print("[ICC466 PHASE5] setup=",EnumToString(g466.setupTF)," context=",EnumToString(g466.contextTF),
         " entry=",EnumToString(g466.entryTF),"; ICC authority unchanged; active-cycle target + owner-TF management + cycle lineage enabled. Requested trade enable=",
         TimeToString(InpTradeEnableTime,TIME_DATE|TIME_SECONDS));
  }

datetime ICC466_DayStart(datetime value)
  {
   MqlDateTime dt; TimeToStruct(value,dt); dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt);
  }

bool ICC466_TradingDay(datetime value)
  {
   MqlDateTime dt; TimeToStruct(value,dt);
   return dt.day_of_week!=0 && dt.day_of_week!=6; // no invented holiday calendar
  }

datetime ICC466_ContextStart(datetime now)
  {
   datetime day=ICC466_DayStart(now); int count=0;
   while(count<3) { day-=86400; if(ICC466_TradingDay(day)) count++; }
   return day; // three complete preceding weekdays, plus current-day price action
  }

// Returns 1 = observed historical activity, 0 = verified empty interval,
// -1 = unavailable/uncertain evidence. Never infer closure from a failed request.
int ICC466_HistoricalActivity(datetime slot,ulong endMsc,const MqlRates &minutes[])
  {
   ulong beginMsc=(ulong)slot*1000;
   if(endMsc<beginMsc) return -1;
   int count=ArraySize(minutes);
   for(int j=0;j<count;j++)
      if(minutes[j].time>=slot && (ulong)minutes[j].time*1000<=endMsc) return 1;
   MqlTick ticks[];
   ResetLastError();
   int copied=CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,beginMsc,endMsc);
   int error=GetLastError();
   // Even a partial positive response proves activity; zero with an error does not prove closure.
   if(copied>0) return 1;
   if(copied<0 || error!=0)
     {
      static datetime lastErrorHour=0;
      datetime hour=(datetime)((long)TimeCurrent()-((long)TimeCurrent()%3600));
      if(hour!=lastErrorHour)
        {
         PrintFormat("[ICC466 CM28] Activity evidence pending: slot=%s tick_count=%d error=%d M1_count=%d",
                     TimeToString(slot,TIME_DATE|TIME_MINUTES),copied,error,count);
         lastErrorHour=hour;
        }
      return -1;
     }
   // Independent M1 history must span the interval. This prevents an empty tick
   // response outside available history being silently counted as a closed market.
   if(count<2 || SeriesInfoInteger(_Symbol,PERIOD_M1,SERIES_SYNCHRONIZED)==0 ||
      minutes[0].time>=slot || (ulong)minutes[count-1].time*1000<=endMsc) return -1;
   return 0;
  }

bool ICC466_ValidH1Bar(const MqlRates &bar)
  {
   return bar.time>0 && (long)bar.time%3600==0 &&
      MathIsValidNumber(bar.open) && MathIsValidNumber(bar.high) &&
      MathIsValidNumber(bar.low) && MathIsValidNumber(bar.close) &&
      bar.low>0 && bar.high>=bar.low && bar.open>=bar.low && bar.open<=bar.high &&
      bar.close>=bar.low && bar.close<=bar.high;
  }

bool ICC466_ContextAvailable(datetime now)
  {
   g466.expectedH1Bars=0; g466.missingH1Bars=0;
   g466.historyStatus="HISTORY_PENDING";
   g466.historyAvailable=false;
   // Initiate range loading even when iBarShift cannot yet resolve the boundary.
   MqlRates range[];
   int requested=CopyRates(_Symbol,PERIOD_H1,g466.contextStart,now,range);
   g466.historyFirst=(datetime)SeriesInfoInteger(_Symbol,PERIOD_H1,SERIES_FIRSTDATE);
   if(requested<=0 || SeriesInfoInteger(_Symbol,PERIOD_H1,SERIES_SYNCHRONIZED)==0) return false;
   g466.historyAvailable=true; // loaded data is distinct from validated coverage
   int boundary=iBarShift(_Symbol,PERIOD_H1,g466.contextStart,false);
   if(boundary<0 || g466.historyFirst<=0 || g466.historyFirst>g466.contextStart)
     { g466.historyStatus="MISSING_CONTEXT_BOUNDARY"; return false; }
   // Exact requested count includes all older neighbors of a boundary pivot.
   int needed=boundary+InpIntSwingStrength+1;
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   int requestedDepth=MathMax(needed,InpStructLookback+InpIntSwingStrength+1);
   int copied=CopyRates(_Symbol,PERIOD_H1,0,requestedDepth,rates);
   if(copied<needed)
      copied=CopyRates(_Symbol,PERIOD_H1,0,needed,rates);
   if(copied<needed)
     { g466.historyStatus="MISSING_BOUNDARY_NEIGHBORS"; return false; }
   for(int j=0;j<copied;j++)
     {
      if(!ICC466_ValidH1Bar(rates[j]) || rates[j].time>now ||
         (j>0 && rates[j].time<=rates[j-1].time))
        { g466.historyStatus="INVALID_H1_BAR_SEQUENCE"; return false; }
     }
   // Historical activity, not today's broker session schedule, owns completeness.
   // Load M1 evidence only if an absent H1 slot needs classification.
   MqlRates minutes[]; ArraySetAsSeries(minutes,false);
   bool minutesLoaded=false;
   int cursor=0,unknownHours=0;
   for(datetime day=g466.contextStart;day<=ICC466_DayStart(now);day+=86400)
     {
      if(!ICC466_TradingDay(day)) continue;
      for(datetime slot=day;slot<day+86400 && slot+3600<=now;slot+=3600)
        {
         while(cursor<copied && rates[cursor].time<slot) cursor++;
         if(cursor<copied && rates[cursor].time==slot)
           { g466.expectedH1Bars++; continue; }
         if(!minutesLoaded)
           {
            ResetLastError();
            // Start at an actual older H1 bar, not 'yesterday': Sunday cannot
            // provide the preceding evidence for a missing Monday 00:00 bar.
            int minuteCount=CopyRates(_Symbol,PERIOD_M1,rates[0].time,now,minutes);
            minutesLoaded=true;
            // Positive M1 records can prove activity even if still downloading.
            // Empty/partial evidence alone never proves an inactive hour.
            if(minuteCount<0) ArrayResize(minutes,0);
           }
         int activity=ICC466_HistoricalActivity(slot,(ulong)(slot+3600)*1000-1,minutes);
         if(activity>0) { g466.expectedH1Bars++; g466.missingH1Bars++; }
         else if(activity<0) unknownHours++;
        }
     }
   if(g466.missingH1Bars>0)
     { g466.historyStatus="MISSING_ACTIVE_H1_BARS"; return false; }
   if(unknownHours>0)
     { g466.historyStatus="ACTIVITY_HISTORY_PENDING"; return false; }
   // Current-hour freshness is also based on observed activity, not weekly metadata.
   datetime currentHour=(datetime)((long)now-((long)now%3600));
   if(ICC466_TradingDay(now) && rates[copied-1].time!=currentHour)
     {
      if(!minutesLoaded)
        {
         int minuteCount=CopyRates(_Symbol,PERIOD_M1,rates[0].time,now,minutes);
         if(minuteCount<0) ArrayResize(minutes,0);
        }
      int activity=ICC466_HistoricalActivity(currentHour,(ulong)now*1000,minutes);
      if(activity>0) { g466.historyStatus="STALE_ACTIVE_H1_BAR"; return false; }
      if(activity<0) { g466.historyStatus="ACTIVITY_HISTORY_PENDING"; return false; }
     }
   if(SeriesInfoInteger(_Symbol,PERIOD_H1,SERIES_SYNCHRONIZED)==0)
     { g466.historyAvailable=false; g466.historyStatus="HISTORY_PENDING"; return false; }
   g466.historyStatus="READY";
   return true;
  }

void ICC466_H1Markup(datetime now,double price)
  {
   ZeroMemory(g466.h1Swings);
   int strength=InpIntSwingStrength,nh=0,nl=0;
   int boundary=iBarShift(_Symbol,PERIOD_H1,g466.contextStart,false);
   // Three weekdays is a MINIMUM horizon; retain the existing broader lookback.
   int end=MathMin(MathMax(boundary,InpStructLookback),Bars(_Symbol,PERIOD_H1)-strength-1);
   g466.scanStart=end>=strength+1?iTime(_Symbol,PERIOD_H1,end):0;
   bool selectedHigh=false,selectedLow=false;
   for(int k=strength+1;k<=end;k++)
     {
      datetime t=iTime(_Symbol,PERIOD_H1,k),known=iTime(_Symbol,PERIOD_H1,k-strength-1);
      if(t<=0 || !ICC466_TradingDay(t) || known<=0 || known>now || known<=t) continue;
      if(IsPivotHighTF(PERIOD_H1,k,strength))
        {
         double high=iHigh(_Symbol,PERIOD_H1,k);
         if(nh==0) { g466.h1Swings.hi=high; g466.h1Swings.hiT=t; g466.h1Swings.hiKnown=known; }
         if(nh==1) { g466.h1Swings.prevHi=high; g466.h1Swings.prevHiT=t; g466.h1Swings.prevHiKnown=known; }
         nh++;
         // A crossing never discards the pre-break level. Replacement requires a
         // newer confirmed pivot, and after a crossing, confirmation AFTER that event.
         if(!selectedHigh && price>0 && high>=price && t>g466.activeH1HighTime &&
            (!g466.activeH1HighCrossed || known>g466.activeH1HighCrossTime))
           {
            g466.activeH1High=high; g466.activeH1HighTime=t; g466.activeH1HighKnownTime=known;
            g466.activeH1HighSelectedTime=now; g466.activeH1HighCrossed=false; g466.activeH1HighCrossTime=0;
            selectedHigh=true;
           }
        }
      if(IsPivotLowTF(PERIOD_H1,k,strength))
        {
         double low=iLow(_Symbol,PERIOD_H1,k);
         if(nl==0) { g466.h1Swings.lo=low; g466.h1Swings.loT=t; g466.h1Swings.loKnown=known; }
         if(nl==1) { g466.h1Swings.prevLo=low; g466.h1Swings.prevLoT=t; g466.h1Swings.prevLoKnown=known; }
         nl++;
         if(!selectedLow && price>0 && low<=price && t>g466.activeH1LowTime &&
            (!g466.activeH1LowCrossed || known>g466.activeH1LowCrossTime))
           {
            g466.activeH1Low=low; g466.activeH1LowTime=t; g466.activeH1LowKnownTime=known;
            g466.activeH1LowSelectedTime=now; g466.activeH1LowCrossed=false; g466.activeH1LowCrossTime=0;
            selectedLow=true;
           }
        }
     }
  }

void ICC466_ObserveCrossings(datetime now,double price)
  {
   // Diagnostic price crossings only: no formal-close/Indication authority.
   // Runs BEFORE reselection, preserving a level already known and selected.
   if(price<=0) return;
   if(g466.activeH1High>0 && !g466.activeH1HighCrossed && price>g466.activeH1High)
     {
      g466.activeH1HighCrossed=true; g466.activeH1HighCrossTime=now;
      g466.preBreakH1High=g466.activeH1High; g466.preBreakH1HighTime=g466.activeH1HighTime;
      g466.preBreakH1HighKnownTime=g466.activeH1HighKnownTime;
      g466.preBreakH1HighSelectedTime=g466.activeH1HighSelectedTime; g466.preBreakH1HighCrossTime=now;
     }
   if(g466.activeH1Low>0 && !g466.activeH1LowCrossed && price<g466.activeH1Low)
     {
      g466.activeH1LowCrossed=true; g466.activeH1LowCrossTime=now;
      g466.preBreakH1Low=g466.activeH1Low; g466.preBreakH1LowTime=g466.activeH1LowTime;
      g466.preBreakH1LowKnownTime=g466.activeH1LowKnownTime;
      g466.preBreakH1LowSelectedTime=g466.activeH1LowSelectedTime; g466.preBreakH1LowCrossTime=now;
     }
  }


// Phase 2 CM-08/11. H1 reuses the Phase-1 latched active levels. An explicitly
// H4-owned setup gets equivalent active boundaries from wick-defined pivots.
// This is structural selection only; it does not create an Indication.
bool ICC466_ScanActiveSetupBounds(ENUM_TIMEFRAMES tf,datetime now,double reference,
                                  double &high,datetime &highTime,datetime &highKnown,
                                  double &low,datetime &lowTime,datetime &lowKnown)
  {
   high=0; low=0; highTime=0; lowTime=0; highKnown=0; lowKnown=0;
   if(tf==PERIOD_H1)
     {
      high=g466.activeH1High; highTime=g466.activeH1HighTime; highKnown=g466.activeH1HighKnownTime;
      low=g466.activeH1Low; lowTime=g466.activeH1LowTime; lowKnown=g466.activeH1LowKnownTime;
      return high>0 && low>0;
     }

   int strength=(tf==PERIOD_H4?InpExtSwingStrength:InpIntSwingStrength);
   int end=MathMin(InpStructLookback,Bars(_Symbol,tf)-strength-1);
   for(int k=strength+1;k<=end && (high<=0 || low<=0);k++)
     {
      datetime t=iTime(_Symbol,tf,k),known=iTime(_Symbol,tf,k-strength-1);
      if(t<=0 || known<=0 || known>now || known<=t) continue;
      if(high<=0 && IsPivotHighTF(tf,k,strength))
        {
         double p=iHigh(_Symbol,tf,k);
         if(reference<=0 || p>=reference) { high=p; highTime=t; highKnown=known; }
        }
      if(low<=0 && IsPivotLowTF(tf,k,strength))
        {
         double p=iLow(_Symbol,tf,k);
         if(reference<=0 || p<=reference) { low=p; lowTime=t; lowKnown=known; }
        }
     }
   return high>0 && low>0;
  }

void ICC466_RefreshSetupZone(datetime now)
  {
   double reference=iClose(_Symbol,g466.setupTF,1);
   if(reference<=0) reference=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   ICC466_ScanActiveSetupBounds(g466.setupTF,now,reference,
      g466.activeSetupHigh,g466.activeSetupHighTime,g466.activeSetupHighKnownTime,
      g466.activeSetupLow,g466.activeSetupLowTime,g466.activeSetupLowKnownTime);

   g466.noTradeZone=false;
   if(g465.indication!=I465_NONE)
     { g466.noTradeReason="INDICATION_ACTIVE"; return; }
   if(g466.activeSetupHigh<=0 || g466.activeSetupLow<=0 ||
      g466.activeSetupHigh<=g466.activeSetupLow || reference<=0)
     { g466.noTradeReason="ACTIVE_SETUP_BOUNDARY_UNAVAILABLE"; return; }

   // Formal-close authority: equality is still inside because no strict break exists.
   g466.noTradeZone=(reference<=g466.activeSetupHigh && reference>=g466.activeSetupLow);
   g466.noTradeReason=g466.noTradeZone?"BETWEEN_ACTIVE_SETUP_SWINGS":"OUTSIDE_ACTIVE_SETUP_SWINGS_AWAIT_FORMAL_BREAK";
  }

string ICC466_State(const S465Swings &sw,int direction)
  {
   if(sw.hi<=0 || sw.prevHi<=0 || sw.lo<=0 || sw.prevLo<=0) return "INSUFFICIENT_PAIRED_SWINGS";
   return direction>0?"BULLISH_HH_HL":direction<0?"BEARISH_LL_LH":"NEUTRAL_CONSOLIDATING";
  }

string ICC466_Time(datetime value)
  {
   return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):"";
  }

void ICC466_Trace()
  {
   if(g466TraceFile=="") return;
   string row=ML_v4_CsvField(_Symbol)+","+EnumToString(g466.setupTF)+","+EnumToString(g466.contextTF)+","+EnumToString(g466.entryTF)
      +","+IntegerToString(g466.setupDirection)+","+IntegerToString(g466.contextDirection)
      +","+DoubleToString(g466.activeH1High,_Digits)+","+ICC466_Time(g466.activeH1HighTime)+","+ICC466_Time(g466.activeH1HighKnownTime)
      +","+DoubleToString(g466.activeH1Low,_Digits)+","+ICC466_Time(g466.activeH1LowTime)+","+ICC466_Time(g466.activeH1LowKnownTime)
      +","+ICC466_Time(g466.contextStart)+","+ICC466_Time(g466.tradeEnableTime)+","+(g466.tradeEnabled?"1":"0")
      +","+ICC466_State(g466.h1Swings,g466.h1Direction)+","+ICC466_State(g466.h4Swings,g466.h4Direction)
      +","+ICC466_Time(g466.historyFirst)+","+(g466.historyAvailable?"1":"0")+","+(g466.contextReady?"1":"0")
      +","+ICC466_Time(InpTradeEnableTime)+","+IntegerToString(g466.h1Direction)+","+IntegerToString(g466.h4Direction)
      +","+g466.historyStatus+","+IntegerToString(g466.expectedH1Bars)+","+IntegerToString(g466.missingH1Bars)
      +","+ICC466_Time(g466.scanStart)+","+ICC466_Time(g466.structureAsOf)
      +","+ICC466_Time(g466.activeH1HighSelectedTime)+","+ICC466_Time(g466.activeH1LowSelectedTime)
      +","+(g466.activeH1HighCrossed?"1":"0")+","+(g466.activeH1LowCrossed?"1":"0")
      +","+DoubleToString(g466.preBreakH1High,_Digits)+","+ICC466_Time(g466.preBreakH1HighTime)
      +","+ICC466_Time(g466.preBreakH1HighKnownTime)+","+ICC466_Time(g466.preBreakH1HighSelectedTime)+","+ICC466_Time(g466.preBreakH1HighCrossTime)
      +","+DoubleToString(g466.preBreakH1Low,_Digits)+","+ICC466_Time(g466.preBreakH1LowTime)
      +","+ICC466_Time(g466.preBreakH1LowKnownTime)+","+ICC466_Time(g466.preBreakH1LowSelectedTime)+","+ICC466_Time(g466.preBreakH1LowCrossTime)
      +","+DoubleToString(g466.activeSetupHigh,_Digits)+","+ICC466_Time(g466.activeSetupHighTime)+","+ICC466_Time(g466.activeSetupHighKnownTime)
      +","+DoubleToString(g466.activeSetupLow,_Digits)+","+ICC466_Time(g466.activeSetupLowTime)+","+ICC466_Time(g466.activeSetupLowKnownTime)
      +","+(g466.noTradeZone?"1":"0")+","+ML_v4_CsvField(g466.noTradeReason)
      +","+ML_v4_CsvField(EnumToString(g466.lastBreakTF))+","+IntegerToString(g466.lastBreakDir)
      +","+DoubleToString(g466.lastBreakLevel,_Digits)+","+ICC466_Time(g466.lastBreakLevelTime)
      +","+ICC466_Time(g466.lastBreakKnownTime)+","+ICC466_Time(g466.lastBreakTime)
      +","+(g466.lastRule3Pass?"1":"0");
   // Exclude tick time from key: identical M15/tick observations produce no duplicate rows.
   if(row==g466LastTraceKey) return;
   int h=FileOpen(g466TraceFile,FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h==INVALID_HANDLE) { Print("[ICC466] structure CSV open failed: ",GetLastError()); return; }
   if(FileSize(h)==0) FileWriteString(h,"time,symbol,setup_tf,context_tf,entry_tf,setup_direction,context_direction,active_H1_high,active_H1_high_time,active_H1_high_known_time,active_H1_low,active_H1_low_time,active_H1_low_known_time,context_start,trade_enable_time,trade_enabled,H1_structure_state,H4_structure_state,history_first,history_available,context_ready,requested_trade_enable_time,H1_direction,H4_direction,history_status,expected_H1_bars,missing_H1_bars,scan_start,structure_asof,active_H1_high_selected_time,active_H1_low_selected_time,active_H1_high_crossed,active_H1_low_crossed,pre_break_H1_high,pre_break_H1_high_time,pre_break_H1_high_known_time,pre_break_H1_high_selected_time,pre_break_H1_high_cross_time,pre_break_H1_low,pre_break_H1_low_time,pre_break_H1_low_known_time,pre_break_H1_low_selected_time,pre_break_H1_low_cross_time,active_setup_high,active_setup_high_time,active_setup_high_known_time,active_setup_low,active_setup_low_time,active_setup_low_known_time,no_trade_zone,no_trade_reason,last_break_tf,last_break_dir,last_break_level,last_break_level_time,last_break_known_time,last_break_time,last_rule3_pass\r\n");
   FileSeek(h,0,SEEK_END);
   uint written=FileWriteString(h,ICC466_Time(TimeCurrent())+","+row+"\r\n");
   FileClose(h);
   if(written>0) g466LastTraceKey=row;
  }

void ICC466_UpdateStructure()
  {
   datetime now=TimeCurrent();
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   ICC466_ObserveCrossings(now,price);
   datetime h1=iTime(_Symbol,PERIOD_H1,0),h4=iTime(_Symbol,PERIOD_H4,0);
   datetime d1=g466.contextTF==PERIOD_D1?iTime(_Symbol,PERIOD_D1,0):0;
   datetime contextStart=ICC466_ContextStart(now);
   datetime currentHour=(datetime)((long)now-((long)now%3600));
   if(SeriesInfoInteger(_Symbol,PERIOD_H1,SERIES_SYNCHRONIZED)==0)
     { g466.contextReady=false; g466.historyAvailable=false; g466.historyStatus="HISTORY_PENDING"; }
   bool structuralClock=(h1!=g466.lastH1Bar || h4!=g466.lastH4Bar || d1!=g466.lastD1Bar ||
                         currentHour!=g466.lastCheckedHour || contextStart!=g466.contextStart);
   // Retry incomplete asynchronous history at deterministic five-second server-time
   // intervals. Cheap crossing observation and trade-enable evaluation still run each tick.
   if(structuralClock || (!g466.contextReady && now>=g466.nextHistoryRetry))
     {
      g466.contextStart=contextStart;
      g466.contextReady=ICC466_ContextAvailable(now);
      if(g466.contextReady)
        {
         ICC466_H1Markup(now,price);
         g466.structureAsOf=now;
        }
      ICC465_Swings(PERIOD_H4,InpExtSwingStrength,0,g466.h4Swings);
      g466.h1Direction=ICC465_Direction(g466.h1Swings);
      g466.h4Direction=ICC465_Direction(g466.h4Swings);
      if(g466.setupTF==PERIOD_H1) g466.setupSwings=g466.h1Swings;
      else g466.setupSwings=g466.h4Swings;
      if(g466.contextTF==PERIOD_H4) g466.contextSwings=g466.h4Swings;
      else ICC465_Swings(PERIOD_D1,InpExtSwingStrength,0,g466.contextSwings);
      g466.setupDirection=ICC465_Direction(g466.setupSwings);
      g466.contextDirection=ICC465_Direction(g466.contextSwings);
      g466.lastH1Bar=h1; g466.lastH4Bar=h4; g466.lastD1Bar=d1;
      g466.lastCheckedHour=currentHour;
      g466.nextHistoryRetry=now+5;
     }
   g466.tradeEnabled=(g466.contextReady && now>=InpTradeEnableTime);
   if(g466.tradeEnabled && g466.tradeEnableTime==0) g466.tradeEnableTime=now;
   ICC466_RefreshSetupZone(now);
   ICC466_Trace();
  }

// v4.6.5 STAGES 1-3: structural authority, chronology, mandatory phase evidence.
// RB 4,19. Same validated-neighbor pivot algorithm as frozen baseline.
void ICC465_Swings(ENUM_TIMEFRAMES tf,int strength,datetime since,S465Swings &s)
  {
   ZeroMemory(s);
   int nh=0,nl=0;
   int end=MathMin(InpStructLookback,Bars(_Symbol,tf)-strength-1);
   for(int k=strength+1;k<=end && (nh<2 || nl<2);k++)
     {
      datetime t=iTime(_Symbol,tf,k), known=iTime(_Symbol,tf,k-strength-1);
      if(t<=0 || known<=0 || (since>0 && t<since)) break;
      if(nh<2 && IsPivotHighTF(tf,k,strength))
        {
         if(nh==0) { s.hi=iHigh(_Symbol,tf,k); s.hiT=t; s.hiKnown=known; }
         else { s.prevHi=iHigh(_Symbol,tf,k); s.prevHiT=t; s.prevHiKnown=known; }
         nh++;
        }
      if(nl<2 && IsPivotLowTF(tf,k,strength))
        {
         if(nl==0) { s.lo=iLow(_Symbol,tf,k); s.loT=t; s.loKnown=known; }
         else { s.prevLo=iLow(_Symbol,tf,k); s.prevLoT=t; s.prevLoKnown=known; }
         nl++;
        }
     }
  }

// RB 4,19: paired HH/HL or LL/LH after a prior opposing swing; never a lone BOS.
int ICC465_Direction(const S465Swings &s)
  {
   if(s.hi<=0 || s.lo<=0 || s.prevHi<=0 || s.prevLo<=0) return 0;
   if(s.hi>s.prevHi && s.lo>s.prevLo && s.hiT>s.prevLoT) return 1;
   if(s.hi<s.prevHi && s.lo<s.prevLo && s.loT>s.prevHiT) return -1;
   return 0;
  }

// RB 13,15. Separate state/evidence schema; old tensors cannot silently gain columns.
string ICC466_TargetSourceText(int code)
  {
   if(code==1) return "ACTIVE_INDICATION_EXTREME";
   if(code==2) return "HIGHER_CONTEXT_SWING";
   return "NONE";
  }

// Phase 5 CM-27: attach prior completed same-direction setup lineage AFTER a new
// structural Indication has already been accepted by the unchanged Phase-2 authority.
void ICC466_AttachCycleLineage()
  {
   g465.parentSetupId=0; g465.nextSetupId=0; g465.lineageSeedExtreme=0;
   if(!g466Cycle.ready || g465.id<=0 || g465.dir==0) return;
   // An opposite/other-owner structural Indication breaks the prior trend-cycle lineage.
   if(g466Cycle.dir!=g465.dir || g466Cycle.ownerTF!=g465.indTF) { g466Cycle.ready=false; return; }
   if(g465.indStart<=g466Cycle.continuationTime) return;
   g465.parentSetupId=g466Cycle.setupId;
   g465.lineageSeedExtreme=g466Cycle.indicationExtreme;
   // On this one lineage event, next_setup_id is the newly-created child setup.
   g465.nextSetupId=g465.id;
   ICC465_Log("CYCLE_PARENT_NEXT_LINK","LINEAGE");
   g465.nextSetupId=0;
  }

// Phase 5 CM-27: a confirmed setup-timeframe Continuation completes a structural
// ICC cycle for lineage purposes, independently of whether execution is later filled.
void ICC466_CommitCycleLineage()
  {
   if(g465.id<=0 || g465.continuation!=T465_CONFIRMED_LTF || g465.contTime<=0 || g465.indTF==PERIOD_CURRENT) return;
   g466Cycle.setupId=g465.id;
   g466Cycle.continuationTime=g465.contTime;
   g466Cycle.dir=g465.dir;
   g466Cycle.ownerTF=g465.indTF;
   g466Cycle.indicationExtreme=(g465.dir>0?g465.indHigh:g465.indLow);
   g466Cycle.ready=(g466Cycle.indicationExtreme>0);
   ICC465_Log("CYCLE_READY_FOR_NEXT_INDICATION","LINEAGE");
  }

void ICC465_Log(string code,string event)
  {
   g465.reason=code;
   PrintFormat("[ICC465] %s %s setup=%I64d parent=%I64d next=%I64d GSTF=%s obs=%s entry=%s zone=%s dir=%d %s/%s/%s/%s key=%.8f boundary=%.8f close=%.8f",
      event,code,(long)g465.id,(long)g465.parentSetupId,(long)g465.nextSetupId,
      EnumToString(g465.gstf),EnumToString(g465.observationTF),EnumToString(g465.entryTF),
      EnumToString(g465.zoneTF),g465.dir,
      EnumToString(g465.indication),EnumToString(g465.correction),EnumToString(g465.continuation),EnumToString(g465.entry),
      g465.keyLevel,g465.boundary,g465.zoneClose);
   if(g465TraceFile=="") return;
   int h=FileOpen(g465TraceFile,FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h==INVALID_HANDLE) { Print("[ICC465] CSV OPEN FAILED ",GetLastError()); return; }
   if(FileSize(h)==0)
      FileWriteString(h,"schema,run_id,event,reason,time,symbol,account_currency,setup_id,gstf,observation_tf,entry_tf,zone_tf,ind_tf,dir,indication,correction,continuation,entry,validity,ind_start,ind_end,correction_start,sweep_time,shift_time,aoi_touch_time,continuation_time,protected_high,protected_low,key,boundary_1pct,actual_close,body_ratio,upper_body,lower_body,wick_range,body_cutoff,wick_cutoff,fvg_low,fvg_high,fvg_mid,fvg_mitigation,correction_low,correction_high,retracement_observed,liquidity_type,liquidity_level,liquidity_level_time,penetration_time,penetration_extreme,reclaim_close,aoi_low,aoi_high,aoi_created,aoi_tf,aoi_valid,aoi_touched,impulse_points,impulse_pips,impulse_money_one_lot,ote_low_anchor,ote_high_anchor,ote_origin_time,ote_endpoint_time,ote_break_time,ote_tf,governing_swing_sequence,broken_level,setup_owner_tf,no_trade_zone,active_setup_high,active_setup_low,parent_setup_id,next_setup_id,lineage_seed_extreme,structural_target,target_tf,target_source,context_tf,continuation_level,continuation_tf,correction_confirm_time,entry_evidence_level,entry_evidence_time,no_trade_reason\r\n");
   double money=0;
   if(g465.indHigh>g465.indLow && g465.indLow>0)
      if(!OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,1.0,g465.indLow,g465.indHigh,money)) money=0;
   FileSeek(h,0,SEEK_END);
   string row="";
   row+=ML_v4_CsvField("ICC467_STATE_4") + ",";
   row+=ML_v4_CsvField(g_mlRunId) + ",";
   row+=ML_v4_CsvField(event) + ",";
   row+=ML_v4_CsvField(code) + ",";
   row+=ML_v4_CsvField(TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)) + ",";
   row+=ML_v4_CsvField(_Symbol) + ",";
   row+=ML_v4_CsvField(AccountInfoString(ACCOUNT_CURRENCY)) + ",";
   row+=DoubleToString((long)g465.id,16) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.gstf)) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.observationTF)) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.entryTF)) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.zoneTF)) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.indTF)) + ",";
   row+=DoubleToString(g465.dir,16) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.indication)) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.correction)) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.continuation)) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.entry)) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.validity)) + ",";
   row+=DoubleToString((long)g465.indStart,16) + ",";
   row+=DoubleToString((long)g465.indEnd,16) + ",";
   row+=DoubleToString((long)g465.corrStart,16) + ",";
   row+=DoubleToString((long)g465.sweepTime,16) + ",";
   row+=DoubleToString((long)g465.shiftTime,16) + ",";
   row+=DoubleToString((long)g465.aoiTouchTime,16) + ",";
   row+=DoubleToString((long)g465.contTime,16) + ",";
   row+=DoubleToString(g465.protectedHigh,16) + ",";
   row+=DoubleToString(g465.protectedLow,16) + ",";
   row+=DoubleToString(g465.keyLevel,16) + ",";
   row+=DoubleToString(g465.boundary,16) + ",";
   row+=DoubleToString(g465.zoneClose,16) + ",";
   row+=DoubleToString(g465.bodyRatio,16) + ",";
   row+=DoubleToString(g465.upperBody,16) + ",";
   row+=DoubleToString(g465.lowerBody,16) + ",";
   row+=DoubleToString(g465.wickRange,16) + ",";
   row+=DoubleToString(InpRule3BodyRatio,16) + ",";
   row+=DoubleToString(InpRule3MaxWickRange,16) + ",";
   row+=DoubleToString(g465.fvgLow,16) + ",";
   row+=DoubleToString(g465.fvgHigh,16) + ",";
   row+=DoubleToString(g465.fvgMid,16) + ",";
   row+=DoubleToString(g465.fvgMitigation,16) + ",";
   row+=DoubleToString(g465.corrLow,16) + ",";
   row+=DoubleToString(g465.corrHigh,16) + ",";
   row+=DoubleToString(g465.retrace,16) + ",";
   row+=ML_v4_CsvField(g465.liquidityType) + ",";
   row+=DoubleToString(g465.sweepLevel,16) + ",";
   row+=DoubleToString((long)g465.sweepLevelTime,16) + ",";
   row+=DoubleToString((long)g465.sweepPenetrationTime,16) + ",";
   row+=DoubleToString(g465.sweepExtreme,16) + ",";
   row+=DoubleToString(g465.reclaimClose,16) + ",";
   row+=DoubleToString(g465.aoiLow,16) + ",";
   row+=DoubleToString(g465.aoiHigh,16) + ",";
   row+=DoubleToString((long)g465.aoiCreated,16) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.aoiTF)) + ",";
   row+=DoubleToString((int)g465.aoiValid,16) + ",";
   row+=DoubleToString((int)g465.aoiTouched,16) + ",";
   row+=DoubleToString((g465.indHigh-g465.indLow)/_Point,16) + ",";
   row+=DoubleToString((g_pip>0?(g465.indHigh-g465.indLow)/g_pip:0),16) + ",";
   row+=DoubleToString(money,16) + ",";
   row+=DoubleToString(g465.oteLowAnchor,16) + ",";
   row+=DoubleToString(g465.oteHighAnchor,16) + ",";
   row+=DoubleToString((long)g465.oteOriginTime,16) + ",";
   row+=DoubleToString((long)g465.oteEndTime,16) + ",";
   row+=DoubleToString((long)g465.oteBreakTime,16) + ",";
   row+=ML_v4_CsvField(EnumToString(g465.entryTF)) + ",";
   row+=ML_v4_CsvField(StringFormat("hi=%.8f@%I64d;prev_hi=%.8f@%I64d;lo=%.8f@%I64d;prev_lo=%.8f@%I64d",
         g465.governing.hi,(long)g465.governing.hiT,g465.governing.prevHi,(long)g465.governing.prevHiT,
         g465.governing.lo,(long)g465.governing.loT,g465.governing.prevLo,(long)g465.governing.prevLoT))+",";
   row+=DoubleToString(g465.brokenLevel,16)+","+ML_v4_CsvField(EnumToString(g466.setupTF))+","+
        DoubleToString((int)g466.noTradeZone,16)+","+DoubleToString(g466.activeSetupHigh,16)+","+
        DoubleToString(g466.activeSetupLow,16)+","+DoubleToString((long)g465.parentSetupId,16)+","+
        DoubleToString((long)g465.nextSetupId,16)+","+DoubleToString(g465.lineageSeedExtreme,16)+","+
        DoubleToString(g465.structuralTarget,16)+","+ML_v4_CsvField(EnumToString(g465.structuralTargetTF))+","+
        ML_v4_CsvField(ICC466_TargetSourceText(g465.structuralTargetSource))+","+
        ML_v4_CsvField(EnumToString(InpContextTF))+","+
        DoubleToString(g465.continuationLevel,16)+","+ML_v4_CsvField(EnumToString(g465.continuationTF))+","+
        DoubleToString((long)g465.corrConfirmTime,16)+","+DoubleToString(g465.entryEvidenceLevel,16)+","+
        DoubleToString((long)g465.entryEvidenceTime,16)+","+ML_v4_CsvField(g466.noTradeReason)+"\r\n";
   uint wrote=FileWriteString(h,row);
   if(wrote==0) Print("[ICC465] CSV WRITE FAILED ",GetLastError());
   FileClose(h);
  }

// Phase 2 CM-06. Legacy 80/20 candle-shape measurement retained for telemetry/confluence.
// It does not authorize or veto Indication.
int ICC465_CandleTest(double open,double close,double high,double low,int dir,double bodyMin,double wickMax)
  {
   double range=high-low,body=MathAbs(close-open);
   if(open<=0 || close<=0 || low<=0 || range<=0 || body<=0 || high<MathMax(open,close) || low>MathMin(open,close) || dir*(close-open)<=0) return 1;
   if(body/range+1e-12<bodyMin) return 2;
   if(wickMax<0) return 3;
   if((range-body)/range-wickMax>1e-12) return 4;
   return 0;
  }

// RB 9: equality is NOT invalidation. This helper is shared with boundary tests.
bool ICC465_ClosedBeyond(int dir,double close,double key,double fraction)
  {
   if(key<=0 || close<=0) return false;
   double boundary=key*(1.0-dir*fraction);
   return dir*(close-boundary)<0;
  }

bool ICC465_Rule3(ENUM_TIMEFRAMES tf,int dir)
  {
   // Phase 2 CM-06/07: Rule-of-Three is telemetry/confluence only.
   // It may describe candle quality, but it cannot authorize or veto Indication.
   if(Bars(_Symbol,tf)<5)
     {
      ICC465_Log("RULE3_TELEMETRY_HISTORY_PENDING","EVIDENCE_ONLY");
      return false;
     }
   bool allPass=true;
   for(int k=3;k>=1;k--)
     {
      double o=iOpen(_Symbol,tf,k),c=iClose(_Symbol,tf,k),hi=iHigh(_Symbol,tf,k),lo=iLow(_Symbol,tf,k);
      double body=MathAbs(c-o),range=hi-lo;
      int outcome=ICC465_CandleTest(o,c,hi,lo,dir,InpRule3BodyRatio,InpRule3MaxWickRange);
      if(range>0 && body>0)
        {
         g465.bodyRatio=body/range;
         g465.upperBody=(hi-MathMax(o,c))/body;
         g465.lowerBody=(MathMin(o,c)-lo)/body;
         g465.wickRange=(range-body)/range;
        }
      string code="RULE3_TELEMETRY_PASS";
      if(outcome==1) code="RULE3_TELEMETRY_DIRECTION_OR_DATA_FAIL";
      else if(outcome==2) code="RULE3_TELEMETRY_BODY_FAIL";
      else if(outcome==3) code="RULE3_TELEMETRY_WICK_CONFIG_FAIL";
      else if(outcome==4) code="RULE3_TELEMETRY_WICK_FAIL";
      if(outcome!=0) allPass=false;
      ICC465_Log(code+"_"+EnumToString(tf)+"_SHIFT_"+IntegerToString(k),"EVIDENCE_ONLY");
     }
   ICC465_Log(allPass?"RULE3_TELEMETRY_SEQUENCE_PASS":"RULE3_TELEMETRY_SEQUENCE_FAIL","EVIDENCE_ONLY");
   return allPass;
  }

// RB 5: at least three; include any earlier adjacent qualifying bodies in the same run.
int ICC465_RunStart(ENUM_TIMEFRAMES tf,int dir)
  {
   int oldest=3,end=MathMin(InpStructLookback,Bars(_Symbol,tf)-2);
   for(int k=4;k<=end;k++)
     {
      if(ICC465_CandleTest(iOpen(_Symbol,tf,k),iClose(_Symbol,tf,k),iHigh(_Symbol,tf,k),iLow(_Symbol,tf,k),
         dir,InpRule3BodyRatio,InpRule3MaxWickRange)!=0) break;
      oldest=k;
     }
   return oldest;
  }

// RB 4-5. Protected break level must have been knowable before displacement starts.
bool ICC465_BreakLevel(ENUM_TIMEFRAMES tf,int dir,double &level,
                       datetime &levelTime,datetime &knownTime,datetime &breakTime)
  {
   // Phase 2 CM-08: the active wick-defined swing is direct Indication authority.
   // Formal-close confirmation is deliberately retained; no Rule3 timing anchor exists.
   level=0; levelTime=0; knownTime=0; breakTime=0;
   if(Bars(_Symbol,tf)<4) return false;
   breakTime=iTime(_Symbol,tf,1);
   double closeNow=iClose(_Symbol,tf,1),closePrev=iClose(_Symbol,tf,2);
   if(breakTime<=0 || closeNow<=0 || closePrev<=0) return false;

   if(tf==PERIOD_H1 && g466.setupTF==PERIOD_H1)
     {
      datetime selected=0;
      if(dir>0)
        {
         // Prefer the latched pre-break snapshot so a tick crossing cannot erase
         // the exact level whose subsequent H1 close confirms Indication.
         if(g466.preBreakH1High>0)
           {
            level=g466.preBreakH1High; levelTime=g466.preBreakH1HighTime;
            knownTime=g466.preBreakH1HighKnownTime; selected=g466.preBreakH1HighSelectedTime;
           }
         else
           {
            level=g466.activeH1High; levelTime=g466.activeH1HighTime;
            knownTime=g466.activeH1HighKnownTime; selected=g466.activeH1HighSelectedTime;
           }
        }
      else
        {
         if(g466.preBreakH1Low>0)
           {
            level=g466.preBreakH1Low; levelTime=g466.preBreakH1LowTime;
            knownTime=g466.preBreakH1LowKnownTime; selected=g466.preBreakH1LowSelectedTime;
           }
         else
           {
            level=g466.activeH1Low; levelTime=g466.activeH1LowTime;
            knownTime=g466.activeH1LowKnownTime; selected=g466.activeH1LowSelectedTime;
           }
        }
      if(level<=0 || levelTime<=0 || knownTime<=0 || selected<=0) return false;
      if(knownTime>breakTime || selected>breakTime) return false; // level had to be known/active first
      return dir*(closePrev-level)<=0 && dir*(closeNow-level)>0;
     }

   // Explicit H4-owned setup path: select the newest eligible pivot that the
   // most recently CLOSED setup bar crosses for the first time.
   int strength=(tf==PERIOD_H4?InpExtSwingStrength:InpIntSwingStrength);
   int end=MathMin(InpStructLookback,Bars(_Symbol,tf)-strength-1);
   for(int k=strength+1;k<=end;k++)
     {
      datetime t=iTime(_Symbol,tf,k),known=iTime(_Symbol,tf,k-strength-1);
      if(t<=0 || known<=0 || known>breakTime || known<=t) continue;
      bool pivot=(dir>0?IsPivotHighTF(tf,k,strength):IsPivotLowTF(tf,k,strength));
      if(!pivot) continue;
      double candidate=(dir>0?iHigh(_Symbol,tf,k):iLow(_Symbol,tf,k));
      if(candidate<=0) continue;
      if(dir*(closePrev-candidate)<=0 && dir*(closeNow-candidate)>0)
        {
         level=candidate; levelTime=t; knownTime=known;
         return true;
        }
     }
   return false;
  }

// SD05: return paired structure that existed BEFORE a candidate source candle.
int ICC465_PreEventDirection(ENUM_TIMEFRAMES tf,int sourceShift)
  {
   int strength=(tf==InpGSTF?InpExtSwingStrength:InpMinorPivotStrength);
   double h1=0,h2=0,l1=0,l2=0; datetime h1t=0,h2t=0,l1t=0,l2t=0;
   int end=MathMin(InpStructLookback,Bars(_Symbol,tf)-strength-1);
   for(int k=sourceShift+1;k<=end && (h2==0 || l2==0);k++)
     {
      if(h2==0 && IsPivotHighTF(tf,k,strength))
        { if(h1==0){h1=iHigh(_Symbol,tf,k);h1t=iTime(_Symbol,tf,k);} else {h2=iHigh(_Symbol,tf,k);h2t=iTime(_Symbol,tf,k);} }
      if(l2==0 && IsPivotLowTF(tf,k,strength))
        { if(l1==0){l1=iLow(_Symbol,tf,k);l1t=iTime(_Symbol,tf,k);} else {l2=iLow(_Symbol,tf,k);l2t=iTime(_Symbol,tf,k);} }
     }
   if(h1<=0 || h2<=0 || l1<=0 || l2<=0) return 0;
   if(h1>h2 && l1>l2 && h1t>l2t) return 1;
   if(h1<h2 && l1<l2 && l1t>h2t) return -1;
   return 0;
  }

// SD05 displacement-quality score (0..10). This score NEVER qualifies Indication;
// legacy AOI quality ranking remains frozen for later confluence-authority work.
double ICC465_AOIDisplacementScore(ENUM_TIMEFRAMES tf,int sourceShift,int dir)
  {
   double bodySum=0,wickSum=0,overlapSum=0; int n=0;
   for(int k=sourceShift-1;k>=sourceShift-3;k--)
     {
      double o=iOpen(_Symbol,tf,k),c=iClose(_Symbol,tf,k),h=iHigh(_Symbol,tf,k),l=iLow(_Symbol,tf,k),r=h-l;
      if(r<=0 || ICC465_CandleTest(o,c,h,l,dir,InpRule3BodyRatio,InpRule3MaxWickRange)!=0) return -1;
      bodySum+=MathAbs(c-o)/r; wickSum+=(r-MathAbs(c-o))/r; n++;
      if(k<sourceShift-1)
        {
         double ph=iHigh(_Symbol,tf,k+1),pl=iLow(_Symbol,tf,k+1);
         double ov=MathMax(0.0,MathMin(h,ph)-MathMax(l,pl));
         overlapSum+=ov/MathMax(r,ph-pl);
        }
     }
   if(n!=3) return -1;
   double bodyQ=MathMax(0.0,MathMin(1.0,(bodySum/3.0-0.80)/0.20));
   double wickQ=MathMax(0.0,MathMin(1.0,1.0-(wickSum/3.0)/0.20));
   double overlapQ=MathMax(0.0,MathMin(1.0,1.0-overlapSum/2.0));
   // Transparent 0..10 ranking: 4 body dominance + 2 wick cleanliness + 2 low overlap
   // + 1 qualifying three-candle impulse + 1 structural break (both prerequisites).
   return 4.0*bodyQ+2.0*wickQ+2.0*overlapQ+2.0;
  }

bool ICC465_AOIBreak(ENUM_TIMEFRAMES tf,int sourceShift,int dir,double &broken)
  {
   broken=0; int strength=(tf==InpGSTF?InpExtSwingStrength:InpMinorPivotStrength);
   int end=MathMin(InpStructLookback,Bars(_Symbol,tf)-strength-1);
   for(int k=sourceShift+1;k<=end;k++)
     {
      bool p=dir>0?IsPivotHighTF(tf,k,strength):IsPivotLowTF(tf,k,strength);
      if(!p) continue;
      double level=dir>0?iHigh(_Symbol,tf,k):iLow(_Symbol,tf,k);
      bool crossed=false;
      for(int b=sourceShift-1;b>=sourceShift-3;b--) if(dir*(iClose(_Symbol,tf,b)-level)>0){crossed=true;break;}
      if(crossed){broken=level;return true;}
     }
   return false;
  }

int ICC465_AOIFreshness(ENUM_TIMEFRAMES tf,int sourceShift,double low,double high,int dir,bool &invalid)
  {
   invalid=false; bool touched=false;
   // Inspect all bars AFTER the displacement completed and BEFORE the current bar.
   for(int k=sourceShift-4;k>=1;k--)
     {
      double h=iHigh(_Symbol,tf,k),l=iLow(_Symbol,tf,k),c=iClose(_Symbol,tf,k);
      if(h<=0 || l<=0 || c<=0) continue;
      if((dir>0 && c<low) || (dir<0 && c>high)){invalid=true;return 0;}
      if(h>=low && l<=high) touched=true;
     }
   return touched?1:2;
  }

bool ICC465_AOIInOTE(double low,double high,int dir)
  {
   // If the internal break swing is not yet available, OTE cannot outrank another candidate.
   if(g465.oteHighAnchor<=g465.oteLowAnchor) return false;
   double span=g465.oteHighAnchor-g465.oteLowAnchor;
   double ol=dir>0?g465.oteHighAnchor-0.79*span:g465.oteLowAnchor+0.62*span;
   double oh=dir>0?g465.oteHighAnchor-0.62*span:g465.oteLowAnchor+0.79*span;
   return MathMax(low,ol)<=MathMin(high,oh);
  }

bool ICC465_AOIBetter(const S465AOI &a,const S465AOI &b,string &why)
  {
   int ag=(a.tf==g465.gstf?1:0),bg=(b.tf==g465.gstf?1:0);
   if(ag!=bg){why="TIMEFRAME_AUTHORITY";return ag>bg;}
   if(a.eventRank!=b.eventRank){why="STRUCTURAL_EVENT";return a.eventRank>b.eventRank;}
   if(MathAbs(a.dispScore-b.dispScore)>1e-9){why="DISPLACEMENT_QUALITY";return a.dispScore>b.dispScore;}
   if(a.liquidityRank!=b.liquidityRank){why="LIQUIDITY_SIGNIFICANCE";return a.liquidityRank>b.liquidityRank;}
   if(a.inOTE!=b.inOTE){why="OTE_LOCATION";return a.inOTE;}
   if(a.freshnessRank!=b.freshnessRank){why="FRESHNESS";return a.freshnessRank>b.freshnessRank;}
   why="RECENCY"; return a.created>b.created;
  }

bool ICC465_BuildAOICandidate(ENUM_TIMEFRAMES tf,int sourceShift,S465AOI &a)
  {
   ZeroMemory(a);
   if(sourceShift<4 || sourceShift>=Bars(_Symbol,tf)-2) return false;
   // Core OB: last opposing candle immediately before the qualifying displacement.
   if(g465.dir*(iClose(_Symbol,tf,sourceShift)-iOpen(_Symbol,tf,sourceShift))>=0) return false;
   double score=ICC465_AOIDisplacementScore(tf,sourceShift,g465.dir); if(score<0) return false;
   double broken=0; if(!ICC465_AOIBreak(tf,sourceShift,g465.dir,broken)) return false;
   a.high=iHigh(_Symbol,tf,sourceShift); a.low=iLow(_Symbol,tf,sourceShift);
   a.created=iTime(_Symbol,tf,sourceShift); a.tf=tf; a.dispScore=score;
   int pre=ICC465_PreEventDirection(tf,sourceShift);
   a.eventRank=(pre==-g465.dir?3:(pre==g465.dir?2:1));
   a.eventType=(a.eventRank==3?"MSS":a.eventRank==2?"BOS":"CHOCH_MINOR");
   a.liquidityRank=(tf==g465.gstf?2:1);
   a.liquidityClass=(a.liquidityRank==2?"EXTERNAL":"INTERNAL");
   a.inOTE=ICC465_AOIInOTE(a.low,a.high,g465.dir);
   bool invalid=false; a.freshnessRank=ICC465_AOIFreshness(tf,sourceShift,a.low,a.high,g465.dir,invalid);
   if(invalid) return false;
   return true;
  }

void ICC465_ApplyAOI(const S465AOI &a,string reason)
  {
   g465.aoiHigh=a.high; g465.aoiLow=a.low; g465.aoiCreated=a.created; g465.aoiTF=a.tf;
   g465.aoiValid=true; g465.aoiTouched=(a.freshnessRank<2);
   g465.aoiEventRank=a.eventRank; g465.aoiDispScore=a.dispScore; g465.aoiLiquidityRank=a.liquidityRank;
   g465.aoiFreshnessRank=a.freshnessRank; g465.aoiInOTE=a.inOTE; g465.aoiEventType=a.eventType;
   g465.aoiLiquidityClass=a.liquidityClass; g465.aoiRankReason=reason;
   g465.aoiRankedWithOTE=(g465.oteHighAnchor>g465.oteLowAnchor);
   PrintFormat("[ICC465 AOI] SELECTED tf=%s GSTF=%s event=%s eventRank=%d disp=%.3f liq=%s liqRank=%d OTE=%d freshness=%d created=%s rankReason=%s",
      EnumToString(a.tf),EnumToString(g465.gstf),a.eventType,a.eventRank,a.dispScore,a.liquidityClass,a.liquidityRank,
      (int)a.inOTE,a.freshnessRank,TimeToString(a.created,TIME_DATE|TIME_MINUTES),reason);
  }

// Phase 3 CM-17: AOI confluence ranking only. Candidate scan remains bounded/deterministic.
bool ICC465_SelectAOI()
  {
   S465AOI best,c; bool have=false; string why="INITIAL";
   ENUM_TIMEFRAMES roles[3]={g465.gstf,g465.observationTF,g465.entryTF};
   for(int r=0;r<3;r++)
     {
      ENUM_TIMEFRAMES tf=roles[r]; bool duplicate=false;
      for(int q=0;q<r;q++) if(roles[q]==tf) duplicate=true;
      if(duplicate) continue;
      int end=MathMin(InpStructLookback,Bars(_Symbol,tf)-5);
      for(int source=4;source<=end;source++)
        {
         if(!ICC465_BuildAOICandidate(tf,source,c)) continue;
         if(!have){best=c;have=true;why="INITIAL";continue;}
         string reason=""; if(ICC465_AOIBetter(c,best,reason)){best=c;why=reason;}
        }
     }
   if(!have){ICC465_Log("COR_AOI_NONE_QUALIFIED","EVIDENCE");return false;}
   ICC465_ApplyAOI(best,why); return true;
  }

// RB 5,17-18: FVG belongs to Indication; immediately preceding opposite candle is OB core.
bool ICC465_StartIndication(ENUM_TIMEFRAMES tf)
  {
   // Phase 2 CM-09: only the explicitly selected setup timeframe may own
   // Indication. H1 is the normal day-trade owner; H4 is available only when
   // explicitly selected by the operator. H4 context never manufactures H1 direction.
   if(tf!=g466.setupTF || !g466.contextReady || !g466.tradeEnabled) return false;

   double upLevel=0,downLevel=0;
   datetime upLevelTime=0,upKnown=0,upBreak=0;
   datetime downLevelTime=0,downKnown=0,downBreak=0;
   bool brokeUp=ICC465_BreakLevel(tf,1,upLevel,upLevelTime,upKnown,upBreak);
   bool brokeDown=ICC465_BreakLevel(tf,-1,downLevel,downLevelTime,downKnown,downBreak);

   if(brokeUp && brokeDown)
     {
      ICC465_Log("IND_BREAK_CONFLICT_BOTH_DIRECTIONS","WAIT");
      return false;
     }
   if(!brokeUp && !brokeDown) return false;

   int dir=brokeUp?1:-1;
   double level=brokeUp?upLevel:downLevel;
   datetime levelTime=brokeUp?upLevelTime:downLevelTime;
   datetime knownTime=brokeUp?upKnown:downKnown;
   datetime breakTime=brokeUp?upBreak:downBreak;
   datetime breakComplete=breakTime+PeriodSeconds(tf);

   // Warm-up may seed structure but a pre-enable structural event may not be
   // promoted into a measured-period Indication after a weekend/session gap.
   if(breakTime<=0 || breakComplete<InpTradeEnableTime || breakComplete<=g465LastUsedInd) return false;

   double breakHigh=iHigh(_Symbol,tf,1),breakLow=iLow(_Symbol,tf,1);
   if(breakHigh<=0 || breakLow<=0 || breakHigh<breakLow) return false;

   g465.indTF=tf;
   g465.dir=dir;

   // CM-06/07: collect the old 80/20 hypothesis, but ignore its pass/fail as authority.
   bool rule3Pass=ICC465_Rule3(tf,dir);

   S465Swings sw;
   int strength=(tf==PERIOD_H4?InpExtSwingStrength:InpIntSwingStrength);
   ICC465_Swings(tf,strength,0,sw);
   g465.governing=sw;

   g465.id=breakTime;
   g465.indStart=breakTime;
   g465.indEnd=breakComplete;
   // Legacy enum name retained for schema compatibility in this phase. Semantics:
   // the selected setup timeframe has a formally confirmed structural Indication.
   g465.indication=I465_CONFIRMED_HTF;
   g465.protectedHigh=sw.hi;
   g465.protectedLow=sw.lo;
   g465.keyLevel=(dir>0?g466.activeSetupLow:g466.activeSetupHigh);
   if(g465.keyLevel<=0) g465.keyLevel=(dir>0?sw.lo:sw.hi);
   g465.zoneTF=tf;
   g465.brokenLevel=level;

   // The structural-break bar seeds the impulse. Later same-direction bars may
   // extend the Indication extreme exactly as the frozen Correction tracker already does.
   g465.indHigh=breakHigh;
   g465.indLow=breakLow;
   g465.corrLow=g465.indHigh;
   g465.corrHigh=g465.indLow;
   g465.lastObserved=symInfo.Bid();

   g_iccDir=dir; g_iccPhase=PH_INDICATION; g_iccStartTime=breakTime;
   g_indLevel=level; g_indExtreme=dir>0?g465.indHigh:g465.indLow;
   g_mlIndStartBar=g_barCount; g_mlDispAtIndication=g_lastDispScore;

   // Preserve existing FVG/AOI measurements as evidence only. Their later
   // authority is intentionally untouched until the approved Correction/entry phases.
   if(dir>0 && iLow(_Symbol,tf,1)>iHigh(_Symbol,tf,3))
     { g465.fvgLow=iHigh(_Symbol,tf,3); g465.fvgHigh=iLow(_Symbol,tf,1); }
   if(dir<0 && iHigh(_Symbol,tf,1)<iLow(_Symbol,tf,3))
     { g465.fvgLow=iHigh(_Symbol,tf,1); g465.fvgHigh=iLow(_Symbol,tf,3); }
   g465.fvgMid=(g465.fvgLow+g465.fvgHigh)*0.5;
   ICC465_SelectAOI();

   g466.lastBreakTF=tf;
   g466.lastBreakDir=dir;
   g466.lastBreakLevel=level;
   g466.lastBreakLevelTime=levelTime;
   g466.lastBreakKnownTime=knownTime;
   g466.lastBreakTime=breakTime;
   g466.lastRule3Pass=rule3Pass;
   ICC466_RefreshSetupZone(TimeCurrent());

   ICC465_Log("IND_STRUCTURAL_BREAK",dir>0?"CONFIRMED_SETUP_BREAK_HIGH":"CONFIRMED_SETUP_BREAK_LOW");
   ICC465_Log(rule3Pass?"RULE3_CONFLUENCE_PASS":"RULE3_CONFLUENCE_FAIL","EVIDENCE_ONLY");
   ICC465_Log(g465.fvgHigh>g465.fvgLow?"IND_FVG_PRESENT":"IND_FVG_NONE","EVIDENCE_ONLY");
   ICC466_Trace();
   return true;
  }

// RB 9: strict >1% ONLY for a subordinate analysis TF. HTF distance policy is unresolved.
bool ICC465_LevelInvalid(int dir,ENUM_TIMEFRAMES tf,double key,double &boundary,double &close)
  {
   boundary=key*(dir>0?0.99:1.01); close=iClose(_Symbol,tf,1);
   if(key<=0 || close<=0 || iTime(_Symbol,tf,0)<=0) return false;
   if(PeriodSeconds(tf)<PeriodSeconds(g465.gstf)) return ICC465_ClosedBeyond(dir,close,key,0.01);
   if(InpHTFClosePolicy==0) return false;
   return ICC465_ClosedBeyond(dir,close,key,InpHTFClosePolicy==2?0.01:0.0);
  }

bool ICC465_CheckInvalidation()
  {
   if(g465.indication==I465_NONE || g465.validity==V465_INVALIDATED) return false;
   bool invalid=ICC465_LevelInvalid(g465.dir,g465.zoneTF,g465.keyLevel,g465.boundary,g465.zoneClose);
   datetime closed=iTime(_Symbol,g465.zoneTF,0);
   if(closed!=g465.lastZoneBar)
     {
      g465.lastZoneBar=closed;
      ICC465_Log(InpHTFClosePolicy==0 && g465.zoneTF==g465.gstf?
         "SPECIFICATION DECISION REQUIRED: SD02 HTF_INVALIDATION_DISTANCE":"ZONE_FORMAL_CLOSE","ZONE_CHECK");
     }
   if(!invalid) return false;
   g465LastUsedInd=g465.indEnd;
   g465.validity=V465_INVALIDATED;
   ICC465_Log(PeriodSeconds(g465.zoneTF)<PeriodSeconds(g465.gstf)?"INVALID_CLOSE_1PCT":"INVALID_HTF_FORMAL_CLOSE","INVALIDATED");
   return true;
  }

// Phase 3 CM-13: Correction is owned by the lower timeframe, not by H4/GSTF
// for a normal H1 day-trade setup. M15 is the primary Correction timeframe;
// an explicitly H4-owned setup keeps a separate long-term path.
ENUM_TIMEFRAMES ICC466_CorrectionTF()
  {
   if(g465.indTF==PERIOD_H1) return PERIOD_M15;
   if(g465.indTF==PERIOD_H4 && PeriodSeconds(g465.observationTF)<PeriodSeconds(g465.indTF))
      return g465.observationTF;
   return g465.entryTF;
  }

// Phase 3 CM-12/13: identify a completed counter-move swing boundary after
// Indication. This is Correction structure only; it is NOT Continuation.
bool ICC465_Correction(ENUM_TIMEFRAMES tf,int dir,datetime since,double &pivot)
  {
   pivot=0;
   int strength=(tf==g465.gstf?InpExtSwingStrength:InpMinorPivotStrength);
   int end=MathMin(InpStructLookback,Bars(_Symbol,tf)-strength-1);
   for(int k=strength+1;k<=end;k++)
     {
      datetime t=iTime(_Symbol,tf,k);
      if(t<since) break;
      // Bullish setup -> Correction boundary is a post-Indication LTF pivot LOW.
      // Bearish setup -> Correction boundary is a post-Indication LTF pivot HIGH.
      if(dir>0 && IsPivotLowTF(tf,k,strength))
        {
         pivot=iLow(_Symbol,tf,k);
         return pivot>0 && pivot<g465.indHigh && g465.corrLow<g465.indHigh;
        }
      if(dir<0 && IsPivotHighTF(tf,k,strength))
        {
         pivot=iHigh(_Symbol,tf,k);
         return pivot>g465.indLow && g465.corrHigh>g465.indLow;
        }
     }
   return false;
  }

// AUTHORIZED LIQUIDITY ENGINE ===================================================
// Priority: 1 external GSTF swing, 2 equal H/L (HTF>LTF; triple=external-equivalent),
// 3 prior completed NY session H/L, 4 prior daily H/L, 5 internal range liquidity,
// 6 round-number liquidity. Invalid candidates are excluded before ranking.
struct S465Liq
  {
   double level; datetime formed; ENUM_TIMEFRAMES tf;
   int hierarchyRank,authorityRank,liquidityTier,touches;
   string type;
  };

bool ICC465_IsJPY()
  {
   string b=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE),q=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
   return b=="JPY" || q=="JPY";
  }
bool ICC465_IsForex()
  {
   string b=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE),q=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
   return StringLen(b)==3 && StringLen(q)==3;
  }
bool ICC465_IsMajorFX()
  {
   string b=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_BASE),q=SymbolInfoString(_Symbol,SYMBOL_CURRENCY_PROFIT);
   string majors[7]={"EURUSD","GBPUSD","USDJPY","USDCHF","USDCAD","AUDUSD","NZDUSD"};
   string pair=b+q,rev=q+b;
   for(int i=0;i<7;i++) if(pair==majors[i] || rev==majors[i]) return true;
   return false;
  }
double ICC465_ADR20()
  {
   int n=MathMax(1,InpADRDays); if(Bars(_Symbol,PERIOD_D1)<n+2) return 0;
   double sum=0; int got=0;
   for(int k=1;k<=n;k++){double h=iHigh(_Symbol,PERIOD_D1,k),l=iLow(_Symbol,PERIOD_D1,k);if(h>l){sum+=h-l;got++;}}
   return got>0?sum/got:0;
  }
double ICC465_LiqTolerance()
  {
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); if(tick<=0) tick=_Point;
   double raw=0,adr=ICC465_ADR20(),px=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(ICC465_IsForex()) raw=adr*(ICC465_IsMajorFX()?0.001:0.002); // 0.1/0.2 * ADR20 * 0.01
   else raw=px*0.0005; // index-CFD specification: 0.05% of price
   if(raw<=0) raw=tick;
   return MathMax(tick,MathRound(raw/tick)*tick);
  }
bool ICC465_IsDispCandle(ENUM_TIMEFRAMES tf,int shift)
  {
   if(shift<1 || shift>=Bars(_Symbol,tf)) return false;
   return ICC465_CandleTest(iOpen(_Symbol,tf,shift),iClose(_Symbol,tf,shift),iHigh(_Symbol,tf,shift),iLow(_Symbol,tf,shift),1,InpRule3BodyRatio,InpRule3MaxWickRange)==0 ||
          ICC465_CandleTest(iOpen(_Symbol,tf,shift),iClose(_Symbol,tf,shift),iHigh(_Symbol,tf,shift),iLow(_Symbol,tf,shift),-1,InpRule3BodyRatio,InpRule3MaxWickRange)==0;
  }
int ICC465_DayOfWeek(datetime t){MqlDateTime x;TimeToStruct(t,x);return x.day_of_week;}
int ICC465_NthSunday(int year,int month,int nth)
  {
   MqlDateTime x; ZeroMemory(x); x.year=year;x.mon=month;x.day=1;
   datetime d=StructToTime(x); int dow=ICC465_DayOfWeek(d); int first=1+((7-dow)%7); return first+7*(nth-1);
  }
bool ICC465_NYDST_UTC(datetime utc)
  {
   MqlDateTime x;TimeToStruct(utc,x); int mar=ICC465_NthSunday(x.year,3,2),nov=ICC465_NthSunday(x.year,11,1);
   MqlDateTime a,b;ZeroMemory(a);ZeroMemory(b);a.year=x.year;a.mon=3;a.day=mar;a.hour=7;b.year=x.year;b.mon=11;b.day=nov;b.hour=6;
   return utc>=StructToTime(a) && utc<StructToTime(b);
  }
bool ICC465_BrokerSummer(datetime server)
  {
   // Deterministic historical broker-DST rule for common EET/CET-style FX servers:
   // last Sunday in March through last Sunday in October. Offsets remain explicit inputs.
   MqlDateTime x; TimeToStruct(server,x);
   int marLast=ICC465_NthSunday(x.year,3,5); if(marLast>31) marLast-=7;
   int octLast=ICC465_NthSunday(x.year,10,5); if(octLast>31) octLast-=7;
   MqlDateTime a,b; ZeroMemory(a);ZeroMemory(b);
   a.year=x.year;a.mon=3;a.day=marLast;a.hour=3;
   b.year=x.year;b.mon=10;b.day=octLast;b.hour=4;
   return server>=StructToTime(a) && server<StructToTime(b);
  }
datetime ICC465_ServerToUTC(datetime server)
  {
   // Never reuse today's server offset for historical bars.
   int h=ICC465_BrokerSummer(server)?InpBrokerUTCSummerHours:InpBrokerUTCWinterHours;
   return (datetime)((long)server-(long)h*3600);
  }
datetime ICC465_UTCToNY(datetime utc){return utc+(ICC465_NYDST_UTC(utc)?-4*3600:-5*3600);}
int ICC465_NYSession(datetime serverTime)
  {
   datetime ny=ICC465_UTCToNY(ICC465_ServerToUTC(serverTime)); MqlDateTime x;TimeToStruct(ny,x); int m=x.hour*60+x.min;
   if(m>=18*60 || m<2*60) return 1; // Asia crosses midnight
   if(m<5*60) return 2; if(m<8*60) return 3; if(m<11*60) return 4; if(m<14*60) return 5; return 0;
  }
int ICC465_NYSessionKey(datetime serverTime)
  {
   datetime ny=ICC465_UTCToNY(ICC465_ServerToUTC(serverTime));MqlDateTime x;TimeToStruct(ny,x);int m=x.hour*60+x.min;
   if(m>=18*60) ny+=6*3600; // bind 18:00-02:00 Asia window to one civil session date
   MqlDateTime y;TimeToStruct(ny,y);return y.year*10000+y.mon*100+y.day;
  }
bool ICC465_Last5SessionMinutes(datetime serverTime)
  {
   datetime ny=ICC465_UTCToNY(ICC465_ServerToUTC(serverTime));MqlDateTime x;TimeToStruct(ny,x);int m=x.hour*60+x.min;
   return (m>=115 && m<120)||(m>=295&&m<300)||(m>=475&&m<480)||(m>=655&&m<660)||(m>=835&&m<840);
  }
void ICC465_SessionDiagnostics()
  {
   long nowOffset=(long)(TimeTradeServer()-TimeGMT());
   int expectedNow=(ICC465_BrokerSummer(TimeTradeServer())?InpBrokerUTCSummerHours:InpBrokerUTCWinterHours)*3600;
   PrintFormat("[ICC465 SESSION DIAG] server_now=%s gmt_now=%s offset_now_hours=%.2f expected_config_hours=%.2f UTC_native=0 historical_offset_table=1",
      TimeToString(TimeTradeServer(),TIME_DATE|TIME_SECONDS),TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
      (double)nowOffset/3600.0,(double)expectedNow/3600.0);
   if(MathAbs((double)nowOffset-(double)expectedNow)>3600.0)
      Print("[ICC465 SESSION DIAG] BROKER_OFFSET_MISMATCH: current offset differs from configured historical offset by >1 hour.");
   int samples=0,disagree=0;
   int bars=MathMin(30,Bars(_Symbol,PERIOD_D1)-2);
   for(int k=1;k<=bars;k++)
     {
      datetime server=iTime(_Symbol,PERIOD_D1,k)+12*3600; // one stable midday sample per historical day
      datetime utcHistorical=ICC465_ServerToUTC(server);
      datetime utcCurrent=(datetime)((long)server-nowOffset);
      int a=ICC465_NYSession(server);
      datetime nyCurrent=ICC465_UTCToNY(utcCurrent);MqlDateTime x;TimeToStruct(nyCurrent,x);int m=x.hour*60+x.min;
      int b=(m>=18*60||m<2*60)?1:(m<5*60?2:(m<8*60?3:(m<11*60?4:(m<14*60?5:0))));
      samples++; if(a!=b)disagree++;
      if(k==1 || k==bars)
         PrintFormat("[ICC465 SESSION SAMPLE] server=%s derivedUTC=%s configuredOffset=%d NYsession=%d currentOffsetSession=%d",
            TimeToString(server,TIME_DATE|TIME_MINUTES),TimeToString(utcHistorical,TIME_DATE|TIME_MINUTES),
            ICC465_BrokerSummer(server)?InpBrokerUTCSummerHours:InpBrokerUTCWinterHours,a,b);
     }
   double pct=samples>0?100.0*disagree/samples:0;
   PrintFormat("[ICC465 SESSION DIAG] samples=%d disagreements=%d rate=%.1f%% status=%s",
      samples,disagree,pct,(pct>10.0?"SESSION_DIAGNOSTIC_FAIL":"PASS"));
  }

int ICC465_TFAuthority(ENUM_TIMEFRAMES tf)
  {
   if(tf==g465.gstf) return 3;
   if(tf==g465.observationTF) return 2;
   if(tf==g465.entryTF) return 1;
   return 0;
  }
double ICC465_CloseBodyRatio(ENUM_TIMEFRAMES tf,int sh,bool lowSide)
  {
   double o=iOpen(_Symbol,tf,sh),c=iClose(_Symbol,tf,sh);
   double bh=MathMax(o,c),bl=MathMin(o,c),d=bh-bl;
   if(d<=0) return 0.5;
   return lowSide?(bh-c)/d:(c-bl)/d;
  }
bool ICC465_EqualCoherent(ENUM_TIMEFRAMES tf,int a,int b,bool lows,double tol)
  {
   double oa=iOpen(_Symbol,tf,a),ca=iClose(_Symbol,tf,a),ob=iOpen(_Symbol,tf,b),cb=iClose(_Symbol,tf,b);
   double ba=lows?MathMin(oa,ca):MathMax(oa,ca);
   double bb=lows?MathMin(ob,cb):MathMax(ob,cb);
   if(MathAbs(ba-bb)>tol*InpEqualBodyTolFactor) return false;
   return MathAbs(ICC465_CloseBodyRatio(tf,a,lows)-ICC465_CloseBodyRatio(tf,b,lows))<=InpEqualCloseRatioMaxDiff;
  }
bool ICC465_M5ExtremeInLast5(int sess,int skey,double level,bool lowSide,double tol)
  {
   int n=MathMin(InpLiquidityLookback*3,Bars(_Symbol,PERIOD_M5)-2);
   for(int k=1;k<=n;k++)
     {
      datetime tm=iTime(_Symbol,PERIOD_M5,k);
      if(ICC465_NYSession(tm)!=sess || ICC465_NYSessionKey(tm)!=skey) continue;
      if(!ICC465_Last5SessionMinutes(tm)) continue;
      double x=lowSide?iLow(_Symbol,PERIOD_M5,k):iHigh(_Symbol,PERIOD_M5,k);
      if(MathAbs(x-level)<=tol) return true;
     }
   return false;
  }
double ICC465_RoundTolerance()
  {
   double pip=(ICC465_IsJPY()?0.01:0.0001);
   if(ICC465_IsForex()) return ICC465_IsJPY()?5.0*pip:1.0*pip;
   return 10.0; // authorized index tolerance upper bound
  }
int ICC465_LiquidityTierForType(string type)
  {
   if(type=="TRIPLE_EQUAL_POOL") return 3;
   if(type=="EXTERNAL_GSTF_SWING" || type=="PRIOR_NY_SESSION" || type=="PRIOR_DAILY") return 2;
   if(type=="EQUAL_POOL") return 1;
   return 0; // internal / round-number
  }
int ICC465_AuthorityForType(string type,ENUM_TIMEFRAMES tf)
  {
   if(type=="EXTERNAL_GSTF_SWING" && tf==g465.gstf) return 3;
   if(tf==g465.gstf || tf==g465.observationTF || type=="PRIOR_DAILY") return 2;
   if(type=="ROUND_NUMBER") return 0;
   return 1;
  }
int ICC465_LiqTierScore(){return ICC465_LiquidityTierForType(g465.liquidityType);}

int ICC465_LiqCompare(const S465Liq &a,const S465Liq &b)
  {
   // Conflict precedence is AuthorityRank FIRST, then LiquidityTier.
   // hierarchyRank remains only after those concepts to preserve category ordering
   // without allowing a subordinate triple pool to defeat GSTF external liquidity.
   if(a.authorityRank!=b.authorityRank) return a.authorityRank>b.authorityRank?1:-1;
   if(a.liquidityTier!=b.liquidityTier) return a.liquidityTier>b.liquidityTier?1:-1;
   if(a.hierarchyRank!=b.hierarchyRank) return a.hierarchyRank<b.hierarchyRank?1:-1;
   if(a.touches!=b.touches) return a.touches>b.touches?1:-1;
   if(a.formed!=b.formed) return a.formed>b.formed?1:-1;
   return 0;
  }
void ICC465_LiqConsider(S465Liq &best,bool &have,double level,datetime formed,ENUM_TIMEFRAMES tf,int hierarchyRank,int touches,string type)
  {
   if(level<=0 || formed<=0 || formed>=g465.corrStart) return;
   S465Liq c;
   c.level=level;c.formed=formed;c.tf=tf;c.hierarchyRank=hierarchyRank;c.touches=touches;c.type=type;
   c.authorityRank=ICC465_AuthorityForType(type,tf);
   c.liquidityTier=ICC465_LiquidityTierForType(type);
   if(!have || ICC465_LiqCompare(c,best)>0){best=c;have=true;}
  }

// Scan mechanically qualified liquidity and select lexicographically by the authorized hierarchy.
bool ICC465_LiquidityCandidate(double &level,datetime &levelTime)
  {
   level=0;levelTime=0;S465Liq best;bool have=false;double tol=ICC465_LiqTolerance();
   ENUM_TIMEFRAMES tfs[3]={g465.gstf,g465.observationTF,g465.entryTF};
   // 1) External GSTF swing.
   int gs=MathMax(1,InpExtSwingStrength),gend=MathMin(InpLiquidityLookback,Bars(_Symbol,g465.gstf)-gs-1);
   for(int k=gs+1;k<=gend;k++)
     {if(iTime(_Symbol,g465.gstf,k)>=g465.corrStart)continue;bool p=g465.dir>0?IsPivotLowTF(g465.gstf,k,gs):IsPivotHighTF(g465.gstf,k,gs);if(p){ICC465_LiqConsider(best,have,g465.dir>0?iLow(_Symbol,g465.gstf,k):iHigh(_Symbol,g465.gstf,k),iTime(_Symbol,g465.gstf,k),g465.gstf,1,1,"EXTERNAL_GSTF_SWING");break;}}
   // 2) Equal highs/lows. HTF outranks LTF; triple pools are external-equivalent within this class.
   for(int r=0;r<3;r++)
     {ENUM_TIMEFRAMES tf=tfs[r];int st=(tf==g465.gstf?InpExtSwingStrength:MathMax(1,InpMinorPivotStrength));int en=MathMin(InpLiquidityLookback,Bars(_Symbol,tf)-st-1);
      for(int a=st+1;a<=en;a++)
       {if(iTime(_Symbol,tf,a)>=g465.corrStart||ICC465_IsDispCandle(tf,a))continue;bool pa=g465.dir>0?IsPivotLowTF(tf,a,st):IsPivotHighTF(tf,a,st);if(!pa)continue;double la=g465.dir>0?iLow(_Symbol,tf,a):iHigh(_Symbol,tf,a);int touches=1;datetime newest=iTime(_Symbol,tf,a);
        for(int b=a+1;b<=en;b++){if(ICC465_IsDispCandle(tf,b))continue;bool pb=g465.dir>0?IsPivotLowTF(tf,b,st):IsPivotHighTF(tf,b,st);if(!pb)continue;double lb=g465.dir>0?iLow(_Symbol,tf,b):iHigh(_Symbol,tf,b);
         if(MathAbs(la-lb)<=tol && ICC465_EqualCoherent(tf,a,b,g465.dir>0,tol)){touches++;}}
        if(touches>=2)
          {
           // Triple pools receive LiquidityTier=3, but do NOT inherit GSTF authority.
           ICC465_LiqConsider(best,have,la,newest,tf,2,touches,touches>=3?"TRIPLE_EQUAL_POOL":"EQUAL_POOL");
          }}}
   // 3) Prior completed NY session high/low: actual session extreme, confirmed 2-left/2-right swing, not last 5 minutes.
   int en=MathMin(InpLiquidityLookback,Bars(_Symbol,g465.entryTF)-4);
   for(int k=3;k<=en;k++)
     {datetime t=iTime(_Symbol,g465.entryTF,k);if(t>=g465.corrStart)continue;int sess=ICC465_NYSession(t),skey=ICC465_NYSessionKey(t);if(sess==0)continue;
      // A session level is eligible only after that exact NY session has ended.
      if(sess==ICC465_NYSession(g465.corrStart)&&skey==ICC465_NYSessionKey(g465.corrStart))continue;
      bool p=g465.dir>0?IsPivotLowTF(g465.entryTF,k,InpSessionPivotStrength):IsPivotHighTF(g465.entryTF,k,InpSessionPivotStrength);if(!p)continue;double x=g465.dir>0?iLow(_Symbol,g465.entryTF,k):iHigh(_Symbol,g465.entryTF,k);bool extreme=true;
      for(int j=MathMax(1,k-40);j<=MathMin(en,k+40);j++){datetime jt=iTime(_Symbol,g465.entryTF,j);if(j==k||ICC465_NYSession(jt)!=sess||ICC465_NYSessionKey(jt)!=skey)continue;double y=g465.dir>0?iLow(_Symbol,g465.entryTF,j):iHigh(_Symbol,g465.entryTF,j);if((g465.dir>0&&y<x)||(g465.dir<0&&y>x)){extreme=false;break;}}
      if(extreme && !ICC465_M5ExtremeInLast5(sess,skey,x,g465.dir>0,tol))
        {ICC465_LiqConsider(best,have,x,t,g465.entryTF,3,1,"PRIOR_NY_SESSION");break;}}
   // 4) Prior daily high/low: previous fully closed D1 candle.
   int d=iBarShift(_Symbol,PERIOD_D1,g465.corrStart,false)+1;if(d>0){double x=g465.dir>0?iLow(_Symbol,PERIOD_D1,d):iHigh(_Symbol,PERIOD_D1,d);ICC465_LiqConsider(best,have,x,iTime(_Symbol,PERIOD_D1,d),PERIOD_D1,4,1,"PRIOR_DAILY");}
   // 5) Internal liquidity: confirmed local swings strictly inside current GSTF dealing range and not displacement.
   double rh=g465.governing.hi,rl=g465.governing.lo;int st=MathMax(1,InpMinorPivotStrength);
   for(int k=st+1;k<=en;k++){datetime t=iTime(_Symbol,g465.entryTF,k);if(t>=g465.corrStart||ICC465_IsDispCandle(g465.entryTF,k))continue;bool p=g465.dir>0?IsPivotLowTF(g465.entryTF,k,st):IsPivotHighTF(g465.entryTF,k,st);if(!p)continue;double x=g465.dir>0?iLow(_Symbol,g465.entryTF,k):iHigh(_Symbol,g465.entryTF,k);if(x>rl+tol&&x<rh-tol){ICC465_LiqConsider(best,have,x,t,g465.entryTF,5,1,"INTERNAL_SWING");break;}}
   // 6) Round-number liquidity, nearest relevant level on sweep side.
   double px=SymbolInfoDouble(_Symbol,SYMBOL_BID),step=0;if(ICC465_IsForex()){if(ICC465_IsJPY())step=0.50;else step=0.00250;}else step=25.0;
   if(step>0&&px>0)
     {
      double x=(g465.dir>0?MathFloor(px/step):MathCeil(px/step))*step;
      if(MathAbs(px-x)<=ICC465_RoundTolerance())
         ICC465_LiqConsider(best,have,x,g465.indStart-1,g465.entryTF,6,1,"ROUND_NUMBER");
     }
   if(!have)return false;
   level=best.level;levelTime=best.formed;g465.liquidityType=best.type;
   g465.liquidityAuthorityRank=best.authorityRank;
   PrintFormat("[ICC465 LIQ] SELECTED type=%s AuthorityRank=%d LiquidityTier=%d hierarchy=%d tf=%s level=%.8f tol=%.8f",
      best.type,best.authorityRank,best.liquidityTier,best.hierarchyRank,EnumToString(best.tf),best.level,tol);
   return true;
  }

// Rule-of-Three displacement is anchored by sweep candle S's datetime.
// As new bars close, iBarShift() moves S to larger shifts, making sequences in which
// S is middle/beginning available without forward-looking or forming-candle access.
double ICC465_BodyOverlap(double aLo,double aHi,double bLo,double bHi)
  {
   double ov=MathMax(0.0,MathMin(aHi,bHi)-MathMax(aLo,bLo));
   double den=MathMax(1e-12,MathMin(aHi-aLo,bHi-bLo));
   return ov/den;
  }
bool ICC465_DisplacementSequence(ENUM_TIMEFRAMES tf,int newest,int dir,double &raw)
  {
   raw=0;
   int oldest=newest+2;
   if(newest<1 || oldest>=Bars(_Symbol,tf)) return false;
   double sumBody=0,sumRange=0;
   bool allDir=true; int sameDir=0;
   double bodyLo[3],bodyHi[3],op[3],cl[3],hi[3],lo[3];
   int idx=0;
   for(int k=oldest;k>=newest;k--)
     {
      op[idx]=iOpen(_Symbol,tf,k);cl[idx]=iClose(_Symbol,tf,k);hi[idx]=iHigh(_Symbol,tf,k);lo[idx]=iLow(_Symbol,tf,k);
      double r=hi[idx]-lo[idx],b=MathAbs(cl[idx]-op[idx]); if(r<=0) return false;
      bodyLo[idx]=MathMin(op[idx],cl[idx]);bodyHi[idx]=MathMax(op[idx],cl[idx]);
      sumBody+=b;sumRange+=r;
      bool d=(dir*(cl[idx]-op[idx])>0); if(d)sameDir++; else allDir=false;
      // Legacy 80/20 displacement-quality filter retained here unchanged for later confluence work; it is not Indication authority.
      if(ICC465_CandleTest(op[idx],cl[idx],hi[idx],lo[idx],dir,InpRule3BodyRatio,InpRule3MaxWickRange)!=0) return false;
      idx++;
     }
   double net=dir*(cl[2]-op[0]);
   int ddir=(allDir || (sameDir>=2 && net>0))?1:0;
   double avgBody=sumBody/3.0;
   // Meaningful quality discriminator: acceleration into D3.
   // D3 is cl[2]/op[2] because arrays are populated oldest -> newest.
   int dMomentum=(avgBody>0 && MathAbs(cl[2]-op[2])>=1.20*avgBody)?1:0;
   double avgRange=sumRange/3.0;
   double ov1=ICC465_BodyOverlap(bodyLo[0],bodyHi[0],bodyLo[1],bodyHi[1]);
   double ov2=ICC465_BodyOverlap(bodyLo[1],bodyHi[1],bodyLo[2],bodyHi[2]);
   bool continuity=(MathAbs(op[1]-cl[0])<=InpDispQualityMaxOpenGap*avgRange &&
                    MathAbs(op[2]-cl[1])<=InpDispQualityMaxOpenGap*avgRange);
   int doverlap=(ov1<=InpDispQualityMaxBodyOverlap && ov2<=InpDispQualityMaxBodyOverlap && continuity)?1:0;
   double adr=ICC465_ADR20();
   int dnet=(adr>0 && net>=InpDispQualityNetADRMin*adr)?1:0;
   raw=ddir+dMomentum+doverlap+dnet; // 0..4; normalized to 0..2 downstream
   return true;
  }
bool ICC465_SweepDisplacementStatus(ENUM_TIMEFRAMES tf,datetime sweepTime,double &bestRaw,double &bestNorm)
  {
   bestRaw=0;bestNorm=0;
   int s=iBarShift(_Symbol,tf,sweepTime,false); if(s<1) return false;
   int sweepDir=-g465.dir;
   bool pass=false;
   // newest=s   => S terminates sequence
   // newest=s-1 => S is middle (available after one later candle closes)
   // newest=s-2 => S begins sequence (available after two later candles close)
   for(int rel=0;rel<=2;rel++)
     {
      int newest=s-rel;
      if(newest<1) continue;
      double raw=0;
      if(ICC465_DisplacementSequence(tf,newest,sweepDir,raw))
        {
         pass=true;
         if(raw>bestRaw) bestRaw=raw;
        }
     }
   bestNorm=bestRaw/2.0; // authorized normalization: raw 0..4 -> 0..2
   return pass;
  }

// Phase 3 CM-17: OTE is telemetry/confluence only. The calculation remains so
// it can be measured, but its presence/location cannot authorize or veto Correction.
bool ICC465_InternalOTE()
  {
   if(g465.aoiTouchTime>0) return true; // anchors belong to the retracement already recorded
   if(g465.shiftTime<=0) return false;
   ENUM_TIMEFRAMES tf=ICC466_CorrectionTF(); int strength=InpMinorPivotStrength;
   int end=MathMin(InpStructLookback,Bars(_Symbol,tf)-strength-1);
   for(int k=strength+1;k<=end;k++)
     {
      datetime endpoint=iTime(_Symbol,tf,k);
      if(iTime(_Symbol,tf,k-1)<g465.shiftTime) break; // breakout bar opens before its formal break close
      bool extreme=g465.dir>0?IsPivotHighTF(tf,k,strength):IsPivotLowTF(tf,k,strength);
      if(!extreme) continue;
      int origin=-1,reference=-1;
      for(int j=k+1;j<=end;j++)
        {
         if(iTime(_Symbol,tf,j)<g465.corrStart) break;
         bool opposing=g465.dir>0?IsPivotLowTF(tf,j,strength):IsPivotHighTF(tf,j,strength);
         if(origin<0 && opposing) origin=j;
         bool same=g465.dir>0?IsPivotHighTF(tf,j,strength):IsPivotLowTF(tf,j,strength);
         if(same) { reference=j; break; }
        }
      if(origin<0 || reference<0 || origin>=reference) continue;
      double broken=g465.dir>0?iHigh(_Symbol,tf,reference):iLow(_Symbol,tf,reference);
      datetime known=iTime(_Symbol,tf,reference-strength-1),breakTime=0;
      for(int b=origin;b>=k;b--)
        {
         if(iTime(_Symbol,tf,b)<known) continue;
         if(g465.dir*(iClose(_Symbol,tf,b)-broken)>0) { breakTime=iTime(_Symbol,tf,b-1); break; }
        }
      if(breakTime<g465.shiftTime) continue;
      double low=g465.dir>0?iLow(_Symbol,tf,origin):iLow(_Symbol,tf,k);
      double high=g465.dir>0?iHigh(_Symbol,tf,k):iHigh(_Symbol,tf,origin);
      if(high<=low) continue;
      bool changed=g465.oteEndTime!=endpoint;
      g465.oteLowAnchor=low; g465.oteHighAnchor=high;
      g465.oteOriginTime=iTime(_Symbol,tf,origin); g465.oteEndTime=endpoint; g465.oteBreakTime=breakTime;
      if(changed) ICC465_Log("OTE_INTERNAL_BREAK_SWING","LOCATION");
      return true;
     }
   return false;
  }

double ICC465_PenetrationADRScore(double level,double extreme)
  {
   double adr=ICC465_ADR20(); if(adr<=0) return 0;
   double p=MathAbs(extreme-level)/adr;
   if(p>=0.0025 && p<=0.0075) return 2;
   if(p>=0.0005 && p<0.0025) return 1;
   return 0;
  }
int ICC465_ContextScore(double level)
  {
   if(g465.aoiValid && level>=g465.aoiLow && level<=g465.aoiHigh) return 2;
   double span=g465.governing.hi-g465.governing.lo;
   if(span>0 && (MathAbs(level-g465.governing.hi)<=0.10*span || MathAbs(level-g465.governing.lo)<=0.10*span)) return 1;
   return 0;
  }
int ICC465_TimingScore(datetime tm)
  {
   int s=ICC465_NYSession(tm);
   return (s==2 || s==4)?1:0; // London / New York; quality only, never a veto
  }
void ICC465_ScoreSweep()
  {
   g465.liqTierScore=ICC465_LiqTierScore();
   g465.liqPenScore=(int)ICC465_PenetrationADRScore(g465.sweepLevel,g465.sweepExtreme);
   g465.liqContextScore=ICC465_ContextScore(g465.sweepLevel);
   g465.liqTimingScore=ICC465_TimingScore(g465.sweepPenetrationTime);
   g465.sweepQuality=g465.liqTierScore+g465.liqPenScore+g465.liqDispScore+g465.liqContextScore+g465.liqTimingScore;
   PrintFormat("[ICC465 LIQ SCORE] SWEEP=%.1f Authority=%d L=%d P=%d DRaw=%.1f DNorm=%.1f C=%d T=%d",
      g465.sweepQuality,g465.liquidityAuthorityRank,g465.liqTierScore,g465.liqPenScore,
      g465.displacementQualityRaw,g465.liqDispScore,g465.liqContextScore,g465.liqTimingScore);
  }
void ICC465_ScoreReclaim(ENUM_TIMEFRAMES tf,int sh)
  {
   int e=g465.reclaimBarShift;
   g465.reclaimTimingScore=(e<=1?3:(e==2?2:(e==3?1:0)));
   double h=iHigh(_Symbol,tf,sh),l=iLow(_Symbol,tf,sh),c=iClose(_Symbol,tf,sh),o=iOpen(_Symbol,tf,sh),r=h-l;
   double inside=(g465.dir>0?c-g465.sweepLevel:g465.sweepLevel-c);
   double rangeRef=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),g465.governing.hi-g465.governing.lo);
   double depth=(inside>0?inside/rangeRef:0);
   g465.reclaimCloseScore=(inside<=0?0:(depth>0.50?3:(depth>=0.20?2:1)));
   double wick=(g465.dir>0?MathMin(o,c)-l:h-MathMax(o,c));
   g465.reclaimWickScore=(r>0 && wick/r>0.50)?2:(r>0 && wick/r>=0.25?1:0);
   g465.reclaimFollowScore=0;
   g465.reclaimStrength=g465.reclaimTimingScore+g465.reclaimCloseScore+g465.reclaimWickScore;
  }
void ICC465_UpdateLiquidityScoreAfterShift()
  {
   if(g465.shiftTime<=0) return;
   g465.reclaimFollowScore=2; // formal MSS/CHoCH confirmed by existing structural function
   g465.reclaimStrength=MathMin(10.0,g465.reclaimTimingScore+g465.reclaimCloseScore+g465.reclaimWickScore+g465.reclaimFollowScore);
   g465.liquidityEventScore=MathMin(20.0,g465.sweepQuality+g465.reclaimStrength);
   // Classification is quality-first. AuthorityRank may refine only the >=15 top tier.
   double score=g465.liquidityEventScore;
   int auth=g465.liquidityAuthorityRank;
   if(score<10.0)
      g465.liquidityEventClass="LOW";
   else if(score<15.0)
      g465.liquidityEventClass="SECONDARY";
   else
     {
      if(auth>=2)
         g465.liquidityEventClass="PRIMARY";
      else
         g465.liquidityEventClass="SECONDARY";
     }
   PrintFormat("[ICC465 LIQ SCORE] RECLAIM=%.1f EVENT=%.1f CLASS=%s Authority=%d Rt=%d Rc=%d W=%d F=%d",
      g465.reclaimStrength,g465.liquidityEventScore,g465.liquidityEventClass,g465.liquidityAuthorityRank,
      g465.reclaimTimingScore,g465.reclaimCloseScore,g465.reclaimWickScore,g465.reclaimFollowScore);
   if(g465.liquidityEventClass=="PRIMARY") ICC465_Log("LIQ_EVENT_PRIMARY_AOI_DRIVER","RANK");
   else if(g465.liquidityEventClass=="SECONDARY") ICC465_Log("LIQ_EVENT_SECONDARY_CONFLUENCE","RANK");
   else ICC465_Log("LIQ_EVENT_LOW_IGNORE_EXECUTION","RANK");
  }
bool LiquidityEventValid()
  {
   return g465.sweepQuality>=5.0 &&
          g465.reclaimStrength>=5.0 &&
          g465.liquidityEventClass!="LOW";
  }
bool LiquidityPrimaryAuthorization()
  {
   return g465.liquidityEventClass=="PRIMARY";
  }

// Phase 3 CM-16/17. Liquidity/AOI/FVG/OTE are Correction confluence/telemetry.
// This function may score/reset its own evidence, but none of those outcomes
// may authorize or veto Correction validity.
void ICC465_CorrectionEvidence()
  {
   ENUM_TIMEFRAMES tf=ICC466_CorrectionTF();datetime bar=iTime(_Symbol,tf,1),closeTime=iTime(_Symbol,tf,0);
   if(closeTime<=g465.corrStart||closeTime==g465.lastEntryBar)return;if(bar<g465.corrStart)return;g465.lastEntryBar=closeTime;
   double hi=iHigh(_Symbol,tf,1),lo=iLow(_Symbol,tf,1),cl=iClose(_Symbol,tf,1);if(hi<=0||lo<=0||cl<=0)return;
   if(g465.sweepLevel<=0){double lv=0;datetime lt=0;if(ICC465_LiquidityCandidate(lv,lt)){g465.sweepLevel=lv;g465.sweepLevelTime=lt;}}
   double level=g465.sweepLevel;
   // Candle S = first CLOSED candle violating the selected level. Wick or body penetration counts.
   if(!g465.sweepConfirmed && level>0 && g465.sweepPenetrationTime==0 && ((g465.dir>0&&lo<level)||(g465.dir<0&&hi>level)))
     {
      g465.sweepPenetrationTime=bar;g465.sweepBarShift=1;g465.sweepExtreme=g465.dir>0?lo:hi;
      g465.sweepPendingDisplacement=true;g465.sweepDisplacement=false;
      double raw=0,norm=0;
      if(ICC465_SweepDisplacementStatus(tf,g465.sweepPenetrationTime,raw,norm))
        {
         g465.sweepDisplacement=true;g465.sweepPendingDisplacement=false;
         g465.displacementQualityRaw=raw;g465.liqDispScore=norm;
         ICC465_Log("LIQUIDITY_RUN_DETECTED","CONFLUENCE_ONLY");
         ICC465_ScoreSweep();
        }
      else ICC465_Log("SWEEP_PENDING_DISPLACEMENT","CONFLUENCE_ONLY");
      // Same-candle reclaim may be recorded while displacement is pending; it has no authority yet.
      bool closeInside=g465.dir>0?cl>level:cl<level;
      bool bodyBeyond=g465.dir>0?MathMin(iOpen(_Symbol,tf,1),cl)<level:MathMax(iOpen(_Symbol,tf,1),cl)>level;
      if(closeInside&&!bodyBeyond){g465.sweepConfirmed=true;g465.sweepTime=closeTime;g465.reclaimTime=closeTime;g465.reclaimBarShift=0;g465.reclaimClose=cl;ICC465_ScoreReclaim(tf,1);ICC465_Log("RECLAIM_RECORDED_SAME_CANDLE","CONFLUENCE_ONLY");}
     }
   // Pending displacement: S can terminate, sit inside, or begin the Rule-of-Three.
   // Resolve against S's datetime as subsequent CLOSED candles make new placements available.
   if(g465.sweepPenetrationTime>0 && !g465.sweepDisplacement)
     {
      int sNow=iBarShift(_Symbol,tf,g465.sweepPenetrationTime,false);
      int elapsedDisp=(sNow>=1?sNow-1:99);
      double raw=0,norm=0;
      if(ICC465_SweepDisplacementStatus(tf,g465.sweepPenetrationTime,raw,norm))
        {
         g465.sweepDisplacement=true;g465.sweepPendingDisplacement=false;
         g465.displacementQualityRaw=raw;g465.liqDispScore=norm;
         ICC465_Log("SWEEP_DISPLACEMENT_CONFIRMED_PENDING","CONFLUENCE_ONLY");
         ICC465_ScoreSweep();
         if(g465.sweepQuality<5.0)
           {
            ICC465_Log("SWEEP_QUALITY_BELOW_5","CONFLUENCE_ONLY");
            g465.sweepPenetrationTime=0;g465.sweepPendingDisplacement=false;g465.sweepConfirmed=false;return;
           }
        }
      else if(elapsedDisp>=3)
        {
         ICC465_Log("SWEEP_DISPLACEMENT_EXPIRED_S_PLUS_3","CONFLUENCE_ONLY");
         g465.sweepPenetrationTime=0;g465.sweepPendingDisplacement=false;g465.sweepConfirmed=false;return;
        }
     }

   // Inclusive four-candle reclaim window: S,S+1,S+2,S+3. For later candles a body close back inside is sufficient.
   if(!g465.sweepConfirmed && g465.sweepPenetrationTime>0)
     {
      int sShift=iBarShift(_Symbol,tf,g465.sweepPenetrationTime,false);int elapsed=(sShift>=1?sShift-1:99);
      if(elapsed>=1&&elapsed<=3)
        {bool inside=g465.dir>0?cl>level:cl<level;if(inside){g465.sweepConfirmed=true;g465.sweepTime=closeTime;g465.reclaimTime=closeTime;g465.reclaimBarShift=elapsed;g465.reclaimClose=cl;ICC465_ScoreReclaim(tf,1);ICC465_Log("RECLAIM_CONFIRMED_S_PLUS_"+IntegerToString(elapsed),"EVIDENCE");}}
      if(!g465.sweepConfirmed&&elapsed>3){ICC465_Log("NO_RECLAIM_S_TO_S3","CONFLUENCE_ONLY");g465.sweepPenetrationTime=0;g465.sweepBarShift=0;g465.sweepExtreme=0;g465.sweepDisplacement=false;}
     }
   // Reclaim has no reversal authority until a post-reclaim micro MSS/CHoCH formal close.
   if(g465.sweepConfirmed&&g465.sweepDisplacement&&g465.shiftTime==0)
     {
      // Re-acceptance beyond swept liquidity before reversal structure kills this event.
      bool continuation=(g465.dir>0?cl<level:cl>level);
      if(continuation)
        {
         ICC465_Log("RECLAIM_INVALIDATED_BY_CONTINUATION","CONFLUENCE_ONLY");
         g465.sweepConfirmed=false;g465.sweepPenetrationTime=0;g465.sweepDisplacement=false;
         g465.reclaimTime=0;g465.reclaimBarShift=0;g465.reclaimClose=0;g465.sweepQuality=0;g465.reclaimStrength=0;g465.liquidityEventScore=0;g465.liquidityEventClass="";g465.sweepPendingDisplacement=false;g465.displacementQualityRaw=0;g465.liqDispScore=0;
         return;
        }
      S465Swings sw;ICC465_Swings(tf,InpMinorPivotStrength,g465.reclaimTime,sw);double key=g465.dir>0?sw.hi:sw.lo;datetime known=g465.dir>0?sw.hiKnown:sw.loKnown;
      if(key>0&&bar>=known&&g465.dir*(cl-key)>0)
        {
         g465.shiftTime=closeTime;ICC465_UpdateLiquidityScoreAfterShift();
         if(!LiquidityEventValid()){ICC465_Log("LIQUIDITY_EVENT_INVALID_AFTER_SHIFT","CONFLUENCE_ONLY");g465.shiftTime=0;g465.sweepConfirmed=false;return;}
         ICC465_Log("MICRO_SHIFT_CONFIRMED","CONFLUENCE_ONLY");
        }
     }
   if(g465.shiftTime>0&&!g465.aoiRankedWithOTE&&ICC465_InternalOTE()){ICC465_SelectAOI();g465.aoiRankedWithOTE=true;ICC465_Log("COR_AOI_RERANKED_WITH_OTE","CONFLUENCE_ONLY");}
   if(g465.aoiValid)
     {
      double boundary=0,zc=0;bool invalid=ICC465_LevelInvalid(g465.dir,g465.aoiTF,g465.dir>0?g465.aoiLow:g465.aoiHigh,boundary,zc);
      if(invalid){g465.aoiValid=false;ICC465_Log("COR_AOI_INVALID_FORMAL_CLOSE","CONFLUENCE_ONLY");}
      if(g465.aoiValid&&hi>=g465.aoiLow&&lo<=g465.aoiHigh){g465.aoiTouched=true;ICC465_Log("COR_AOI_TOUCH","CONFLUENCE_ONLY");}
     }
  }

// Phase 3 CM-12/13/14: Correction authority gate.
// First counter-tick remains DEVELOPING only. A valid Correction requires:
//   (1) a real counter-move from the Indication extreme, and
//   (2) a defined completed LTF structural boundary on the Correction timeframe.
// There is NO mandatory OTE depth, micro-BOS/resumption, H4 confirmation,
// liquidity sweep, AOI touch, FVG, or displacement requirement here.
bool ICC465_CorrectionAuthority(double &boundaryPrice)
  {
   boundaryPrice=0;
   if(g465.correction==C465_NONE || g465.corrStart<=0) return false;

   double span=g465.indHigh-g465.indLow;
   if(span<=0) return false;

   bool retracement=(g465.dir>0 ? g465.corrLow<g465.indHigh : g465.corrHigh>g465.indLow);
   if(!retracement) return false;

   ENUM_TIMEFRAMES corrTF=ICC466_CorrectionTF();
   double pivot=0;
   if(!ICC465_Correction(corrTF,g465.dir,g465.corrStart,pivot)) return false;
   if(pivot<=0) return false;

   boundaryPrice=pivot;
   return true;
  }

// Phase 3 CM-12..17: M15/LTF owns ordinary H1-set-up Correction.
// Developing evidence is collected early, but only an observed counter-move plus
// a completed LTF Correction boundary can promote Correction. OTE/liquidity/AOI/FVG
// are confluence only. H4/GSTF Correction confirmation is reserved for an explicitly
// H4-owned long-term setup and is never required for an H1-owned setup.
void ICC465_TrackCorrection(ENUM_TIMEFRAMES tf)
  {
   ENUM_TIMEFRAMES corrTF=ICC466_CorrectionTF();
   bool h4Owned=(g465.indTF==PERIOD_H4);
   bool ltfPass=(tf==corrTF);
   bool h4Pass=(h4Owned && tf==g465.gstf);
   if(!ltfPass && !h4Pass) return;

   datetime bar=iTime(_Symbol,tf,1),closeTime=iTime(_Symbol,tf,0);
   if(bar<g465.indEnd) return;
   if(tf==g465.gstf) { if(closeTime==g465.lastGSTFBar) return; g465.lastGSTFBar=closeTime; }
   else { if(closeTime==g465.lastCorrBar) return; g465.lastCorrBar=closeTime; }
   double hi=iHigh(_Symbol,tf,1),lo=iLow(_Symbol,tf,1),cl=iClose(_Symbol,tf,1),op=iOpen(_Symbol,tf,1);
   if(hi<=0 || lo<=0 || op<=0 || cl<=0) return;

   // For normal H1 setups only corrTF may start/own Correction. The H4 pass is
   // a separate long-term confirmation path and cannot manufacture an H1 Correction.
   if(g465.correction==C465_NONE)
     {
      if(!ltfPass) return;
      if(g465.dir*(cl-op)>=0 && g465.dir*(cl-iClose(_Symbol,tf,2))>=0)
        {
         g465.indHigh=MathMax(g465.indHigh,hi); g465.indLow=MathMin(g465.indLow,lo);
         return;
        }
      g465.correction=C465_DEVELOPING_LTF; g465.corrStart=bar;
      g465.corrHigh=hi; g465.corrLow=lo;
      g_corrStartTime=bar; g_iccPhase=PH_CORRECTION; g_mlCorrStartBar=g_barCount;
      ICC465_Log("COR_ACTIVE","LTF_COUNTER_MOVE_DEVELOPING");
     }

   if(bar>=g465.corrStart)
     {
      g465.corrHigh=MathMax(g465.corrHigh,hi);
      g465.corrLow=MathMin(g465.corrLow,lo);
     }
   g_corrExtreme=g465.dir>0?g465.corrLow:g465.corrHigh;
   double span=g465.indHigh-g465.indLow;
   g465.retrace=span>0?(g465.dir>0?g465.indHigh-g465.corrLow:g465.corrHigh-g465.indLow)/span:0;

   if(ltfPass)
     {
      // CM-16/17: collect confluence without granting it Correction authority.
      ICC465_CorrectionEvidence();

      double boundaryPrice=0;
      bool authority=ICC465_CorrectionAuthority(boundaryPrice);
      if(!authority)
        {
         ICC465_Log("COR_DEVELOPING_NO_AUTHORITY","WAIT_LTF_CORRECTION_BOUNDARY");
         return;
        }

      if(g465.correction==C465_DEVELOPING_LTF)
        {
         g465.correction=C465_CLARIFIED_LTF;
         g465.corrConfirmTime=closeTime;
         ICC465_Log("COR_LTF_CONFIRMED_AUTHORITY","LTF_STRUCTURAL_BOUNDARY_NO_OTE_VETO");
         ICC465_Log(g465.sweepConfirmed?"COR_LIQUIDITY_CONFLUENCE_PRESENT":"COR_LIQUIDITY_CONFLUENCE_NONE","EVIDENCE_ONLY");
         ICC465_Log(g465.aoiTouched?"COR_AOI_CONFLUENCE_TOUCHED":"COR_AOI_CONFLUENCE_NOT_REQUIRED","EVIDENCE_ONLY");
         ICC465_Log(g465.fvgHigh>g465.fvgLow?"COR_FVG_CONFLUENCE_PRESENT":"COR_FVG_CONFLUENCE_NONE","EVIDENCE_ONLY");
         ICC465_Log("COR_OTE_DEPTH_TELEMETRY_ONLY","EVIDENCE_ONLY");
        }
      return;
     }

   // Separate long-term path: only an explicitly H4-owned setup can receive
   // GSTF/H4 Correction confirmation. H1-owned setups never enter this branch.
   if(h4Pass && g465.correction>=C465_CLARIFIED_LTF)
     {
      double edge=0;
      if(ICC465_Correction(g465.gstf,g465.dir,g465.corrStart,edge) && g465.correction!=C465_CONFIRMED_HTF)
        {
         g465.correction=C465_CONFIRMED_HTF;
         g465.corrConfirmTime=closeTime;
         ICC465_Log("COR_HTF_CONFIRMED_AUTHORITY","H4_OWNED_LONG_TERM_PATH_ONLY");
        }
     }
  }

// RB 3,5,7: explicit confirmation of the SAME developing displacement on GSTF close.
void ICC465_PromoteIndication()
  {
   // Phase 2 CM-10: mandatory H1 -> H4 Indication promotion is retired.
   // The selected setup break is already authoritative. H4/D1 is recorded only
   // as non-vetoing context until later state-machine work is explicitly authorized.
   if(g465.indication==I465_NONE || g465.indContextLogged) return;
   g465.indContextLogged=true;
   string relation="CONTEXT_NEUTRAL";
   if(g466.contextDirection==g465.dir) relation="CONTEXT_ALIGNED";
   else if(g466.contextDirection==-g465.dir) relation="CONTEXT_OPPOSED";
   ICC465_Log("IND_"+relation,"EVIDENCE_ONLY");
  }

// Transcript entry path: after an H1/H4 Indication and confirmed correction,
// M15/M5 resumption through a correction swing can confirm Continuation and entry.
// The owning H1/H4 indication remains the direction and first-target authority.
bool ICC466_LTFEntryQualified(datetime &breakTime,double &evidenceLevel)
  {
   breakTime=0; evidenceLevel=0;
   if(g465.indication==I465_NONE || g465.correction<C465_CLARIFIED_LTF || g465.corrConfirmTime<=0) return false;
   if(g465.entryTF!=PERIOD_M15 && g465.entryTF!=PERIOD_M5) return false;
   // Confirm only on the newest fully closed entry bar, using a pivot already
   // known before that bar. A pre-correction pivot or the first H1 break is not entry evidence.
   ENUM_TIMEFRAMES tf=g465.entryTF;
   datetime barOpen=iTime(_Symbol,tf,1),barClose=iTime(_Symbol,tf,0);
   if(barOpen<g465.corrConfirmTime || barClose<=g465.corrConfirmTime) return false;
   double prev=iClose(_Symbol,tf,2),current=iClose(_Symbol,tf,1);
   if(prev<=0 || current<=0) return false;
   int strength=InpMinorPivotStrength;
   int end=MathMin(InpStructLookback,Bars(_Symbol,tf)-strength-1);
   for(int k=strength+1;k<=end;k++)
     {
      datetime pivotTime=iTime(_Symbol,tf,k);
      if(pivotTime<g465.corrStart) break;
      bool pivot=g465.dir>0?IsPivotHighTF(tf,k,strength):IsPivotLowTF(tf,k,strength);
      if(!pivot) continue;
      datetime known=iTime(_Symbol,tf,k-strength-1);
      double level=g465.dir>0?iHigh(_Symbol,tf,k):iLow(_Symbol,tf,k);
      if(known<=0 || known>barOpen || level<=0) continue;
      if(g465.dir*(prev-level)<=0 && g465.dir*(current-level)>0)
        { evidenceLevel=level; breakTime=barClose; g465.continuationLevelTime=pivotTime; return true; }
     }
   return false;
  }

// Phase 3 CM-12: first counter-tick starts DEVELOPING only; live ticks track the protective Correction extreme.
void ICC465_TrackLiveExtreme()
  {
   if(g465.indication==I465_NONE || g465.consumed || g465.validity!=V465_ACTIVE) return;
   double bid=symInfo.Bid();
   if(bid<=0) return;
   if(g465.correction==C465_NONE)
     {
      if(g465.lastObserved>0 && g465.dir*(bid-g465.lastObserved)<0 && TimeCurrent()>=g465.indEnd)
        {
         g465.correction=C465_DEVELOPING_LTF; g465.corrStart=TimeCurrent();
         g465.corrHigh=bid; g465.corrLow=bid;
         g_corrStartTime=g465.corrStart; g_iccPhase=PH_CORRECTION; g_mlCorrStartBar=g_barCount;
         ICC465_Log("COR_ACTIVE","FIRST_OBSERVED_COUNTER_TICK");
         // No qualification authority is granted here. Evidence collection begins
         // on subsequent closed entry-TF processing in ICC465_CorrectionEvidence().
        }
      else
        { g465.indHigh=MathMax(g465.indHigh,bid); g465.indLow=MathMin(g465.indLow,bid); }
      g465.lastObserved=bid;
      if(g465.correction==C465_NONE) return;
     }
   g465.corrHigh=MathMax(g465.corrHigh,bid); g465.corrLow=MathMin(g465.corrLow,bid);
   g_corrExtreme=g465.dir>0?g465.corrLow:g465.corrHigh;
   // Liquidity sweep authority is closed-candle owned; live ticks only track Correction extremes.
  }

// Phase 4 CM-22: only a fully sequenced setup may signal.
// Indication alone and DEVELOPING Correction remain hard no-entry states.
void ICC465_Signal(E465 path)
  {
   if(g465.indication==I465_NONE)
     {
      ICC465_Log("SIGNAL_BLOCKED_NO_INDICATION","INVARIANT");
      return;
     }
   if(g465.correction==C465_NONE || g465.correction==C465_DEVELOPING_LTF)
     {
      ICC465_Log("SIGNAL_BLOCKED_CORRECTION_NO_AUTHORITY","INVARIANT");
      return;
     }
   if(g465.continuation!=T465_CONFIRMED_LTF || g465.contTime<=0)
     {
      ICC465_Log("SIGNAL_BLOCKED_NO_SETUP_CONTINUATION","INVARIANT");
      return;
     }
   if(path!=E465_BASELINE_LTF || g465.entryEvidenceTime<g465.contTime || g465.entryEvidenceLevel<=0)
     {
      ICC465_Log("SIGNAL_BLOCKED_NO_LTF_EXECUTION_EVIDENCE","INVARIANT");
      return;
     }

   g465.entry=path; g465.consumed=true; g465LastUsedInd=g465.indEnd;
   iccBuySig=g465.dir>0; iccSellSig=g465.dir<0;
   // CM-22: stop remains beyond the owning Correction extreme.
   iccSigSL=g465.dir>0?g465.corrLow:g465.corrHigh;
   g_mlOTEDepth=g465.retrace; g_mlCorrectionDepth=g465.retrace;
   double span=g465.indHigh-g465.indLow;
   g_mlImpulseLegATR=g_mseATRval>0?span/g_mseATRval:0;
   g_mlImpulseAgeBars=g_mlCorrStartBar-g_mlIndStartBar;
   g_mlCorrectionAgeBars=g_barCount-g_mlCorrStartBar; g_mlSigPhaseAtFire=PH_CORRECTION;
   g_mlSweepAge=g465.sweepConfirmed?iBarShift(_Symbol,g465.entryTF,g465.sweepTime,false):-99;
   g_mlSweepLeadBars=g465.sweepConfirmed?(double)(g465.indStart-g465.sweepTime)/PeriodSeconds(g465.entryTF):-99;
   g_mlImpulseConcentration=ICC_ImpulseConcentration(span);
   g_mlCorrLegCount=ICC_CorrectionLegCount(); g_mlCorrRecovery=ICC_CorrectionRecovery(g465.dir,iClose(_Symbol,g465.entryTF,1));
   ICC465_Log("ENTRY_BASELINE_LTF","SIGNAL");
  }

// Evidence-only equivalent of StartIndication's confirmed H1 break qualification.
// Does not refresh structure, run Rule3 telemetry, or write any cycle/lineage state.
void ICC467_DiagActiveOwnerBreak()
  {
   ENUM_TIMEFRAMES tf=g466.setupTF;
   if(g465.indication==I465_NONE || tf!=PERIOD_H1 || !g466.contextReady || !g466.tradeEnabled) return;
   double upLevel=0,downLevel=0;
   datetime upLevelTime=0,upKnown=0,upBreak=0,downLevelTime=0,downKnown=0,downBreak=0;
   bool up=ICC465_BreakLevel(tf,1,upLevel,upLevelTime,upKnown,upBreak);
   bool down=ICC465_BreakLevel(tf,-1,downLevel,downLevelTime,downKnown,downBreak);
   if(up==down) return; // neither, or conflicting simultaneous confirmed breaks
   int dir=up?1:-1;
   double level=up?upLevel:downLevel;
   datetime levelTime=up?upLevelTime:downLevelTime,known=up?upKnown:downKnown;
   datetime breakTime=up?upBreak:downBreak,complete=breakTime+PeriodSeconds(tf);
   if(breakTime<=0 || complete<InpTradeEnableTime || complete<=g465LastUsedInd || complete<=g465.indEnd) return;
   double hi=iHigh(_Symbol,tf,1),lo=iLow(_Symbol,tf,1);
   if(hi<=0 || lo<=0 || hi<lo) return;
   // Candidate setup identity matches StartIndication: confirmed break-bar time.
   static datetime logged[];
   for(int i=0;i<ArraySize(logged);i++) if(logged[i]==breakTime) return;
   int n=ArraySize(logged); if(ArrayResize(logged,n+1)!=n+1) return; logged[n]=breakTime;
   PrintFormat("[ICC467 DIAG ACTIVE_OWNER_BREAK] time=%s old_setup=%I64d candidate_setup=%I64d owner=%s old_dir=%d break_dir=%d broken_level=%.8f level_time=%s level_known=%s break_bar=%s break_confirmed=%s old_ind_end=%s indication=%s correction=%s continuation=%s corr_confirmed=%s validity=%s consumed=%d action=EVIDENCE_ONLY",
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),(long)g465.id,(long)breakTime,EnumToString(tf),g465.dir,dir,level,
      TimeToString(levelTime,TIME_DATE|TIME_SECONDS),TimeToString(known,TIME_DATE|TIME_SECONDS),
      TimeToString(breakTime,TIME_DATE|TIME_SECONDS),TimeToString(complete,TIME_DATE|TIME_SECONDS),
      TimeToString(g465.indEnd,TIME_DATE|TIME_SECONDS),EnumToString(g465.indication),EnumToString(g465.correction),
      EnumToString(g465.continuation),TimeToString(g465.corrConfirmTime,TIME_DATE|TIME_SECONDS),EnumToString(g465.validity),(int)g465.consumed);
  }

void ICC465_Update()
  {
   iccBuySig=false; iccSellSig=false; iccSigSL=0;
   if(!UseICCPullback) return;
   if(g465.consumed || g465.validity==V465_INVALIDATED) ICC_Reset();
   if(g465.indication==I465_NONE)
     {
      // Phase 2 CM-09/11: explicit setup owner first; no H4 fallback is invented.
      // Confirmed-trend direction remains diagnostic and is NOT a prerequisite
      // for the first structural Indication break.
      ICC466_RefreshSetupZone(TimeCurrent());
      ICC465_Log(g466.setupDirection>0?"SETUP_TF_BULL":
                 g466.setupDirection<0?"SETUP_TF_BEAR":"SETUP_TF_NEUTRAL","STRUCTURE");
      if(ICC465_StartIndication(g466.setupTF)) { ICC466_AttachCycleLineage(); return; }

      bool h1Unclear=(g466.setupTF==PERIOD_H1 && g466.h1Direction==0);
      if(h1Unclear)
        {
         string context=g466.h4Direction>0?"H4_BULL_CONTEXT":
                        g466.h4Direction<0?"H4_BEAR_CONTEXT":"H4_NEUTRAL_CONTEXT";
         ICC465_Log("H1_UNCLEAR_"+context,"CONTEXT_ONLY_NO_MANUFACTURED_DIRECTION");
        }

      if(g466.noTradeZone)
        {
         ICC465_Log("NO_TRADE_ZONE","BETWEEN_ACTIVE_SETUP_SWINGS");
         return;
        }

      if(h1Unclear)
        {
         ICC465_Log("H1_UNCLEAR_NO_STRUCTURAL_BREAK","WAIT");
         return;
        }

      ICC465_Log("IND_WAIT_ACTIVE_SWING_BREAK","WAIT");
      return;
     }
   if(ICC465_CheckInvalidation()) return;
   ICC467_DiagActiveOwnerBreak();
   ICC465_PromoteIndication();
   // Phase 3 Correction remains authoritative and unchanged: H1-owned setups are M15-correction-owned;
   // explicitly H4-owned setups retain their separate long-term confirmation pass.
   ICC465_TrackCorrection(g465.gstf);
   ICC465_TrackCorrection(ICC466_CorrectionTF());
   if(g465.correction==C465_NONE) return;

   // CM-22 invariant: a DEVELOPING Correction can never create Continuation or entry.
   if(g465.correction==C465_DEVELOPING_LTF)
     {
      ICC465_Log("WAIT_CORRECTION_CONFIRMATION","NO_CONTINUATION_OR_ENTRY_AUTHORITY");
      return;
     }

   // Transcript sequencing: the correction's M15/M5 structural resumption is
   // entry confirmation. Requiring an H1 close through its original break level
   // first can push entry beyond the H1 indication objective.
   if(g465.continuation!=T465_CONFIRMED_LTF)
     {
      double contLevel=0; datetime entryBreak=0;
      if(!ICC466_LTFEntryQualified(entryBreak,contLevel))
        {
         ICC465_Log("WAIT_LTF_CORRECTION_RESUMPTION","NO_ENTRY_BEFORE_SECOND_MOVE");
         return;
        }
      g465.continuation=T465_CONFIRMED_LTF;
      g465.contTime=entryBreak;
      g465.continuationTF=g465.entryTF;
      g465.continuationLevel=contLevel;
      g465.entryEvidenceTF=g465.entryTF;
      g465.entryEvidenceTime=entryBreak;
      g465.entryEvidenceLevel=contLevel;
      PrintFormat("[ICC467 CONT] owner=%s entry=%s dir=%d level=%.8f confirmed=%s correction_confirmed=%s",
         EnumToString(g465.indTF),EnumToString(g465.entryTF),g465.dir,g465.continuationLevel,
         TimeToString(g465.contTime,TIME_DATE|TIME_MINUTES),TimeToString(g465.corrConfirmTime,TIME_DATE|TIME_MINUTES));
      ICC465_Log("CONT_LTF_CORRECTION_RESUMPTION","SECOND_MOVE_AFTER_H1_INDICATION");
      ICC466_CommitCycleLineage(); // CM-27 metadata only; no change to Continuation authority.
     }
   PrintFormat("[ICC466 ENTRY] tf=%s dir=%d level=%.8f confirmed=%s setup_cont=%s",
      EnumToString(g465.entryEvidenceTF),g465.dir,g465.entryEvidenceLevel,
      TimeToString(g465.entryEvidenceTime,TIME_DATE|TIME_MINUTES),TimeToString(g465.contTime,TIME_DATE|TIME_MINUTES));
   ICC465_Log("LTF_ENTRY_EVIDENCE_CONFIRMED","BASELINE_STRUCTURE_ONLY");
   ICC465_Signal(E465_BASELINE_LTF);
   return;
  }

// v4.6.5 STAGE 4: monetary risk, executable Correction stops, GSTF lifecycle.
// RB 10. Direction-aware tick-grid rounding, not decimal-digit-only rounding.
double ICC465_TickRound(double price,bool up)
  {
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) return 0;
   return NormalizeDouble((up?MathCeil(price/tick-1e-9):MathFloor(price/tick+1e-9))*tick,_Digits);
  }

// RB 10,15; broker computes the account-currency loss including cross-currency conversion.
double ICC465_Lots(int dir,double entry,double sl)
  {
   if(entry<=0 || sl<=0 || dir*(entry-sl)<=0) return 0;
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),profit=0;
   if(mn<=0 || mx<mn || step<=0) return 0;
   if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,mn,entry,sl,profit) || profit>=0) return 0;
   double unit=-profit/mn;
   double budget=AccountInfoDouble(ACCOUNT_BALANCE)*RiskPercent/100.0;
   double want=FixedLots>0?FixedLots:budget/unit;
   double lots=NormalizeDouble(MathFloor(MathMin(want,mx)/step+1e-9)*step,8);
   if(lots<mn || lots<=0) { ICC465_Log("EXEC_RISK_BELOW_MIN_VOLUME","VETO"); return 0; }
   if(FixedLots<=0 && lots*unit>budget+0.0000001) return 0;
   return lots;
  }

// RB 2,10,13: account+magic+position identifier namespace persists beyond reattachment.
string ICC465_Key(ulong id,string field)
  {
   // Broker/account/magic identity gets two independent 32-bit accumulators;
   // position ID remains exact hexadecimal. Max key length stays below 63.
   string identity=AccountInfoString(ACCOUNT_SERVER)+"|"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"|"+IntegerToString((long)MagicNumber);
   uint h1=2166136261,h2=5381;
   for(int k=0;k<StringLen(identity);k++) { uint c=StringGetCharacter(identity,k); h1=(h1^c)*16777619; h2=h2*33+c; }
   return StringFormat("I465.%08X%08X.%I64X.%s",h1,h2,id,field);
  }
string ICC465_RealizedRText(ulong id)
  {
   double risk=ICC465_Get(id,"risk");
   if(risk<=0) return "UNAVAILABLE";
   return DoubleToString(ICC465_Get(id,"realized")/risk,8);
  }
double ICC465_Get(ulong id,string field)
  {
   string key=ICC465_Key(id,field);
   return GlobalVariableCheck(key)?GlobalVariableGet(key):0.0;
  }
bool ICC465_Set(ulong id,string field,double value)
  {
   if(GlobalVariableSet(ICC465_Key(id,field),value)==0)
     { Print("[ICC465] POSITION METADATA WRITE FAILED ",id," ",field," ",GetLastError()); return false; }
   return true;
  }

// RB 10,13,15: each deal is joinable by position ID; partial-exit realized R is monetary.
void ICC465_DealLog(ulong deal,ulong id,string event,double money)
  {
   string file="ICC465_lifecycle_"+g_mlRunId+".csv";
   int h=FileOpen(file,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI,',');
   if(h==INVALID_HANDLE) { Print("[ICC465] lifecycle CSV OPEN FAILED ",GetLastError()); return; }
   if(FileSize(h)==0) FileWrite(h,"schema","run_id","symbol","account_currency","deal_id","position_id","setup_id","event","gstf","observation_tf","entry_tf","zone_tf","entry_path","structural_anchor","executable_sl","initial_risk_money","initial_risk_r","realized_money_cumulative","realized_r","deal_money","owner_tf","context_tf","parent_setup_id","lineage_seed_extreme","structural_target","target_tf","target_source","target_money","target_r");
   double risk=ICC465_Get(id,"risk"),realized=ICC465_Get(id,"realized");
   FileSeek(h,0,SEEK_END);
   uint n=FileWrite(h,"ICC465_LIFE_2",g_mlRunId,_Symbol,AccountInfoString(ACCOUNT_CURRENCY),deal,id,
      (long)ICC465_Get(id,"setup"),event,(int)ICC465_Get(id,"gstf"),(int)ICC465_Get(id,"obs"),
      (int)ICC465_Get(id,"entrytf"),(int)ICC465_Get(id,"zone"),(int)ICC465_Get(id,"path"),
      ICC465_Get(id,"anchor"),ICC465_Get(id,"sl"),risk,risk>0?1.0:0.0,realized,
      risk>0?DoubleToString(realized/risk,8):"UNAVAILABLE",money,(int)ICC465_Get(id,"owner"),
      (int)ICC465_Get(id,"context"),(long)ICC465_Get(id,"parent"),ICC465_Get(id,"seed"),
      ICC465_Get(id,"target"),(int)ICC465_Get(id,"targettf"),
      ICC466_TargetSourceText((int)ICC465_Get(id,"targetsrc")),ICC465_Get(id,"targetmoney"),
      risk>0?DoubleToString(ICC465_Get(id,"targetmoney")/risk,8):"UNAVAILABLE");
   if(n==0) Print("[ICC465] lifecycle CSV WRITE FAILED ",GetLastError());
   FileClose(h);
  }

void ICC465_RecordDeal(ulong deal)
  {
   ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   ENUM_DEAL_ENTRY kind=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   double fees=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
   double money=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)+fees;
   if(kind==DEAL_ENTRY_IN)
     {
      bool exists=ICC465_Get(id,"gstf")>0;
      if(!exists && (!g465PendingValid || (ulong)HistoryDealGetInteger(deal,DEAL_ORDER)!=g465PendingOrder))
        { Print("SPECIFICATION DECISION REQUIRED: SD08 entry position has no v4.6.5 ownership snapshot ",id); return; }
      if(!exists)
        {
         ICC465_Set(id,"gstf",(double)g465Pending.gstf);
         ICC465_Set(id,"obs",(double)g465Pending.observationTF); ICC465_Set(id,"entrytf",(double)g465Pending.entryTF);
         ICC465_Set(id,"zone",(double)g465Pending.zoneTF); ICC465_Set(id,"path",(double)g465Pending.entry);
         ICC465_Set(id,"ind",(double)g465Pending.indication); ICC465_Set(id,"cor",(double)g465Pending.correction);
         ICC465_Set(id,"cont",(double)g465Pending.continuation);
         ICC465_Set(id,"setup",(double)g465Pending.id); ICC465_Set(id,"key",g465Pending.keyLevel);
         ENUM_TIMEFRAMES ownerTF=(g465Pending.indTF==PERIOD_H1 || g465Pending.indTF==PERIOD_H4)?g465Pending.indTF:InpSetupStructureTF;
         int ownerStrength=(ownerTF==PERIOD_H4?InpExtSwingStrength:InpIntSwingStrength);
         ICC465_Set(id,"owner",(double)ownerTF); ICC465_Set(id,"context",(double)InpContextTF);
         ICC465_Set(id,"ownerstrength",ownerStrength); ICC465_Set(id,"strength",ownerStrength);
         ICC465_Set(id,"htfpolicy",InpHTFClosePolicy);
         ICC465_Set(id,"parent",(double)g465Pending.parentSetupId); ICC465_Set(id,"seed",g465Pending.lineageSeedExtreme);
         ICC465_Set(id,"target",g465Pending.structuralTarget); ICC465_Set(id,"targettf",(double)g465Pending.structuralTargetTF);
         ICC465_Set(id,"targetsrc",g465Pending.structuralTargetSource); ICC465_Set(id,"targetmoney",0); ICC465_Set(id,"targetr",0);
         ICC465_Set(id,"anchor",g465Pending.dir>0?g465Pending.corrLow:g465Pending.corrHigh);
         ICC465_Set(id,"sl",g465PendingSL); ICC465_Set(id,"risk",0); ICC465_Set(id,"volume",0); ICC465_Set(id,"realized",0);
        }
      double volume=HistoryDealGetDouble(deal,DEAL_VOLUME),entry=HistoryDealGetDouble(deal,DEAL_PRICE),loss=0;
      int dir=HistoryDealGetInteger(deal,DEAL_TYPE)==DEAL_TYPE_BUY?1:-1;
      if(OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,ICC465_Get(id,"sl"),loss) && loss<0)
        {
         ICC465_Set(id,"risk",ICC465_Get(id,"risk")-loss);
         ICC465_Set(id,"volume",ICC465_Get(id,"volume")+volume);
        }
      else Print("[ICC465] INITIAL RISK UNAVAILABLE position=",id," err=",GetLastError());
      double targetPx=ICC465_Get(id,"target"),targetMoney=0;
      if(targetPx>0 && OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,targetPx,targetMoney) && targetMoney>0)
         ICC465_Set(id,"targetmoney",ICC465_Get(id,"targetmoney")+targetMoney);
      double riskNow=ICC465_Get(id,"risk");
      ICC465_Set(id,"targetr",riskNow>0?ICC465_Get(id,"targetmoney")/riskNow:0);
      ICC465_Set(id,"realized",ICC465_Get(id,"realized")+money);
      ICC465_DealLog(deal,id,"ENTRY_FILL",money);
      // Keep snapshot until routing a subsequent order; partial fills share this order's metadata.
     }
   else if(kind==DEAL_ENTRY_OUT || kind==DEAL_ENTRY_OUT_BY)
     {
      if(ICC465_Get(id,"gstf")<=0) return;
      ICC465_Set(id,"realized",ICC465_Get(id,"realized")+money);
      ICC465_DealLog(deal,id,"EXIT_FILL",money);
     }
   else if(kind==DEAL_ENTRY_INOUT)
      Print("SPECIFICATION DECISION REQUIRED: SD08 unexpected netting reversal ownership ",id);
   GlobalVariablesFlush();
  }

void ICC465_Execute(int dir,double anchor,string tag,color boxCol)
  {
   if(!symInfo.RefreshRates()) return;
   double entry=dir>0?symInfo.Ask():symInfo.Bid(),exitQuote=dir>0?symInfo.Bid():symInfo.Ask();
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(entry<=0 || exitQuote<=0 || anchor<=0 || tick<=0) return;
   double legal=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   // Smallest tick strictly outside Correction, enlarged only by broker stop legality.
   double sl=dir>0?ICC465_TickRound(anchor,false):ICC465_TickRound(anchor,true);
   if(dir>0 && sl>=anchor) sl-=tick;
   if(dir<0 && sl<=anchor) sl+=tick;
   sl=dir>0?ICC465_TickRound(MathMin(sl,exitQuote-legal),false):ICC465_TickRound(MathMax(sl,exitQuote+legal),true);
   if(sl<=0 || dir*(entry-sl)<=0) return;
   double lots=ICC465_Lots(dir,entry,sl);
   if(lots<=0) { g_mlPendValid=false; ICC465_Log("EXEC_RISK_UNAVAILABLE","VETO"); return; }
   bool target=false;
   double tp=ResolveTP(dir,entry,MathAbs(entry-sl),target);
   if(tp>0) tp=ICC465_TickRound(tp,dir<0);
   double riskMoney=0,targetMoney=0;
   bool riskOK=OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,entry,sl,riskMoney) && riskMoney<0;
   bool targetOK=(tp>0 && OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,entry,tp,targetMoney) && targetMoney>0);
   double targetR=(riskOK && targetOK)?targetMoney/(-riskMoney):0;
   PrintFormat("[ICC465 RISK] setup=%I64d owner=%s risk_money=%.2f currency=%s structural_target=%.8f target_tf=%s target_source=%s target_R=%.4f",
      (long)g465.id,EnumToString(g465.indTF),riskOK?-riskMoney:0.0,AccountInfoString(ACCOUNT_CURRENCY),tp,
      EnumToString(g465.structuralTargetTF),ICC466_TargetSourceText(g465.structuralTargetSource),targetR);
   if(tp>0 && dir*(tp-exitQuote)<legal)
     { ICC465_Log("EXEC_STRUCTURAL_TARGET_TOO_CLOSE","VETO"); g_mlPendValid=false; return; }
   double margin=0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,lots,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     { ICC465_Log("EXEC_MARGIN","VETO"); g_mlPendValid=false; return; }
   g465Pending=g465; g465PendingSL=sl; g465PendingValid=true;
   g_pInitSLguess=sl; g_lastTP=tp; g_lastTPstruct=target;
   ICC465_Log("SL_CORRECTION_EXTREME","EXECUTION");
   PrintFormat("[ICC465] SL anchor=%.8f executable=%.8f cushion=%.8f lots=%.8f currency=%s",anchor,sl,MathAbs(anchor-sl),lots,AccountInfoString(ACCOUNT_CURRENCY));
   ICC467_DiagTarget("PRE_SUBMIT",dir,entry,tp);
   bool ok=dir>0?trade.Buy(lots,_Symbol,entry,sl,tp,TradeComment):trade.Sell(lots,_Symbol,entry,sl,tp,TradeComment);
   if(ok && TradeResultSucceeded())
     { g465PendingOrder=trade.ResultOrder(); TriggerFlash(tag,boxCol,true,entry,sl,tp); ICC465_Log("EXEC_ORDER_ACCEPTED","EXECUTION"); }
   else
     {
      g_mlPendValid=false; g465PendingValid=false;
      ICC465_Log("EXEC_ORDER_REJECTED","EXECUTION");
      PrintFormat("[ICC465] rc=%u %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
     }
  }

// Phase 5 CM-26. Persisted setup-owner timeframe governs core position health;
// subordinate M15/M5 noise cannot close the trade. Higher context is stored for
// a future explicit runner-promotion rule, but no automatic H4/D1 promotion is invented.
bool ICC465_ManagePosition()
  {
   ulong id=(ulong)posInfo.Identifier(),ticket=posInfo.Ticket();
   double tfValue=ICC465_Get(id,"owner");
   if(tfValue<=0) tfValue=ICC465_Get(id,"gstf"); // backward-compatible pre-Phase5 position fallback only
   if(tfValue<=0)
     {
      static ulong lastMissing=0;
      if(lastMissing!=id) { Print("SPECIFICATION DECISION REQUIRED: SD08 no owner-TF metadata for position ",id,"; existing broker SL/TP retained"); lastMissing=id; }
      return false;
     }
   ENUM_TIMEFRAMES tf=(ENUM_TIMEFRAMES)(int)tfValue;
   int dir=posInfo.PositionType()==POSITION_TYPE_BUY?1:-1;
   double entry=posInfo.PriceOpen(),sl=posInfo.StopLoss(),tp=posInfo.TakeProfit();
   double quote=dir>0?symInfo.Bid():symInfo.Ask();
   if(quote<=0) return false;
   int strength=(int)ICC465_Get(id,"ownerstrength");
   if(strength<1) strength=(int)ICC465_Get(id,"strength");
   if(strength<1) return false;
   S465Swings s; ICC465_Swings(tf,strength,0,s);
   double close=iClose(_Symbol,tf,1),key=ICC465_Get(id,"key");
   int policy=(int)ICC465_Get(id,"htfpolicy");
   int ownerDir = ICC465_Direction(s);
   datetime ownerDirectionKnown = 0;
   if(ownerDir > 0)
      ownerDirectionKnown = s.hiKnown;
   else if(ownerDir < 0)
      ownerDirectionKnown = s.loKnown;
   bool reversal=ownerDir==-dir && ownerDirectionKnown>posInfo.Time() && ICC465_ClosedBeyond(dir,close,key,policy==2?0.01:0.0);
   if((CloseOnOpposite || (InpUseRexit && InpUseTrendHealth)) && reversal && policy>0)
     {
      RX_StageCloseTag(id,"OWNER-REVERSAL");
      bool ok=trade.PositionClose(ticket) && TradeResultSucceeded();
      if(!ok) RX_ConsumeCloseTag(id);
      return ok;
     }
   // Trail only a confirmed setup-owner swing formed AFTER entry. No M15/M5/ATR/point fallback.
   double candidate=0,tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double diagRisk=0,diagOpenR=0,diagLock=-1e18,diagFloor=0;
   bool diagRSelected=false;
   datetime pivotTime=dir>0?s.loT:s.hiT;
   if(tick<=0) return false;
   if(InpRunnerExternStruct && pivotTime>posInfo.Time() && ICC465_Direction(s)==dir)
      candidate=ICC465_TickRound((dir>0?s.lo-tick:s.hi+tick),dir<0);
   if(InpUseRexit)
     {
      double risk=ICC465_Get(id,"risk"),volume=ICC465_Get(id,"volume"),unitProfit=0;
      double markProfit=posInfo.Profit()+posInfo.Swap()+ICC465_Get(id,"realized");
      diagRisk=risk; if(risk>0) diagOpenR=markProfit/risk;
      if(InpUsePartial && risk>0 && markProfit/risk>=InpActivateAtR && ICC465_Get(id,"partial")==0)
        {
         double vol=NormalizeLots(posInfo.Volume()*InpPartialPct/100.0);
         if(vol>=symInfo.LotsMin() && vol<posInfo.Volume() && posInfo.Volume()-vol>=symInfo.LotsMin())
           {
            RX_StageCloseTag(id,"R-POLICY-PARTIAL");
            if(RX_ClosePartial(ticket,vol)) ICC465_Set(id,"partial",1);
            else RX_ConsumeCloseTag(id);
            return false; // refresh volume/quotes/realized ledger after the deal callback
           }
         ICC465_Set(id,"partial",1);
        }
      if(risk>0 && volume>0 && OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,posInfo.Volume(),entry,entry+dir*tick,unitProfit) && unitProfit>0)
        {
         double lock=RX_LockedR(markProfit/risk);
         diagLock=lock;
         if(lock>=0)
           {
            double requiredMoney=MathMax(0.0,lock*risk-ICC465_Get(id,"realized")-posInfo.Swap());
            double floor=entry+dir*(requiredMoney/unitProfit)*tick;
            diagFloor=floor; diagRSelected=(candidate==0 || dir*(floor-candidate)>0);
            if(candidate==0 || dir*(floor-candidate)>0) candidate=floor;
           }
        }
     }
   if(candidate<=0) return false;
   double minDist=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   // Skip illegal structure; moving the stop onto a different level would change its meaning.
   if(dir*(quote-candidate)<=minDist || (sl>0 && dir*(candidate-sl)<tick*0.5)) return false;
   candidate=ICC465_TickRound(candidate,dir<0);
   bool modified=RX_SafeModify(ticket,dir>0,candidate,tp,quote);
   if(modified)
     {
      double requested=NormalizeDouble(candidate,_Digits);
      ICC467_DiagRememberSL(id,requested);
      PrintFormat("[ICC467 DIAG STOP_MODIFY] position=%I64u ticket=%I64u setup=%I64d time=%s Bid=%.8f Ask=%.8f spread_price=%.8f exit_side=%s risk_money=%.8f open_R=%s lock_R=%s floor=%.8f protect_at_R=%.4f lock_at_R=%.4f activate_at_R=%.4f old_sl=%.8f new_sl=%.8f source=%s currency=%s",
         id,ticket,(long)ICC465_Get(id,"setup"),TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),symInfo.Bid(),symInfo.Ask(),symInfo.Ask()-symInfo.Bid(),dir>0?"Bid":"Ask",
         InpUseRexit?diagRisk:ICC465_Get(id,"risk"),InpUseRexit && diagRisk>0?DoubleToString(diagOpenR,8):"UNAVAILABLE",
         diagLock>-1e17?DoubleToString(diagLock,8):"INACTIVE",diagFloor,InpProtectAtR,InpLockAtR,InpActivateAtR,
         sl,requested,diagRSelected?"R_FLOOR":"OWNER_STRUCTURE",AccountInfoString(ACCOUNT_CURRENCY));
     }
   return modified;
  }
