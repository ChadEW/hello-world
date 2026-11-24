//+------------------------------------------------------------------+
//|        ICC_TradesBySci_EA_v4.6.3_HOSTILE_AUDIT_CORRECTED.mq5           |
//|   EXPERT ADVISOR v4.6.3 -- TRADING EA (executes live orders;      |
//|   this is NOT an indicator).                                      |
//|                                                                   |
//|   v4.6.3 ADDITIONAL HOSTILE-AUDIT CORRECTIONS - 2026-09-17.       |
//|   H1 HIGH: failed close/partial-close requests left staged exit    |
//|      reason tags behind; later unrelated exits could inherit them. |
//|   H2 HIGH: contract-token input contradicted the compiled token    |
//|      actually enforced by ML_Load2RModel. Validation now agrees.   |
//|   H3 MED: trend-reversal manager reported closed after a failed    |
//|      PositionClose. It now returns the actual close result.        |
//|                                                                   |
//|   v4.6.2 HOSTILE-AUDIT CORRECTIONS - 2026-09-17.                  |
//|   Line-by-line review of v4.6.1. Ten findings, four of them on    |
//|   the runtime or trade path. Full reasoning per finding is at     |
//|   each fix site; summary only here.                               |
//|                                                                   |
//|   F1 CRITICAL RUNTIME. RX_Ensure() returns -1 when the ticket     |
//|      cannot be selected, and BOTH call sites (RX_ManageOne,       |
//|      RX_DashInfo) indexed g_rxRisk[idx] with no guard -- an       |
//|      ARRAY OUT OF RANGE that HALTS the EA, reached on every       |
//|      managed tick and every dashboard refresh.                    |
//|   F2 HIGH MODEL CONTRACT. The v4.6.0 sweep arm stamps were never  |
//|      cleared, and ICC_SweepLeadBars() tested only "armT>0" -- so  |
//|      an EXPIRED raid from many setups ago was emitted as a        |
//|      genuine early-raid reading and ML2R_NO_SWEEP was effectively |
//|      unreachable. Now requires the sweep to still be ARMED, and   |
//|      the stamp is cleared when its window expires.                |
//|   F3 HIGH MODEL CONTRACT. The sweep is DETECTED on g_intTF bar 1  |
//|      but was STAMPED with bar 0 (still forming), while            |
//|      g_iccStartTime follows the v4.3.3 closed-bar convention.     |
//|      The two ends of sweep_lead_bars sat on DIFFERENT conventions,|
//|      biasing every reading by one bar and flipping the sign of    |
//|      the same-bar case the feature exists to distinguish.         |
//|   F4 HIGH TRADE PATH. The v4.5.0 Finding 2 fix was INOPERATIVE at |
//|      default inputs: g_mlRunner is only assigned after a          |
//|      SUCCESSFUL inference, so with InpMLModelEnabled=false (the   |
//|      default) it stayed true and every order was sent with        |
//|      tpPrice=0.0. ResolveTP, StructuralTPTarget, RR_Ratio,        |
//|      InpTPMode, InpTPMinRR and the InpMinTPRR 2R hard floor were  |
//|      ALL still unreachable out of the box. New input              |
//|      InpRunnerWhenNoInference (default false) attaches a real     |
//|      >=InpMinTPRR target when no probability exists.              |
//|      *** TRADING-AFFECTING AT DEFAULTS -- A/B per s15.1. ***      |
//|   F5 MED. impulse_concentration returned a hard 0.0 whenever the  |
//|      Correction confirmed on the same g_intTF bar as the          |
//|      Indication -- i.e. it reported "no concentration" for the    |
//|      fastest setups, the exact population it exists to find.      |
//|   F6 MED. Contract-guard comparison is CASE-SENSITIVE; v4.6.1     |
//|      documented it as case-insensitive. Code kept, doc corrected. |
//|   F7 MED. ValidateInputs made any InpMLContractToken override     |
//|      FATAL under enforcement -- a settable input with exactly one |
//|      legal value. Override now allowed and logged loudly.         |
//|   F8 LOW. The "v1" filename advisory matched any substring, so it |
//|      fired on ICC_2R_v10.onnx and rev1.onnx.                      |
//|   F9 LOW. ML_v4_RegisterEntry hardcoded fRunner=1 over the real   |
//|      staged g_pRunner -- latent, pending a schema change.         |
//|   F10 LOW. sweep_age is a REMAINING-validity countdown (high =    |
//|      fresh); the name reads as the opposite. Documented, not      |
//|      renamed -- renaming would invalidate a second artifact.      |
//|                                                                   |
//|   NOT CHANGED, DELIBERATELY: the 28-slot tensor order and the     |
//|   schema-4.2.0 CSV layout are untouched, so v4.6.2 needs NO       |
//|   retrain relative to v4.6.0/v4.6.1. F2/F3/F5 change the VALUES   |
//|   three path features take, so a model trained on v4.6.0-era      |
//|   exports should be refreshed once a clean dataset exists.        |
//|                                                                   |
//|   MODEL CONTRACT                                                  |
//|     Input  : one float tensor [1,28], CONTRACT ORDER below.       |
//|     Output : one probability tensor [1,1] = P(trade reaches 2R).  |
//|     Role   : ICC is the SETUP AUTHORITY. The model GATES, SIZES   |
//|              and SELECTS THE EXIT POLICY (runner vs real TP).     |
//|              It is subtractive, never generative.                 |
//|     File   : InpMLModelFile, default ICC_2R_v2.onnx.              |
//|     Bound  : ONNX INPUT TENSOR NAME must equal InpMLContractToken |
//|              (ML2R_CONTRACT_TOKEN, "icc_path_v2"). Enforced in    |
//|              ML_Load2RModel; fail-closed by default.              |
//|                                                                   |
//|   v4.6.1 BINDING MODEL CONTRACT GUARD - 2026-09-16.               |
//|   v4.6.0 changed the FEATURE SET but not the tensor SHAPE, so a   |
//|   pre-v4.6.0 .onnx passed inputs==1/outputs==1/[1,28] and LOADED  |
//|   CLEANLY, then scored garbage -- indistinguishable at runtime    |
//|   from a working gate. The v4.6.0 mitigations (renaming the       |
//|   default file to _v2, printing a feature-set banner) were        |
//|   ADVISORY ONLY: neither could prevent the load.                  |
//|   The guard now binds to the ONNX INPUT TENSOR NAME, which the    |
//|   trainer sets at export and which is baked into the graph, so it |
//|   cannot be defeated by renaming or copying the artifact.         |
//|     Export with:                                                  |
//|       skl2onnx: initial_types=[("icc_path_v2",                    |
//|                                 FloatTensorType([1,28]))]         |
//|       torch   : input_names=["icc_path_v2"]                       |
//|   Models exported WITHOUT an explicit name carry the framework    |
//|   default ("float_input", "onnx::Gemm_0") and are REJECTED -- an  |
//|   unnamed artifact cannot prove which feature set trained it.     |
//|   InpMLEnforceContract=false restores v4.6.0 shape-only loading   |
//|   and logs a FAIL-OPEN warning; InpMLAutonomous=true refuses to   |
//|   initialise in that state, because autonomous mode SIZES and     |
//|   picks the EXIT POLICY from the probability, so a wrong model    |
//|   does not merely filter badly.                                   |
//|   g_mlModelVersion now reports VERIFIED vs UNVERIFIED and reaches |
//|   the v4 CSV, so provenance survives the Journal being cleared.   |
//|                                                                   |
//|   v4.6.0 PATH-DEPENDENT FEATURE SET - 2026-09-16.                 |
//|   The 28 scalars were all POINT-IN-TIME summaries, so the tensor  |
//|   could not distinguish two setups with identical magnitudes but  |
//|   different event ORDER or leg SHAPE. Four low-information slots  |
//|   are replaced by four path-dependent ones; the COUNT stays 28 so |
//|   the sample-per-parameter ratio does not get worse.              |
//|     OUT  ext_trend        (collinear with direction by the gate)  |
//|          icc_phase        (constant PH_CORRECTION on every fire)  |
//|          correction_depth (clamped twin of ote_depth)             |
//|          sweep_long/short (collapsed to one sweep_age)            |
//|     IN   sweep_lead_bars       (event ORDER: sweep vs Indication) |
//|          impulse_concentration (leg SHAPE: spike vs grind)        |
//|          corr_leg_count        (pullback SHAPE: flag vs sloppy)   |
//|          corr_recovery_frac    (WHERE in the correction we fired) |
//|   Latched in BOTH continuation branches BEFORE ICC_Reset(), the   |
//|   same discipline the v4.4.1 Finding A and v4.5.0 Finding 5 fixes |
//|   established. v4 dataset schema 4.1.0 -> 4.2.0, new columns      |
//|   APPENDED so existing column indices are preserved.              |
//|                                                                   |
//|   VALIDATION GATES (do not skip, in this order):                  |
//|     0. F1 REGRESSION GATE (v4.6.2). Run any configuration that    |
//|        opens a position and let it close. The EA must NOT halt    |
//|        with "array out of range" in RX_ManageOne/RX_DashInfo.     |
//|     0b. F4 TAKE-PROFIT GATE (v4.6.2). With InpMLModelEnabled=     |
//|        false (default), open ONE trade and inspect it in the      |
//|        Trade tab: it MUST now carry a non-zero TP at >=           |
//|        InpMinTPRR. If TP is still 0.00 the F4 fix is not wired.   |
//|        Set InpRunnerWhenNoInference=true to reproduce v4.6.1.     |
//|     1. Compile; banner reads v4.6.2 and "[ML2R] init-contract"    |
//|        prints featureSet=PATH_v2 token=icc_path_v2 enforce=YES.   |
//|     3b. F2/F3 GATE (v4.6.2). Grep "[ML2R FEAT]" slot 03. It MUST  |
//|        read -99 whenever no sweep is ARMED (not merely whenever   |
//|        none was ever stamped), and its non-sentinel values must   |
//|        be small integers consistent with InpSweepValidBars -- NOT |
//|        large magnitudes, which indicate a stale stamp survived.   |
//|     1b. CONTRACT GUARD PROOF (v4.6.1). Point InpMLModelFile at    |
//|        any pre-v4.6.0 .onnx with InpMLModelEnabled=true. OnInit   |
//|        MUST fail with "MODEL CONTRACT REJECTED" and the EA MUST   |
//|        NOT attach. If it attaches and trades, the guard is not    |
//|        wired -- stop and fix before any further validation.       |
//|     2. InpMLLogInference=true, InpRejectWeakBreaks=true. Grep     |
//|        "[ML2R FEAT]". Confirm slots 02,03,19,21,22 are NON-       |
//|        CONSTANT across signals -- that is the whole point of this |
//|        build and it cannot be seen in any CSV.                    |
//|     3. Confirm slot 03 sweep_lead_bars takes BOTH signs across a  |
//|        run, and -99 only when no sweep is armed.                  |
//|     4. Regenerate a homogeneous schema-4.2.0 dataset. Do NOT mix  |
//|        it with 4.1.0 rows. Retrain, then A/B per Master Spec      |
//|        s15.1 on $ expectancy and max drawdown, never trade count. |
//|                                                                   |
//|   Full version history: see CHANGELOG.md.                         |
//|   Built for Chad Woodyard, July 2026.                             |
//+------------------------------------------------------------------+
#property copyright   "Chad Woodyard"
#property version     "4.62"
#property description "ICC TradesBySci EA v4.6.2 HOSTILE-AUDIT CORRECTIONS (TRADING EA)"
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
//============================= INPUTS ================================
input group "=== Entry Path (Sci ICC only) ==="
input bool   UseICCPullback    = true;          // Sci Indication->Correction->Continuation pullback (the ONLY entry path)
input bool   CloseOnOpposite   = true;          // Close open trade on an opposite ICC continuation (structure flip)
input group "=== Bias / Filter (Sci: HTF sets bias, LTF entry) ==="
input bool   BiasLoose         = true;          // single BOS sets trend (HH w/o LL = bull)
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
input bool   InpHTFStrictBoundary = false;      // HTF conviction gate: OFF=>=/<= (v4.2.3), ON=strict >/< (veto opposing-D1 at exact floor)
input group "=== ICC Pullback Tuning ==="
input double CorrRetraceMin    = 0.500;         // Min pullback into discount/premium (fib of impulse)
input double CorrRetraceMax    = 0.900;         // Max pullback before setup invalidates (fib)
input int    ICC_ExpiryBars    = 30;            // Bars to complete Correction+Continuation, else reset
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
input bool   InpUseStructuralCorrection = false; // Correction = structural LH/HL + impulse-origin hold (OFF = 0.50-0.90 fib band)
input double InpStructCorrMinRetrace    = 0.10;  // Structural: min fraction of the impulse leg retraced before a pivot counts (anti-noise floor)
input bool   InpStructCorrKeepMaxDepth  = false; // Structural: ALSO keep the CorrRetraceMax deep-invalidation cap as a secondary guard
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
input ENUM_LIQ_PHASE InpLiquidityPhase = LIQ_INDICATION; // LIQ_INDICATION=legacy v4.3.5, LIQ_CORRECTION=CORE-06 chronology, LIQ_OFF=confluence only
// s7 bullet 5 + CORE-07/08: the continuation pivot must be the CORRECTION's own
// structural transition, not merely the latest qualifying pivot in a lookback.
input bool InpContTrigSinceCorrection = false; // Continuation pivot must have formed AFTER the Correction began
// s4 CORE-01: HH+HL / LH+LL only; otherwise NEUTRAL (consolidation) rather than a forced direction.
input bool InpNeutralOnConsolidation  = false; // External trend returns to NEUTRAL when HH/HL (or LH/LL) is not intact
input int  InpConsolidationBars       = 12;    // MidTF bars without a fresh protected-swing BOS before declaring consolidation
// Unit correction: the Correction develops on WorkTF, but expiry counts CHART bars.
input bool InpExpiryInWorkTFBars      = false; // Count ICC_ExpiryBars in WorkTF bars (OFF = legacy chart bars)

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
input double       InpMinTPRR    = 2.0;         // HARD floor: no take-profit closer than this reward:risk (Sci 2R objective)
input group "=== Trailing Stop ==="
input bool   UseTrailingStop   = true;
input int    TrailingStart_Pts = 200;
input int    TrailingStep_Pts  = 100;
input group "=== Break Even ==="
input bool   UseBreakEven      = true;
input int    BreakEvenAt_Pts   = 150;
input int    BreakEvenProfit   = 10;
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
input bool   InpLetWinnersRun     = true;   // Ride winners: no fixed TP; profit-lock ratchet keeps a profitable trade open
input int    InpRunnerArmPts      = 200;    // Profit (points) before the profit-lock arms
input int    InpRunnerLockPts     = 40;     // Profit (points) locked in at arm (break-even + this)
input int    InpRunnerTrailPts    = 150;    // Trail behind peak by this many points once armed (0 = structure-only trail)
input bool   InpRunnerUseStructure= true;   // Also trail behind the last protected internal swing (structure trail)
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
input bool   InpUseRexit           = true;   // MASTER: use the R-multiple phased exit engine (OFF = exact v3.5.0 BE/trail/runner)
input double InpProtectAtR         = 1.0;    // +R to move the stop to break-even (Phase 2 protect)
input double InpProtectLockR       = 0.0;    // R locked at protect (0 = pure break-even + buffer)
input double InpLockAtR            = 1.5;    // +R at which to lock meaningful profit (Phase 2b)
input double InpLockProfitR        = 0.5;    // R of profit locked from +LockR onward
input double InpActivateAtR        = 2.0;    // +R to activate the STRUCTURE RUNNER (Phase 3)
input double InpRunnerGiveBackR    = 2.0;    // Progressive floor beyond activation: lock (curR - this) in R
input bool   InpRunnerExternStruct = true;   // Runner trails behind PROTECTED EXTERNAL structure (primary)
input bool   InpRunnerInternStruct = true;   // Runner also trails behind protected INTERNAL structure (aggressive)
input bool   InpRunnerATRFloor     = true;   // Keep a wide ATR emergency floor under the runner
input double InpRunnerATRfloorMult = 3.0;    // ATR emergency-floor multiple (wide)
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
input string TradeComment       = "ICC-Sci-EA-v4.6.4";
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
input ENUM_ML_MODE InpMLMode=ML_OBSERVE;
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
input bool   InpMLRunnerByProb  = true;  // Learned exit policy: P(2R) selects RUNNER vs a real take-profit (OFF = v4.4.2: never a TP)
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
input bool   InpRunnerWhenNoInference = false; // No ML probability available -> ride open-ended (true=legacy v4.6.1) or attach a >=InpMinTPRR take-profit (false)
input double InpMLRunnerMinP2R  = 0.75;  // P(2R) at/above which the trade runs with NO fixed TP (below it, a >=InpMinTPRR target is attached)
input double InpML2RLowThreshold= 0.00;  // >0: signals in [this .. InpML2RThreshold) TRADE at InpMLLowRiskMult instead of being vetoed (0 = legacy veto)
input bool   InpMLObserveWhenBusy=true;  // Evaluate + log the gate for signals that fire while a position is open (records only; places NO order)
input bool   InpMLLogInference=false;
input bool   InpMLExportCSV=true;
input string InpMLCSVFile="ICC_ML_dataset_v1.csv";
input group "=== ML v2 Trade Labeling (icc_ml_v2) ==="
input bool   InpMLv2Export  = true;                 // Write ONE finalized row per completed trade (true 2R label)
input string InpMLv2CSVFile = "ICC_ML_dataset_v2.csv"; // Separate one-row-per-trade dataset (train the 2R model on this)
input group "=== ML v4.0 Canonical Dataset ==="
input bool   InpMLv4Export = true;
input string InpMLv4CSVFile = "ICC_ML_dataset_v4.csv";
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
input bool   InpRequireSweep       = true;       // Require a liquidity sweep + reclaim before Indication
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
void PrintBrokerDiagnostics()
  {
   if(!ShowDiagnostics) return;
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long   digits = SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long   stopsLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   spread   = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   Print("==============================================================");
   Print("       ICC TradesBySci EA v4.6.4 - BROKER DIAGNOSTICS         ");
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
//+==================================================================+
//|   v4.1.0 CONTINUATION MINOR-PIVOT FINDER (Core-Engine Finding 3)  |
//|   Replaces the old rolling, unconfirmed iHigh/iLow(TrigTF,2)       |
//|   "2 bars ago" Continuation trigger with a genuine CONFIRMED       |
//|   minor-swing fractal on TrigTF (M15), reusing the SAME validated- |
//|   neighbor-bar pivot test (IsPivotHighTF/IsPivotLowTF) already      |
//|   used by the D1/H4/H1/M15 cascade -- just at a much shallower,     |
//|   faster strength (InpMinorPivotStrength, default 1 bar each side). |
//|   Scans backward from the most recent confirmable bar and returns   |
//|   the FIRST (i.e. nearest / most recent) confirmed pivot within      |
//|   InpMinorPivotLookback bars, so the trigger level reflects a real   |
//|   swing the correction itself actually built, not an arbitrary        |
//|   rolling offset.                                                     |
//+==================================================================+
bool ICC_FindMinorPivotHigh(double &lvl)
  {
   int strength=MathMax(1,InpMinorPivotStrength);
   int bars=Bars(_Symbol,TrigTF);
   int maxShift=MathMin(InpMinorPivotLookback,bars-strength-2);
   for(int s=strength+1;s<=maxShift;s++)
     {
      if(IsPivotHighTF(TrigTF,s,strength)){ lvl=iHigh(_Symbol,TrigTF,s); return true; }
     }
   return false;
  }
bool ICC_FindMinorPivotLow(double &lvl)
  {
   int strength=MathMax(1,InpMinorPivotStrength);
   int bars=Bars(_Symbol,TrigTF);
   int maxShift=MathMin(InpMinorPivotLookback,bars-strength-2);
   for(int s=strength+1;s<=maxShift;s++)
     {
      if(IsPivotLowTF(TrigTF,s,strength)){ lvl=iLow(_Symbol,TrigTF,s); return true; }
     }
   return false;
  }
//+==================================================================+
//|   v4.3.0 STRUCTURAL CORRECTION HELPERS (deferred fidelity item)   |
//|   Implements the Sci definition of a Correction as a CONFIRMED    |
//|   counter-trend structural swing plus a held impulse origin,       |
//|   rather than a fib-percentage band. Both helpers are PURE reads   |
//|   (no global mutation) and use only CONFIRMED pivots on closed     |
//|   bars, so they introduce no lookahead: ICC_FindMinorPivotHigh/Low |
//|   scan from shift=strength+1 and IsPivotHighTF/LowTF require the   |
//|   newer neighbour bars to already exist and be valid (>0).         |
//+==================================================================+
//--- A genuine counter-trend structural swing has formed against the
//    impulse: a confirmed LOWER HIGH below the impulse extreme (dir=+1),
//    or a confirmed HIGHER LOW above the impulse extreme (dir=-1).
//    'bandEdge' returns the pivot level, which becomes the shallow edge
//    of the pullback band for the FVG-containment test (replacing the
//    fib disc/prem edge when structural mode is ON).
//    'leg' is the impulse leg; the pivot must sit at least
//    InpStructCorrMinRetrace * leg away from the impulse extreme so a
//    micro-pivot at the top/bottom of the impulse cannot pose as a
//    correction.
// AUDIT FIX (v4.3.1 / Finding A, CRITICAL): bounded variants of the minor-pivot
// finders. They are identical to ICC_FindMinorPivotHigh/Low EXCEPT that the scan
// is additionally capped at 'maxShiftLimit', so only pivots NEWER than a given
// bar can be returned. Leakage discipline is unchanged: the scan still starts at
// shift=strength+1 and IsPivotHighTF/LowTF still require the newer neighbour bars
// to exist and be valid (>0), so only CONFIRMED pivots on CLOSED bars are used.
bool ICC_FindMinorPivotHighSince(double &lvl,int maxShiftLimit)
  {
   int strength=MathMax(1,InpMinorPivotStrength);
   int bars=Bars(_Symbol,TrigTF);
   int maxShift=MathMin(InpMinorPivotLookback,bars-strength-2);
   if(maxShiftLimit>=0) maxShift=MathMin(maxShift,maxShiftLimit);
   for(int s=strength+1;s<=maxShift;s++)
     {
      if(IsPivotHighTF(TrigTF,s,strength)){ lvl=iHigh(_Symbol,TrigTF,s); return true; }
     }
   return false;
  }
bool ICC_FindMinorPivotLowSince(double &lvl,int maxShiftLimit)
  {
   int strength=MathMax(1,InpMinorPivotStrength);
   int bars=Bars(_Symbol,TrigTF);
   int maxShift=MathMin(InpMinorPivotLookback,bars-strength-2);
   if(maxShiftLimit>=0) maxShift=MathMin(maxShift,maxShiftLimit);
   for(int s=strength+1;s<=maxShift;s++)
     {
      if(IsPivotLowTF(TrigTF,s,strength)){ lvl=iLow(_Symbol,TrigTF,s); return true; }
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
// AUDIT FIX (v4.3.1 / Finding A, CRITICAL -- structural correction could confirm
// with NO pullback at all). As written in v4.3.0 this helper had TWO defects:
//   (1) It called the UNBOUNDED ICC_FindMinorPivotHigh/Low, which returns the
//       nearest confirmed pivot within InpMinorPivotLookback (20) TrigTF bars --
//       with NO requirement that the pivot formed AFTER the Indication. A pivot
//       high left behind BEFORE the impulse trivially satisfies the "lower high"
//       test, so a Correction could be declared on the very bar the Indication
//       fired, off a pivot that has nothing to do with any pullback.
//   (2) It never verified that price had ACTUALLY RETRACED. The only price test
//       was on the pivot level, not on the pullback extreme.
//   The two combined were self-triggering: g_indExtreme = MathMax(wkH1,m15c1), so
//   whenever m15c1 is the impulse extreme the LH test "mpHi < g_indExtreme -
//   floorDist" ALGEBRAICALLY IMPLIES "m15c1 > mpHi" -- which is exactly the
//   Continuation trigger. Indication -> Correction -> Continuation could therefore
//   complete within a bar or two with ZERO pullback: the precise opposite of the
//   Sci definition this toggle exists to implement.
//   FIX: (a) bound the pivot search to bars NEWER than the Indication via
//   ICC_FindMinorPivot*Since(), and (b) require a genuine retracement --
//   'pullbackPx' (the live counter-trend extreme) must itself have travelled at
//   least InpStructCorrMinRetrace * leg back from the impulse extreme. Both
//   conditions must hold, so a correction now requires real counter-trend travel
//   AND a confirmed counter-trend swing that formed during it.
bool ICC_StructuralCorrectionOK(int dir,double leg,double pullbackPx,double &bandEdge)
  {
   bandEdge=0.0;
   if(leg<=0.0) return false;
   if(pullbackPx<=0.0) return false;
   double floorDist=MathMax(0.0,InpStructCorrMinRetrace)*leg;
   int indShift=ICC_IndicationShiftTrigTF();
   // Only pivots strictly NEWER than the Indication bar qualify. indShift-1 is
   // the newest bar that is still at-or-after the Indication; -1 means the stamp
   // is unavailable (fresh attach) in which case we FAIL CLOSED rather than fall
   // back to the unbounded scan that caused this defect.
   if(indShift<0) return false;
   int maxShiftLimit=indShift-1;
   if(maxShiftLimit<1) return false;      // Indication too recent for a confirmed pivot yet
   if(dir==1)
     {
      // (b) ACTUAL retracement: the pullback low must sit below the impulse peak
      //     by at least the anti-noise floor.
      if(pullbackPx > g_indExtreme-floorDist) return false;
      double mpHi=0.0;
      if(!ICC_FindMinorPivotHighSince(mpHi,maxShiftLimit)) return false;
      if(mpHi<=0.0) return false;
      // (a) LOWER HIGH formed SINCE the Indication, below the impulse peak by at
      //     least the anti-noise floor.
      if(mpHi >= g_indExtreme-floorDist) return false;
      bandEdge=mpHi;
      return true;
     }
   if(dir==-1)
     {
      // (b) ACTUAL retracement: the pullback high must sit above the impulse
      //     trough by at least the anti-noise floor.
      if(pullbackPx < g_indExtreme+floorDist) return false;
      double mpLo=0.0;
      if(!ICC_FindMinorPivotLowSince(mpLo,maxShiftLimit)) return false;
      if(mpLo<=0.0) return false;
      // (a) HIGHER LOW formed SINCE the Indication.
      if(mpLo <= g_indExtreme+floorDist) return false;
      bandEdge=mpLo;
      return true;
     }
   return false;
  }
//--- Structural invalidation: a BODY CLOSE back beyond the protected swing
//    the Indication broke (g_indLevel). Reclaiming the broken level means
//    the BOS failed -- the structural death of the setup. Uses the just-
//    closed TrigTF close (m15c1), consistent with every other body-close
//    test in this EA (InpBOSUseClose semantics).
bool ICC_StructuralInvalidated(int dir,double m15c1)
  {
   if(g_indLevel<=0.0 || m15c1<=0.0) return false;
   if(dir==1)  return (m15c1 < g_indLevel);   // bull impulse origin lost
   if(dir==-1) return (m15c1 > g_indLevel);   // bear impulse origin lost
   return false;
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
int HTFbias()
  {
   const int h4Ext = g_extTrend;
   if(h4Ext==0) return 0;                 // no confirmed external H4 trend yet
   if(!UseD1Filter) return h4Ext;         // D1 ignored -> pure external H4
   double sc = HTFscore();
   // v4.2.4 (judgment call (a)): InpHTFStrictBoundary selects the comparison.
   // OFF -> inclusive >=/<= (EXACT v4.2.3): score AT the floor passes.
   // ON  -> strict  >/<           : score EXACTLY at the floor is VETOED, so an
   //        opposing D1 that drags conviction down to the threshold blocks the
   //        trade instead of allowing it. See the input comment for the worked
   //        example and A/B guidance.
   if(InpHTFStrictBoundary)
     {
      if(h4Ext==1  && sc >  HTF_MinConviction) return  1;
      if(h4Ext==-1 && sc < -HTF_MinConviction) return -1;
     }
   else
     {
      if(h4Ext==1  && sc >=  HTF_MinConviction) return  1;
      if(h4Ext==-1 && sc <= -HTF_MinConviction) return -1;
     }
   return 0;                              // D1 opposition reduced H4 conviction below threshold
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
//--- DUAL MARKET STRUCTURE: external governs DIRECTION, internal ENTRY.
//    AUDIT FIX (v4.1.0 / Finding 1+2): External now genuinely computes on
//    g_extTF (MidTF/H4); Internal now genuinely computes on g_intTF (WorkTF/
//    H1) -- previously both shared g_mseTF and differed ONLY by fractal
//    strength, which is not genuine timeframe separation.
void MSE_UpdateStructure()
  {
   int extBefore=g_extTrend;
   bool extBOS=false,intBOS=false;
   MSE_UpdateTrendScale(InpExtSwingStrength,g_extProtHigh,g_extProtLow,g_extTrend,g_extTF,extBOS);
   MSE_UpdateTrendScale(InpIntSwingStrength,g_intProtHigh,g_intProtLow,g_intTrend,g_intTF,intBOS);
   // AUDIT FIX (v4.5.0 / Finding 6, MEDIUM, LOGIC -- corrects the v4.3.6 Finding C
   // implementation). v4.3.6 asserted "a CHANGE in the external trend is the only
   // evidence of a genuine fresh protected-swing BOS" and stamped on
   // "g_extTrend!=extBefore". That is false, and it inverts the rule it implements.
   // A market in a STRONG, HEALTHY trend keeps breaking protected swings in the SAME
   // direction: every one of those is a fresh BOS, but none of them CHANGES the trend
   // value, so g_extLastBOSTime was never restamped and g_extBarsNoBOS kept counting.
   // With InpNeutralOnConsolidation=ON, after InpConsolidationBars MidTF bars the
   // engine therefore declared CONSOLIDATION and forced g_extTrend=0 in the middle of
   // the cleanest trend available -- HTFbias() then returns 0 and the ICC engine
   // refuses to start any new setup. The toggle that exists to STOP the EA
   // manufacturing setups in chop was instead suppressing it in trend.
   // FIX: stamp on a genuine BOS (reported by the scale updater), not on a change of
   // sign. A trend change without a BOS (i.e. the consolidation reset below) is
   // deliberately NOT treated as BOS evidence.
   if(extBOS)
     { g_extLastBOSTime=iTime(_Symbol,g_extTF,0); g_extBarsNoBOS=0; }
   else if(g_extTrend!=extBefore && g_extTrend!=0)
     { g_extLastBOSTime=iTime(_Symbol,g_extTF,0); g_extBarsNoBOS=0; }
   MSE_ApplyConsolidationNeutral();
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
//--- Master per-bar refresh: structure -> liquidity -> FVGs -> OBs.
//    Also feeds the PROTECTED internal swings to the ICC anchors so
//    the ICC Indication only ever breaks a protected swing.
//    AUDIT FIX (v4.1.0 / Finding 1+2): g_extTF/g_intTF are now FIXED to
//    MidTF/WorkTF respectively (assigned once in OnInit; MidTF/WorkTF are
//    themselves plain ENUM_TIMEFRAMES inputs and cannot change mid-run), so
//    there is no more per-bar "which TF am I on" resolution here -- removed
//    the g_mseTF=(InpMSE_TF==PERIOD_CURRENT)?... line entirely (InpMSE_TF no
//    longer exists). The bar-count readiness guard now checks BOTH TFs, since
//    External (H4) and Internal (H1) each need their own history loaded.
void MSE_Update()
  {
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
//+==================================================================+
//|        ICC PULLBACK ENGINE  (Indication -> Correction ->         |
//|        Continuation)  — the genuine Sci-style entry.             |
//+==================================================================+
//+==================================================================+
//|   v3.9.3 ICC IMPULSE MATURATION                                  |
//|   Returns true when the current Indication impulse is mature      |
//|   enough to evaluate the discount/premium and invalidation band.  |
//|   Mature = (bars since Indication >= InpICCImpulseBars) OR         |
//|   (leg >= InpICCMinLegATR x ATR). Guard OFF -> always true, i.e.   |
//|   EXACT v3.9.2 behaviour. Leakage-free: uses only the just-closed  |
//|   impulse leg and the confirmed ATR, no future bars.              |
//+==================================================================+
bool ICC_ImpulseMature(double leg)
  {
   if(!InpUseImpulseMaturation) return true;                 // default OFF = exact v3.9.2
   bool barsOK = ((g_barCount-g_iccStartBar) >= InpICCImpulseBars);
   double atr  = g_mseATRval;
   bool legOK  = (InpICCMinLegATR>0.0 && atr>0.0 && leg >= InpICCMinLegATR*atr);
   return (barsOK || legOK);
  }
void ICC_Reset()
  {
   g_iccPhase=PH_NONE; g_iccDir=0;
   g_indLevel=0; g_indExtreme=0; g_corrExtreme=0; g_iccStartBar=0;
   g_iccStartTime=0;   // v4.3.1 (Finding A): clear the Indication time stamp too
   g_corrStartTime=0;  // v4.3.6 (Finding B): clear the Correction stamp too
   g_mlIndStartBar=0; g_mlCorrStartBar=0;
  }
// AUDIT FIX (v4.0.6 / GATE-DIAGNOSTIC CALL-PATH, EA<->Pine PARITY): the Pine
// twin's own v4.0.5 changelog documents this exact defect and claims it
// "mirrors EA v4.0.5 1:1" -- but the EA never actually received the fix. As
// originally written, ICC_Update() called this function AFTER a data guard
// (if(m15c1<=0||wkH1<=0||wkL1<=0) return;), so on ANY bar where WorkTF/TrigTF
// history wasn't yet available (extremely common in the Strategy Tester
// depending on modeling mode, or right after attach/symbol-switch), the
// diagnostic was never reached at all -- zero [ICC GATE] lines, with no
// indication of WHY. Separately, this function only ever printed when
// htf==1 or htf==-1, so a FLAT HTF bias (very possible if D1/H4 don't yet
// have 2 confirmed pivots) also produced total silence. Fix: ICC_Update()
// now calls this BEFORE the data guard (see below), and three new log paths
// ensure the engine can never go dark with zero explanation: (1) an explicit
// SKIP log when UseICCPullback is OFF, (2) a FLAT log when htf==0, and (3) a
// DATA-GUARD tripped log emitted from ICC_Update() itself when the M15/H1
// series aren't ready. Purely additive/diagnostic -- no ICC/entry/trading
// logic changed.
// AUDIT FIX (v4.1.0 / Core-Engine Finding 3): m15h2/m15l2 parameters removed --
// the Continuation trigger is no longer a fixed rolling 2-bar-ago offset
// computed once in ICC_Update() and passed in; each CONT branch below now
// calls ICC_FindMinorPivotHigh/Low() itself to report the SAME genuine
// confirmed minor-pivot level the real Continuation gate now uses.
void ICC_LogGateDiagnostics(int htf,double m15c1,double wkH1,double wkL1)
  {
   // v4.2.1 HEARTBEAT: fires BEFORE the InpICCGateDiagnostics flag check (and is
   // reached every bar because ICC_Update() calls this before its data guard),
   // so it prints even when the full gate-diagnostics are OFF. Throttled to one
   // line per InpGateHeartbeatBars processed bars. Read-only: no ICC/gating/
   // sizing/trading state is touched -> trade results are unchanged.
   if(InpGateHeartbeatBars>0)
     {
      static int s_gateHeartbeat=0;
      if((++s_gateHeartbeat % InpGateHeartbeatBars)==0)
         PrintFormat("[ICC GATE] heartbeat bar=%d htf=%d phase=%d dir=%d extTrend=%d intTrend=%d sweepL=%d sweepS=%d sig(b/s)=%d/%d",
            g_barCount,htf,g_iccPhase,g_iccDir,g_extTrend,g_intTrend,
            g_sweepConfLong,g_sweepConfShort,(int)iccBuySig,(int)iccSellSig);
     }
   if(!InpICCGateDiagnostics) return;
   if(!UseICCPullback)
     {
      PrintFormat("[ICC GATE] SKIP: UseICCPullback=OFF (ICC engine disabled) | phase=%d dir=%d",g_iccPhase,g_iccDir);
      return;
     }
   if(htf==0)
     {
      PrintFormat("[ICC GATE] FLAT: HTFbias()=0 (D1=%d H4cascade=%d H4ext=%d, no confirmed external H4 trend or D1 conviction failed) | phase=%d dir=%d",
          biasD1,biasH4,g_extTrend,g_iccPhase,g_iccDir);
      return;
     }
   if(htf==1)
     {
      bool extOK=(!InpExtTrendControlsDir)||g_extTrend>=0;
      bool sweepOK=(!InpRequireSweep)||g_sweepConfLong>0;
      // AUDIT FIX (v4.0.5 / F6): use the PURE MSE_ScoreDisplacementCalc() for this
      // diagnostics Print only. The mutating MSE_ScoreDisplacement() wrapper was
      // being called here on EVERY bar this flag is on -- including bars where an
      // existing setup already sits in PH_CORRECTION, long after the real
      // Indication break -- silently overwriting g_lastDispScore (and therefore
      // the dashboard AND the "disp" ML feature in all three CSVs) with the
      // CURRENT bar's unrelated score. This diagnostic line only needs the number
      // for its own Print(), never the side effect.
      double disp=MSE_ScoreDisplacementCalc(1,1);
      bool dispOK=(!InpRejectWeakBreaks)||(disp>=InpDispMinScore);
      bool bos=(wkLastHi>0.0 && m15c1>wkLastHi);
      PrintFormat("[ICC GATE] LONG | wkLastHi=%.5f close=%.5f BOS=%d | ext=%d trend=%d | sweep=%d valid=%d | disp=%.2f min=%.2f ok=%d | phase=%d dir=%d | wkH1=%.5f wkL1=%.5f",
         wkLastHi,m15c1,(int)bos,(int)extOK,g_extTrend,(int)sweepOK,g_sweepConfLong,disp,InpDispMinScore,(int)dispOK,g_iccPhase,g_iccDir,wkH1,wkL1);
      if(g_iccPhase==PH_CORRECTION && g_iccDir==1)
        {
         double leg=g_indExtreme-g_indLevel;
         double disc=(leg>0.0)?g_indExtreme-leg*(InpUseOTE?InpOTEmin:CorrRetraceMin):0.0;
         // AUDIT FIX (v4.3.2 / Finding F6, MEDIUM, MISLEADING DIAGNOSTIC): the
         // structural state was computed BELOW this point, so fvgOK was
         // evaluated against the FIB disc edge even when
         // InpUseStructuralCorrection=ON -- while the ENGINE (ICC_Update's
         // PH_CORRECTION branch) substitutes the correction's own confirmed
         // LOWER HIGH for that edge before calling MSE_FVGContainOK. The
         // printed "FVG=" field could therefore DISAGREE with the gate the
         // engine actually evaluated on the same bar -- precisely the log
         // field used to diagnose blocked continuations. Fix: hoist the
         // structural read ABOVE fvgOK and apply the SAME substitution the
         // engine performs, so the diagnostic mirrors the real gate. Both
         // helpers remain PURE reads (no ICC state mutated), and when the
         // toggle is OFF discEff==disc, so the OFF-path line is unchanged.
         double sEdgeL=0.0; bool sOKL=ICC_StructuralCorrectionOK(1,leg,g_corrExtreme,sEdgeL); // v4.3.1: pullback extreme
         bool   originHeldL=!ICC_StructuralInvalidated(1,m15c1);
         double discEff=disc;
         if(InpUseStructuralCorrection && sOKL && sEdgeL>0.0) discEff=sEdgeL;
         bool fvgOK=(!InpRequireFVGpullback)||MSE_FVGContainOK(1,g_corrExtreme,discEff);
         bool obOK=(!InpRequireOB)||!InpUseOrderBlocks||MSE_InActiveOB(1,g_corrExtreme);
         double mpHi=0.0; bool haveMP=ICC_FindMinorPivotHigh(mpHi);
         bool reclaim=haveMP && m15c1>mpHi;
         // v4.3.0: expose WHICH correction definition is governing and the
         // structural state behind it (pure reads; no state mutated).
         // v4.3.2: print the EFFECTIVE edge actually used by the containment
         // test (discEff), alongside the raw fib edge, so both are visible.
         PrintFormat("[ICC GATE] LONG CONT | leg=%.5f corr=%.5f discEff=%.5f (fib=%.5f) | minorPivotHi=%.5f(%d) | trigger=%d | FVG=%d | OB=%d | corrDef=%s structLH=%.5f(%d) originHeld=%d",leg,g_corrExtreme,discEff,disc,mpHi,(int)haveMP,(int)reclaim,(int)fvgOK,(int)obOK,(InpUseStructuralCorrection?"STRUCT":"FIB"),sEdgeL,(int)sOKL,(int)originHeldL);
        }
     }
   else if(htf==-1)
     {
      bool extOK=(!InpExtTrendControlsDir)||g_extTrend<=0;
      bool sweepOK=(!InpRequireSweep)||g_sweepConfShort>0;
      // AUDIT FIX (v4.0.5 / F6): pure Calc variant -- see the LONG branch comment above.
      double disp=MSE_ScoreDisplacementCalc(1,-1);
      bool dispOK=(!InpRejectWeakBreaks)||(disp>=InpDispMinScore);
      bool bos=(wkLastLo>0.0 && m15c1<wkLastLo);
      PrintFormat("[ICC GATE] SHORT | wkLastLo=%.5f close=%.5f BOS=%d | ext=%d trend=%d | sweep=%d valid=%d | disp=%.2f min=%.2f ok=%d | phase=%d dir=%d | wkH1=%.5f wkL1=%.5f",
         wkLastLo,m15c1,(int)bos,(int)extOK,g_extTrend,(int)sweepOK,g_sweepConfShort,disp,InpDispMinScore,(int)dispOK,g_iccPhase,g_iccDir,wkH1,wkL1);
      if(g_iccPhase==PH_CORRECTION && g_iccDir==-1)
        {
         double leg=g_indLevel-g_indExtreme;
         double prem=(leg>0.0)?g_indExtreme+leg*(InpUseOTE?InpOTEmin:CorrRetraceMin):0.0;
         // AUDIT FIX (v4.3.2 / Finding F6): mirror of the LONG branch -- the
         // structural read is hoisted ABOVE fvgOK and the engine's own edge
         // substitution (correction's confirmed HIGHER LOW) is applied, so the
         // printed "FVG=" field can no longer disagree with the gate the
         // engine actually evaluated. Pure reads; OFF-path unchanged.
         double sEdgeS=0.0; bool sOKS=ICC_StructuralCorrectionOK(-1,leg,g_corrExtreme,sEdgeS); // v4.3.1: pullback extreme
         bool   originHeldS=!ICC_StructuralInvalidated(-1,m15c1);
         double premEff=prem;
         if(InpUseStructuralCorrection && sOKS && sEdgeS>0.0) premEff=sEdgeS;
         bool fvgOK=(!InpRequireFVGpullback)||MSE_FVGContainOK(-1,g_corrExtreme,premEff);
         bool obOK=(!InpRequireOB)||!InpUseOrderBlocks||MSE_InActiveOB(-1,g_corrExtreme);
         double mpLo=0.0; bool haveMP=ICC_FindMinorPivotLow(mpLo);
         bool reclaim=haveMP && m15c1<mpLo;
         // v4.3.0: mirror of the LONG CONT diagnostic (pure reads).
         // v4.3.2: print the EFFECTIVE edge actually used by the containment
         // test (premEff), alongside the raw fib edge, so both are visible.
         PrintFormat("[ICC GATE] SHORT CONT | leg=%.5f corr=%.5f premEff=%.5f (fib=%.5f) | minorPivotLo=%.5f(%d) | trigger=%d | FVG=%d | OB=%d | corrDef=%s structHL=%.5f(%d) originHeld=%d",leg,g_corrExtreme,premEff,prem,mpLo,(int)haveMP,(int)reclaim,(int)fvgOK,(int)obOK,(InpUseStructuralCorrection?"STRUCT":"FIB"),sEdgeS,(int)sOKS,(int)originHeldS);
        }
     }
  }
//+==================================================================+
//|  v4.3.6 SCI CORE FIDELITY SHADOW EVALUATOR  (Working Document s9) |
//|  DIAGNOSTIC ONLY. Reads state, sets NONE. Never gates a trade.    |
//|                                                                  |
//|  The Working Document s13 states the working hypothesis plainly:  |
//|  "the EA's lack of trades may not mean the core ICC setup is      |
//|  absent. It may mean the implementation has accumulated enough    |
//|  additional SMC/ICT-style filters that legitimate ICC setups are  |
//|  being rejected before reaching the entry gate."                  |
//|  s9 prescribes the experiment: evaluate every bar against the     |
//|  CORE rulebook in three layers and LOG THE FIRST RULE THAT FAILS, |
//|  so a methodology failure can be told apart from over-filtering:  |
//|    Layer A  SCI CORE        CORE-01..CORE-09 (must hold)          |
//|    Layer B  SCI CONFLUENCE  liquidity, session                    |
//|    Layer C  EA ENHANCEMENT  FVG, OB, displacement, fib/OTE        |
//|  s10 fixes the record's fields; this emits exactly those, on ONE  |
//|  compact line, so the MT5 Journal is not flooded.                 |
//+==================================================================+
void ICC_ShadowEvaluate(int htf,double m15c1,double wkH1,double wkL1)
  {
   if(!InpSciCoreShadow) return;
   // Throttle (s10: "without flooding the MT5 Journal").
   if(InpSciShadowThrottle>0)
     {
      static int s_shadowN=0;
      if((++s_shadowN % InpSciShadowThrottle)!=0) return;
     }
   if(m15c1<=0.0 || wkH1<=0.0 || wkL1<=0.0) return;   // no verdict without data

   //--- Layer A : SCI CORE -------------------------------------------------
   // CORE-02/03: higher-timeframe authority + a marked structural level.
   string firstFail="";
   int    dir=0;
   if(htf==0)                       firstFail="CORE-01/02 HTF direction (neutral or conviction failed)";
   else                             dir=htf;
   double lvl=(dir>0)? wkLastHi : wkLastLo;              // CORE-03 relevant level
   if(firstFail=="" && lvl<=0.0)    firstFail="CORE-03 no relevant protected structural level";
   // CORE-04: a meaningful BODY break of that level = Indication.
   bool coreInd=(firstFail=="" && ((dir>0)? (m15c1>lvl) : (m15c1<lvl)));
   bool inSetup=(g_iccPhase!=PH_NONE && g_iccDir==dir);
   if(firstFail=="" && !coreInd && !inSetup) firstFail="CORE-04 no indication (level not broken by close)";
   // CORE-05: a DISTINCT correction must exist -- measured structurally, never by a
   // fixed fib percentage ("Do not define correction solely by a fixed Fibonacci
   // percentage"). Here: has price actually travelled back off the impulse extreme?
   double legS=(dir>0)? (g_indExtreme-g_indLevel) : (g_indLevel-g_indExtreme);
   double corrTravel=(dir>0)? (g_indExtreme-g_corrExtreme) : (g_corrExtreme-g_indExtreme);
   // AUDIT FIX (v4.3.7 / Finding A, CRITICAL -- MEASUREMENT DEFECT in the v4.3.6
   // evaluator itself). The v4.3.6 test read:
   //     if(firstFail=="" && inSetup && g_iccPhase==PH_INDICATION && !coreCorr)
   // so CORE-05 was only ever applied when a setup was ALREADY LIVE and sitting in
   // PH_INDICATION. On the far more common bar where price merely broke the level
   // with NO setup registered (inSetup==false), the test was SKIPPED ENTIRELY --
   // firstFail stayed empty, and CORE-07 below was likewise skipped because it too
   // required g_iccPhase==PH_CORRECTION. coreEntry therefore evaluated TRUE on a
   // bare Indication bar that had neither a correction NOR a continuation.
   // CONSEQUENCE (observed): the 2026 XAUUSD run reported 4,078 ENH-REJECT and
   // ZERO CORE+ENH PASS. That exact zero was the tell -- it was partly MANUFACTURED,
   // because those bars were fed to Layer C with g_corrExtreme==0.0 (see Finding B).
   // FIX: CORE-05 is now an UNCONDITIONAL requirement of the ICC sequence, exactly
   // as the Working Document defines it (CORE-04 -> CORE-05 -> CORE-07 -> CORE-09:
   // "Enter only after continuation confirmation, not merely because indication
   // occurred"). A bar with no genuine correction now correctly reports CORE-05 as
   // its firstFail instead of silently passing.
   bool coreCorr=(g_iccPhase==PH_CORRECTION && g_iccDir==dir) ||
                 (legS>0.0 && corrTravel>0.0);
   if(firstFail=="" && !coreCorr)
      firstFail="CORE-05 no distinct correction yet";
   // CORE-07/08: continuation = the correction's own structure fails, confirmed on the
   // execution timeframe. Evaluated with the CORRECTION-BOUNDED pivot, which is what
   // CORE-07 actually describes (see Finding B).
   double sPiv=0.0; bool sHave=false;
   if(g_corrStartTime>0)
     {
      int cS=iBarShift(_Symbol,TrigTF,g_corrStartTime,false);
      if(cS>=1) sHave=(dir>0)? ICC_FindMinorPivotHighSince(sPiv,cS-1)
                             : ICC_FindMinorPivotLowSince (sPiv,cS-1);
     }
   bool coreCont=sHave && ((dir>0)? (m15c1>sPiv) : (m15c1<sPiv));
   // AUDIT FIX (v4.3.7 / Finding A): same defect -- the "g_iccPhase==PH_CORRECTION"
   // qualifier meant CORE-07/08 was NEVER tested unless the engine had already
   // reached PH_CORRECTION, so a bar could be scored CORE-PASS with no continuation
   // break at all. CORE-09 states entry follows continuation CONFIRMATION, so this
   // is now unconditional too.
   if(firstFail=="" && !coreCont)
      firstFail="CORE-07/08 no LTF continuation break of the correction structure";
   bool coreEntry=(firstFail=="");                       // CORE-09

   //--- Layer B : SCI CONFLUENCE (never a CORE failure) ---------------------
   int  liq=(dir>0)? g_sweepConfLong : g_sweepConfShort;
   bool liqPresent=(liq>0);
   // NOTE: IsInKillzone() is (a) declared far below this point -- MQL5 needs
   // declaration before use -- and (b) NOT pure: it WRITES g_kzActive/g_inKillzone.
   // Calling it here would break this function's "reads state, sets none" guarantee
   // and could clobber the dashboard readout. Read the cached global instead.
   bool sessOK=g_inKillzone;

   //--- Layer C : EA ENHANCEMENTS (s8 "non-core unless separately validated") --
   // AUDIT FIX (v4.3.7 / Finding B, CRITICAL -- MEASUREMENT DEFECT): v4.3.6 evaluated
   // this layer UNCONDITIONALLY, i.e. even on bars where no setup was live. On those
   // bars ICC_Reset() has set g_corrExtreme = 0.0, and the price 0.0 is of course
   // never inside a fair-value gap or an order block -- so MSE_FVGContainOK and
   // MSE_InActiveOB were FORCED FALSE by a sentinel, not by market structure.
   // Combined with Finding A (which let such bars reach coreEntry==true), EVERY one
   // of them was classified "CORE-PASS / ENH-REJECT". The 4,078 ENH-REJECT count was
   // therefore INFLATED and the 0 CORE+ENH PASS was partly an artifact of this
   // function, not a property of the trading engine.
   // FIX: Layer C is only MEANINGFUL when a genuine correction extreme exists. When
   // it does not, the enhancement verdict is reported as NOT-APPLICABLE and the bar
   // can never be counted as an over-filtering candidate.
   bool corrPxValid=(g_corrExtreme>0.0 && legS>0.0 && corrTravel>0.0);
   bool fvgOK=true, obOK=true, fibOK=true;
   if(corrPxValid)
     {
      double bandEdge=(dir>0)? g_indExtreme-legS*(InpUseOTE?InpOTEmin:CorrRetraceMin)
                             : g_indExtreme+legS*(InpUseOTE?InpOTEmin:CorrRetraceMin);
      fvgOK=(!InpRequireFVGpullback) || MSE_FVGContainOK(dir,g_corrExtreme,bandEdge);
      obOK =(!InpRequireOB) || !InpUseOrderBlocks || MSE_InActiveOB(dir,g_corrExtreme);
      double depth=corrTravel/legS;                      // fib/OTE depth of the correction
      fibOK=(!InpUseStructuralCorrection) ? (depth>=(InpUseOTE?InpOTEmin:CorrRetraceMin)) : true;
     }
   double dispC=MSE_ScoreDisplacementCalc(1,dir);        // PURE read (never clobbers g_lastDispScore)
   bool dispOK=(!InpRejectWeakBreaks) || (dispC>=InpDispMinScore);
   double depthRpt=(legS>0.0)? corrTravel/legS : 0.0;    // reported depth (0 when no correction)
   // The decisive measurement s9 asks for: did the CORE model approve a setup that the
   // ENHANCEMENT layer then rejected? That count is the whole point of the experiment --
   // and it is only valid when Layer C was actually evaluable.
   bool enhAll=(fvgOK && obOK && dispOK && fibOK);
   string verdict;
   if(!coreEntry)             verdict="CORE-REJECT";
   else if(!corrPxValid)      verdict="CORE-PASS / ENH-N/A";   // must not be counted either way
   else if(enhAll)            verdict="CORE+ENH PASS";
   else                       verdict="CORE-PASS / ENH-REJECT  <<< over-filtering candidate";

   PrintFormat("[SCI CORE] bar=%d t=%s | H4ext=%d D1=%d htf=%d | H1prot=%.5f dir=%d | indLvl=%.5f brokeByClose=%d | phase=%s corrRange=%.5f depth=%.2f | liq=%s(%d) sess=%s | LTFcont=%d pivot=%.5f | CORE=%s | FVG=%d OB=%d DISP=%.0f/%.0f=%d FIB=%d | %s%s",
      g_barCount,TimeToString(iTime(_Symbol,_Period,1),TIME_DATE|TIME_MINUTES),
      g_extTrend,biasD1,htf,
      lvl,dir,
      g_indLevel,(int)coreInd,
      (g_iccPhase==PH_INDICATION?"IND":g_iccPhase==PH_CORRECTION?"COR":"---"),
      corrTravel,depthRpt,
      (liqPresent?"present":"absent"),liq,(sessOK?"in":"out"),
      (int)coreCont,sPiv,
      (coreEntry?"ENTRY":"no"),
      (int)fvgOK,(int)obOK,dispC,InpDispMinScore,(int)dispOK,(int)fibOK,
      verdict,
      (coreEntry?"":"  firstFail="+firstFail));
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

//--- LEG SHAPE. Widest single g_intTF bar range inside the impulse, as a
//    fraction of the whole impulse leg. ~1.0 = one violent displacement bar did
//    all the work; ~0.2 = a slow grind. impulse_leg_atr cannot express this:
//    both profiles can measure 2.3 ATR.
//    Scanned from the Indication bar down to the Correction bar, so correction
//    bars are excluded from the measurement.
double ICC_ImpulseConcentration(double leg)
  {
   if(leg<=0.0 || g_iccStartTime<=0) return 0.0;
   int shInd=iBarShift(_Symbol,g_intTF,g_iccStartTime,false);
   if(shInd<1) return 0.0;
   int shEnd=1;
   if(g_corrStartTime>0)
     { int sc=iBarShift(_Symbol,g_intTF,g_corrStartTime,false); if(sc>=1) shEnd=sc+1; }
   // AUDIT FIX (v4.6.2 / Finding 5, MEDIUM, MODEL CONTRACT): when the Correction
   // confirms on the SAME g_intTF bar as the Indication (common on an M15 chart
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
      double h=iHigh(_Symbol,g_intTF,sBar), l=iLow(_Symbol,g_intTF,sBar);
      if(h<=0.0 || l<=0.0) continue;              // incomplete history -> skip bar
      double rng=h-l; if(rng>widest) widest=rng;
     }
   return MathMax(0.0,MathMin(1.0,widest/leg));
  }

//--- PULLBACK SHAPE. Count of CONFIRMED TrigTF minor pivots (highs and lows)
//    formed since the Correction began. 1-2 = a tight single-leg flag; 4+ = a
//    sloppy multi-leg pullback. Uses the SAME validated-neighbour-bar fractal
//    test (IsPivotHighTF/IsPivotLowTF) the cascade and the continuation trigger
//    already use, so only pivots on CLOSED, CONFIRMED bars are counted and no
//    lookahead is introduced.
double ICC_CorrectionLegCount()
  {
   if(g_corrStartTime<=0) return 0.0;
   int cSh=iBarShift(_Symbol,TrigTF,g_corrStartTime,false);
   if(cSh<1) return 0.0;
   if(cSh>400) cSh=400;                           // hard bound; expiry makes this unreachable
   int strength=MathMax(1,InpMinorPivotStrength);
   int n=0;
   for(int sBar=strength+1;sBar<=cSh;sBar++)
     {
      if(IsPivotHighTF(TrigTF,sBar,strength))     n++;
      else if(IsPivotLowTF(TrigTF,sBar,strength)) n++;
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

void ICC_Update()
  {
   iccBuySig=false; iccSellSig=false; iccSigSL=0;
   // v4.2.2 (Audit F1/F6): the UseICCPullback early-return was RELOCATED to
   // BELOW the ICC_LogGateDiagnostics() call further down. Previously it sat
   // here, so when UseICCPullback=OFF the function returned before the
   // diagnostic ran -- making BOTH the v4.2.1 heartbeat AND the "[ICC GATE]
   // SKIP: UseICCPullback=OFF" branch unreachable dead code, in exactly the
   // "engine disabled / dark" configuration the heartbeat was added to expose.
   // HTFbias()/iClose()/iHigh()/iLow() below are side-effect-free reads, so
   // evaluating them before the return is safe and changes no trading state.
   int    htf   = HTFbias();
   double m15c1 = iClose(_Symbol,TrigTF,1);   // just-closed M15 close
   // AUDIT FIX (v4.1.0 / Core-Engine Finding 3): m15h2/m15l2 (the old rolling,
   // unconfirmed "2 bars ago" offset) are REMOVED here -- the genuine confirmed
   // minor-pivot level is now looked up fresh, only when actually needed, inside
   // the CONTINUATION branches below via ICC_FindMinorPivotHigh/Low().
   double wkH1  = iHigh (_Symbol,WorkTF,1);   // last closed H1 high
   double wkL1  = iLow  (_Symbol,WorkTF,1);   // last closed H1 low
   // AUDIT FIX (v4.0.6 / GATE-DIAGNOSTIC CALL-PATH): moved BEFORE the data
   // guard below (was AFTER it) -- see the full explanation on
   // ICC_LogGateDiagnostics() above. An HTF-eligible bar now ALWAYS reports
   // either its gate reasons or the specific reason it aborts; this call
   // changes NO ICC state and NO trading decision.
   ICC_LogGateDiagnostics(htf,m15c1,wkH1,wkL1);
   // v4.3.6 (Working Document s9): the Core Fidelity shadow evaluator runs on the SAME
   // call path and BEFORE the data guard, so a CORE verdict exists for every bar the
   // gate diagnostics can describe. Diagnostic-only: it reads state and sets none.
   ICC_ShadowEvaluate(htf,m15c1,wkH1,wkL1);
   if(!UseICCPullback) return;   // v4.2.2 (F1/F6): moved here from the top of the
                                 // function so the heartbeat + SKIP diagnostic above
                                 // always run first; no ICC state was touched before this.
   if(m15c1<=0 || wkH1<=0 || wkL1<=0)
     {
      // AUDIT FIX (v4.0.6 / GATE-DIAGNOSTIC CALL-PATH): explicit visibility for
      // the data guard itself -- previously this silently returned with zero
      // trace of which series was missing (the Pine analogue of this same
      // tester/history-gap condition already logs this).
      if(InpICCGateDiagnostics)
         PrintFormat("[ICC GATE] DATA-GUARD tripped -> ICC update aborted | TrigTF close=%.5f | WorkTF H1=%.5f L1=%.5f | htf=%d phase=%d  (ensure TrigTF+WorkTF history is loaded)",
            m15c1,wkH1,wkL1,htf,g_iccPhase);
      return; // data guard (tester modeling)
     }
   // v3.4.0 OTE window: when ON, the Correction must reach the 0.62-0.79
   // OTE band; effMin/effMax replace the raw CorrRetrace bounds below.
   double effMin = InpUseOTE ? InpOTEmin : CorrRetraceMin;
   double effMax = InpUseOTE ? InpOTEmax : CorrRetraceMax;
   // Bias flip cancels an in-progress setup facing the wrong way
   if(g_iccPhase!=PH_NONE && g_iccDir!=0 && htf!=0 && htf!=g_iccDir)
      ICC_Reset();
   // Expiry: setup must complete inside the window
   // AUDIT FIX (v4.3.6 / Finding D, MEDIUM, unit mismatch): ICC_ExpiryBars is
   // documented as "Bars to complete Correction+Continuation", but the Correction
   // develops on WorkTF/H1 (wkH1/wkL1) while g_barCount counts CHART bars. On the
   // documented M15 chart, 30 "bars" is 7.5 hours = ~7 H1 bars, so the setup expires
   // roughly 4x sooner than the input implies. This is the SAME unit-mismatch family
   // already fixed twice (v4.2.7 sweep window, v4.3.3 Finding E sweep re-arm); the
   // expiry counter was simply never brought along. Opt-in so the legacy window is
   // reproducible for A/B.
   bool expired;
   if(InpExpiryInWorkTFBars && g_iccStartTime>0)
     {
      int wSh=iBarShift(_Symbol,WorkTF,g_iccStartTime,false);
      // AUDIT FIX (v4.5.0 / Finding 7, MEDIUM, EDGE CASE): iBarShift() returns -1 when
      // the stamp cannot be located (history gap, tester rebuild, symbol resync, or a
      // stamp older than the loaded WorkTF series). The old test "wSh>=0 && ..." then
      // evaluated FALSE, i.e. NOT EXPIRED -- so precisely in the case where the setup's
      // age is UNKNOWABLE, the expiry guard was disabled and a stale setup could sit in
      // PH_INDICATION/PH_CORRECTION indefinitely, still arming a Continuation off ICC
      // geometry anchored to a bar the terminal can no longer see. An unlocatable stamp
      // must FAIL CLOSED, consistent with every other stamp guard in this file
      // (ICC_StructuralCorrectionOK and InpContTrigSinceCorrection both fail closed).
      expired=(wSh<0) || (wSh>ICC_ExpiryBars);
     }
   else
      expired=((g_barCount-g_iccStartBar)>ICC_ExpiryBars);
   if(g_iccPhase!=PH_NONE && expired)
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
         // AUDIT FIX (v4.3.6 / Finding A, CRITICAL, FIDELITY -- Working Document s7
         // bullet 1 + CORE-04/05/06): the sweep requirement gates the INDICATION.
         // The reviewed public material places liquidity interaction INSIDE THE
         // CORRECTION ("Corrections commonly follow an indication and may grab
         // liquidity"), and CORE-06 explicitly says a mandatory sweep "should not be
         // assumed unless direct methodology evidence supports it". Requiring the raid
         // BEFORE the break therefore REVERSES the documented ICC chronology and, with
         // InpRequireSweep defaulting ON, silently converts a CONFLUENCE factor into a
         // hard pre-condition -- a prime suspect for legitimate ICC setups never
         // reaching the entry gate (Working Document s13). InpLiquidityPhase selects:
         //   LIQ_INDICATION = legacy v4.3.5 (default, byte-identical)
         //   LIQ_CORRECTION = CORE-06 chronology (checked in the Correction instead)
         //   LIQ_OFF        = liquidity is pure confluence, never a gate
         bool sweepOK = (!InpRequireSweep) || (InpLiquidityPhase!=LIQ_INDICATION)
                        || g_sweepConfLong>0;      // SSL swept+reclaimed
         // v4.5.0 Finding 5: latch the PURE score first so the ML feature is populated
         // regardless of InpRejectWeakBreaks; the mutating wrapper below is unchanged.
         g_mlDispAtIndication=MSE_ScoreDisplacementCalc(1,1);
         bool dispOK  = (!InpRejectWeakBreaks)    || (MSE_ScoreDisplacement(1,1)>=InpDispMinScore);
         if(wkLastHi>0 && m15c1>wkLastHi && extOK && sweepOK && dispOK)
           {
            g_iccPhase   = PH_INDICATION;
            g_iccDir     = 1;
            g_indLevel   = wkLastHi;      // impulse origin (broken protected swing)
            g_indExtreme = MathMax(wkH1,m15c1);
            // AUDIT FIX (v4.3.3 / Finding A, CRITICAL): was "g_corrExtreme = wkL1" --
            // the WorkTF LOW OF THE VERY BAR THAT MADE THE BREAK. That low is the
            // BOTTOM OF THE IMPULSE BAR ITSELF, i.e. a price printed BEFORE/DURING
            // the impulse, not a pullback. Measured on the 2025.10.01-2026.08.27
            // XAUUSD M15 journal: the seeded value sat BEYOND the impulse ORIGIN on
            // 74.9% of Indications and already past the deep-invalidation line on
            // 76.9% -- so the very next bar's "wkL1<=inval" test killed the setup
            // instantly. 308 of 315 Indications lasted exactly ONE bar and only
            // 12.7% ever reached Correction. Seed with the impulse extreme: at the
            // instant of the break NO pullback has occurred yet, so the correction
            // extreme IS the extreme.
            g_corrExtreme= g_indExtreme;
            g_iccStartBar= g_barCount;
            // AUDIT FIX (v4.3.3 / Finding D): stamp the CLOSED bar the signal was
            // derived from (bar 1), not the still-forming bar 0. ICC_FindMinorPivot*
            // Since() bounds its scan with this stamp, so a bar-0 stamp shifted the
            // whole structural window one bar into the future.
            g_iccStartTime= iTime(_Symbol,_Period,1);
            g_mlIndStartBar=g_barCount;   // AUDIT FIX (v4.0.5/F7): stamp Indication start for impulse_age_bars
           }
        }
      else if(g_iccPhase==PH_INDICATION && g_iccDir==1)
        {
         // AUDIT FIX (v4.3.4 / Finding B, MEDIUM-HIGH, TRADING-AFFECTING -- residual of
         // the v4.3.3 Finding A): v4.3.3 stopped the IMPULSE BAR's own low from being
         // seeded as the pullback, but the SAME defect survived one bar later. On any
         // later bar this branch (a) extends g_indExtreme with that bar's wkH1 and
         // then (b) lets that SAME bar's wkL1 define the pullback low. On a wide
         // impulsive WorkTF bar that makes a NEW HIGH, its own low is not a
         // retracement at all -- it is the base of a fresh impulse leg -- yet it was
         // written straight into g_corrExtreme and tested against the deep-
         // invalidation line, killing setups on the very bars that confirm strength.
         // FIX: a bar that EXTENDED the impulse cannot also define the correction.
         // The next non-extending bar supplies the genuine pullback.
         // AUDIT FIX (v4.3.5 / Finding A, CRITICAL, TRADE-PATH -- defect INTRODUCED by
         // the v4.3.4 Finding-B guard): v4.3.4 correctly stopped an EXTENDING bar from
         // donating its own low as the pullback -- but it left g_corrExtreme FROZEN at
         // the Indication seed (= the ORIGINAL g_indExtreme) while g_indExtreme kept
         // RISING. The discount threshold disc = ext - leg*CorrRetraceMin therefore
         // climbs toward that frozen value and eventually CROSSES it, so PH_CORRECTION
         // is declared purely because the impulse EXTENDED -- with ZERO retracement.
         // Algebra: pbLow<=disc  <=>  seedExt <= 0.5*(newExt+indLevel)
         //                       <=>  newExt >= 2*seedExt - indLevel.
         // Worked example from the real journal (bar 41): indLevel=3875.58,
         // seedExt=3879.88 -> the moment newExt reaches 3884.18 (just 4.3 pts of
         // FURTHER impulse, no pullback at all) the engine prints PH_CORRECTION, with
         // g_corrExtreme sitting AT the impulse extreme. The Continuation can then fire
         // immediately and iccSigSL = g_corrExtreme - g_slBuf places the stop right at
         // the impulse high. This is the exact zero-pullback failure mode v4.3.1 and
         // v4.3.3 were written to eliminate, reintroduced through the back door.
         // FIX: while the impulse is still EXTENDING no retracement exists by
         // definition, so the correction extreme must TRACK the impulse extreme.
         bool extendedNow=(wkH1>g_indExtreme);
         if(extendedNow){ g_indExtreme=wkH1; g_corrExtreme=g_indExtreme; }  // extend impulse high; no pullback yet
         // AUDIT FIX (v4.3.3 / Finding A, CRITICAL -- second half): the disc/inval
         // band was evaluated against the RAW wkL1 of whatever WorkTF bar happened
         // to be bar-1, INCLUDING the impulse bar itself, whose own low sits at the
         // START of the impulse. A genuine Correction can only be measured from bars
         // that CLOSED AFTER the Indication. We therefore (a) never evaluate the band
         // on the Indication bar itself, and (b) track a real post-impulse pullback
         // low in g_corrExtreme and test THAT, not the raw bar-1 low.
         // NOTE (v4.3.4 / Finding D): "g_barCount>g_iccStartBar" is retained as a
         // DEFENSIVE guard, but it can never be false here -- the PH_NONE branch that
         // fires the Indication and this PH_INDICATION branch are arms of the SAME
         // if/else-if chain, so this code cannot run on the Indication bar. The
         // v4.3.3 changelog credited part of its Finding-A fix to this guard; in
         // reality the seed change (and now Finding B above) is what fixes it.
         if(!extendedNow && g_barCount>g_iccStartBar && wkL1<g_corrExtreme) g_corrExtreme=wkL1;
         double pbLow = g_corrExtreme;                 // genuine post-impulse pullback low
         double leg = g_indExtreme-g_indLevel;
         // v3.9.3: hold the impulse open until it matures (bars OR ATR leg)
         // before arming the disc/inval band; OFF = exact v3.9.2 behaviour.
         if(g_barCount>g_iccStartBar && leg>0 && ICC_ImpulseMature(leg))
           {
            double disc = g_indExtreme - leg*effMin;  // discount threshold
            double inval= g_indExtreme - leg*effMax;  // too-deep threshold
            if(InpUseStructuralCorrection)
              {
               // v4.3.0 STRUCTURAL (Sci definition): the Correction is confirmed
               // by a genuine CONFIRMED LOWER HIGH forming against the impulse --
               // not by price touching a 0.50 fib level -- and the setup stays
               // alive as long as the IMPULSE ORIGIN (g_indLevel, the protected
               // swing the Indication broke) is not reclaimed on a body close.
               // The CorrRetraceMax deep cap is applied ONLY when the operator
               // explicitly keeps it via InpStructCorrKeepMaxDepth.
               double sBandEdge=0.0;
               if(ICC_StructuralInvalidated(1,m15c1) ||
                  (InpStructCorrKeepMaxDepth && pbLow<=inval))
                  ICC_Reset();
               else if(ICC_StructuralCorrectionOK(1,leg,pbLow,sBandEdge))  // v4.3.3: post-impulse pullback low
                 {
                  g_iccPhase   = PH_CORRECTION;
                  g_corrExtreme= pbLow;
                  g_mlCorrStartBar=g_barCount; g_corrStartTime=iTime(_Symbol,_Period,1); // v4.3.6 Finding B: bound the continuation pivot
                 }
              }
            else if(pbLow<=inval)              // pulled back too far -> invalidate
               ICC_Reset();
            else if(pbLow<=disc)               // reached discount -> Correction
              {
               g_iccPhase   = PH_CORRECTION;
               g_corrExtreme= pbLow;
               g_mlCorrStartBar=g_barCount; g_corrStartTime=iTime(_Symbol,_Period,1); // v4.3.6 Finding B: bound the continuation pivot   // AUDIT FIX (v4.0.5/F7): stamp Correction start for correction_age_bars
              }
           }
        }
      else if(g_iccPhase==PH_CORRECTION && g_iccDir==1)
        {
         if(wkL1<g_corrExtreme) g_corrExtreme=wkL1;     // track pullback low
         double leg  = g_indExtreme-g_indLevel;
         double inval= (leg>0)? g_indExtreme-leg*effMax : 0;
         double disc = (leg>0)? g_indExtreme-leg*effMin : g_corrExtreme; // v3.3.9 shallow edge of discount band
         // v4.3.0 STRUCTURAL: (a) the deep-fib invalidation is replaced by the
         // impulse-origin test (body close back below the broken protected
         // swing), and (b) the shallow edge of the pullback band handed to the
         // FVG-containment test becomes the correction's OWN confirmed lower
         // high -- semantically the top of the correction -- instead of the
         // 0.50 fib level. Both revert exactly when the toggle is OFF.
         bool structInval=false;
         if(InpUseStructuralCorrection)
           {
            double sEdge=0.0;
            if(ICC_StructuralCorrectionOK(1,leg,g_corrExtreme,sEdge) && sEdge>0.0) disc=sEdge;   // v4.3.1
            structInval = ICC_StructuralInvalidated(1,m15c1) ||
                          (InpStructCorrKeepMaxDepth && leg>0 && g_corrExtreme<=inval);
           }
         // AUDIT FIX (v4.3.5 / Finding D, LOW, consistency): these tests read the RAW
         // bar-1 low instead of the LATCHED pullback extreme g_corrExtreme (which is
         // the running minimum and was just updated on the line above). Because
         // g_corrExtreme <= wkL1 always, a pullback that breached the deep-invalidation
         // line and then RECOVERED within the same bar-series escaped invalidation --
         // the breach was recorded in g_corrExtreme (and is what the SL is anchored to)
         // but never acted on. Test the latched extreme so invalidation is monotonic,
         // matching the PH_INDICATION branch which already uses pbLow.
         if(InpUseStructuralCorrection ? structInval : (leg>0 && g_corrExtreme<=inval))
           { ICC_Reset(); }
         else
           {
            // CONTINUATION (v3.0): resume up ONLY if the correction pulled into an
            // active bullish FVG and (optionally) an unmitigated bullish order block.
            // v3.3.9: containment via MSE_FVGContainOK (strict point-in-gap, or
            // relaxed tolerance/band overlap when InpRelaxFVGContain is ON).
            bool fvgOK = (!InpRequireFVGpullback) || MSE_FVGContainOK(1,g_corrExtreme,disc);
            bool obOK  = (!InpRequireOB) || !InpUseOrderBlocks || MSE_InActiveOB(1,g_corrExtreme); // v3.3.4: active (unviolated) OB, not "unmitigated"
            // v4.3.6 (Finding A / CORE-06): when the operator moves liquidity to its
            // documented phase, the sweep is required HERE -- during the correction --
            // instead of before the Indication.
            bool liqOK = (InpLiquidityPhase!=LIQ_CORRECTION) || (!InpRequireSweep) || g_sweepConfLong>0;
            // AUDIT FIX (v4.1.0 / Core-Engine Finding 3): the trigger was
            // iHigh(TrigTF,2) -- a rolling, UNCONFIRMED "2 bars ago" offset
            // recomputed every bar with no relation to the correction's own
            // structure. Now a genuine CONFIRMED minor-swing pivot on TrigTF
            // (M15), found via ICC_FindMinorPivotHigh() -- the same validated-
            // neighbor-bar fractal test used by the D1/H4/H1/M15 cascade, at a
            // shallow InpMinorPivotStrength (default 1 bar each side).
            // AUDIT FIX (v4.3.6 / Finding B, HIGH, FIDELITY -- Working Document s7
            // bullet 5 + CORE-07/CORE-08): the trigger called the UNBOUNDED finder,
            // which returns the NEAREST confirmed pivot anywhere in the last
            // InpMinorPivotLookback(20) TrigTF bars -- with NO requirement that the
            // pivot belongs to THIS correction. CORE-07 defines continuation as "the
            // opposing/internal CORRECTION structure fails", so the level that must
            // break is the correction's OWN structural transition. As written, a pivot
            // left behind BEFORE the correction (even before the Indication) could
            // satisfy the trigger -- and because a correction prints LOWER highs, the
            // nearest pivot high typically sits BELOW the correction's top, so the
            // trigger fires early on noise rather than on a genuine structural
            // resumption. The bounded helpers to fix this ALREADY EXIST in this file
            // (ICC_FindMinorPivotHighSince/LowSince, added in v4.3.1) but were only
            // ever wired to the structural-correction helper, never to the trigger.
            // FIX (opt-in): bound the scan to bars newer than the CORRECTION start.
            double minorPivotHi=0.0;
            bool   haveMinorPivot;
            if(InpContTrigSinceCorrection && g_corrStartTime>0)
              {
               int cSh=iBarShift(_Symbol,TrigTF,g_corrStartTime,false);
               // FAIL CLOSED if the stamp is unavailable or the Correction is too
               // recent to contain a confirmed pivot -- never silently fall back to
               // the unbounded scan this fix exists to replace.
               haveMinorPivot=(cSh>=1) && ICC_FindMinorPivotHighSince(minorPivotHi,cSh-1);
              }
            else
               haveMinorPivot=ICC_FindMinorPivotHigh(minorPivotHi);
            if(haveMinorPivot && m15c1>minorPivotHi && fvgOK && obOK && liqOK)
              {
               iccBuySig=true;
               iccSigSL = g_corrExtreme - g_slBuf;      // SL below correction low
               g_mlOTEDepth=(leg>0.0)?(g_indExtreme-g_corrExtreme)/leg:0.0;
               // AUDIT FIX (v4.4.1 / Finding A): latch correction_depth HERE. The
               // feature builder used to recompute it from g_indExtreme/g_indLevel/
               // g_corrExtreme, all of which ICC_Reset() zeroes four lines below --
               // so the feature was a hard 0.0 on every single inference. 'leg' is
               // the impulse span (g_indExtreme-g_indLevel) and is still valid here.
               g_mlCorrectionDepth=(leg>0.0)
                  ? MathMax(0.0,MathMin(1.0,MathAbs(g_corrExtreme-g_indExtreme)/leg))
                  : 0.0;
               // AUDIT FIX (v4.0.5/F7): capture impulse_leg_atr, impulse_age_bars,
               // correction_age_bars, and the genuine phase-at-fire BEFORE ICC_Reset()
               // wipes g_iccPhase/g_indLevel/g_indExtreme back to PH_NONE/0 below.
               g_mlImpulseLegATR=(g_mseATRval>0.0)?leg/g_mseATRval:0.0;
               g_mlImpulseAgeBars=g_mlCorrStartBar-g_mlIndStartBar;
               g_mlCorrectionAgeBars=g_barCount-g_mlCorrStartBar;
               g_mlSigPhaseAtFire=g_iccPhase;
               // v4.6.0 PATH FEATURES: latch all four here, in BOTH branches,
               // while g_iccDir / g_indExtreme / g_corrExtreme / g_iccStartTime /
               // g_corrStartTime are still valid. ICC_Reset() on the next line
               // zeroes every one of them, and ML_Build2RFeatures runs AFTER that
               // -- the exact failure mode of v4.4.1 Finding A. The code is
               // identical in both branches because every calculator takes the
               // direction explicitly, which also removes the long/short drift
               // that produced v4.3.5 Finding A.
               g_mlSweepAge           =(double)((g_iccDir>0)? g_sweepConfLong : g_sweepConfShort);
               g_mlSweepLeadBars      =ICC_SweepLeadBars(g_iccDir);
               g_mlImpulseConcentration=ICC_ImpulseConcentration(leg);
               g_mlCorrLegCount       =ICC_CorrectionLegCount();
               g_mlCorrRecovery       =ICC_CorrectionRecovery(g_iccDir,m15c1);
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
         // AUDIT FIX (v4.3.6 / Finding A): mirror of the LONG branch -- see the full
         // CORE-06 chronology note there.
         bool sweepOK = (!InpRequireSweep) || (InpLiquidityPhase!=LIQ_INDICATION)
                        || g_sweepConfShort>0;     // BSL swept+reclaimed
         // v4.5.0 Finding 5: mirror of the LONG branch -- pure latch for the ML feature.
         g_mlDispAtIndication=MSE_ScoreDisplacementCalc(1,-1);
         bool dispOK  = (!InpRejectWeakBreaks)    || (MSE_ScoreDisplacement(1,-1)>=InpDispMinScore);
         if(wkLastLo>0 && m15c1<wkLastLo && extOK && sweepOK && dispOK)      // INDICATION: BOS down
           {
            g_iccPhase   = PH_INDICATION;
            g_iccDir     = -1;
            g_indLevel   = wkLastLo;      // broken protected support
            g_indExtreme = MathMin(wkL1,m15c1);
            // AUDIT FIX (v4.3.3 / Finding A, CRITICAL): mirror of the LONG branch --
            // was "g_corrExtreme = wkH1", the HIGH of the impulse bar itself (a
            // pre-impulse price), which instantly tripped "wkH1>=inval". Seed with
            // the impulse extreme: no pullback exists at the instant of the break.
            g_corrExtreme= g_indExtreme;
            g_iccStartBar= g_barCount;
            // AUDIT FIX (v4.3.3 / Finding D): stamp the CLOSED signal bar (1).
            g_iccStartTime= iTime(_Symbol,_Period,1);
            g_mlIndStartBar=g_barCount;   // AUDIT FIX (v4.0.5/F7): stamp Indication start for impulse_age_bars
           }
        }
      else if(g_iccPhase==PH_INDICATION && g_iccDir==-1)
        {
         // AUDIT FIX (v4.3.4 / Finding B): mirror of the LONG branch -- a WorkTF bar
         // that makes a NEW LOW (extending the bear impulse) must not simultaneously
         // have its own HIGH treated as the corrective pullback.
         // AUDIT FIX (v4.3.5 / Finding A, CRITICAL): mirror of the LONG branch. While the
         // bear impulse is still EXTENDING, the correction extreme must track the
         // impulse extreme -- otherwise the frozen seed and the RISING premium
         // threshold cross and a Correction is declared with no retracement at all.
         bool extendedNow=(wkL1<g_indExtreme);
         if(extendedNow){ g_indExtreme=wkL1; g_corrExtreme=g_indExtreme; } // extend impulse low; no pullback yet
         // AUDIT FIX (v4.3.3 / Finding A, CRITICAL -- second half): mirror of the
         // LONG branch. Only bars that CLOSED AFTER the Indication may define the
         // pullback; the impulse bar's own HIGH is not a retracement.
         if(!extendedNow && g_barCount>g_iccStartBar && wkH1>g_corrExtreme) g_corrExtreme=wkH1;
         double pbHigh = g_corrExtreme;                // genuine post-impulse pullback high
         double leg = g_indLevel-g_indExtreme;
         // v3.9.3: hold the impulse open until it matures (bars OR ATR leg)
         // before arming the prem/inval band; OFF = exact v3.9.2 behaviour.
         if(g_barCount>g_iccStartBar && leg>0 && ICC_ImpulseMature(leg))
           {
            double prem = g_indExtreme + leg*effMin;  // premium threshold
            double inval= g_indExtreme + leg*effMax;
            if(InpUseStructuralCorrection)
              {
               // v4.3.0 STRUCTURAL: mirror of the LONG branch -- the Correction
               // is confirmed by a CONFIRMED HIGHER LOW against the impulse, and
               // the setup dies only when the impulse ORIGIN is reclaimed on a
               // body close (or the optional deep cap is kept).
               double sBandEdge=0.0;
               if(ICC_StructuralInvalidated(-1,m15c1) ||
                  (InpStructCorrKeepMaxDepth && pbHigh>=inval))
                  ICC_Reset();
               else if(ICC_StructuralCorrectionOK(-1,leg,pbHigh,sBandEdge)) // v4.3.3: post-impulse pullback high
                 {
                  g_iccPhase   = PH_CORRECTION;
                  g_corrExtreme= pbHigh;
                  g_mlCorrStartBar=g_barCount; g_corrStartTime=iTime(_Symbol,_Period,1); // v4.3.6 Finding B: bound the continuation pivot
                 }
              }
            else if(pbHigh>=inval)
               ICC_Reset();
            else if(pbHigh>=prem)
              {
               g_iccPhase   = PH_CORRECTION;
               g_corrExtreme= pbHigh;
               g_mlCorrStartBar=g_barCount; g_corrStartTime=iTime(_Symbol,_Period,1); // v4.3.6 Finding B: bound the continuation pivot   // AUDIT FIX (v4.0.5/F7): stamp Correction start for correction_age_bars
              }
           }
        }
      else if(g_iccPhase==PH_CORRECTION && g_iccDir==-1)
        {
         if(wkH1>g_corrExtreme) g_corrExtreme=wkH1;     // track pullback high
         double leg  = g_indLevel-g_indExtreme;
         double inval= (leg>0)? g_indExtreme+leg*effMax : 0;
         double prem = (leg>0)? g_indExtreme+leg*effMin : g_corrExtreme; // v3.3.9 shallow edge of premium band
         // v4.3.0 STRUCTURAL: mirror of the LONG branch -- impulse-origin
         // invalidation, and the correction's own confirmed HIGHER LOW becomes
         // the shallow edge of the premium band for FVG containment.
         bool structInval=false;
         if(InpUseStructuralCorrection)
           {
            double sEdge=0.0;
            if(ICC_StructuralCorrectionOK(-1,leg,g_corrExtreme,sEdge) && sEdge>0.0) prem=sEdge;  // v4.3.1
            structInval = ICC_StructuralInvalidated(-1,m15c1) ||
                          (InpStructCorrKeepMaxDepth && leg>0 && g_corrExtreme>=inval);
           }
         // AUDIT FIX (v4.3.5 / Finding D): mirror of the LONG branch -- test the
         // latched pullback extreme, not the raw bar-1 high.
         if(InpUseStructuralCorrection ? structInval : (leg>0 && g_corrExtreme>=inval))
           { ICC_Reset(); }
         else
           {
            // CONTINUATION (v3.0): resume down ONLY if the correction pulled into an
            // active bearish FVG and (optionally) an unmitigated bearish order block.
            // v3.3.9: containment via MSE_FVGContainOK (strict point-in-gap, or
            // relaxed tolerance/band overlap when InpRelaxFVGContain is ON).
            bool fvgOK = (!InpRequireFVGpullback) || MSE_FVGContainOK(-1,g_corrExtreme,prem);
            bool obOK  = (!InpRequireOB) || !InpUseOrderBlocks || MSE_InActiveOB(-1,g_corrExtreme); // v3.3.4: active (unviolated) OB, not "unmitigated"
            // v4.3.6 (Finding A / CORE-06): mirror of the LONG branch.
            bool liqOK = (InpLiquidityPhase!=LIQ_CORRECTION) || (!InpRequireSweep) || g_sweepConfShort>0;
            // AUDIT FIX (v4.1.0 / Core-Engine Finding 3): see the LONG branch
            // comment above -- same genuine confirmed minor-pivot trigger,
            // mirrored for the bearish Continuation via ICC_FindMinorPivotLow().
            // AUDIT FIX (v4.3.6 / Finding B): mirror of the LONG branch -- the
            // continuation pivot must belong to THIS correction (CORE-07/08).
            double minorPivotLo=0.0;
            bool   haveMinorPivot;
            if(InpContTrigSinceCorrection && g_corrStartTime>0)
              {
               int cSh=iBarShift(_Symbol,TrigTF,g_corrStartTime,false);
               haveMinorPivot=(cSh>=1) && ICC_FindMinorPivotLowSince(minorPivotLo,cSh-1);
              }
            else
               haveMinorPivot=ICC_FindMinorPivotLow(minorPivotLo);
            if(haveMinorPivot && m15c1<minorPivotLo && fvgOK && obOK && liqOK)
              {
               iccSellSig=true;
               iccSigSL = g_corrExtreme + g_slBuf;      // SL above correction high
               g_mlOTEDepth=(leg>0.0)?(g_corrExtreme-g_indExtreme)/leg:0.0;
               // AUDIT FIX (v4.4.1 / Finding A): mirror of the LONG branch -- latch
               // correction_depth before ICC_Reset() wipes the ICC geometry. Here
               // 'leg' is g_indLevel-g_indExtreme (a positive bear impulse span), so
               // MathAbs() keeps the ratio direction-agnostic, exactly as the old
               // feature-builder formula did.
               g_mlCorrectionDepth=(leg>0.0)
                  ? MathMax(0.0,MathMin(1.0,MathAbs(g_corrExtreme-g_indExtreme)/leg))
                  : 0.0;
               // AUDIT FIX (v4.0.5/F7): capture impulse_leg_atr, impulse_age_bars,
               // correction_age_bars, and the genuine phase-at-fire BEFORE ICC_Reset()
               // wipes g_iccPhase/g_indLevel/g_indExtreme back to PH_NONE/0 below.
               g_mlImpulseLegATR=(g_mseATRval>0.0)?leg/g_mseATRval:0.0;
               g_mlImpulseAgeBars=g_mlCorrStartBar-g_mlIndStartBar;
               g_mlCorrectionAgeBars=g_barCount-g_mlCorrStartBar;
               g_mlSigPhaseAtFire=g_iccPhase;
               // v4.6.0 PATH FEATURES: latch all four here, in BOTH branches,
               // while g_iccDir / g_indExtreme / g_corrExtreme / g_iccStartTime /
               // g_corrStartTime are still valid. ICC_Reset() on the next line
               // zeroes every one of them, and ML_Build2RFeatures runs AFTER that
               // -- the exact failure mode of v4.4.1 Finding A. The code is
               // identical in both branches because every calculator takes the
               // direction explicitly, which also removes the long/short drift
               // that produced v4.3.5 Finding A.
               g_mlSweepAge           =(double)((g_iccDir>0)? g_sweepConfLong : g_sweepConfShort);
               g_mlSweepLeadBars      =ICC_SweepLeadBars(g_iccDir);
               g_mlImpulseConcentration=ICC_ImpulseConcentration(leg);
               g_mlCorrLegCount       =ICC_CorrectionLegCount();
               g_mlCorrRecovery       =ICC_CorrectionRecovery(g_iccDir,m15c1);
               ICC_Reset();
              }
           }
        }
     }
   else // htf flat: don't start new setups (let existing expire/flip handle itself)
     {
      // AUDIT FIX (v4.3.6 / Finding E, LOW, dead code): this read
      // "if(g_iccPhase==PH_NONE) ICC_Reset();" -- a guaranteed NO-OP, because it only
      // reset state that was ALREADY reset. The genuinely interesting case (a live
      // setup while HTF goes flat) fell through untouched, which IS the documented
      // intent (expiry / bias-flip handle it), so the behaviour is correct -- only the
      // statement was meaningless. Replaced with an explicit, honest comment plus a
      // diagnostic so a flat-HTF hold is visible rather than silent.
      // NOTE: PhaseTxt() is defined far below this point, so it is NOT called here --
      // MQL5 requires declaration before use and a forward reference would not compile.
      if(g_iccPhase!=PH_NONE && InpICCGateDiagnostics)
         PrintFormat("[ICC GATE] HTF flat -> holding existing phase=%d setup dir=%d (expiry/bias-flip will resolve it)",
                     g_iccPhase,g_iccDir);
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
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_INOUT) return;
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
void ML_v2_WriteRow(int i)
  {
   if(!InpMLv2Export) return;
   ML_v2_EnsureHeader(); // guarantees file + header exist
   int h=FileOpen(g_mlv2FileEff,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI,',');
   if(h==INVALID_HANDLE){ Print("[MLv2] CSV open failed: ",GetLastError()); return; }
   FileSeek(h,0,SEEK_END);
   double risk=g_mlv2[i].initRisk; if(risk<=0.0) risk=1.0;
   double mfeR=g_mlv2[i].mfe/risk, maeR=g_mlv2[i].mae/risk;
   double exitR=(g_mlv2[i].dir>0? (g_mlv2[i].exitPx-g_mlv2[i].entryPx) : (g_mlv2[i].entryPx-g_mlv2[i].exitPx))/risk;
   double riskPips=(g_pip>0.0? g_mlv2[i].initRisk/g_pip : 0.0);
   long t2r=(g_mlv2[i].t2rTime>0 && g_mlv2[i].entryTime>0)? (long)(g_mlv2[i].t2rTime-g_mlv2[i].entryTime) : -1;
   string tradeId=_Symbol+"_"+IntegerToString((int)g_mlv2[i].posId);
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
   ML_v2_WriteRow(idx);
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
// AUDIT FIX (v4.0.5 / F10): removed the unused ML_v4_CsvLine() helper (dead code --
// grep confirmed zero call sites in the whole file; ML_v4_WriteRow() below builds
// its row manually field-by-field via ML_v4_CsvField() instead).
void ML_v4_EnsureHeader()
  {
   if(!InpMLv4Export) return;
   int h=FileOpen(g_mlv4FileEff,FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI); // AUDIT FIX (v4.0.4): FILE_TXT added -- FileWriteString's documented behaviour branches on FILE_TXT/CSV/BIN; none was set before, unlike every other dataset in this EA
   if(h==INVALID_HANDLE){ Print("[MLv4] CSV create/verify FAILED err=",GetLastError()," file=",g_mlv4FileEff); return; }
   if(FileSize(h)==0)
     {
      string header="dataset_version,schema_version,run_id,trade_id,trade_seq,position_id,dir,symbol,period,digits,point,tick_size,tick_value,contract_size,broker,account_currency,execution_mode,signal_time,entry_time,exit_time,entry_price,initial_stop,initial_risk,initial_risk_pips,htf_score,ext_trend,int_trend,sweep_long,sweep_short,displacement,fvg_active,ob_active,atr,session,regime,fvg_mid_dist,fvg_mid_dist_atr,ote_depth,fvg_size_atr,risk_distance,risk_distance_atr,risk_distance_pips,spread_price,spread_points,hour,minute_of_day,time_sin,time_cos,icc_phase,impulse_age_bars,impulse_leg_atr,correction_age_bars,correction_depth,distance_to_external_high_atr,distance_to_external_low_atr,distance_to_internal_high_atr,distance_to_internal_low_atr,mfe_price,mae_price,mfe_r,mae_r,reached_1r,reached_2r,reached_3r,reached_5r,reached_10r,time_to_1r_sec,time_to_2r_sec,time_to_3r_sec,time_to_5r_sec,time_to_10r_sec,mfe_30m_r,mfe_1h_r,mfe_2h_r,mfe_4h_r,mfe_8h_r,mfe_24h_r,exit_price,exit_r,exit_money,exit_reason,exit_external_trend,exit_internal_trend,exit_protected_high,exit_protected_low,exit_structure_break,exit_opposite_signal,exit_fvg_active,exit_ob_active,exit_atr,model_version,ml_2r_prob,ml_decision,ml_risk_mult,initial_risk_money,mfe_money,mae_money,sweep_age,sweep_lead_bars,impulse_concentration,corr_leg_count,corr_recovery_frac\r\n";
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
   r.fDatasetVersion="ICC_ML_v4"; r.fSchemaVersion="4.2.0"; r.fModelVersion=ML_v4_ModelVersion();
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

void ML_v4_WriteRow(int i)
  {
   if(!InpMLv4Export) return;
   ML_v4_EnsureHeader();
   int h=FileOpen(g_mlv4FileEff,FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI); // AUDIT FIX (v4.0.4): FILE_TXT added -- FileWriteString's documented behaviour branches on FILE_TXT/CSV/BIN; none was set before, unlike every other dataset in this EA
   if(h==INVALID_HANDLE){ Print("[MLv4] CSV open failed: ",GetLastError()); return; }
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
   row+=DoubleToString(g_mlv4[i].exitPx,_Digits)+","+DoubleToString(ML_v4_R(g_mlv4[i].exitPx,g_mlv4[i].entryPx,risk,g_mlv4[i].dir),8)+","+DoubleToString(g_mlv4[i].exitMoney,2)+","+ML_v4_CsvField(g_mlv4[i].exitReason)+",";
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
       +DoubleToString(g_mlv4[i].fCorrRecovery,8)+"\r\n";

   // AUDIT FIX (v4.0.5 / F9): FileWriteString() is VOID for FILE_TXT files, so error
   // detection uses ResetLastError()/GetLastError() -- previously no check of any
   // kind was performed, so a disk-full/permission/agent-interrupt condition could
   // silently drop a completed trade's row with zero indication anywhere.
   ResetLastError();
   FileWriteString(h,row);
   int werr=GetLastError();
   if(werr!=0) Print("[MLv4] WARNING: CSV row write may have FAILED err=",werr," trade=",g_mlv4[i].tradeId," file=",g_mlv4FileEff);
   FileClose(h);
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
   ML_v4_WriteRow(idx);
   int n=ArraySize(g_mlv4);for(int j=idx;j<n-1;j++)g_mlv4[j]=g_mlv4[j+1];ArrayResize(g_mlv4,n-1);
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
double CalculateLotSize(double sd)
  {
   if(FixedLots>0) return NormalizeLots(FixedLots);
   if(sd<=0) return 0;
   double bal=AccountInfoDouble(ACCOUNT_BALANCE);
   double risk=bal*RiskPercent/100.0;
   if(InpMLMode==ML_FILTER_SIZE || InpMLMode==ML_FULL) risk*=g_mlRiskMult;
   double tv=symInfo.TickValue(), ts=symInfo.TickSize();
   // AUDIT FIX (v4.3.4 / Finding C, MEDIUM, RISK CONTROL): this returned LotsMin
   // when the tick metrics were unavailable -- i.e. it TRADED at an unvalidated
   // size precisely when the size could not be computed. Refuse the trade instead.
   if(tv<=0||ts<=0)
     {
      if(DebugLog) Print("SIZING skip: TickValue/TickSize unavailable -> cannot size risk");
      return 0.0;
     }
   double want=risk/((sd/ts)*tv);
   // AUDIT FIX (v4.3.4 / Finding C, MEDIUM, RISK CONTROL): NormalizeLots() opens with
   // "l=MathMax(l,mn)", so ANY risk-derived size below the broker minimum was silently
   // RAISED to LotsMin -- and the trade was taken anyway at a risk LARGER than
   // RiskPercent, with no warning. On a small balance, a wide (deep-pullback) stop, or
   // a reduced ML risk multiplier, that can be a multiple of the configured risk. The
   // stop distance is what varies most here, so this is not a rare edge case. Refuse
   // the trade instead of silently exceeding the risk mandate.
   double mn=symInfo.LotsMin();
   if(want < mn)
     {
      PrintFormat("SIZING skip: risk-derived lots %.4f < broker LotsMin %.4f -> taking it would risk MORE than RiskPercent=%.2f%% (stopDist=%.5f). Trade refused.",
                  want,mn,RiskPercent,sd);
      return 0.0;
     }
   return NormalizeLots(want);
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
//--- Guarded stop-loss modify. Returns true only if a modify was actually sent
//    AND accepted. Silently no-ops (no broker call, no log) when the new SL is
//    the same as the current SL, is broker-illegal, or equals the last value
//    that already failed for this ticket.
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
   double minDist = GetMinStopDistance();
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

//--- Trend-health for a position direction (+1 long / -1 short).
ENUM_TREND_HEALTH RX_Health(int dir)
  {
   if(dir>0)
     {
      if(g_extTrend==-1) return TH_REVERSAL;   // confirmed external bearish BOS (protected ext low broken)
      if(g_intTrend==-1) return TH_CAUTION;    // internal bearish only
      return TH_HEALTHY;
     }
   if(g_extTrend== 1) return TH_REVERSAL;
   if(g_intTrend== 1) return TH_CAUTION;
   return TH_HEALTHY;
  }
string RX_HealthTxt(ENUM_TREND_HEALTH h){ return h==TH_HEALTHY?"HEALTHY":h==TH_CAUTION?"CAUTION":"REVERSAL"; }

//--- Dashboard helper: current open R (this EA) + health text by ref.
double RX_DashInfo(string &htxt)
  {
   htxt="-";
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      // AUDIT FIX (v4.0.4): use RX_Ensure (registers on first sight, idempotent
      // thereafter) instead of RX_Find, so a brand-new position no longer shows
      // a spurious 0.00R for one dashboard refresh before ManagePositions gets
      // to register it on a later tick.
      int idx=RX_Ensure(posInfo.Ticket(),posInfo.PriceOpen(),posInfo.StopLoss());
      // AUDIT FIX (v4.6.2 / Finding 1, CRITICAL, RUNTIME): RX_Ensure() returns -1
      // when PositionSelectByTicket() fails (ticket closed between PositionsTotal()
      // and here, a tester history resync, or a broker-side ticket change). The next
      // line then evaluated g_rxRisk[-1] -- an ARRAY OUT OF RANGE that terminates
      // the EA, not a silent wrong number. The window is small but it is reached on
      // EVERY dashboard refresh and EVERY managed tick, so over a long run it is a
      // matter of time. Guard the sentinel before indexing.
      if(idx<0) return 0.0;
      bool isLong=(posInfo.PositionType()==POSITION_TYPE_BUY);
      double risk=g_rxRisk[idx]; if(risk<=0.0) return 0.0;
      double px=isLong? symInfo.Bid() : symInfo.Ask();
      if(px<=0.0) return 0.0;   // v3.9.2 guard: stale/zero quote
      double curR=isLong? (px-posInfo.PriceOpen())/risk : (posInfo.PriceOpen()-px)/risk;
      htxt=RX_HealthTxt(RX_Health(isLong?1:-1));
      return curR;
     }
   return 0.0;
  }

//--- Manage ONE already-selected position under the R-engine.
//    Returns true if it CLOSED the position (loop should move on).
bool RX_ManageOne(double minStop)
  {
   double op=posInfo.PriceOpen(), sl=posInfo.StopLoss(), tp=posInfo.TakeProfit();
   double pt=symInfo.Point(); ulong tk=posInfo.Ticket();
   bool   isLong=(posInfo.PositionType()==POSITION_TYPE_BUY);
   int    idx=RX_Ensure(tk,op,sl);
   // AUDIT FIX (v4.6.2 / Finding 1, CRITICAL, RUNTIME): see RX_DashInfo. Same
   // unguarded -1 index, but on the TRADE-MANAGEMENT path -- an out-of-range halt
   // here stops break-even, profit-lock, the structure runner and the trend-health
   // exit from running on a LIVE position.
   if(idx<0) return false;
   double risk=g_rxRisk[idx]; if(risk<=0.0) return false;
   double px  = isLong? symInfo.Bid() : symInfo.Ask();
   if(px<=0.0) return false;   // v3.9.2 guard: never manage on a stale/zero quote
   double curR= isLong? (px-op)/risk : (op-px)/risk;
   ENUM_TREND_HEALTH health = InpUseTrendHealth ? RX_Health(isLong?1:-1) : TH_HEALTHY;

   // (A) confirmed external reversal -> exit the whole position (cuts weak trades too)
   if(InpUseTrendHealth && health==TH_REVERSAL)
     {
      ulong closeId=(ulong)posInfo.Identifier();
      RX_StageCloseTag(closeId,"TREND-REV");
      bool closeOK=(trade.PositionClose(tk) && TradeResultSucceeded());
      if(closeOK)
        { TriggerFlash("EXIT (ext reversal)",ColExit,false,0,0,0); DispatchAlert("EXIT ext-reversal | "+_Symbol); }
      else
        {
         RX_ConsumeCloseTag(closeId);
         PrintFormat("[RX] trend-reversal close FAILED #%I64u rc=%d (%s)",tk,trade.ResultRetcode(),trade.ResultRetcodeDescription());
        }
      return closeOK;
     }

   // (B) optional partial at activation (once)
   if(InpUsePartial && !g_rxPartial[idx] && curR>=InpActivateAtR)
     {
      double vol=NormalizeLots(posInfo.Volume()*InpPartialPct/100.0);
      if(vol>0.0 && vol<posInfo.Volume() && (posInfo.Volume()-vol)>=symInfo.LotsMin())
        {
         ulong closeId=(ulong)posInfo.Identifier();
         RX_StageCloseTag(closeId,"PARTIAL");
         if(RX_ClosePartial(tk,vol))
           { g_rxPartial[idx]=true; TriggerFlash("PARTIAL +"+DoubleToString(InpActivateAtR,1)+"R",ColExit,false,0,0,0); }
         else
           {
            RX_ConsumeCloseTag(closeId);
            PrintFormat("[RX] partial close FAILED #%I64u rc=%d (%s)",tk,trade.ResultRetcode(),trade.ResultRetcodeDescription());
           }
         if(!posInfo.SelectByTicket(tk)) return true; // fully gone (shouldn't happen)
         op=posInfo.PriceOpen(); sl=posInfo.StopLoss(); tp=posInfo.TakeProfit();
        }
      else g_rxPartial[idx]=true; // too small to split -> skip once
     }

   // (C) most-protective valid stop candidate (one-way)
   double cand = isLong? -DBL_MAX : DBL_MAX;
   bool   have=false;
   // profit floor (BE / lock / progressive give-back)
   double lockR=RX_LockedR(curR);
   if(lockR>-1.0e17)
     {
      // AUDIT FIX (v4.0.4): this reused the legacy UseBreakEven input's points
      // value unconditionally, so turning UseBreakEven OFF did not, as a user
      // would reasonably expect, remove its influence on the R-engine's own
      // protect-stage cushion. Zero it unless the legacy toggle is ON.
      double be=UseBreakEven? BEprofit_Runtime*pt : 0.0; // small asset-scaled break-even cushion
      double fp= isLong? op + MathMax(lockR,0.0)*risk + be
                       : op - MathMax(lockR,0.0)*risk - be;
      cand = isLong? MathMax(cand,fp) : MathMin(cand,fp); have=true;
     }
   // structure runner (only once activated)
   if(curR>=InpActivateAtR)
     {
      bool useInt = InpRunnerInternStruct || (health==TH_CAUTION); // CAUTION forces internal tighten
      bool useExt = InpRunnerExternStruct;
      double atr  = GetRawATR(); // AUDIT FIX (v4.0.4): read raw ATR directly, no back-solve
      if(isLong)
        {
         if(useExt && g_extProtLow>0.0){ double x=g_extProtLow-g_slBuf; cand=MathMax(cand,x); have=true; }
         if(useInt && g_intProtLow>0.0){ double x=g_intProtLow-g_slBuf; cand=MathMax(cand,x); have=true; }
         if(InpRunnerATRFloor && atr>0.0){ double x=px-atr*InpRunnerATRfloorMult; cand=MathMax(cand,x); have=true; }
        }
      else
        {
         if(useExt && g_extProtHigh>0.0){ double x=g_extProtHigh+g_slBuf; cand=MathMin(cand,x); have=true; }
         if(useInt && g_intProtHigh>0.0){ double x=g_intProtHigh+g_slBuf; cand=MathMin(cand,x); have=true; }
         if(InpRunnerATRFloor && atr>0.0){ double x=px+atr*InpRunnerATRfloorMult; cand=MathMin(cand,x); have=true; }
        }
     }
   if(!have) return false;

   // (D) broker-legal clamp + one-way ratchet
   // v4.2.8: the raw clamp + direct PositionModify were the source of the #12
   // "Invalid stops" flood -- routed through RX_SafeModify, which enforces the
   // no-op / broker-legality / anti-spam guards. The one-way ratchet condition
   // is preserved so the stop still only ever tightens.
   double newSL=cand;
   if(isLong)
     {
      if(newSL>px-minStop) newSL=px-minStop;
      if(newSL>sl) RX_SafeModify(tk,true,newSL,tp,px);
     }
   else
     {
      if(newSL<px+minStop) newSL=px+minStop;
      if(newSL<sl || sl==0.0) RX_SafeModify(tk,false,newSL,tp,px);
     }
   return false;
  }
//--- v3.5.0 LET WINNERS RUN. Every stop candidate below only ever ratchets
//    the stop in the FAVOURABLE direction (never loosens), and every candidate
//    is clamped to the broker minimum stop distance so the modify is legal.
//    Because the runner lock sits IN PROFIT after arming, the position stays
//    open while it keeps advancing and closes only when price retraces into
//    the locked floor (or an opposite ICC continuation flips structure).
void ManagePositions()
  {
   double minStop=GetMinStopDistance();
   // AUDIT FIX (v4.3.5 / Finding B, MEDIUM, unbounded growth -- v4.3.4 Finding E was
   // only HALF applied): v4.3.4 added fail-registry pruning INSIDE RX_Prune(), but
   // RX_Prune() itself is called only when InpUseRexit is ON. The LEGACY management
   // branch below also calls RX_SafeModify() (see the two RX_SafeModify calls at the
   // end of this function), which populates g_rxFailTicket/g_rxFailSL via
   // RX_SetFailSL(). With InpUseRexit=OFF that registry was therefore STILL never
   // pruned -- it grew for the life of the run and both linear-scan lookups
   // (RX_LastFailSL/RX_SetFailSL) ran on every managed tick. Prune unconditionally;
   // RX_Prune() is idempotent and cheap when the registries are empty.
   RX_Prune();
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=MagicNumber||posInfo.Symbol()!=_Symbol) continue;
      // AUDIT FIX (v4.0.4): previously only ran RX_ManageOne() when TakeProfit()==0.0.
      // If ML runner-selection (g_mlRunner) was false at entry, a real TP got attached
      // and the position was PERMANENTLY excluded from the entire R-engine (no BE, no
      // lock, no structure trail, no trend-health exit) for its whole life. InpUseRexit
      // is the sole master switch documented to "supersede legacy BE/trail/point-runner
      // management" -- it must not silently depend on whether a TP happens to be set.
      if(InpUseRexit){ RX_ManageOne(minStop); continue; } // v3.6.0 R-engine supersedes legacy mgmt
      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss(), tp=posInfo.TakeProfit();
      double pt=symInfo.Point(); ulong tk=posInfo.Ticket();
      if(posInfo.PositionType()==POSITION_TYPE_BUY)
        {
         double bid=symInfo.Bid(); if(bid<=0.0) continue; // v3.9.2 guard: stale/zero quote
         double pp=(bid-op)/pt;
         double newSL=sl;                                   // longs: newSL only ever RISES
         if(UseBreakEven && pp>=BEat_Runtime)
           { double v=op+BEprofit_Runtime*pt;         if(v>newSL) newSL=v; }
         if(UseTrailingStop && pp>=TrailStart_Runtime)
           { double v=bid-TrailStep_Runtime*pt;       if(v>newSL) newSL=v; }
         // --- Let Winners Run: profit-lock ratchet + optional structure trail ---
         if(InpLetWinnersRun && pp>=RunnerArm_Runtime)
           {
            double v=op+RunnerLock_Runtime*pt;         if(v>newSL) newSL=v;   // lock BE+lock in profit
            if(RunnerTrail_Runtime>0)
              { double t=bid-RunnerTrail_Runtime*pt;   if(t>newSL) newSL=t; } // trail behind peak
            if(InpRunnerUseStructure && g_intProtLow>0.0)
              { double s=g_intProtLow-g_slBuf;          if(s>newSL) newSL=s; } // trail behind protected swing low
           }
         if(newSL>bid-minStop) newSL=bid-minStop;           // broker-legal clamp
         if(newSL>sl) RX_SafeModify(tk,true,newSL,tp,bid);   // v4.2.8 guarded modify
        }
      else if(posInfo.PositionType()==POSITION_TYPE_SELL)
        {
         double ask=symInfo.Ask(); if(ask<=0.0) continue; // v3.9.2 guard: stale/zero quote
         double pp=(op-ask)/pt;
         double newSL=(sl>0.0)? sl : ask+minStop;           // shorts: newSL only ever FALLS
         if(UseBreakEven && pp>=BEat_Runtime)
           { double v=op-BEprofit_Runtime*pt;         if(v<newSL) newSL=v; }
         if(UseTrailingStop && pp>=TrailStart_Runtime)
           { double v=ask+TrailStep_Runtime*pt;       if(v<newSL) newSL=v; }
         // --- Let Winners Run: profit-lock ratchet + optional structure trail ---
         if(InpLetWinnersRun && pp>=RunnerArm_Runtime)
           {
            double v=op-RunnerLock_Runtime*pt;         if(v<newSL) newSL=v;   // lock BE+lock in profit
            if(RunnerTrail_Runtime>0)
              { double t=ask+RunnerTrail_Runtime*pt;   if(t<newSL) newSL=t; } // trail behind peak
            if(InpRunnerUseStructure && g_intProtHigh>0.0)
              { double s=g_intProtHigh+g_slBuf;         if(s<newSL) newSL=s; } // trail behind protected swing high
           }
         if(newSL<ask+minStop) newSL=ask+minStop;           // broker-legal clamp
         if(newSL<sl || sl==0.0) RX_SafeModify(tk,false,newSL,tp,ask); // v4.2.8 guarded modify
        }
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
   // AUDIT FIX (v4.5.0 / Finding 4, HIGH, TAKE-PROFIT CRITERIA): the effective
   // structural acceptance floor is now the STRICTER of the legacy InpTPMinRR and
   // the new hard InpMinTPRR, so a 1R structural level can no longer become the
   // take-profit of a trade the 2R classifier approved.
   double minRR = MathMax(InpTPMinRR, InpMinTPRR);
   double rrBase= MathMax(RR_Ratio, InpMinTPRR);
   double tpx = (dir>0)? entryPx + d*rrBase : entryPx - d*rrBase; // fixed-RR base (floored)
   if(InpTPMode==TP_STRUCTURAL)
     {
      double lvl=StructuralTPTarget(dir,entryPx);
      if(lvl>0.0)
        {
         double dist=(dir>0)? (lvl-entryPx) : (entryPx-lvl);
         if(dist>=_Point*10 && dist>=d*minRR)
           {
            tpx=lvl;
            usedStruct=true;
           }
        }
     }
   // FINAL GUARD: whatever route produced tpx, it may never sit closer than the
   // hard floor. A structural level beyond the floor is untouched; one inside it
   // is pushed out (the trade keeps its 2R objective rather than being silently
   // downgraded to a sub-2R target).
   double floorTP = (dir>0)? entryPx + d*InpMinTPRR : entryPx - d*InpMinTPRR;
   if(dir>0 && tpx < floorTP){ tpx=floorTP; usedStruct=false; }
   if(dir<0 && tpx > floorTP){ tpx=floorTP; usedStruct=false; }
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
   // v3.5.0 LET WINNERS RUN: open the trade with NO fixed TP so the winner can run;
   // the profit-lock ratchet in ManagePositions rides and protects it.
   if((InpLetWinnersRun || InpUseRexit) && g_mlRunner){ tpPrice=0.0; tpStruct=false; }
   g_lastTP=tpPrice; g_lastTPstruct=tpStruct;
   double lots=CalculateLotSize(slFinal);
   if(lots<=0){ if(DebugLog) Print("BUY skip: lots<=0"); return; }
   if(trade.Buy(lots,_Symbol,ask,slPrice,tpPrice,TradeComment) && TradeResultSucceeded())
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
   // v3.5.0 LET WINNERS RUN: open the trade with NO fixed TP so the winner can run;
   // the profit-lock ratchet in ManagePositions rides and protects it.
   if((InpLetWinnersRun || InpUseRexit) && g_mlRunner){ tpPrice=0.0; tpStruct=false; }
   g_lastTP=tpPrice; g_lastTPstruct=tpStruct;
   double lots=CalculateLotSize(slFinal);
   if(lots<=0){ if(DebugLog) Print("SELL skip: lots<=0"); return; }
   if(trade.Sell(lots,_Symbol,bid,slPrice,tpPrice,TradeComment) && TradeResultSucceeded())
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
//--- v3.5.0: the ONLY entry path is the Sci ICC continuation. The v1 cascade-
//    breakout and the classic S/R retest-confirmation paths were removed, as
//    was the generic UTC session filter (the kill-zone engine is the Sci
//    session model). CloseOnOpposite now reacts purely to an opposite ICC
//    continuation, i.e. a genuine market-structure flip.
void TryEntries()
  {
   // Sci kill-zone gate: block NEW ICC entries outside an enabled kill zone.
   // IsInKillzone() also refreshes the dashboard KZ readout.
   // AUDIT FIX (v4.0.4): this gate previously RETURNED out of the whole
   // function, which also silently skipped CloseOnOpposite below -- an
   // opposite-signal structure-flip close could never fire outside kill-zone
   // hours, even though kill-zones are documented as an ENTRY-only filter.
   // The gate now applies ONLY to the two new-entry blocks at the bottom.
   bool kzOK=IsInKillzone();
   bool kzEntryOK = (!InpUseKillzones || kzOK);
   if(InpUseKillzones && !kzOK && VerboseLog)
      Print("[ICC] kill-zone gate: outside KZ (",g_kzActive,"), no NEW entries (existing-position management still runs)");
   bool buySig  = iccBuySig;
   bool sellSig = iccSellSig;
   // --- verbose diagnostic line (root-cause visibility) ---
   if(VerboseLog)
      PrintFormat("[ICC] bar=%d bias D1/H4c/H1/M15=%d/%d/%d/%d H4ext=%d HTF=%d HTFsc=%.2f | phase=%s dir=%d ind=%.2f ext=%.2f corr=%.2f | sig ICC(b/s)=%d/%d | SR lvls=%d",
         g_barCount,biasD1,biasH4,biasH1,biasM15,g_extTrend,HTFbias(),HTFscore(),
         PhaseTxt(g_iccPhase),g_iccDir,g_indLevel,g_indExtreme,g_corrExtreme,
         (int)iccBuySig,(int)iccSellSig,ActiveSRCount());
   int dir=OpenTradeDir();
   // v3.6.0: an opposite ICC ALONE no longer ejects a runner. When
   // InpCloseOnConfirmedRev is ON the close also requires a CONFIRMED
   // external reversal (external BOS against the position); the R-engine's
   // trend-health governor is the primary reversal exit.
   bool extRevLong  = (g_extTrend==-1);
   bool extRevShort = (g_extTrend== 1);
   if(CloseOnOpposite && dir==1 && sellSig && (!InpCloseOnConfirmedRev || extRevLong)){ CloseAllThisEA("EXIT LONG"); dir=0; }
   if(CloseOnOpposite && dir==-1 && buySig && (!InpCloseOnConfirmedRev || extRevShort)){ CloseAllThisEA("EXIT SHORT"); dir=0; }
   // AUDIT FIX (v4.5.0 / Finding 9, MEDIUM, SAMPLING BIAS + OBSERVABILITY): both
   // returns below sit BEFORE ML_Evaluate2R(), so a Continuation that fires while a
   // position is open was discarded with NO inference, NO [ML2R GATE] record and NO
   // SIGNAL row. Two consequences, both material to an autonomous ML system:
   //   (1) the learned model is trained on a sample CONDITIONED ON BEING FLAT -- a
   //       selection bias that compounds the Working Document s7.8 circularity
   //       concern, because the setups seen during a trade are systematically the
   //       trend-continuation ones; and
   //   (2) the Journal cannot distinguish "the gate vetoed it" from "the engine was
   //       busy", so the s14 block-rate denominator was wrong.
   // FIX: when InpMLObserveWhenBusy is ON, evaluate and RECORD the signal, then
   // return. This places NO order and stages NO pending snapshot -- ML_v2_StagePending
   // is only ever called on the executing path below -- so it is trading-neutral.
   bool busy=(CountOpenTrades()>=MaxOpenTrades) || (dir!=0);
   if(busy)
     {
      if(InpMLObserveWhenBusy && (iccBuySig || iccSellSig))
        {
         int obsDir=iccBuySig?1:-1;
         ML_Evaluate2R(obsDir);
         ML_LogGateVerdict(obsDir);
         PrintFormat("[ML2R GATE] NOT-ROUTED (engine busy: open=%d/%d dir=%d) -- signal evaluated and recorded, NO order placed",
                     CountOpenTrades(),MaxOpenTrades,dir);
        }
      return;
     }
   // --- entry when flat: the Sci ICC continuation only (kill-zone gated) ---
   if(!kzEntryOK) return;   // AUDIT FIX: gate NEW entries here, not the whole function
   // v4.4.2 (Working Document v1.2 s9): the ML gate is the LAST authority on
   // whether a CORE-valid setup becomes an order, and until this build its
   // veto was effectively invisible. ML_LogGateVerdict() is called
   // UNCONDITIONALLY after evaluation and BEFORE the pass/block branch, so a
   // record exists whether the setup trades or is discarded. The call order
   // matters: ML_Evaluate2R must run first (it populates the probability, the
   // risk multiplier and the inference-validity flags the record reports).
   // NOTHING about the gating DECISION is changed here -- that is the s14 A/B
   // question and must be settled on evidence, not edited into the engine.
   if(iccBuySig)
     {
      ML_Evaluate2R(1);
      ML_LogGateVerdict(1);              // v4.4.2 Layer-D record (trading-neutral)
      ML_Export("SIGNAL",1);
      if(!g_mlPass)
        {
         // v4.4.2: kept for continuity, but it is now redundant -- the
         // [ML2R GATE] line above already reports this unconditionally,
         // whereas this message is suppressed whenever VerboseLog is off.
         if(VerboseLog) Print("[ML2R] BUY blocked P2R=",DoubleToString(g_ml2RProb,3)," reason=",g_mlInferenceError);
         return;
        }
      ML_v2_StagePending(1);
      double anchor=(iccSigSL>0)? iccSigSL : wkLastLo;
      ExecuteBuy(anchor,"ICC BUY (continuation)",ColBuy);
      return;
     }
   if(iccSellSig)
     {
      ML_Evaluate2R(-1);
      ML_LogGateVerdict(-1);             // v4.4.2 Layer-D record (trading-neutral)
      ML_Export("SIGNAL",-1);
      if(!g_mlPass)
        {
         if(VerboseLog) Print("[ML2R] SELL blocked P2R=",DoubleToString(g_ml2RProb,3)," reason=",g_mlInferenceError);
         return;
        }
      ML_v2_StagePending(-1);
      double anchor=(iccSigSL>0)? iccSigSL : wkLastHi;
      ExecuteSell(anchor,"ICC SELL (continuation)",ColSell);
      return;
     }
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
   string d ="=== ICC TradesBySci EA v4.6.2 (SMC/ML AUTONOMOUS) ====\n";
   d+=" Cascade (D1 H4 H1 M15): "+bD+" "+b4+" "+b1+" "+b5+"  ["+casc+"]\n";
   d+=" HTF filter: "+(HTFbias()==1?"^ BULL":HTFbias()==-1?"v BEAR":"- flat")+
      "  score="+DoubleToString(HTFscore(),2)+" (min "+DoubleToString(HTF_MinConviction,2)+")\n";
   d+=" ICC phase: "+PhaseTxt(g_iccPhase)+" (dir "+IntegerToString(g_iccDir)+")  [ICC is the only entry]\n";
   d+=" Position: "+pos+"  ("+IntegerToString(CountOpenTrades())+"/"+IntegerToString(MaxOpenTrades)+")\n";
   // v3.6.1: dual floating-P/L — $ (account outcome) + pips (chart behaviour)
   double flMoney, flPips; int flN;
   FloatingPL(flMoney, flPips, flN);
   if(flN>0)
     {
      string sgn=(flMoney>=0?"+":"");
      d+=" Floating P/L: "+sgn+DoubleToString(flMoney,2)+" "+AccountInfoString(ACCOUNT_CURRENCY)+
         "  ( "+sgn+DoubleToString(flPips,1)+" pips )\n";
     }
   else
      d+=" Floating P/L: flat\n";
   d+=" S/R lvls (TP map): "+IntegerToString(ActiveSRCount())+"\n";
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
   d+=" TP mode: "+((InpLetWinnersRun||InpUseRexit)? "RUNNER (no fixed TP)" : (InpTPMode==TP_STRUCTURAL?"STRUCTURAL":"FIXED_RR"));
   if(!(InpLetWinnersRun||InpUseRexit) && g_lastTP>0.0) d+="  last="+DoubleToString(g_lastTP,_Digits)+(g_lastTPstruct?" [s]":" [rr]");
   d+="\n";
   // v3.5.0: let-winners-run readout — arm/lock/trail + structure-trail flag
   d+=" Runner: "+(InpLetWinnersRun? ("ON arm="+IntegerToString(RunnerArm_Runtime)+
      " lock="+IntegerToString(RunnerLock_Runtime)+" trail="+IntegerToString(RunnerTrail_Runtime)+
      (InpRunnerUseStructure?"+struct":"")) : "OFF")+"\n";
   // v3.6.0: R-multiple exit-engine readout (+ live position R / health)
   d+=" Exit R-eng: "+(InpUseRexit? ("ON prot="+DoubleToString(InpProtectAtR,1)+"R lock@"+DoubleToString(InpLockAtR,1)+"R/+"+DoubleToString(InpLockProfitR,1)+"R act="+DoubleToString(InpActivateAtR,1)+"R give="+DoubleToString(InpRunnerGiveBackR,1)+"R"+(InpRunnerExternStruct?" +E":"")+(InpRunnerInternStruct?" +I":"")) : "OFF (legacy BE/trail)")+"\n";
   if(InpUseRexit && OpenTradeDir()!=0)
     { string _htxt; double _curR=RX_DashInfo(_htxt);
       d+="   pos: "+DoubleToString(_curR,2)+"R  health="+_htxt+(InpUsePartial?("  partial="+DoubleToString(InpPartialPct,0)+"%"):"")+"\n"; }
   // v3.3.9: FVG-containment mode readout — RELAXED (tol/band) vs STRICT point-in-gap
   d+=" FVG contain: "+(InpRelaxFVGContain? ("RELAX tol="+DoubleToString(g_fvgContainTol,_Digits)+(InpUseFVGband?"+band":"")) : "STRICT")+"\n";
   // v3.4.0: kill-zone + OTE readout
   d+=" Kill-zone: "+(InpUseKillzones? ("ON -> "+g_kzActive+(g_inKillzone?"  [OPEN]":"  [SHUT]")) : "OFF (all hours)")+"\n";
   d+=" OTE window: "+(InpUseOTE? ("ON "+DoubleToString(InpOTEmin,2)+"-"+DoubleToString(InpOTEmax,2)) : "OFF (Corr "+DoubleToString(CorrRetraceMin,2)+"-"+DoubleToString(CorrRetraceMax,2)+")")+"\n";
   // v3.3.10: exit-label readout — mode + closed-trade count + last exit reason
   d+=" Exit lbls: "+(InpShowExitLabels? ("ON"+(InpExitLblShowProfit?"+P&L":"")) : "OFF")+
      "  Closed="+IntegerToString(g_closedTrades)+"  last="+g_lastExitReason+"\n";
   d+=" ML2R: "+(InpMLMode==ML_OFF?"OFF":(g_mlPass?"PASS":"BLOCK"))+"  P(2R)="+DoubleToString(g_ml2RProb,3)+" risk=x"+DoubleToString(g_mlRiskMult,2)+" model="+g_mlModelVersion+"\n";
   d+=" ML regime: "+g_mlRegimeTxt+" session="+IntegerToString(g_mlSession)+"\n";
   d+=" ML feat: OTE="+DoubleToString(g_mlOTEDepth,3)+" FVGdist="+DoubleToString(g_mlFVGMidDistATR,2)+"ATR FVGsize="+DoubleToString(g_mlFVGSizeATR,2)+"ATR risk="+DoubleToString(g_mlRiskDistanceATR,2)+"ATR spread="+DoubleToString(g_mlSpreadPoints,0)+"pt hour="+IntegerToString(g_mlHour)+"\n";
   d+="=========================================";
   Comment(d);
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

bool ValidateInputs()
  {
   if(MagicNumber==0 || Slippage<0 || MaxOpenTrades<1)
     { Print("[INIT] FATAL: invalid MagicNumber/Slippage/MaxOpenTrades."); return false; }
   if(CorrRetraceMin<=0.0 || CorrRetraceMax<=CorrRetraceMin || CorrRetraceMax>1.0)
     { Print("[INIT] FATAL: require 0 < CorrRetraceMin < CorrRetraceMax <= 1."); return false; }
   if(InpUseOTE && (InpOTEmin<=0.0 || InpOTEmax<=InpOTEmin || InpOTEmax>1.0))
     { Print("[INIT] FATAL: invalid OTE range."); return false; }
   if(ICC_ExpiryBars<1 || CascadeSwingLen<1 || InpIntSwingStrength<1 ||
      InpExtSwingStrength<1 || InpStructLookback<2 || InpMinorPivotStrength<1 ||
      InpMinorPivotLookback<1)
     { Print("[INIT] FATAL: structure/pivot lengths must be positive."); return false; }
   if(ATR_Period<1 || InpATRautoLen<1 || InpDispATRPeriod<1 ||
      ATR_Multiplier<=0.0 || BrokerStopCushion<=0.0)
     { Print("[INIT] FATAL: ATR periods/multipliers must be positive."); return false; }
   if(RR_Ratio<=0.0 || InpTPMinRR<=0.0 || InpMinTPRR<=0.0 || InpTPLookback<1)
     { Print("[INIT] FATAL: TP/RR inputs must be positive."); return false; }
   if((RiskPercent<=0.0 && FixedLots<=0.0) || FixedLots<0.0)
     { Print("[INIT] FATAL: invalid RiskPercent/FixedLots."); return false; }
   if(TrailingStart_Pts<0 || TrailingStep_Pts<0 || BreakEvenAt_Pts<0 || BreakEvenProfit<0 ||
      InpRunnerArmPts<0 || InpRunnerLockPts<0 || InpRunnerTrailPts<0)
     { Print("[INIT] FATAL: point-based management inputs cannot be negative."); return false; }
   if(InpProtectAtR<0.0 || InpProtectLockR<0.0 || InpLockAtR<0.0 ||
      InpLockProfitR<0.0 || InpActivateAtR<0.0 || InpRunnerGiveBackR<0.0 ||
      InpRunnerATRfloorMult<0.0)
     { Print("[INIT] FATAL: R-exit inputs cannot be negative."); return false; }
   if(InpUsePartial && (InpPartialPct<=0.0 || InpPartialPct>=100.0))
     { Print("[INIT] FATAL: InpPartialPct must be >0 and <100 when partial close is enabled."); return false; }
   if(SR_MinTouch<1 || SR_DurN<1 || SR_TolPips<0.0 || SR_FillAlpha<0 || SR_FillAlpha>255 || SR_RefLen<1)
     { Print("[INIT] FATAL: invalid S/R inputs."); return false; }
   if(InpLiqLookback<2 || InpEqualLevelTolPips<0.0 || InpReclaimBars<1 ||
      InpSweepValidBars<1 || InpSweepMinPips<0.0)
     { Print("[INIT] FATAL: invalid liquidity inputs."); return false; }
   if(InpFVGScanBars<1 || InpMaxTrackedFVG<1 || InpMinFVGPips<0.0 ||
      InpFVGFillInvalidate<0.0 || InpFVGFillInvalidate>100.0)
     { Print("[INIT] FATAL: invalid FVG inputs."); return false; }
   if(InpOBScanBack<1 || InpOBScanBars<1 || InpMaxTrackedOB<1)
     { Print("[INIT] FATAL: invalid order-block inputs."); return false; }
   if(InpDispMinBodyPct<0.0 || InpDispMinBodyPct>1.0 ||
      InpDispMinCloseStr<0.0 || InpDispMinCloseStr>1.0 ||
      InpDispMaxWickRatio<0.0 || InpDispMinScore<0.0 || InpDispMinScore>100.0)
     { Print("[INIT] FATAL: invalid displacement thresholds."); return false; }
   if(FlashOn && (FlashSeconds<1 || FlashMs<50))
     { Print("[INIT] FATAL: FlashSeconds>=1 and FlashMs>=50 are required when flashing is enabled."); return false; }
   if(InpML2RThreshold<0.0 || InpML2RThreshold>1.0 ||
      InpML2RHighThreshold<0.0 || InpML2RHighThreshold>1.0 ||
      InpML2RHighThreshold<InpML2RThreshold ||
      InpML2RLowThreshold<0.0 || InpML2RLowThreshold>1.0 ||
      (InpML2RLowThreshold>0.0 && InpML2RLowThreshold>=InpML2RThreshold))
     { Print("[INIT] FATAL: invalid ML probability thresholds."); return false; }
   if(InpMLLowRiskMult<=0.0 || InpMLBaseRiskMult<=0.0 || InpMLHighRiskMult<=0.0 ||
      InpMLRunnerMinP2R<0.0 || InpMLRunnerMinP2R>1.0)
     { Print("[INIT] FATAL: invalid ML risk/runner inputs."); return false; }
    // v4.6.3 H2: the loader binds to the COMPILED ML2R_CONTRACT_TOKEN.
    if(InpMLContractToken=="")
      { Print("[INIT] FATAL: InpMLContractToken must not be empty."); return false; }
    if(StringCompare(InpMLContractToken,ML2R_CONTRACT_TOKEN,true)!=0)
      {
       if(InpMLEnforceContract)
         {
          PrintFormat("[INIT] FATAL: token input \"%s\" differs from compiled contract \"%s\" while enforcement is ON.",InpMLContractToken,ML2R_CONTRACT_TOKEN);
          return false;
         }
       PrintFormat("[INIT] *** WARNING: token input \"%s\" differs from compiled loader contract \"%s\"; enforcement is OFF and loader still uses compiled token.",InpMLContractToken,ML2R_CONTRACT_TOKEN);
      }
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
   g_extTF=MidTF;
   g_intTF=WorkTF;
   // v4.2.1 HARDENING: print the ACTUAL runtime state of the gate-diagnostic
   // and key signal-path toggles UNCONDITIONALLY at init, so "flag is OFF" can
   // never again masquerade as "diagnostic function not reached / engine dark".
   PrintFormat("[ICC GATE] init-check -> InpICCGateDiagnostics=%s | Heartbeat=%s | UseICCPullback=%s | VerboseLog=%s | InpRequireSweep=%s | InpSweepNearestPool=%s | InpRejectWeakBreaks=%s(min=%.1f)",
      (InpICCGateDiagnostics?"TRUE":"FALSE"),
      (InpGateHeartbeatBars>0? ("every "+IntegerToString(InpGateHeartbeatBars)+" bars") : "OFF"),
      (UseICCPullback?"ON":"OFF"),(VerboseLog?"ON":"OFF"),
      (InpRequireSweep?"ON":"OFF"),(InpSweepNearestPool?"ON":"OFF"),(InpRejectWeakBreaks?"ON":"OFF"),InpDispMinScore);
   // v4.3.0: the correction definition is a methodology-level choice, so its
   // runtime state is printed UNCONDITIONALLY at init alongside the other
   // signal-path toggles -- every run's journal records which arm it used.
   PrintFormat("[ICC GATE] init-check -> CorrectionDefinition=%s | InpStructCorrMinRetrace=%.2f | InpStructCorrKeepMaxDepth=%s | CorrRetrace=%.2f-%.2f | OTE=%s",
      (InpUseStructuralCorrection?"STRUCTURAL (LH/HL + impulse-origin hold)":"FIB BAND (v4.2.9 default)"),
      InpStructCorrMinRetrace,(InpStructCorrKeepMaxDepth?"ON":"OFF"),
      CorrRetraceMin,CorrRetraceMax,(InpUseOTE?"ON":"OFF"));
   g_mseATR=iATR(_Symbol,g_intTF,InpDispATRPeriod);
   if(g_mseATR==INVALID_HANDLE) Print("WARNING: SMC ATR handle failed; displacement ATR score will be 0.");
   ICC_Reset();
   EvaluateCascade();
   MSE_Update();                 // prime protected swings / liquidity / FVGs / OBs
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
void OnTick()
  {
   if(g_mlPendValid && g_mlPendSigTime>0 && (TimeCurrent()-g_mlPendSigTime)>120)
      g_mlPendValid=false;
   symInfo.RefreshRates();   // v3.9.2 CRITICAL: prime live Bid/Ask BEFORE any management
                             // reads them (management runs before the new-bar Refresh()).
   ManagePositions();
   ML_v2_TrackOpen();   // v3.9.0 compatibility recorder
    ML_v4_TrackOpen();   // v4.0 canonical recorder
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
   // 3) body-close S/R level map (broken tracking + retest visual). v3.5.0:
   //    this now feeds ONLY the structural take-profit; there is no retest entry.
   if(SR_Show)
     {
      SR_CheckBroken(c);
      SR_CheckRetest(barHi,barLo,c);
      ProcessBar(c,t);
      ExpireLevels(iTime(_Symbol,_Period,0));
      UpdateActiveLevels(iTime(_Symbol,_Period,0));
     }
   // 4) ICC Indication->Correction->Continuation pullback engine
   ICC_Update();
   // 5) entry routing (real orders)
   TryEntries();
   // 6) dashboard
   UpdateDashboard();
  }
//+------------------------------------------------------------------+
