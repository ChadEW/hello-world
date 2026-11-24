//+------------------------------------------------------------------+
//|                                 ICC_TradesBySci_EA_v4.2.0_H4_AUTHORITY.mq5 |
//|   EXPERT ADVISOR v4.2.0 — Sci-style Indication -> Correction ->   |
//|   Continuation (ICC) pullback entries.                           |
//|                                                                  |
//|   v4.3.7 SHADOW-EVALUATOR CORRECTION - 2026-09-10. Fixes TWO        |
//|   measurement defects in the v4.3.6 ICC_ShadowEvaluate() itself --   |
//|   NOT in the trading engine. NO entry, exit, sizing, gating or       |
//|   structure logic is touched, so backtest TRADE results are          |
//|   byte-identical to v4.3.6 (which is itself byte-identical to        |
//|   v4.3.5 at default settings).                                       |
//|   WHY THIS BUILD EXISTS: the first v4.3.6 shadow run on 2026 XAUUSD  |
//|   returned CORE-REJECT=16,812 / ENH-REJECT=4,078 / CORE+ENH PASS=0.  |
//|   An EXACT zero is not a plausible measurement -- the live engine    |
//|   produced 18 signals over the same period -- so the instrument was  |
//|   audited before the result was acted on. Both defects were real.    |
//|   (A, CRITICAL, MEASUREMENT) CORE-05 AND CORE-07 WERE CONDITIONALLY  |
//|   SKIPPED. The tests read "...&& inSetup && g_iccPhase==            |
//|   PH_INDICATION && !coreCorr" and "...&& g_iccPhase==PH_CORRECTION   |
//|   && !coreCont", so BOTH were bypassed on any bar where no setup was |
//|   registered. On such a bar firstFail stayed empty and coreEntry     |
//|   evaluated TRUE off a bare Indication -- with neither a correction  |
//|   nor a continuation. That inverts CORE-09 ("Enter only after        |
//|   continuation confirmation, not merely because indication           |
//|   occurred"). FIX: both are now UNCONDITIONAL requirements of the    |
//|   ICC sequence, so a bar lacking a correction correctly reports      |
//|   CORE-05 as its firstFail instead of silently passing.              |
//|   (B, CRITICAL, MEASUREMENT) LAYER C WAS SCORED AGAINST A ZEROED     |
//|   PRICE. The enhancement tests ran unconditionally against           |
//|   g_corrExtreme, but ICC_Reset() sets that to 0.0 whenever no setup  |
//|   is live -- and price 0.0 is never inside an FVG or an order block. |
//|   fvgOK/obOK were therefore forced FALSE by a SENTINEL, not by       |
//|   market structure. Combined with (A), every such bar was labelled   |
//|   "CORE-PASS / ENH-REJECT", inflating that count and manufacturing   |
//|   the zero. FIX: Layer C is evaluated ONLY when a genuine correction |
//|   extreme exists (corrPxValid). When it does not, the bar is         |
//|   reported as "CORE-PASS / ENH-N/A" and is excluded from the         |
//|   over-filtering count in either direction.                          |
//|   WHAT THE OLD NUMBERS STILL MEAN: CORE-REJECT=16,812 is             |
//|   UNAFFECTED -- that branch exits on firstFail before any            |
//|   enhancement value is read -- so "80.5% of bars fail the CORE model |
//|   outright" stands. ENH-REJECT=4,078 and CORE+ENH PASS=0 must be     |
//|   DISCARDED and re-measured with this build.                         |
//|   NEW VERDICT VOCABULARY (update any grep/parser):                    |
//|     CORE-REJECT              core rulebook failed (firstFail names it)|
//|     CORE-PASS / ENH-N/A      core ok, Layer C not evaluable (NEW)     |
//|     CORE-PASS / ENH-REJECT   the genuine over-filtering candidate     |
//|     CORE+ENH PASS            survived everything                      |
//|   RE-RUN PROTOCOL: identical tester case, all switches at default,    |
//|   InpSciCoreShadow=true. Count all FOUR verdicts. Then break the      |
//|   CORE-REJECT bars down by firstFail= -- whichever CORE rule          |
//|   dominates is the next item to take up, per Working Document s9.     |
//|                                                                  |
//|   v4.3.6 SCI CORE FIDELITY AUDIT - 2026-09-10. FIRST audit conducted |
//|   against the ICC Research & Methodology WORKING DOCUMENT rather than |
//|   against the code's own prior assumptions. Six findings; the two     |
//|   most severe are METHODOLOGY-FIDELITY defects, not C-level bugs --   |
//|   which is exactly the failure mode the Working Document s13          |
//|   predicted: "the EA's lack of trades may not mean the core ICC setup |
//|   is absent. It may mean the implementation has accumulated enough    |
//|   additional SMC/ICT-style filters that legitimate ICC setups are     |
//|   being rejected before reaching the entry gate."                     |
//|   EVERY behavioural change ships DEFAULT-OFF, so this build is        |
//|   byte-identical to v4.3.5 until a switch is thrown. That is required |
//|   by Working Document s9: "Do not immediately modify the production   |
//|   trading logic. First build a diagnostic-only shadow evaluator."     |
//|   (A, CRITICAL, FIDELITY -- CORE-04/05/06, s7 bullet 1) ICC           |
//|   CHRONOLOGY REVERSED. InpRequireSweep (default ON) gates the         |
//|   INDICATION, but the reviewed public material places liquidity       |
//|   interaction INSIDE THE CORRECTION ("Corrections commonly follow an  |
//|   indication and may grab liquidity"), and CORE-06 states a mandatory |
//|   sweep "should not be assumed unless direct methodology evidence     |
//|   supports it". The EA therefore demands the raid BEFORE the break    |
//|   -- the reverse of the documented sequence -- and promotes a         |
//|   CONFLUENCE factor to a hard pre-condition. FIX: new                 |
//|   InpLiquidityPhase { LIQ_INDICATION (legacy, default) /              |
//|   LIQ_CORRECTION (CORE-06 chronology) / LIQ_OFF (pure confluence) }.  |
//|   (B, HIGH, FIDELITY -- CORE-07/08, s7 bullet 5) THE CONTINUATION     |
//|   TRIGGER DID NOT REFERENCE THE CORRECTION. Both CONT branches called |
//|   the UNBOUNDED ICC_FindMinorPivotHigh/Low, which returns the nearest |
//|   confirmed pivot ANYWHERE in the last InpMinorPivotLookback(20)      |
//|   TrigTF bars with no requirement that it belongs to this correction. |
//|   CORE-07 defines continuation as "the opposing/internal CORRECTION   |
//|   structure fails", so the level that breaks must be the correction's |
//|   OWN transition. Because a correction prints LOWER highs, the        |
//|   nearest pivot typically sits BELOW the correction top -> the        |
//|   trigger fires early on noise. NOTE: the bounded helpers that fix    |
//|   this (ICC_FindMinorPivotHighSince/LowSince) have existed since      |
//|   v4.3.1 but were only ever wired to the structural-correction        |
//|   helper -- never to the trigger itself. FIX: new g_corrStartTime     |
//|   stamps the Correction, and InpContTrigSinceCorrection bounds the    |
//|   scan to it (FAILING CLOSED if the stamp is unusable).               |
//|   (C, HIGH, FIDELITY -- CORE-01) CONSOLIDATION COULD NEVER BE         |
//|   DETECTED. CORE-01: "Bullish = HH + HL... If neither sequence is     |
//|   intact, classify the environment as neutral/consolidating rather    |
//|   than forcing direction." MSE_UpdateTrendScale violates both halves: |
//|   it sets a trend on a SINGLE protected-swing break (never requiring  |
//|   the paired HH+HL), and once set "trend persists" with NO path back  |
//|   to 0. After the first BOS in a symbol's history the EA therefore    |
//|   ALWAYS believes it has a direction, so HTFbias() effectively never  |
//|   returns 0 and the "no trade is preferable to manufacturing a setup" |
//|   discipline is structurally unreachable. FIX (opt-in): after         |
//|   InpConsolidationBars MidTF bars with no fresh BOS in either         |
//|   direction, the external trend returns to NEUTRAL.                   |
//|   (D, MEDIUM, unit mismatch) ICC_ExpiryBars counts CHART bars while   |
//|   the Correction develops on WorkTF/H1 -- on the documented M15 chart |
//|   30 "bars" is ~7 H1 bars, expiring setups ~4x sooner than the input  |
//|   implies. Same family as the v4.2.7 sweep window and v4.3.3 Finding  |
//|   E; the expiry counter was simply never brought along. Opt-in        |
//|   InpExpiryInWorkTFBars.                                              |
//|   (E, LOW, dead code) The htf-flat branch read "if(g_iccPhase==       |
//|   PH_NONE) ICC_Reset();" -- a guaranteed NO-OP that only reset state  |
//|   already reset. Behaviour was correct (expiry/bias-flip resolve a    |
//|   live setup); the statement was meaningless. Replaced with an honest |
//|   comment + an optional diagnostic so a flat-HTF hold is visible.     |
//|   (F, s9/s10 DELIVERABLE) NEW SCI CORE FIDELITY SHADOW EVALUATOR.     |
//|   ICC_ShadowEvaluate() grades every bar in the three layers s9        |
//|   prescribes -- A: SCI CORE (CORE-01..09), B: CONFLUENCE (liquidity,  |
//|   session), C: EA ENHANCEMENTS (FVG, OB, displacement, fib/OTE) --    |
//|   emits exactly the s10 field list on ONE compact line, and reports   |
//|   the FIRST CORE rule that failed. Critically it flags               |
//|   "CORE-PASS / ENH-REJECT" whenever the core model approved a setup   |
//|   the enhancement stack then killed: that count IS the s9 experiment. |
//|   It is trading-NEUTRAL (reads state, sets none) and deliberately     |
//|   uses the PURE MSE_ScoreDisplacementCalc plus a cached g_inKillzone  |
//|   read, because IsInKillzone() would WRITE dashboard state.           |
//|   RECOMMENDED FIRST RUN: leave every switch at default, set           |
//|   InpSciCoreShadow=true, and count CORE-PASS/ENH-REJECT bars before   |
//|   changing any gate -- exactly the controlled comparison s9 asks for. |
//|                                                                  |
//|   v4.3.5 ZERO-PULLBACK-CORRECTION HOTFIX - 2026-09-10.            |
//|   Hostile line-by-line re-audit of v4.3.4. FOUR defects, one of    |
//|   them CRITICAL and INTRODUCED BY v4.3.4 ITSELF.                   |
//|   (A, CRITICAL, TRADE-PATH) v4.3.4 RE-OPENED THE ZERO-PULLBACK     |
//|   CORRECTION. v4.3.4's Finding-B guard correctly stopped an        |
//|   EXTENDING WorkTF bar from donating its own low as the pullback   |
//|   -- but it then left g_corrExtreme FROZEN at the Indication seed  |
//|   (= the ORIGINAL g_indExtreme, per the v4.3.3 seed fix) while     |
//|   g_indExtreme kept RISING on every extending bar. The discount    |
//|   threshold disc = ext - leg*CorrRetraceMin climbs with ext, so it |
//|   eventually CROSSES the frozen seed and PH_CORRECTION is declared |
//|   purely because the impulse EXTENDED -- with ZERO retracement.    |
//|   ALGEBRA: pbLow<=disc  <=>  seedExt <= 0.5*(newExt+indLevel)      |
//|                        <=>  newExt  >= 2*seedExt - indLevel.       |
//|   WORKED EXAMPLE (real journal, bar 41): indLevel=3875.58,         |
//|   seedExt=3879.88 -> the instant newExt reaches 3884.18 (just 4.3  |
//|   points of FURTHER impulse, price never retraced a tick) the      |
//|   engine prints PH_CORRECTION with g_corrExtreme sitting AT the    |
//|   impulse extreme. The Continuation can then fire immediately and  |
//|   iccSigSL = g_corrExtreme - g_slBuf plants the stop right at the  |
//|   impulse high -- a near-zero-distance stop on a fake setup. This  |
//|   is exactly the failure mode v4.3.1 and v4.3.3 were written to    |
//|   eliminate, reintroduced through the back door.                   |
//|   FIX: while the impulse is still EXTENDING no retracement exists  |
//|   BY DEFINITION, so the correction extreme must TRACK the impulse  |
//|   extreme: "if(extendedNow){ g_indExtreme=wkH1;                    |
//|   g_corrExtreme=g_indExtreme; }". Mirrored in the bear branch.     |
//|   (B, MEDIUM, unbounded growth) v4.3.4's Finding E was only HALF   |
//|   applied. It added fail-registry pruning INSIDE RX_Prune(), but   |
//|   RX_Prune() is called only when InpUseRexit is ON -- while the    |
//|   LEGACY management branch ALSO calls RX_SafeModify(), which fills |
//|   g_rxFailTicket/g_rxFailSL via RX_SetFailSL(). With the R-engine  |
//|   OFF the registry therefore still grew for the whole run and both |
//|   linear-scan lookups ran on every managed tick. RX_Prune() is now |
//|   called unconditionally (idempotent, cheap when empty).           |
//|   (C, MEDIUM, TRADING-AFFECTING) v4.3.4 capped the post-warm-up    |
//|   FVG/OB scan at a HARDCODED 4 bars. That assumes at most ~4       |
//|   g_intTF (WorkTF/H1) bars elapse between MSE_Update() calls --    |
//|   true ONLY on the documented M15 chart. On an H4 or D1 chart (or  |
//|   after a terminal reconnect / tester history rebuild) 6, 24 or    |
//|   more H1 bars pass per update, so every gap and order block       |
//|   formed in that window is NEVER detected -- permanently, because  |
//|   the shallow scan can never reach back that far again. FIX: new   |
//|   tracker g_lastScanIntBarTime + helper MSE_ScanDepthNeeded() size |
//|   the depth from the ACTUAL elapsed g_intTF bars (+ margin), which |
//|   is self-correcting on any chart TF and after any processing gap. |
//|   The v4.3.4 performance win is preserved: in steady state on M15  |
//|   the computed depth is 1-2 bars, i.e. SHALLOWER than the old 4.   |
//|   (D, LOW, consistency) The PH_CORRECTION deep-invalidation tests  |
//|   read the RAW bar-1 wkL1/wkH1 instead of the LATCHED pullback     |
//|   extreme g_corrExtreme (the running min/max, updated on the line  |
//|   directly above). Since g_corrExtreme is always at least as       |
//|   extreme as the raw bar, a pullback that BREACHED the deep line   |
//|   and then recovered escaped invalidation -- even though the       |
//|   breach is what the SL is anchored to. Now tests the latched      |
//|   extreme, so invalidation is monotonic and matches the            |
//|   PH_INDICATION branch, which already uses pbLow/pbHigh.           |
//|   (A) and (D) change live signal generation -- (A) REMOVES the     |
//|   fake zero-pullback Corrections v4.3.4 was creating, so trade     |
//|   count may FALL versus v4.3.4 and that is the CORRECT outcome.    |
//|   (C) can add genuine detections on non-M15 charts. (B) is pure    |
//|   housekeeping. Re-run the identical tester case (Master Spec      |
//|   15.1) and judge on $ expectancy and max drawdown, not on trade   |
//|   count.                                                           |
//|                                                                  |
//|   v4.3.4 SCAN-COST + PULLBACK + SIZING FIXES - 2026-09-10.        |
//|   Hostile line-by-line re-audit of v4.3.3. FIVE defects, one of    |
//|   them a RUNTIME REGRESSION that v4.3.3 itself introduced.         |
//|   (A, HIGH, RUNTIME REGRESSION) DEAD FVGs/OBs RE-SCANNED FOREVER.  |
//|   v4.3.3 correctly gave MSE_AddFVG/MSE_AddOB a history back-fill so |
//|   a stale structure could not enter the store as fresh -- but both  |
//|   REJECT an already-dead structure by returning WITHOUT inserting   |
//|   it. Because it is then absent from the store, MSE_FVGExists /     |
//|   MSE_OBExists is false again on the NEXT bar, so the scanner       |
//|   re-detects it and re-runs the whole O(barsSince) back-fill --     |
//|   every bar, forever. With InpFVGScanBars=120 that is sum(s-1) =    |
//|   7,140 loop iterations per direction per bar (14,280 both ways,    |
//|   ~28,560 iHigh/iLow reads per bar) = ~857 MILLION redundant history|
//|   calls across a 30,000-bar M15 run, on top of the OB scan. FIX:    |
//|   the deep historical scan is only needed ONCE, at warm-up; after   |
//|   that bars arrive singly, so the only structure that can newly     |
//|   COMPLETE is at the shallow end (a gap spans s, s+1, s+2, so the   |
//|   newest completable one is s=1). New g_fvgScanPrimed/g_obScanPrimed|
//|   make the first scan deep and later scans shallow. Structures      |
//|   already stored keep being maintained by MSE_UpdateFVGFills /      |
//|   MSE_UpdateOBMitigation, so NO detection is lost.                  |
//|   (B, MEDIUM-HIGH, TRADING-AFFECTING) THE v4.3.3 PULLBACK DEFECT    |
//|   SURVIVED ONE BAR LATER. v4.3.3 stopped the IMPULSE BAR's own low  |
//|   being seeded as the pullback, but PH_INDICATION still (a) extended|
//|   g_indExtreme with a bar's wkH1 and then (b) let that SAME bar's   |
//|   wkL1 define the pullback low. On a wide impulsive WorkTF bar that |
//|   makes a NEW HIGH, its own low is not a retracement -- it is the   |
//|   base of a fresh impulse leg -- yet it was written into            |
//|   g_corrExtreme and tested against the deep-invalidation line,      |
//|   killing setups on the very bars that confirm strength. FIX: a bar |
//|   that EXTENDED the impulse can no longer also define the           |
//|   correction; the next non-extending bar supplies the real pullback.|
//|   Mirrored in the bear branch.                                      |
//|   (C, MEDIUM, RISK CONTROL) SUB-MINIMUM LOTS SILENTLY OVER-RISKED.  |
//|   NormalizeLots() opens with "l=MathMax(l,mn)", so any risk-derived |
//|   size below the broker minimum was RAISED to LotsMin and the trade |
//|   taken anyway at MORE than RiskPercent, with no warning. With a    |
//|   small balance, a wide (deep-pullback) stop, or a reduced ML risk  |
//|   multiplier that can be a multiple of the mandate -- and stop      |
//|   distance is exactly what varies most here, so it is not rare.     |
//|   CalculateLotSize now REFUSES the trade and logs it. Same function |
//|   also returned LotsMin when TickValue/TickSize were unavailable -- |
//|   i.e. traded an unvalidated size precisely when it could not be    |
//|   computed; that now returns 0 too.                                 |
//|   (D, LOW, OVERSTATED FIX) The "never evaluate on the Indication    |
//|   bar" guard added in v4.3.3 (g_barCount>g_iccStartBar) can NEVER   |
//|   be false: the PH_NONE branch that fires the Indication and the    |
//|   PH_INDICATION branch are arms of the SAME if/else-if chain, so    |
//|   the latter cannot run on the Indication bar. v4.3.3 credited part |
//|   of its fix to that guard; in reality only the seed change did the |
//|   work. Kept as a defensive no-op and documented honestly.          |
//|   (E, LOW-MEDIUM, unbounded growth) The v4.2.8 anti-spam registry   |
//|   g_rxFailTicket/g_rxFailSL was only cleared from inside            |
//|   RX_SafeModify, which runs for OPEN positions only -- a ticket     |
//|   whose last modify FAILED and then closed left its row behind      |
//|   permanently, so both linear-scan lookups got slower for the life  |
//|   of the run. Now pruned in RX_Prune alongside the position table.  |
//|   (F, LOW) MSE_AddFVG tested its degenerate-span guard AFTER the    |
//|   back-fill loop, so a zero-span gap walked history before being    |
//|   discarded. Guard hoisted.                                         |
//|   (A) is a pure performance/robustness fix and does NOT change which|
//|   structures are detected. (B) and (C) DO change live behaviour --  |
//|   (B) should let materially more Indications reach Correction, and  |
//|   (C) will REFUSE trades it previously took over-risked. Re-run the |
//|   identical tester case (Master Spec 15.1) and watch $ expectancy   |
//|   and max drawdown, not just trade count.                           |
//|                                                                  |
//|   v4.3.3 ICC CORRECTION-SEED HOTFIX + 6 AUDIT FIXES - 2026-09-10.  |
//|   Hostile line-by-line re-audit of v4.3.2, GROUNDED IN THE REAL     |
//|   2025.10.01->2026.08.27 XAUUSD M15 TESTER JOURNAL (35,583 lines).  |
//|   Journal evidence that drove finding A: 459 Indications, but 308   |
//|   of 315 IND runs lasted EXACTLY ONE BAR, 275 died straight to      |
//|   PH_NONE, and only 40 (12.7%) ever reached PH_CORRECTION -> just   |
//|   18 signals / 22 deals in 11 months.                              |
//|   (A, CRITICAL, TRADE-PATH) THE CORRECTION EXTREME WAS SEEDED WITH  |
//|   A PRE-IMPULSE PRICE. At the Indication the engine did             |
//|     g_indExtreme = MathMax(wkH1,m15c1);  g_corrExtreme = wkL1;      |
//|   -- wkL1 is the WorkTF LOW OF THE VERY BAR THAT PRODUCED THE       |
//|   BREAK, i.e. the BOTTOM of the impulse bar, a price printed BEFORE |
//|   the impulse finished. It is not a pullback at all. The next bar   |
//|   then tested that seed against the deep-invalidation line          |
//|   (inval = extreme - leg*CorrRetraceMax) and killed the setup.      |
//|   Measured over all 459 logged Indications: the seed was already    |
//|   BEYOND the invalidation line on 76.9%, and beyond the IMPULSE     |
//|   ORIGIN itself -- a structurally impossible pullback -- on 74.9%.  |
//|   Worked example from the journal (bar 41): ind=3875.58 ext=3879.88 |
//|   seed corr=3859.03; leg=4.30 so inval=3876.01; 3859.03<=3876.01 -> |
//|   instant ICC_Reset() on the following bar.                         |
//|   FIX (two halves, both branches):                                  |
//|     (1) seed g_corrExtreme = g_indExtreme -- at the instant of the  |
//|         break NO retracement has occurred, so the correction        |
//|         extreme IS the impulse extreme; and                         |
//|     (2) only bars that CLOSED AFTER the Indication may define the   |
//|         pullback: PH_INDICATION now tracks a genuine post-impulse   |
//|         extreme (pbLow/pbHigh) and the disc/inval/structural tests  |
//|         read THAT instead of the raw bar-1 wkL1/wkH1, and are       |
//|         skipped entirely on the Indication bar itself.              |
//|   TRADING-LOGIC change: far more Indications now survive to         |
//|   Correction, so trade count should rise materially. NOT identical  |
//|   to v4.3.2 -- re-run the identical tester case (Master Spec 15.1). |
//|   (B, HIGH, TRADING-AFFECTING) STALE FVGs ENTERED THE STORE AS      |
//|   FRESH. MSE_ScanFVGs detects gaps up to InpFVGScanBars(120) bars   |
//|   old, but MSE_UpdateFVGFills only ever inspects bar 1 -- so a gap  |
//|   price traded clean through 90 bars ago was inserted with          |
//|   fillPct=0.0/active=true and could never be corrected, because the |
//|   fill that killed it lies in history the loop never revisits. The  |
//|   Continuation's containment gate (MSE_FVGContainOK) was therefore  |
//|   validating entries against dead gaps. FIX: MSE_AddFVG back-fills  |
//|   the true fill% over every bar printed since the gap formed and    |
//|   refuses to track one already >= InpFVGFillInvalidate.             |
//|   (C, HIGH, TRADING-AFFECTING) Same defect in the ORDER-BLOCK store:|
//|   MSE_UpdateOBMitigation also only reads bar 1, so blocks already   |
//|   CLOSED THROUGH were inserted active. MSE_AddOB now replays the    |
//|   bars since formation with the SAME mitigation/violation rules and |
//|   discards a block that was already violated. Affects both the OB   |
//|   entry gate and the ML ob_active feature.                          |
//|   (D, MEDIUM) g_iccStartTime stamped iTime(_Period,0) -- the still- |
//|   FORMING bar -- although the Indication is derived from bar 1.     |
//|   ICC_FindMinorPivot*Since() bounds its scan with that stamp, so    |
//|   the structural-correction window sat one bar in the future. Now   |
//|   stamps bar 1, the closed bar the signal actually came from.       |
//|   (E, MEDIUM, TRADING-AFFECTING) SWEEP WINDOW COULD NEVER EXPIRE:   |
//|   MSE_DetectSweep reads g_intTF(H1) bar 1, but MSE_UpdateLiquidity  |
//|   runs every CHART (M15) bar, so one H1 sweep was re-detected up to |
//|   4x and each detection RESET g_sweepConf* to InpSweepValidBars --  |
//|   refreshing the countdown as fast as v4.2.7 ticked it down. Arming |
//|   is now gated on a genuinely new H1 bar, the same gate used by the |
//|   decrement.                                                        |
//|   (F, LOW) FVG/OB chart-object names cast the 64-bit datetime to    |
//|   int -- truncating past 2038 and able to alias two objects onto    |
//|   one name. IntegerToString() takes a long; the cast is removed.    |
//|   (G, LOW) ML_BuildPerSymbolFilename split on the FIRST dot, so any |
//|   filename with an earlier dot produced a mangled per-symbol name.  |
//|   Now splits on the LAST dot.                                       |
//|   (A)(B)(C)(E) change live signal generation; (D)(F)(G) are         |
//|   telemetry/robustness. Re-validate on the tester before adopting.  |
//|                                                                  |
//|   v4.3.2 CONT-DIAGNOSTIC EDGE FIX — 2026-09-03. Closes audit      |
//|   Finding F6 from the Fibonacci-usage review. DIAGNOSTIC-ONLY:    |
//|   NO entry, exit, sizing, gating, or structure logic changed, so  |
//|   backtest TRADE results are byte-identical to v4.3.1.            |
//|   (F6, MEDIUM, MISLEADING DIAGNOSTIC) The [ICC GATE] LONG/SHORT   |
//|   CONT lines computed their fvgOK from the FIB band edge          |
//|   (disc/prem = extreme -/+ leg*CorrRetraceMin, or the OTE edge)   |
//|   even when InpUseStructuralCorrection=ON -- because the          |
//|   structural read (ICC_StructuralCorrectionOK) sat BELOW the      |
//|   fvgOK line. The ENGINE, by contrast, substitutes the            |
//|   correction's OWN confirmed LOWER HIGH / HIGHER LOW for that     |
//|   edge before calling MSE_FVGContainOK (see ICC_Update's          |
//|   PH_CORRECTION branches, "if(...OK(...,sEdge) && sEdge>0.0)      |
//|   disc=sEdge"). The printed "FVG=" field could therefore report   |
//|   a DIFFERENT result than the gate the engine actually evaluated  |
//|   on the same bar -- and that field is exactly what an operator   |
//|   reads to diagnose why continuations are blocked, so a wrong     |
//|   value could send tuning in the wrong direction entirely.        |
//|   FIX: in BOTH CONT branches the structural read is hoisted ABOVE |
//|   fvgOK, a local discEff/premEff applies the SAME substitution    |
//|   the engine performs, and fvgOK is evaluated against it. The     |
//|   line now prints discEff/premEff (the edge actually used) AND    |
//|   the raw fib edge, so both are visible side by side. Both        |
//|   helpers remain PURE reads (no ICC state mutated); with the      |
//|   toggle OFF discEff==disc and premEff==prem, so the OFF-path     |
//|   log line is unchanged apart from the added "(fib=...)" field.   |
//|   STILL OPEN (documentation, not applied here): the               |
//|   CorrRetraceMin/Max inline comments say "(fib of impulse)" but   |
//|   0.500 and 0.900 are NOT Fibonacci ratios -- only the OTE band   |
//|   (0.62~0.618, 0.79~0.786, default OFF) is genuinely Fib-derived. |
//|                                                                  |
//|   v4.3.1 STRUCTURAL-CORRECTION HOTFIX + 5 AUDIT FIXES — 2026-09-03.|
//|   Hostile line-by-line re-audit of the v4.3.0 build. SIX defects,  |
//|   one of them CRITICAL and self-triggering.                        |
//|   (A, CRITICAL, TRADE-PATH) STRUCTURAL CORRECTION COULD CONFIRM AND|
//|   CONTINUE WITH ZERO PULLBACK. ICC_StructuralCorrectionOK() had two|
//|   defects that COMBINED into a self-triggering loop:               |
//|     (1) it called the UNBOUNDED ICC_FindMinorPivotHigh/Low, which  |
//|         returns the nearest confirmed pivot in the last            |
//|         InpMinorPivotLookback(20) TrigTF bars with NO requirement  |
//|         that the pivot formed AFTER the Indication -- so a pivot   |
//|         left behind BEFORE the impulse satisfied the "lower high"  |
//|         test; and                                                  |
//|     (2) it never checked that price had ACTUALLY RETRACED -- the   |
//|         only price test was on the pivot level, never on the       |
//|         pullback extreme.                                          |
//|   Because g_indExtreme = MathMax(wkH1,m15c1), whenever m15c1 is the|
//|   impulse extreme the LH test "mpHi < g_indExtreme - floorDist"    |
//|   ALGEBRAICALLY IMPLIES "m15c1 > mpHi" -- which is exactly the     |
//|   Continuation trigger. Indication -> Correction -> Continuation   |
//|   could therefore complete within a bar or two on a stale pivot    |
//|   with NO pullback whatsoever: the precise OPPOSITE of the Sci     |
//|   definition this toggle exists to implement. FIX: new datetime    |
//|   g_iccStartTime stamps the Indication bar; new bounded finders    |
//|   ICC_FindMinorPivotHighSince/LowSince reject any pivot older than |
//|   it (failing CLOSED if the stamp is unavailable); and the helper  |
//|   now takes the live pullback extreme and requires it to have      |
//|   travelled InpStructCorrMinRetrace*leg back from the impulse      |
//|   extreme. Affects ONLY InpUseStructuralCorrection=ON (default OFF |
//|   remains byte-identical to v4.2.9).                               |
//|   (B, MEDIUM, data integrity) ML v4 distance_to_external/internal_ |
//|   high/low_atr were assigned ONLY inside "if(atr>0.0)" and only    |
//|   when the matching protected swing was >0. MQL5 does not zero-    |
//|   initialise local struct members, so warm-up entries wrote        |
//|   UNINITIALISED memory into four dataset columns. Now seeded to 0. |
//|   (C, MEDIUM, telemetry) ML v4 MONEY LAYER SILENTLY ZERO: the entry|
//|   volume came only from PositionSelectByTicket(), which is not     |
//|   always selectable on the DEAL_ENTRY_IN transaction (and returns  |
//|   the AGGREGATE on a multi-deal fill). initRiskMoney then stayed 0,|
//|   and since mfe/mae_money derive from initRiskMoney/initRisk the   |
//|   WHOLE money layer for that trade collapsed to 0 silently. Fix:   |
//|   pass the entry deal's own DEAL_VOLUME, warn if still unavailable.|
//|   (D, LOW, resource leak) ProcessBar's ">60 levels" eviction called|
//|   RemoveAt(0) WITHOUT DeleteLevelObjects(0) -- unlike every other  |
//|   eviction path -- orphaning that level's _box/_ln/_lb objects with|
//|   its name discarded, so they could never be deleted individually. |
//|   (E, MEDIUM, sizing) NormalizeLots() rounded to a HARDCODED 2     |
//|   decimals AFTER step-aligning, which on a 0.001-lot-step broker   |
//|   re-rounds straight back OFF the step (0.125 -> 0.13): can exceed |
//|   intended risk and be rejected as an invalid volume. Lot digits   |
//|   are now derived from the broker's own LotsStep, then re-clamped. |
//|   (F, MEDIUM, TRADING-AFFECTING) FVG/OB EVICTION ORDER INVERTED:   |
//|   MSE_DropOldestFVG/OB evicted index 0 assuming it is the oldest.  |
//|   MSE_ScanFVGs/ScanOBs walk s=1 (NEWEST bar) upward, so warm-up    |
//|   inserts NEWEST-FIRST and index 0 is the most RECENTLY FORMED     |
//|   gap/block. With scan depth 120 > max tracked 40 the store        |
//|   overflows on the first scan, so the engine repeatedly discarded  |
//|   the freshest, most tradable gaps and kept the stalest -- directly |
//|   degrading the FVG-containment gate the Continuation depends on.  |
//|   Fix: evict the genuinely oldest entry BY TIMESTAMP (correct for  |
//|   any insertion order; scan direction untouched).                  |
//|   NOTE: (A) and (F) change live signal generation; (B)(C)(D)(E) are|
//|   telemetry/resource/sizing. Re-validate on the tester.            |
//|                                                                  |
//|   v4.3.0 STRUCTURAL CORRECTION DEFINITION — 2026-09-03. Takes up   |
//|   the LAST open Sci-FIDELITY item deferred since the v4.1.0 audit: |
//|   "the default 0.50-0.90 retracement band vs a structural higher-  |
//|   low/lower-high correction interpretation."                       |
//|   METHODOLOGY: Trades-by-Sci defines a Correction STRUCTURALLY --  |
//|   a counter-trend leg that prints a confirmed LOWER HIGH (bull) or |
//|   HIGHER LOW (bear), which stays valid for as long as the IMPULSE  |
//|   ORIGIN holds -- not by an arbitrary fib percentage of the leg.   |
//|   The v4.2.9 engine instead confirmed the Correction on a 0.50 fib |
//|   TOUCH and killed the setup on a 0.90 fib TOUCH, so a shallow but |
//|   structurally perfect pullback never became a Correction, while a |
//|   deep-but-still-valid pullback that never lost the impulse origin |
//|   was discarded. Both are fidelity defects, not tuning knobs.      |
//|   NEW INPUT InpUseStructuralCorrection (default FALSE):            |
//|     OFF -> EXACT v4.2.9 behaviour (fib band; byte-identical).      |
//|     ON  -> CONFIRM on a CONFIRMED counter-trend minor pivot        |
//|            (ICC_StructuralCorrectionOK) beyond an anti-noise floor |
//|            InpStructCorrMinRetrace (default 0.10 of the leg), and  |
//|            INVALIDATE only on a BODY CLOSE back beyond g_indLevel  |
//|            (ICC_StructuralInvalidated) -- the protected swing the  |
//|            Indication broke. Reclaiming it means the BOS failed.   |
//|            InpStructCorrKeepMaxDepth (default FALSE) optionally    |
//|            retains the CorrRetraceMax cap as a secondary guard.    |
//|   Also: in STRUCTURAL mode the shallow edge of the pullback band   |
//|   handed to MSE_FVGContainOK becomes the correction's OWN confirmed|
//|   LH/HL (semantically the top/bottom of the correction) instead of |
//|   the 0.50 fib level, so FVG containment is measured against real  |
//|   structure. LEAKAGE-SAFE: both helpers are PURE reads that reuse  |
//|   ICC_FindMinorPivotHigh/Low -> IsPivotHighTF/LowTF, which require |
//|   the newer neighbour bars to already exist and be valid (>0), so  |
//|   only CONFIRMED pivots on CLOSED bars are ever used.              |
//|   TRADING-LOGIC change when ON: alters which Corrections confirm   |
//|   and when setups invalidate -> live signal generation. Expected   |
//|   to INCREASE trade count (shallow structural pullbacks now        |
//|   qualify; deep-but-valid ones survive). NOT byte-identical with   |
//|   the toggle ON -- run the one-variable A/B against the OFF        |
//|   baseline per Master Spec 15.1 before adopting. Diagnostics: the  |
//|   broker banner, the init-check banner and both [ICC GATE] CONT    |
//|   lines now print corrDef=STRUCT/FIB plus the structural LH/HL and |
//|   originHeld state, so every run records which arm governed.       |
//|                                                                  |
//|   v4.2.9 ML MONEY LAYER (schema 4.0.2) — 2026-09-03. ADDITIVE     |
//|   telemetry per Chad's three-layer PRICE/RISK/MONEY request. The   |
//|   v4 dataset already had PRICE (mfe/mae_price) and RISK (mfe/mae_r,|
//|   reached_1r..10r, exit_r) but only REALIZED money (exit_money).   |
//|   Adds the missing MONEY-EXCURSION fields as THREE new columns,    |
//|   appended AFTER model_version so every pre-existing column index  |
//|   stays stable for already-merged CSVs:                           |
//|     initial_risk_money -- 1R in account currency                  |
//|     mfe_money           -- peak UNREALIZED profit before exit ($)  |
//|     mae_money           -- worst UNREALIZED drawdown ($)           |
//|   CRITICAL: all three are computed with MT5's OrderCalcProfit()    |
//|   (contract size, tick value/size, volume, currency conversion),  |
//|   NEVER a hand-rolled pips*$/pip -- which mis-scales XAUUSD vs FX. |
//|   initial_risk_money is set once at entry; mfe/mae_money tracked   |
//|   live in ML_v4_TrackOpen() and sampled at exit. $-at-N-R is       |
//|   downstream-derivable as N*initial_risk_money, so no redundant    |
//|   per-R dollar columns were added. schema_version 4.0.1->4.0.2.    |
//|   ML LABELS UNCHANGED: R stays the training target (reached_2r/    |
//|   exit_r); money is DESCRIPTIVE only. NO entry/exit/sizing/gating  |
//|   logic touched -- backtest TRADE results byte-identical to v4.2.8.|
//|                                                                  |
//|   v4.2.8 GUARDED STOP-MODIFY (log-flood / broker-spam fix) —      |
//|   2026-09-03. Diagnosed from the 2026.03.19 XAUUSD tester journal   |
//|   (a 26 MB log): position #12 (short) emitted TENS OF THOUSANDS of  |
//|   identical "failed modify #12 ... sl:4854.32 -> sl:4854.32         |
//|   [Invalid stops]" (retcode 10016) -- one per tick for ~50 minutes  |
//|   of a single stalled bar. Filling mode was FINE (mask=3/FOK, deals |
//|   #10/#12 both filled); the flood came from the trailing/R-engine   |
//|   re-sending a broker-ILLEGAL, UNCHANGED stop every tick with its   |
//|   PositionModify return value discarded. Fix: all four              |
//|   trade.PositionModify() sites (RX_ManageOne long/short + legacy    |
//|   ManagePositions long/short) now route through a new RX_SafeModify |
//|   wrapper that (a) no-ops when the new SL equals the live SL within |
//|   a tick, (b) validates the SL against GetMinStopDistance (stops +  |
//|   freeze + spread) BEFORE sending so an illegal stop is never even  |
//|   submitted, and (c) records the last SL that FAILED per ticket and |
//|   refuses to re-attempt that identical value until price/level      |
//|   actually moves -- and logs a real failure only ONCE per new       |
//|   value. Pure execution hardening: NO entry/exit/sizing/gating      |
//|   decision changed; the one-way ratchet is preserved. Eliminates    |
//|   the log flood and the wasted trade-context calls.                |
//|                                                                  |
//|   v4.2.7 SWEEP-VALIDITY WINDOW -> H1 BARS — 2026-09-03. Takes up   |
//|   the LAST deferred item (b). The sweep-validity counters          |
//|   (g_sweepConfLong/Short, set to InpSweepValidBars) gate how long  |
//|   an armed liquidity sweep can trigger an Indication. The sweep is |
//|   DETECTED on g_intTF (WorkTF/H1), so the window is conceptually    |
//|   in H1 bars -- but it was decremented once per MSE_UpdateLiquidity |
//|   () call, i.e. once per new CHART-TF bar (M15 in the cascade). On  |
//|   an M15 chart that burned the window ~4x too fast: InpSweepValid-  |
//|   Bars=8 meant 8xM15 (~2 hours = ~2 H1 bars), not 8 H1 bars, so     |
//|   sweeps expired well before the documented arming window and could |
//|   suppress otherwise-valid Indications. Fix: new tracker            |
//|   g_lastLiqIntBarTime decrements the counters exactly ONCE PER NEW  |
//|   H1 (g_intTF) BAR; the first call primes the tracker without       |
//|   decrementing. InpSweepValidBars is now a genuine count of H1 bars,|
//|   matching the timeframe the sweep is detected on. TRADING-LOGIC    |
//|   change (windows now last longer on sub-H1 charts -> more sweeps   |
//|   stay armed): NOT byte-identical to v4.2.6; re-validate on the     |
//|   tester. This closes the audit backlog -- no deferred items remain.|
//|                                                                  |
//|   v4.2.6 EQUAL-LEVEL MAGNET STRENGTH ALIGN — 2026-09-03. Takes up |
//|   previously-DEFERRED item (c). MSE_DetectEqualHighs/Lows (the     |
//|   BSL/SSL equal-level liquidity magnets) scan g_intTF (WorkTF/H1,  |
//|   the INTERNAL entry-side structure TF) but seeded their fractal   |
//|   test with InpExtSwingStrength (4) -- the EXTERNAL/direction      |
//|   strength -- while every other H1 consumer (MSE_FindProtected ->  |
//|   g_intProtHigh/Low, internal trend, the nearest-pool builders)    |
//|   uses InpIntSwingStrength (2). The equal-level magnet was thus     |
//|   systematically STRICTER than, and structurally inconsistent with,|
//|   the protected swings feeding the sweep pool beside it. Fix: both |
//|   detectors now use InpIntSwingStrength, matching the timeframe     |
//|   they operate on. TRADING-LOGIC change: alters which equal-level  |
//|   clusters are detected -> which sweep pools arm -> live signals;  |
//|   generally makes the H1 magnet slightly more permissive (surfaces |
//|   more genuine 2-bar equal-level pools). NOT byte-identical to     |
//|   v4.2.5 -- re-validate on the tester. Only remaining deferred     |
//|   item: (b) InpSweepValidBars M15-vs-H1 decrement-unit mismatch.  |
//|                                                                  |
//|   v4.2.5 FILLING-MODE AUTODETECT + ML-CONSUME GUARD — 2026-09-03. |
//|   Hostile line-by-line re-audit of the v4.2.4 build. Two defects   |
//|   fixed:                                                          |
//|   (F1, MEDIUM-HIGH, TRADE-BLOCKING) FILLING MODE HARDCODED TO FOK:|
//|   OnInit did trade.SetTypeFilling(ORDER_FILLING_FOK) with NO check |
//|   of the symbol's SYMBOL_FILLING_MODE bitmask. Brokers that support|
//|   only IOC (very common on XAUUSD ECN / market-execution) reject   |
//|   EVERY order with retcode 10030 "Unsupported filling mode" -> the |
//|   EA silently places ZERO trades regardless of signal quality.    |
//|   Fix: detect the supported mode and prefer FOK -> IOC -> RETURN,  |
//|   and log the chosen mode + broker mask at init. Execution-layer   |
//|   only; no signal/sizing/exit logic changed.                      |
//|   (F2, LOW, telemetry) ML PENDING-SNAPSHOT CONSUME NOT GUARANTEED:|
//|   the single-use g_mlPendValid flag is cleared inside ML_v2_       |
//|   RegisterEntry, which early-returns when InpMLv2Export=false --   |
//|   so with v4 export ON and v2 export OFF the flag was never reset, |
//|   a latent stale-provenance path. Fix: OnTradeTransaction now      |
//|   clears g_mlPendValid explicitly after both registrars, so the    |
//|   snapshot is single-use regardless of export toggles.            |
//|   Still deferred (unchanged): (b) InpSweepValidBars M15-vs-H1 unit;|
//|   (c) equal-level fractal strength (Ext 4 vs Int 2).             |
//|                                                                  |
//|   v4.2.4 HTF-BOUNDARY A/B TOGGLE — 2026-09-03. Takes up the       |
//|   previously-DEFERRED judgment call (a): the HTFbias conviction    |
//|   gate boundary. New input InpHTFStrictBoundary (default FALSE)    |
//|   selects the comparison against HTF_MinConviction:               |
//|     OFF -> inclusive >=/<=  == EXACT v4.2.3 behaviour (score AT    |
//|            the floor passes; an opposing D1 that drags conviction  |
//|            to exactly the threshold still trades).                 |
//|     ON  -> strict   >/<    : score EXACTLY at the floor is VETOED, |
//|            so an opposing D1 at the threshold BLOCKS the trade.    |
//|   Worked example (defaults D1Weight=0.5, HTF_MinConviction=0.5):   |
//|   H4 up + opposing D1 -> score=1+(-1)*0.5=0.5; OFF: 0.5>=0.5 pass, |
//|   ON: 0.5>0.5 veto. This is a TRADING-LOGIC choice, delivered as a |
//|   toggle so it can be A/B-tested with ONE variable changing and no |
//|   recompile. Default OFF keeps trade results byte-identical to     |
//|   v4.2.3. The broker-diagnostics banner now prints HTFboundary=    |
//|   STRICT/INCLUSIVE so every run's log records which arm it used.   |
//|   A/B PROTOCOL: run OFF (baseline) then ON over the SAME symbol/   |
//|   period/model; compare net profit, trade count, profit factor,    |
//|   expectancy (R), and max drawdown. Adopt STRICT only if it        |
//|   improves risk-adjusted return without over-thinning the sample.  |
//|   Still deferred (unchanged): (b) InpSweepValidBars M15-vs-H1 unit;|
//|   (c) equal-level fractal strength (Ext 4 vs Int 2).              |
//|                                                                  |
//|   v4.2.3 ML-PROVENANCE FIX — 2026-09-03. Hostile line-by-line     |
//|   re-audit of the v4.2.2 build. One genuine (paired) defect found |
//|   and fixed; TELEMETRY/DATA-PROVENANCE only -- NO entry, exit,     |
//|   sizing, gating, or structure logic changed, so backtest TRADE    |
//|   results are byte-identical to v4.2.2.                           |
//|   (G1/G2, LOW) ML-SNAPSHOT REGISTRATION ORDER INVERTED:           |
//|   OnTradeTransaction's DEAL_ENTRY_IN branch called ML_v2_Register- |
//|   Entry BEFORE ML_v4_RegisterEntry, but v4's own body comment      |
//|   documents the intent as v4-FIRST ("Do not consume the pending    |
//|   snapshot here; the legacy v2 recorder still needs it"). v2 sets  |
//|   g_mlPendValid=false as it exits, so v4 -- running second -- ALWAYS|
//|   saw g_mlPendValid==false and took the PositionGetInteger()        |
//|   fallback for r.dir, and read g_mlPendSigTime UNGUARDED for        |
//|   r.sigTime. The fallback is correct on a live entry deal, so       |
//|   trades and even the v4 dir were unaffected in normal flow -- but  |
//|   the dataset's dir/sigTime provenance no longer traced to the      |
//|   genuine staged ICC signal, and a manual/unstaged entry logged a   |
//|   STALE prior-signal timestamp. Fix: (G1) reorder to v4-then-v2 so  |
//|   v4 reads the real staged snapshot without consuming it; (G2)      |
//|   guard v4 r.sigTime with g_mlPendValid, mirroring v2. The g_p*     |
//|   frozen FEATURE globals were never cleared by v2, so v4's feature  |
//|   columns were already correct and are unchanged.                  |
//|   RE-FLAGGED (still deferred, judgment calls -- unchanged): (a)    |
//|   HTFbias >=/<= boundary passes an opposing D1 exactly at          |
//|   HTF_MinConviction; (b) InpSweepValidBars decremented per         |
//|   MSE_Update (M15) call though the sweep is detected on H1; (c)    |
//|   MSE_DetectEqualHighs/Lows use InpExtSwingStrength(4) for the      |
//|   equal-level magnets while internal swings use InpIntSwingStr(2). |
//|   VERDICT: after this pass, no compile-time or critical runtime/   |
//|   trade-path defect remains; residuals above are LOW-severity       |
//|   design choices awaiting Chad's explicit sign-off.                |
//|                                                                  |
//|   v4.2.2 DIAGNOSTIC-REACH + ML-RISK-GUARD — 2026-09-03. Hostile  |
//|   line-by-line re-audit of the v4.2.1 build. Two genuine defects  |
//|   found and fixed; both are DIAGNOSTIC/TELEMETRY only -- NO entry,|
//|   exit, sizing, gating, or structure logic changed, so backtest   |
//|   TRADE results are byte-identical to v4.2.1.                     |
//|   (F1/F6, MEDIUM) HEARTBEAT + SKIP DIAGNOSTIC UNREACHABLE WHEN    |
//|   UseICCPullback=OFF: ICC_Update() ran "if(!UseICCPullback)       |
//|   return;" as its 2nd line -- BEFORE ICC_LogGateDiagnostics() --  |
//|   so the v4.2.1 heartbeat and the "[ICC GATE] SKIP" branch were   |
//|   dead code in precisely the "engine disabled / dark" case the    |
//|   heartbeat exists to reveal. Fix: the early-return moved to AFTER |
//|   the diagnostic call (HTFbias()/iClose/iHigh/iLow are side-      |
//|   effect-free, so evaluating them first is safe).                 |
//|   (F2, MEDIUM) ML v4 DEGENERATE-RISK: ML_v4_RegisterEntry set     |
//|   initRisk=|entry-initSL| with NO fallback -- unlike the v2       |
//|   recorder. A momentarily-0 POSITION_SL (or entry==stop) made     |
//|   initRisk 0 (-> reached_1r..10r never labeled in TrackOpen, and  |
//|   a risk=1.0 sentinel in WriteRow distorting mfe_r/exit_r) or a   |
//|   garbage ~entry-price magnitude. Fix: mirror the v2 fallback     |
//|   (g_pRiskDist -> ATR). ML v4 dataset integrity only.            |
//|   RE-FLAGGED (still deferred, judgment calls -- unchanged): (a)   |
//|   HTFbias >=/<= boundary passes an opposing D1 sitting exactly at |
//|   HTF_MinConviction; (b) InpSweepValidBars is decremented per     |
//|   MSE_Update (M15) call though the sweep is detected on H1; (c)   |
//|   MSE_DetectEqualHighs/Lows use InpExtSwingStrength(4) for the    |
//|   equal-level magnets while internal swings use InpIntSwingStr(2).|
//|                                                                  |
//|   v4.2.1 SIGNAL-PATH + TRACEABILITY FIX — 2026-09-03.            |
//|   Grounded in the REAL source + a full 2025.10.01->2026.08.27     |
//|   XAUUSD M15 tester log that printed phase=--- / sig 0/0 on ALL   |
//|   ~30k bars (ZERO Indications, ZERO trades). Fixes:              |
//|   (A, CRITICAL) SWEEP-POOL vs HTF-ALIGNMENT CONTRADICTION:       |
//|   MSE_BuildSSL/BSL built the sweep pool as the 120-bar RANGE     |
//|   EXTREME (iLowest/iHighest via MIN/MAX). A long also needs      |
//|   g_extTrend==1 and a short g_extTrend==-1, so a same-side sweep |
//|   of the 120-bar extreme is a deep counter-trend event that      |
//|   never co-occurs with the required HTF trend -> zero signals    |
//|   forever. New input InpSweepNearestPool (default ON) rebuilds   |
//|   the pool from the NEAREST internal protected swing / equal-    |
//|   level cluster (the genuine ICC pullback-liquidity magnet).     |
//|   OFF = exact v4.2.0 range-extreme behaviour. NOTE: changes      |
//|   live trade generation; re-validate on the tester.             |
//|   (B) VERBOSE [ICC] LINE printed legacy cascade biasH4 only,     |
//|   never the AUTHORITATIVE g_extTrend that actually gates the     |
//|   trade -> added H4ext=g_extTrend (H4 relabelled H4c=cascade).   |
//|   (C) VERSION DRIFT: #property version 4.10, description/Trade-  |
//|   Comment/broker-diag/alert strings all said v4.1.0 while the    |
//|   file was v4.2.0 -> ALL unified to v4.2.1 (version "4.21").     |
//|   (D) HARDENING: OnInit now prints InpICCGateDiagnostics and the |
//|   key signal-path toggles UNCONDITIONALLY, so a false flag can   |
//|   never again look like a dark engine. Plus a trading-neutral    |
//|   HEARTBEAT: input InpGateHeartbeatBars (default 50, 0=off) emits |
//|   one "[ICC GATE] heartbeat" line every N bars INDEPENDENT of the |
//|   InpICCGateDiagnostics flag, so "gate alive & correctly quiet"   |
//|   is always distinguishable from "engine dark". Log-only; reads   |
//|   state, sets none -> backtest trade results byte-identical.      |
//|   DEFERRED (unchanged, judgment calls): HTFbias boundary uses    |
//|   >=/<= at exactly HTF_MinConviction (an opposing D1 at the      |
//|   threshold still passes); InpSweepValidBars is decremented per  |
//|   MSE_Update (M15) call while the sweep is detected on H1.       |
//|                                                                  |
//|   v4.2.0 H4 AUTHORITY CORRECTION — 2026-09-03.                   |
//|   SURGICAL CHANGE: ICC HTF direction now uses the MSE External   |
//|   protected-structure trend on H4 (g_extTrend). The legacy      |
//|   cascade H4 pivot bias remains intact for dashboard/secondary   |
//|   visibility. D1 remains a soft higher-timeframe conviction      |
//|   weight. No other entry, exit, sizing, ML, FVG, OB, liquidity,  |
//|   displacement, or protected-swing logic was changed.            |
//|   v4.1.0 CORE ICC/SMC ENGINE REWRITE — 2026-09-02. Requested by    |
//|   Chad Woodyard following a hostile line-by-line audit + SMC/ICC   |
//|   fidelity review of the entry-signal engine (never previously     |
//|   audited in prior versions -- those audits were scoped to ML     |
//|   functions and a gate-diagnostic logging bug only). That review   |
//|   scored this EA 4/10 on faithfulness to the Trades-by-Sci ICC      |
//|   method and found the compromised core traced to 4 concrete        |
//|   findings, ALL fixed in this build:                                 |
//|   (FINDING 1, CRITICAL) INDICATION ANCHOR SILENT OVERRIDE: MSE_Update|
//|   fed g_intProtHigh/Low (fractals on a SINGLE shared structure TF,   |
//|   g_mseTF, which defaulted to WHATEVER the chart was attached to)    |
//|   into wkLastHi/wkLastLo, silently overwriting the EA's own          |
//|   documented WorkTF (H1) "swing anchor" the moment this EA was        |
//|   attached to, e.g., an M15 chart -- defeating the D1->H4->H1->M15   |
//|   cascade the whole system claims to implement.                      |
//|   (FINDING 2, CRITICAL) EXTERNAL/INTERNAL STRUCTURE SHARED ONE TF:    |
//|   External (direction-gating) and Internal (entry-gating) structure  |
//|   both computed on the IDENTICAL g_mseTF, differing ONLY by fractal  |
//|   strength (4 vs 2 bars) -- not genuine timeframe separation, so the |
//|   "dual market structure" the header describes could collapse to     |
//|   single-timeframe analysis under common configurations.             |
//|   FIX (1+2 together): g_mseTF/InpMSE_TF are REMOVED. External         |
//|   structure now ALWAYS computes on MidTF (H4 -- already documented   |
//|   as the "primary Indication TF"); Internal structure -- and every   |
//|   engine that feeds the entry side (liquidity sweep/reclaim, FVG,    |
//|   order blocks, institutional displacement) -- now ALWAYS computes   |
//|   on WorkTF (H1 -- already documented as the "swing anchor"). New    |
//|   globals g_extTF=MidTF, g_intTF=WorkTF (assigned once in OnInit)    |
//|   replace g_mseTF everywhere. MSE_IsFractalHigh/Low, MSE_FindProtect-|
//|   ed, and MSE_UpdateTrendScale now take an explicit tf parameter     |
//|   instead of reading a shared global, so External and Internal can   |
//|   never again accidentally share a timeframe. As a direct            |
//|   consequence, the former "silent WorkTF override" is no longer a    |
//|   bug: internal structure genuinely IS WorkTF/H1-based now, so       |
//|   feeding its protected swings into wkLastHi/wkLastLo is the         |
//|   CORRECT, intended Indication anchor, not a contradiction of it.    |
//|   (FINDING 3) CONTINUATION TRIGGER WAS AN ARBITRARY ROLLING OFFSET:   |
//|   the Continuation trigger tested price against iHigh/iLow(TrigTF,2) |
//|   -- an UNCONFIRMED "2 bars ago" level recomputed fresh every bar,    |
//|   with zero relationship to the correction's own structure; as the   |
//|   Correction phase persisted, this level slid forward arbitrarily,    |
//|   letting Continuation fire on stale noise or blocking a genuine     |
//|   one based purely on what happened to sit 2 candles back. FIX: new  |
//|   ICC_FindMinorPivotHigh()/ICC_FindMinorPivotLow() locate a genuine   |
//|   CONFIRMED minor-swing fractal on TrigTF (M15), reusing the SAME     |
//|   validated-neighbor-bar pivot test (IsPivotHighTF/IsPivotLowTF)      |
//|   already used by the D1/H4/H1/M15 cascade, at a new configurable    |
//|   InpMinorPivotStrength (default 1 bar each side -- matches M15's     |
//|   documented "entry timing" role and Sci's stated preference for      |
//|   simple, timely entries over added filtering) within a new           |
//|   InpMinorPivotLookback window (default 20 bars). Both the LONG and   |
//|   SHORT Continuation branches, and the [ICC GATE] CONT diagnostic      |
//|   lines, now report this same genuine pivot level.                     |
//|   (FINDING 4) SwingLen/InpLiqLookback CROSS-WIRE: MSE_BuildBSL/SSL      |
//|   (buy-/sell-side liquidity pool detection) used SwingLen*2 bars as     |
//|   its scan depth -- SwingLen is documented under "Visuals: Swings +    |
//|   Dashboard", i.e. meant to be COSMETIC swing-ray drawing ONLY, so      |
//|   adjusting a purely visual input silently changed real liquidity-      |
//|   pool detection range, while InpLiqLookback (the input actually        |
//|   documented for this purpose) was ignored here. FIX: both functions     |
//|   now use InpLiqLookback, matching MSE_DetectEqualHighs/Lows and their    |
//|   own documented liquidity-engine scope.                                  |
//|   SCOPE NOTE: per Chad's explicit sign-off, this rewrite is SCOPED to      |
//|   the 4 findings above only. Two further audit findings (displacement      |
//|   scoring formula fidelity; default 0.5-0.9 retracement band vs a           |
//|   structural higher-low/lower-high test) were EXPLICITLY DEFERRED as        |
//|   judgment calls requiring Chad's separate sign-off, and are NOT             |
//|   changed in this build. Everything else in the EA (SL/sizing engine,        |
//|   R-multiple exit engine, ML export pipeline v1/v2/v4, dashboard, kill-       |
//|   zones, OTE, ATR-auto, exit labels) is UNCHANGED -- already validated         |
//|   through its own prior fix cycles and not implicated by the fidelity          |
//|   audit. No ML function, exit-engine rule, sizing formula, or CSV/JSON          |
//|   schema was touched by this build.                                              |
//|                                                                  |
//|   v4.0.6 GATE-DIAGNOSTIC CALL-PATH FIX (EA<->Pine PARITY) —       |
//|   2026-09-01. Reported by Chad Woodyard: with InpICCGateDiagnostics|
//|   =true, ZERO [ICC GATE] lines were ever printed -- no output at   |
//|   all, not even occasional. Root cause: ICC_LogGateDiagnostics()   |
//|   was called AFTER the M15/H1 data guard (if(m15c1<=0||wkH1<=0||   |
//|   wkL1<=0) return;), so on any bar where WorkTF/TrigTF history      |
//|   wasn't ready (Strategy Tester modeling mode, fresh attach, symbol|
//|   switch) the diagnostic was never reached; separately, the       |
//|   function only ever printed when htf==1/-1, so a FLAT HTF bias    |
//|   (D1/H4 without 2 confirmed pivots yet) ALSO produced total       |
//|   silence. Notably, the Pine twin's own v4.0.5 changelog claims    |
//|   this exact fix "mirrors EA v4.0.5 1:1" -- but the EA never        |
//|   actually received it; this build closes that parity gap. Fix:    |
//|   the diagnostic call now runs BEFORE the data guard, and three     |
//|   new log paths guarantee the engine can never go dark with zero    |
//|   explanation: (1) "[ICC GATE] SKIP" when UseICCPullback=OFF, (2)   |
//|   "[ICC GATE] FLAT" when HTFbias()==0, (3) "[ICC GATE] DATA-GUARD   |
//|   tripped" naming exactly which series (TrigTF close / WorkTF H1/   |
//|   L1) was unavailable. Purely additive/diagnostic -- no ICC state,  |
//|   gating, sizing, or trading decision changed.                      |
//|                                                                  |
//|   v4.0.5 ML HOSTILE-AUDIT REMEDIATION — 2026-09-01. Second-pass   |
//|   hostile line-by-line review of the ML functions requested by   |
//|   Chad Woodyard (audited against v4.0.4 AUDITFIX). Fixes applied |
//|   (ALL additive/surgical; no ICC/entry-signal logic changed      |
//|   unless explicitly noted below):                                |
//|   (F1) DEAD v4 ML PIPELINE (CRITICAL): ML_v4_RegisterEntry() was |
//|   fully implemented but never called from anywhere -- the v4.0  |
//|   canonical dataset (ICC_ML_dataset_v4.csv) silently received    |
//|   ZERO completed-trade rows regardless of how many trades ran.  |
//|   Fix: OnTradeTransaction's DEAL_ENTRY_IN branch now also calls  |
//|   ML_v4_RegisterEntry(), mirroring the existing v2 call.         |
//|   (F2) ML_Surrogate() SCORE-COLLAPSE (CRITICAL): the surrogate   |
//|   re-scored confluence conditions the ICC entry gates (sweep,    |
//|   FVG containment, displacement>=InpDispMinScore) already        |
//|   GUARANTEE true for any signal reaching it, so under default    |
//|   inputs the realistic floor sat near ~0.66 and commonly reached |
//|   0.80-0.99 -- collapsing InpMLMinScore/risk-multiplier tiers    |
//|   into a near-constant PASS/high-multiplier regardless of setup  |
//|   quality. Fix: rebalanced so terms already guaranteed by the    |
//|   entry gates (HTF match, sweep, FVG presence) carry reduced     |
//|   fixed weight, and terms with genuine per-signal variance       |
//|   (order-block presence, displacement HEADROOM above             |
//|   InpDispMinScore, regime, session, internal-trend agreement)    |
//|   carry increased weight -- restores a realistic ~0.30-0.99      |
//|   spread. NOTE: changes the surrogate's OUTPUT DISTRIBUTION      |
//|   only; InpMLMinScore/InpMLHighMult/InpMLBaseMult/InpMLLowMult   |
//|   thresholds may need re-tuning against the new distribution --  |
//|   flagged for Chad's review of live behaviour.                   |
//|   (F3) risk_distance_atr ATR-SOURCE MISMATCH: the ML feature     |
//|   normalized the SL-engine's risk distance (built from           |
//|   atrHandle, chart TF, ATR_Period) by g_mseATRval (a SEPARATE    |
//|   indicator on the SMC structure TF g_mseTF, InpDispATRPeriod)   |
//|   -- silently wrong whenever InpMSE_TF != chart TF or ATR_Period |
//|   != InpDispATRPeriod. Fix: ML_CaptureSignalFeatures now         |
//|   normalizes with GetRawATR() (the same raw ATR reader           |
//|   CalculateSLDistance/the SL engine itself uses).                |
//|   (F4) g_pendingCloseTag GLOBAL RACE (MaxOpenTrades>1): a single |
//|   shared global staged the close-reason tag; closing two         |
//|   positions in one ManagePositions() pass (possible once         |
//|   MaxOpenTrades>1) left only the LAST tag standing, so an         |
//|   earlier deal's queued OnTradeTransaction could read the WRONG  |
//|   reason (mislabels the chart exit tag, dashboard, and the       |
//|   exit_reason ML column). Fix: replaced the single global with   |
//|   a ticket-keyed pending-tag registry (RX_StageCloseTag /        |
//|   RX_ConsumeCloseTag) so each closing deal reads back only ITS   |
//|   OWN staged reason.                                             |
//|   (F5) SHARED NON-SYMBOL-QUALIFIED CSV FILENAMES: all three ML   |
//|   datasets used fixed filenames with no per-symbol/per-instance  |
//|   discriminator -- unsafe for the multi-symbol data-collection   |
//|   workflow already in use (multiple chart instances writing the  |
//|   same FILE_COMMON file, no locking). Fix: an effective, per-     |
//|   symbol filename (base_SYMBOL.csv) is resolved ONCE at OnInit   |
//|   and used by every reader/writer, so each symbol/instance gets  |
//|   its own file. Existing merged multi-symbol CSVs from prior     |
//|   runs are unaffected; new runs write one file per symbol.       |
//|   (F6) InpICCGateDiagnostics DISPLACEMENT-SCORE RE-CLOBBER:      |
//|   turning this normally-OFF diagnostics flag on called the       |
//|   SIDE-EFFECTING MSE_ScoreDisplacement() every bar (even mid-    |
//|   Correction, long after the real Indication break), silently    |
//|   overwriting g_lastDispScore -- and therefore the dashboard AND |
//|   the "disp" ML feature -- with an unrelated current-bar score.  |
//|   Fix: ICC_LogGateDiagnostics now calls the PURE                 |
//|   MSE_ScoreDisplacementCalc() for its own printed values; only   |
//|   the genuine Indication-gate checks still call the mutating     |
//|   wrapper.                                                       |
//|   (F7) DEAD/HARDCODED v4 TELEMETRY COLUMNS: impulse_age_bars,    |
//|   correction_age_bars and impulse_leg_atr were declared/reset    |
//|   but never actually computed (permanent 0), and icc_phase was a |
//|   hardcoded PH_CORRECTION literal rather than a genuine captured |
//|   state. Fix: g_mlIndStartBar/g_mlCorrStartBar are now stamped   |
//|   at the real Indication/Correction phase transitions, the       |
//|   impulse leg and bar-ages are computed the instant a            |
//|   Continuation fires (before ICC_Reset()), and a new             |
//|   g_mlSigPhaseAtFire captures the genuine phase at that instant  |
//|   for icc_phase. Telemetry-only; no trading/gating behaviour     |
//|   changed. (InpMLForecastATR remains exported-but-unused in the  |
//|   forecastOK gate -- adding it to LIVE entry gating would be a   |
//|   trading-behaviour change and is flagged for Chad's separate    |
//|   sign-off, not applied here.)                                   |
//|   (F9) MISSING FileWrite/FileWriteString ERROR HANDLING: all     |
//|   three CSV writers discarded the return value of every write    |
//|   call, so a disk-full/permission/agent-interrupt condition      |
//|   could silently drop a row with zero indication anywhere. Fix:  |
//|   each writer now checks the write result and Prints a warning   |
//|   (with GetLastError()) on failure, matching the FileOpen()-     |
//|   failure diagnostic standard already used elsewhere.            |
//|   (F10) CODE HYGIENE: removed the unused ML_v4_CsvLine() helper  |
//|   and corrected a stray "v2 one-row-per-trade finalize" comment  |
//|   that actually sat on the ML_v4_OnExitDeal() call site.         |
//|   (F8, ML_EXTERNAL live-model bridge) is a DESIGN gap, not a     |
//|   bug -- InpMLExternalP2..P10 remain static per-session inputs,  |
//|   not a live per-bar feed from an external model. Flagged in the |
//|   audit write-up for Chad's sign-off on approach; intentionally  |
//|   NOT changed here so as not to silently alter ML_EXTERNAL       |
//|   behaviour.                                                     |
//|   No ICC/entry-signal/sizing/exit logic was changed by this      |
//|   build except where explicitly noted above (F2's scoring-       |
//|   distribution change and F5's filename change are visible       |
//|   behaviour changes; everything else is telemetry/data-          |
//|   integrity only).                                               |
//|                                                                  |
//|   v4.0.4 AUDIT HOTFIX — 2026-09-01. Hostile line-by-line code     |
//|   review requested by Chad Woodyard. Fixes applied (ALL additive/ |
//|   surgical, no ICC/entry-signal logic changed):                  |
//|   (1) VERSION-STRING UNIFICATION: the build previously showed 7   |
//|   different version labels (file header, #property version/desc, |
//|   TradeComment, broker-diagnostics Print, DispatchAlert Print,    |
//|   email subject, dashboard header) ranging from v3.5.0 to v4.0.1. |
//|   All now read v4.0.4 consistently.                               |
//|   (2) KILL-ZONE / CLOSE-ON-OPPOSITE BUG: TryEntries() returned    |
//|   BEFORE evaluating CloseOnOpposite whenever InpUseKillzones=ON   |
//|   and the broker hour sat outside a kill zone -> an opposite-ICC  |
//|   structure-flip could never close a runner outside kill-zone     |
//|   hours, even though kill-zones are documented as an ENTRY-only   |
//|   filter. Fix: the gate now wraps ONLY the two new-entry blocks.  |
//|   (3) R-ENGINE TP==0 GATING BUG (CRITICAL): ManagePositions only  |
//|   called RX_ManageOne() when posInfo.TakeProfit()==0.0. If        |
//|   InpMLMode used runner-selection (P3<InpMLRunnerMinP3 -> a real  |
//|   TP got attached), the position was PERMANENTLY EXCLUDED from    |
//|   the entire v3.6.0 R-multiple exit engine (no BE/lock/structure  |
//|   trail/trend-health exit) for its whole life. Fix: RX_ManageOne  |
//|   now runs for every InpUseRexit position regardless of TP.       |
//|   (4) g_lastDispScore GLOBAL CORRUPTION (CRITICAL for ML):        |
//|   MSE_ScoreDisplacement() wrote its result into the shared global |
//|   g_lastDispScore on EVERY call. MSE_ScanOBs() (order-block scan, |
//|   default ON) called it up to ~2x maxBars times per bar purely   |
//|   for historical OB detection, so the LAST such call (an old bar, |
//|   wrong direction) clobbered the "current" displacement score on  |
//|   most bars -> corrupted the dashboard readout AND the "disp"     |
//|   feature exported into ALL THREE ML CSV datasets (v1/v2/v4) plus |
//|   ML_Surrogate(). Fix: split into a pure MSE_ScoreDisplacementCalc |
//|   (no side effect, used by the OB scanner) and the original       |
//|   MSE_ScoreDisplacement wrapper (side effect intact, used only by |
//|   the genuine live ICC signal checks / diagnostics).              |
//|   (5) EXIT-REASON MISLABELING: ExitReasonText() mapped EVERY      |
//|   EA-initiated close (trend-health reversal, partial take,        |
//|   opposite-signal close) to "OPP-CLOSE", regardless of the real   |
//|   cause. Fix: a g_pendingCloseTag set at each close call site is   |
//|   now consulted first.                                            |
//|   (6) PARTIAL-CLOSE FALSE "TRADE CLOSED" LABEL: a partial fill    |
//|   (InpUsePartial) drew a full closed-trade chart label/arrow and   |
//|   incremented g_closedTrades even though the remainder stayed     |
//|   open. Fix: label/counter now gated on the position truly being   |
//|   flat (mirrors the existing ML v2/v4 partial-close guard).        |
//|   (7) UseBreakEven=false COULD NOT DISABLE ITS OWN CUSHION IN THE  |
//|   R-ENGINE: RX_ManageOne always added BreakEvenProfit points to    |
//|   the protect-stage floor even with UseBreakEven OFF. Fix: that    |
//|   cushion is now zero unless UseBreakEven is ON.                   |
//|   (8) FRAGILE ATR BACK-SOLVE: RX_ManageOne derived the raw ATR by  |
//|   dividing GetATRStopDistance() back by ATR_Multiplier, silently   |
//|   collapsing to 0 (disabling the ATR emergency floor) if a user    |
//|   set ATR_Multiplier near 0. Fix: a dedicated GetRawATR() reads    |
//|   the ATR buffer directly, once, shared by both callers.           |
//|   (9) CASCADE PIVOT NEIGHBOR-BAR GUARD: IsPivotHighTF/LowTF (D1/   |
//|   H4/H1/M15 bias) validated only the CENTER bar's price, never the |
//|   neighbor bars sampled — a not-yet-synchronised HTF history bar   |
//|   (iHigh/iLow==0) could never fail the "greater/lower than mid"    |
//|   test, letting a false pivot (false HTF bias) through right after |
//|   attach/in the tester. Fix: neighbor bars are now validated >0    |
//|   too (mirrors the RE10008-class guards already used elsewhere).  |
//|   (10) ML v4 FileOpen() MISSING FILE_TXT: the v4.0 canonical CSV   |
//|   (FileWriteString-based) opened its file with neither FILE_CSV,  |
//|   FILE_BIN nor FILE_TXT set, unlike every other dataset in this    |
//|   EA. FileWriteString's documented behaviour branches explicitly  |
//|   on which of those three flags is set. Fix: FILE_TXT added.       |
//|   (11) ML SIGNAL-TIME RISK-DISTANCE FEATURE vs ACTUAL ORDER SL:    |
//|   g_mlRiskDistance was computed from the raw ICC anchor           |
//|   (iccSigSL), while the REAL broker stop (used for every 1R/2R/   |
//|   ..10R label in the v2/v4 datasets) is the larger of that anchor,|
//|   the ATR stop, and the broker-min cushion (CalculateSLDistance). |
//|   That mismatch between a TRAINING FEATURE and its own LABEL basis |
//|   can bias a 2R classifier. Fix: the signal-time feature is now    |
//|   computed with the SAME CalculateSLDistance() formula the order   |
//|   will actually use, so risk_distance matches initial_risk. NOTE:  |
//|   this is a FEATURE-ACCURACY fix only — no order/sizing/trading    |
//|   behaviour changed. (The underlying design question of whether   |
//|   SL_Buffer_Points should still stack on top of the ICC signal     |
//|   buffer RetestSLbufPips for the ACTUAL executed stop is a         |
//|   separate, larger decision flagged for Chad's sign-off — see the  |
//|   accompanying audit write-up.)                                   |
//|   RX_DashInfo also now calls RX_Ensure() instead of RX_Find() so a |
//|   brand-new position no longer shows a spurious 0.00R for one bar. |
//|   No ICC engine, MSE engine, sizing, S/R, or entry-signal logic    |
//|   was changed by this hotfix.                                     |
//|                                                                  |
//|   v3.9.3 ICC IMPULSE-MATURATION GUARD — 2026-08-29. OPT-IN,       |
//|   DEFAULT OFF. Fixes the "IND then instant reset" signal-scarcity  |
//|   seen on XAUUSD M15: the Indication impulse leg is measured at the |
//|   instant of the protected-swing break, so g_indExtreme sits ~at    |
//|   the breakout price and the deep-invalidation threshold (ext -     |
//|   leg*CorrRetraceMax) lands basically ON the breakout. Any normal   |
//|   next-bar pullback then trips inval and ICC_Reset()s before the    |
//|   setup can mature -> Correction/Continuation never form -> zero     |
//|   signals. FIX: a new helper ICC_ImpulseMature() holds the impulse  |
//|   OPEN (no disc/inval evaluation, no premature COR) until it has     |
//|   either developed for InpICCImpulseBars bars OR its leg reaches     |
//|   InpICCMinLegATR x ATR. A strong impulse (leg>=ATR frac) matures    |
//|   instantly, so only tiny-leg breaks wait. ICC_ExpiryBars still      |
//|   bounds the wait. Master InpUseImpulseMaturation=OFF reproduces the |
//|   EXACT v3.9.2 ICC behaviour. No change to bias, sweep, displacement |
//|   FVG/OB gates, sizing, exits, or ML. Mirrors the Pine v3.9.3 twin. |
//|                                                                  |
//|   v3.9.2 INVALID-STOPS (STALE-QUOTE) FIX — 2026-08-29. CRITICAL.  |
//|   Same root cause as v3.9.1 (symInfo is Refresh()ed but never     |
//|   RefreshRates()ed, so symInfo.Bid()/Ask() were 0), but here it   |
//|   corrupted the EXIT ENGINE, not just ML logging. ManagePositions |
//|   runs at the TOP of OnTick (before the new-bar Refresh) and reads |
//|   the live price via symInfo.Bid()/Ask(). With a 0 quote, a SHORT  |
//|   computed curR=(open-0)/risk ~= +58R, the R-runner engaged, and   |
//|   the ATR emergency floor pushed the stop to px+atr*mult = 0+~51   |
//|   -> a stop far BELOW a short entry -> broker "Invalid stops",     |
//|   retried every tick. (Entries were unaffected because the entry   |
//|   SL is anchor-based and the stale bid cancels out.) FIX: prime    |
//|   live quotes with symInfo.RefreshRates() at the TOP of OnTick     |
//|   (before ManagePositions), and add px<=0 / bid<=0 / ask<=0 safety |
//|   guards in RX_ManageOne, the legacy trailing, RX_DashInfo, and    |
//|   FloatingPL so a bad quote can NEVER push an absurd stop. No ICC/ |
//|   entry/sizing/structure logic changed; management math untouched. |
//|                                                                  |
//|   v3.9.1 DISTANCE-FEATURE CAPTURE FIX — 2026-08-28. ADDITIVE.     |
//|   The shared CSymbolInfo object is refreshed with Refresh()       |
//|   (contract specs) but never RefreshRates() (quotes), so          |
//|   symInfo.Ask()/Bid() returned 0 inside ML_CaptureSignalFeatures. |
//|   That turned every signal-time DISTANCE feature into a raw price  |
//|   magnitude (risk_distance == the SL price; fvg_mid_dist == the    |
//|   gap-mid price; risk_distance_atr in the hundreds). Fix: source   |
//|   the entry price locally via SymbolInfoDouble (BID/ASK) with an   |
//|   iClose fallback, WITHOUT mutating the shared symInfo used later  |
//|   by ExecuteBuy/ExecuteSell — so order execution and every other   |
//|   engine value are byte-for-byte unchanged. Only the ML feature    |
//|   snapshot (v1 CSV + v2 frozen features) is corrected.            |
//|                                                                  |
//|   v3.9.0 icc_ml_v2 TRUE-2R TRADE LABELS — 2026-08-28. ADDITIVE.  |
//|   Adds a one-row-per-COMPLETED-TRADE dataset (ICC_ML_dataset_v2  |
//|   .csv) with a stable trade_id, actual entry, frozen initial     |
//|   stop/risk, live MFE/MAE tracking, and explicit reached_1r..     |
//|   reached_10r labels plus exit_r, so a genuine 2R classifier can  |
//|   be trained. Signal-time features are frozen at entry (no future |
//|   leakage). Runs alongside the v1 SIGNAL/EXIT stream; no ICC,     |
//|   entry, exit, sizing, or R-engine rule is changed.              |
//|                                                                  |
//|   v3.8.1 CSV STARTUP FIX — 2026-08-28. ADDITIVE. Creates the ML |
//|   dataset file and writes its header at OnInit so OBSERVE mode is |
//|   verifiable even before the first ICC signal. Adds a startup     |
//|   diagnostic and notes the Strategy Tester FILE_COMMON sandbox     |
//|   redirect. No ICC/entry/exit/sizing logic changed.               |
//|                                                                  |
//|   v3.8.0 ML FEATURE EXPANSION — 2026-08-27. ADDITIVE telemetry. |
//|   Adds signal-time nearest FVG midpoint distance, OTE depth, FVG |
//|   size/ATR, initial risk distance, spread, time-of-day, and symbol |
//|   fields to the CSV dataset. No ICC or trade-management changes.   |
//|                                                                  |
//|   v3.7.0 ML ENABLEMENT LAYER — 2026-08-27. ADDITIVE, default OFF. |
//|   Adds feature extraction, observe/filter modes, manual/external or |
//|   embedded-surrogate probabilities, forecast agreement, regime and |
//|   session features, confidence sizing, runner selection, dashboard |
//|   telemetry, and CSV signal/exit export for model training. The ICC |
//|   engine remains the signal authority; ML only scores/gates/sizes.  |
//|                                                                  |
//|   v3.6.1 DUAL FLOATING-P/L READOUT — 2026-08-27. Adds a dashboard  |
//|   line showing the open position's unrealised result in BOTH       |
//|   account-currency $ AND volume-weighted pips. Read-only; no        |
//|   engine/order/entry change. Mirrors the Pine twin at v3.6.1.       |
//|                                                                  |
//|   v3.6.0 EXIT ENGINE OVERHAUL (R-MULTIPLE PHASED RUNNER) —        |
//|   2026-08-26. TRADING EA. Replaces the point-based BE/Trailing/   |
//|   runner arithmetic (which ran THREE competing trailing systems   |
//|   and let a conventional price-trail eject valid trends) with a   |
//|   staged R-MULTIPLE model measured from the ACTUAL initial risk   |
//|   (1R = |entry - initial SL|), so protection self-scales to each  |
//|   setup and to volatility (no arbitrary points). Stages: (Phase 2)|
//|   PROTECT at +ProtectR -> break-even; (Phase 2b) LOCK +LockProfitR|
//|   at +LockR; (Phase 3) ACTIVATE a STRUCTURE RUNNER at +ActivateR  |
//|   that follows CONFIRMED protected structure (external primary,   |
//|   internal aggressive) PLUS a progressive R give-back profit floor|
//|   and a wide ATR emergency floor — the MOST-PROTECTIVE valid level|
//|   wins, the stop only ratchets TIGHTER, and ordinary retracements |
//|   no longer eject the trade. A TREND-HEALTH governor HOLDS when   |
//|   HEALTHY, tightens to internal structure on CAUTION, and EXITS on|
//|   a CONFIRMED EXTERNAL reversal (external BOS against the trade).  |
//|   An opposite ICC signal ALONE no longer closes a runner (it also |
//|   needs a confirmed external reversal when InpCloseOnConfirmedRev).|
//|   Optional PARTIAL (e.g. 25% at +ActivateR) leaves the rest to run|
//|   No fixed TP; no time-based exit. Master InpUseRexit=OFF restores |
//|   the EXACT v3.5.0 BE/Trailing/point-runner management. New input |
//|   group "Exit Engine v3.6"; NOTHING in the MSE engine, ICC state  |
//|   machine, sizing, kill-zones, OTE, FVG, OB, S/R, or entries      |
//|   changed. Mirrors the Pine twin at v3.6.0.                       |
//|                                                                  |
//|   v3.5.0 SCI-PURITY CLEANUP + LET-WINNERS-RUN — 2026-08-25.       |
//|   TRADING EA (executes live orders; not an indicator).           |
//|   (A) REMOVED every entry path that is NOT the Trades-by-Sci ICC  |
//|   model: (1) the v1 CASCADE BREAKOUT path (UseCascadeEntries +    |
//|   buyCont/sellCont/cascBuy/cascSell/prevBuyCont/prevSellCont) —   |
//|   chasing a breakout is the opposite of an ICC pullback; (2) the  |
//|   classic S/R RETEST-CONFIRMATION entry (UseRetestEntries,        |
//|   SR_CheckConfirm, retestBuySig/retestSellSig, RetestConfBufPips/ |
//|   RetestArmBars/RetestSepBar) — a retail horizontal-level retest, |
//|   not an SMC liquidity entry; (3) the v1 STRICTALIGN 4-TF lockstep |
//|   gate (explicitly "leave OFF for Sci style"); (4) the generic    |
//|   UTC SESSION FILTER (UseSessionFilter/SessionStartHour/EndHour)  |
//|   — the Sci KILL-ZONE engine is the correct session model. Only   |
//|   the genuine Sci stack remains: HTF-bias cascade, dual market    |
//|   structure (protected swings/BOS), liquidity sweep+reclaim,      |
//|   institutional displacement, FVG, order blocks, kill zones, OTE, |
//|   discount/premium, and the structural take-profit. The body-close|
//|   S/R map is retained ONLY as the structural-TP level source      |
//|   (Sci: "target the previous high / next liquidity pool").        |
//|   (B) ADDED "Let Winners Run": a Sci runner that removes the fixed |
//|   TP cap and rides a profitable trade with a profit-LOCK ratchet  |
//|   (+ optional protected-swing structure trail). Once armed, the   |
//|   stop sits in profit and only ratchets tighter, so the trade     |
//|   REMAINS OPEN AS LONG AS IT IS PROFITABLE and exits only when     |
//|   price retraces into the locked floor or structure flips         |
//|   (CloseOnOpposite). NOTHING in the MSE engine, ICC state machine, |
//|   sizing, kill-zones, OTE, FVG, OB, or structural-TP math changed. |
//|                                                                  |
//|   v3.4.0 SCI FIDELITY: KILL-ZONE SESSIONS + OTE ENTRY WINDOW —   |
//|   2026-08-12. Two ADDITIVE, opt-in modules that tighten the EA    |
//|   onto the Trades-by-Sci method. (1) KILL-ZONE ENGINE: new input  |
//|   group "Sci Kill-Zone Sessions" (InpUseKillzones + three broker- |
//|   time windows: London / NY-AM / NY-PM) gates EVERY entry path    |
//|   (ICC / retest / cascade) so orders fire only inside a Sci kill   |
//|   zone. Helpers IsInKillzone()/InKillWindow(); gated once in       |
//|   TryEntries (uniform; engine state untouched). (2) OTE ENTRY      |
//|   WINDOW: new group "Sci OTE Entry Window" (InpUseOTE, InpOTEmin   |
//|   0.62, InpOTEmax 0.79). When ON, the ICC Correction must retrace  |
//|   into the 0.62-0.79 Optimal-Trade-Entry band before a            |
//|   Continuation; effMin/effMax replace the raw CorrRetrace bounds   |
//|   INSIDE ICC_Update only. Both toggles default OFF -> EXACT        |
//|   v3.3.10 behaviour preserved. Dashboard + broker diagnostics gain |
//|   KZ/OTE readouts. NO change to the MSE engine, ICC state machine, |
//|   MM, trailing/BE, S/R, structural-TP, ATR-auto, FVG-relax, or     |
//|   exit-label behaviour.                                            |
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
#property version     "4.37"
#property description "ICC TradesBySci EA v4.3.7 H4-AUTHORITY + SHADOW-EVALUATOR CORRECTION (TRADING EA)"
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
enum ENUM_ML_MODE { ML_OFF=0, ML_OBSERVE=1, ML_FILTER=2, ML_FILTER_SIZE=3 };
enum ENUM_ML_SOURCE { ML_SURROGATE=0, ML_EXTERNAL=1 }; // v3.6.0 exit governor
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
input string TradeComment       = "ICC-Sci-EA-v4.3.7";
input bool   DebugLog           = false;        // Print SL/lot skip reasons
input bool   VerboseLog         = true;         // Print bias/phase/signals every bar
input group "=== ML Enablement v3.7 ==="
input ENUM_ML_MODE   InpMLMode=ML_OFF;
input ENUM_ML_SOURCE InpMLSource=ML_SURROGATE;
input double InpMLMinScore=0.70;
input double InpMLExternalP2=0.75;
input double InpMLExternalP3=0.60;
input double InpMLExternalP5=0.35;
input double InpMLExternalP10=0.10;
input int    InpMLForecastDir=0;
input double InpMLForecastATR=0.0;
input bool   InpMLRequireForecast=false;
input double InpMLRunnerMinP3=0.55;
input double InpMLLowMult=0.50;
input double InpMLBaseMult=1.00;
input double InpMLHighMult=2.00;
input bool   InpMLExportCSV=true;
input string InpMLCSVFile="ICC_ML_dataset_v1.csv";
input group "=== ML v2 Trade Labeling (icc_ml_v2) ==="
input bool   InpMLv2Export  = true;                 // Write ONE finalized row per completed trade (true 2R label)
input string InpMLv2CSVFile = "ICC_ML_dataset_v2.csv"; // Separate one-row-per-trade dataset (train the 2R model on this)
input group "=== ML v4.0 Canonical Dataset ==="
input bool   InpMLv4Export = true;
input string InpMLv4CSVFile = "ICC_ML_dataset_v4.csv";
input bool   InpMLv4IncludeSurrogate = false; // diagnostics only; never a target
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
void RX_StageCloseTag(ulong tk,string tag)
  {
   for(int i=0;i<ArraySize(g_pendingTagTicket);i++)
      if(g_pendingTagTicket[i]==tk){ g_pendingTagText[i]=tag; return; }
   int n=ArraySize(g_pendingTagTicket);
   ArrayResize(g_pendingTagTicket,n+1); ArrayResize(g_pendingTagText,n+1);
   g_pendingTagTicket[n]=tk; g_pendingTagText[n]=tag;
  }
//--- Consume (read + remove) the staged tag for a ticket; "" if none was staged
//    (e.g. a manual close from the terminal, not initiated by this EA).
string RX_ConsumeCloseTag(ulong tk)
  {
   for(int i=0;i<ArraySize(g_pendingTagTicket);i++)
     {
      if(g_pendingTagTicket[i]!=tk) continue;
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
double g_mlP2=0.0,g_mlP3=0.0,g_mlP5=0.0,g_mlP10=0.0,g_mlRiskMult=1.0;
bool g_mlPass=true,g_mlRunner=true;
int g_mlRegime=0,g_mlSession=0;
string g_mlRegimeTxt="RANGE";
// v3.8.0 feature snapshot, captured at the raw ICC signal
double g_mlOTEDepth=0.0,g_mlFVGMidDist=0.0,g_mlFVGMidDistATR=0.0,g_mlFVGSizeATR=0.0;
double g_mlRiskDistance=0.0,g_mlRiskDistanceATR=0.0,g_mlRiskDistancePips=0.0;
double g_mlSpreadPrice=0.0,g_mlSpreadPoints=0.0,g_mlTimeSin=0.0,g_mlTimeCos=0.0;
int g_mlHour=0,g_mlMinuteOfDay=0;
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
  };
MLTradeV2 g_mlv2[];

// AUDIT FIX (v4.0.5 / F5): all three ML datasets used a fixed, non-symbol-qualified
// filename with no locking, unsafe for a multi-symbol data-collection workflow --
// multiple chart instances (one per symbol) writing the SAME shared FILE_COMMON
// file with no coordination can interleave/duplicate header rows or clobber each
// other's appends. Each input filename is now resolved ONCE at OnInit into an
// effective, per-symbol filename (root_SYMBOL.ext) stored here and used by every
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
   return root+"_"+_Symbol+ext;
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
   double fDistExtHighATR,fDistExtLowATR,fDistIntHighATR,fDistIntLowATR;
   int fSymbolDigits; double fPoint,fTickSize,fTickValue,fContractSize;
   string fBroker,fAccountCurrency,fExecutionMode,fPeriod;
   string fDatasetVersion,fSchemaVersion,fModelVersion;
   double fP2,fP3,fP5,fP10,fRiskMult; int fRunner;
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
   Print("       ICC TradesBySci EA v4.3.7 - BROKER DIAGNOSTICS         ");
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
void MSE_UpdateTrendScale(int strength,double &protHigh,double &protLow,int &trend,ENUM_TIMEFRAMES tf)
  {
   MSE_FindProtected(strength,protHigh,protLow,tf);
   double c1=iClose(_Symbol,tf,1);
   double bH=InpBOSUseClose? c1 : iHigh(_Symbol,tf,1);
   double bL=InpBOSUseClose? c1 : iLow (_Symbol,tf,1);
   if(protHigh>0.0 && bH>protHigh)      trend=1;   // bullish BOS on protected high
   else if(protLow>0.0 && bL<protLow)   trend=-1;  // bearish BOS on protected low
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
   MSE_UpdateTrendScale(InpExtSwingStrength,g_extProtHigh,g_extProtLow,g_extTrend,g_extTF);
   MSE_UpdateTrendScale(InpIntSwingStrength,g_intProtHigh,g_intProtLow,g_intTrend,g_intTF);
   // v4.3.6 (Finding C / CORE-01): a CHANGE in the external trend is the only evidence
   // of a genuine fresh protected-swing BOS, so stamp it and restart the idle counter.
   if(g_extTrend!=extBefore)
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
        { g_sweepConfLong=InpSweepValidBars; g_lastSweepLvl=lvl; g_liqStatus="SSL swept+reclaim"; armedNow=true; }
      else if(MSE_DetectSweep(-1,wick,lvl) && MSE_ReclaimConfirmed(-1,lvl))
        { g_sweepConfShort=InpSweepValidBars; g_lastSweepLvl=lvl; g_liqStatus="BSL swept+reclaim"; armedNow=true; }
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
   double atrFac  =(g_mseATRval>0.0)? range/g_mseATRval : 0.0;
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
   int maxBars=MathMin(InpFVGScanBars,bars-(InpOBScanBack+3));
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
      expired=(wSh>=0 && wSh>ICC_ExpiryBars);
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
               // AUDIT FIX (v4.0.5/F7): capture impulse_leg_atr, impulse_age_bars,
               // correction_age_bars, and the genuine phase-at-fire BEFORE ICC_Reset()
               // wipes g_iccPhase/g_indLevel/g_indExtreme back to PH_NONE/0 below.
               g_mlImpulseLegATR=(g_mseATRval>0.0)?leg/g_mseATRval:0.0;
               g_mlImpulseAgeBars=g_mlCorrStartBar-g_mlIndStartBar;
               g_mlCorrectionAgeBars=g_barCount-g_mlCorrStartBar;
               g_mlSigPhaseAtFire=g_iccPhase;
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
               // AUDIT FIX (v4.0.5/F7): capture impulse_leg_atr, impulse_age_bars,
               // correction_age_bars, and the genuine phase-at-fire BEFORE ICC_Reset()
               // wipes g_iccPhase/g_indLevel/g_indExtreme back to PH_NONE/0 below.
               g_mlImpulseLegATR=(g_mseATRval>0.0)?leg/g_mseATRval:0.0;
               g_mlImpulseAgeBars=g_mlCorrStartBar-g_mlIndStartBar;
               g_mlCorrectionAgeBars=g_barCount-g_mlCorrStartBar;
               g_mlSigPhaseAtFire=g_iccPhase;
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
   Print("ICC-Sci-EA v4.3.7: ",m);
   if(AlertPopup) Alert(m);
   if(AlertPush)  SendNotification(m);
   if(AlertEmail) SendMail("ICC TradesBySci EA v4.3.7 - "+_Symbol,m);
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
   bool fullyClosed = !PositionSelectByTicket((ulong)posId);
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
// AUDIT FIX (v4.0.5 / F2): REBALANCED. The original weights re-scored several
// confluence conditions the ICC entry gates THEMSELVES already guarantee true
// for any signal reaching this function under this EA's default inputs
// (InpRequireSweep, InpRequireFVGpullback, InpRejectWeakBreaks+InpDispMinScore,
// InpExtTrendControlsDir) -- see F2 in the v4.0.5 header for the full
// derivation. That collapsed the realistic output range to roughly 0.66-0.99,
// defeating InpMLMinScore and the risk-multiplier tiers as real
// discriminators between setup quality. This rebalance:
//  - shrinks the weight of terms already GUARANTEED true by the entry gates
//    (HTF match, sweep presence, FVG presence) so they stop dominating;
//  - re-expresses the displacement term as HEADROOM above InpDispMinScore
//    (not the raw 0..100 score), so a signal that JUST cleared the gate scores
//    near 0 on this term, and only a genuinely strong break scores near its
//    cap;
//  - increases the weight of terms with genuine per-signal variance (internal-
//    trend agreement, order-block presence, regime, session).
// Output is still clamped to 0.99 and this remains a PLACEHOLDER surrogate
// (used only when InpMLSource=ML_SURROGATE) -- this fix restores real spread
// to its distribution, it does not change what it is. Re-tune InpMLMinScore /
// InpMLHighMult / InpMLBaseMult / InpMLLowMult against the NEW distribution if
// you rely on ML_FILTER or ML_FILTER_SIZE in live trading.
double ML_Surrogate(int dir)
  {
   double s=0.05;                                             // base
   if(HTFbias()==dir) s+=0.05;                                 // guaranteed true whenever a signal exists -> low weight
   s+=(g_extTrend==dir?0.08:(g_extTrend==0?0.03:0.0));          // external agreement (opposite excluded by the entry gate)
   s+=(g_intTrend==dir?0.16:(g_intTrend==0?0.06:0.0));          // internal agreement: REAL per-signal variance -> weighted up
   if((dir>0&&g_sweepConfLong>0)||(dir<0&&g_sweepConfShort>0)) s+=0.05; // guaranteed true when InpRequireSweep=ON
   // Displacement HEADROOM above the gate's own floor, not the raw 0..100 score --
   // a signal that just cleared InpDispMinScore contributes ~0 here; only a
   // genuinely strong break earns meaningful weight. Falls back to the plain
   // normalized score when InpRejectWeakBreaks is OFF (no gate floor to measure from).
   double dispQuality;
   if(InpRejectWeakBreaks && InpDispMinScore<100.0)
      dispQuality=MathMax(0.0,MathMin(1.0,(g_lastDispScore-InpDispMinScore)/(100.0-InpDispMinScore)));
   else
      dispQuality=MathMax(0.0,MathMin(1.0,g_lastDispScore/100.0));
   s+=dispQuality*0.22;
   if(ML_CountActiveFVG()>0) s+=0.03;                          // guaranteed true when InpRequireFVGpullback=ON
   if(ML_CountActiveOB()>0) s+=0.14;                            // REAL variance: OB is optional confluence, not gated
   s+=(InpUseOTE?0.05:0.02);                                    // static per-run setting; kept small (not a per-signal discriminator)
   s+=(g_mlSession>0?0.05:0.01);                                // fired inside an active kill-zone session
   if(g_mlRegime>=3) s+=0.05; else if(g_mlRegime>=2) s+=0.03;   // trending / trend+expansion regime
   return MathMin(s,0.99);
  }
void ML_Evaluate(int dir)
  {
   ML_UpdateContext();
   ML_CaptureSignalFeatures(dir);
   g_mlP2=(InpMLSource==ML_EXTERNAL)?InpMLExternalP2:ML_Surrogate(dir);
   g_mlP3=(InpMLSource==ML_EXTERNAL)?InpMLExternalP3:MathMax(0.0,g_mlP2-0.15);
   g_mlP5=(InpMLSource==ML_EXTERNAL)?InpMLExternalP5:MathMax(0.0,g_mlP2-0.38);
   g_mlP10=(InpMLSource==ML_EXTERNAL)?InpMLExternalP10:MathMax(0.0,g_mlP2-0.63);
   bool forecastOK=(!InpMLRequireForecast||InpMLForecastDir==0||InpMLForecastDir==dir);
   g_mlPass=(InpMLMode==ML_OFF||InpMLMode==ML_OBSERVE||(g_mlP2>=InpMLMinScore&&forecastOK));
   g_mlRiskMult=(g_mlP2>=0.85?InpMLHighMult:(g_mlP2>=0.70?InpMLBaseMult:InpMLLowMult));
   g_mlRunner=(InpMLMode==ML_OFF||InpMLMode==ML_OBSERVE||g_mlP3>=InpMLRunnerMinP3);
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
      uint whdr=FileWrite(h,"schema","event","time","symbol","period","dir","htf_score","ext_trend","int_trend","sweep_long","sweep_short","disp","fvg_active","ob_active","atr","session","regime","p2","p3","p5","p10","forecast_dir","forecast_atr","fvg_mid_dist","fvg_mid_dist_atr","ote_depth","fvg_size_atr","risk_distance","risk_distance_atr","risk_distance_pips","spread_price","spread_points","hour","minute_of_day","time_sin","time_cos","symbol_id","risk_mult","runner","result_money");
      if(whdr==0) Print("[ML] WARNING: v1 CSV header write may have FAILED err=",GetLastError()," file=",g_mlv1FileEff);
     }
   uint wrow=FileWrite(h,"icc_ml_v1",eventName,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),_Symbol,EnumToString((ENUM_TIMEFRAMES)_Period),dir,HTFscore(),g_extTrend,g_intTrend,g_sweepConfLong,g_sweepConfShort,g_lastDispScore,ML_CountActiveFVG(),ML_CountActiveOB(),g_mseATRval,g_mlSession,g_mlRegime,g_mlP2,g_mlP3,g_mlP5,g_mlP10,InpMLForecastDir,InpMLForecastATR,g_mlFVGMidDist,g_mlFVGMidDistATR,g_mlOTEDepth,g_mlFVGSizeATR,g_mlRiskDistance,g_mlRiskDistanceATR,g_mlRiskDistancePips,g_mlSpreadPrice,g_mlSpreadPoints,g_mlHour,g_mlMinuteOfDay,g_mlTimeSin,g_mlTimeCos,_Symbol,g_mlRiskMult,(int)g_mlRunner,resultMoney);
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
      FileWrite(h,"schema","event","time","symbol","period","dir","htf_score","ext_trend","int_trend","sweep_long","sweep_short","disp","fvg_active","ob_active","atr","session","regime","p2","p3","p5","p10","forecast_dir","forecast_atr","fvg_mid_dist","fvg_mid_dist_atr","ote_depth","fvg_size_atr","risk_distance","risk_distance_atr","risk_distance_pips","spread_price","spread_points","hour","minute_of_day","time_sin","time_cos","symbol_id","risk_mult","runner","result_money");
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
   // g_ml* feature globals were just populated by ML_Evaluate(dir)
   g_mlPendValid=true; g_mlPendDir=dir; g_mlPendSigTime=TimeCurrent();
   g_pHTF=HTFscore(); g_pExt=g_extTrend; g_pInt=g_intTrend;
   g_pSweepL=g_sweepConfLong; g_pSweepS=g_sweepConfShort; g_pDisp=g_lastDispScore;
   g_pFVG=ML_CountActiveFVG(); g_pOB=ML_CountActiveOB(); g_pATR=g_mseATRval;
   g_pSession=g_mlSession; g_pRegime=g_mlRegime;
   g_pFVGdist=g_mlFVGMidDist; g_pFVGdistATR=g_mlFVGMidDistATR; g_pOTE=g_mlOTEDepth; g_pFVGsizeATR=g_mlFVGSizeATR;
   g_pRiskDist=g_mlRiskDistance; g_pRiskDistATR=g_mlRiskDistanceATR; g_pRiskDistPips=g_mlRiskDistancePips;
   g_pSpreadPx=g_mlSpreadPrice; g_pSpreadPts=g_mlSpreadPoints; g_pHour=g_mlHour; g_pMinOfDay=g_mlMinuteOfDay;
   g_pTsin=g_mlTimeSin; g_pTcos=g_mlTimeCos;
   g_pP2=g_mlP2; g_pP3=g_mlP3; g_pP5=g_mlP5; g_pP10=g_mlP10; g_pRiskMult=g_mlRiskMult; g_pRunner=(int)g_mlRunner;
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
   if(PositionSelectByTicket(posId)) sl=PositionGetDouble(POSITION_SL);
   if(sl<=0.0) sl=g_pInitSLguess;
   r.initSL=sl;
   r.initRisk=(sl>0.0)? MathAbs(entryPx-sl) : (g_pRiskDist>0.0? g_pRiskDist : GetATRStopDistance());
   if(r.initRisk<=0.0) r.initRisk=GetATRStopDistance();
   r.dir = g_mlPendValid? g_mlPendDir : ((PositionSelectByTicket(posId) && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1);
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
      if(!PositionSelectByTicket(g_mlv2[i].posId)) continue; // closed -> finalized on the exit deal
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
   if(PositionSelectByTicket(posId)) return; // partial close -> wait for full close
   ML_v2_WriteRow(idx);
   int n=ArraySize(g_mlv2);
   for(int j=idx;j<n-1;j++) g_mlv2[j]=g_mlv2[j+1];
   ArrayResize(g_mlv2,n-1);
  }
//+==================================================================+
//|                 ML v4.0 CANONICAL DATA ENGINE                    |
//+==================================================================+
string ML_v4_ModelVersion(){ return "SURROGATE_PENDING"; }
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
      string header="dataset_version,schema_version,run_id,trade_id,trade_seq,position_id,dir,symbol,period,digits,point,tick_size,tick_value,contract_size,broker,account_currency,execution_mode,signal_time,entry_time,exit_time,entry_price,initial_stop,initial_risk,initial_risk_pips,htf_score,ext_trend,int_trend,sweep_long,sweep_short,displacement,fvg_active,ob_active,atr,session,regime,fvg_mid_dist,fvg_mid_dist_atr,ote_depth,fvg_size_atr,risk_distance,risk_distance_atr,risk_distance_pips,spread_price,spread_points,hour,minute_of_day,time_sin,time_cos,icc_phase,impulse_age_bars,impulse_leg_atr,correction_age_bars,correction_depth,distance_to_external_high_atr,distance_to_external_low_atr,distance_to_internal_high_atr,distance_to_internal_low_atr,mfe_price,mae_price,mfe_r,mae_r,reached_1r,reached_2r,reached_3r,reached_5r,reached_10r,time_to_1r_sec,time_to_2r_sec,time_to_3r_sec,time_to_5r_sec,time_to_10r_sec,mfe_30m_r,mfe_1h_r,mfe_2h_r,mfe_4h_r,mfe_8h_r,mfe_24h_r,exit_price,exit_r,exit_money,exit_reason,exit_external_trend,exit_internal_trend,exit_protected_high,exit_protected_low,exit_structure_break,exit_opposite_signal,exit_fvg_active,exit_ob_active,exit_atr,model_version,initial_risk_money,mfe_money,mae_money\r\n";
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
   if(ML_v4_Find(posId)>=0) return;
   int n=ArraySize(g_mlv4); ArrayResize(g_mlv4,n+1);
   MLTradeV4 r;
   r.used=true; r.posId=posId; r.seq=0; r.dir=g_mlPendValid?g_mlPendDir:((PositionSelectByTicket(posId) && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1);
   r.mfe=0.0; r.mae=0.0; r.r1=false; r.r2=false; r.r3=false; r.r5=false; r.r10=false;
   r.t1rTime=0; r.t2rTime=0; r.t3rTime=0; r.t5rTime=0; r.t10rTime=0;
   r.mfe30m=0.0; r.mfe1h=0.0; r.mfe2h=0.0; r.mfe4h=0.0; r.mfe8h=0.0; r.mfe24h=0.0;
   r.cp30m=false; r.cp1h=false; r.cp2h=false; r.cp4h=false; r.cp8h=false; r.cp24h=false;
   r.exitPx=0.0; r.exitMoney=0.0; r.exitTime=0; r.exitReason="-";
   // AUDIT FIX (v4.2.3 / G2): guard sigTime with g_mlPendValid, mirroring
   // ML_v2_RegisterEntry. Previously v4 read g_mlPendSigTime UNCONDITIONALLY,
   // so a manual / unstaged entry (no ICC signal) recorded a STALE prior-signal
   // timestamp instead of its own entry time. With G1's reorder v4 now sees a
   // valid pending for genuine EA entries; this guard covers the manual case.
   r.entryPx=entryPx; r.entryTime=entryTime; r.sigTime=(g_mlPendValid? g_mlPendSigTime : entryTime);
   r.seq=++g_mlTradeSeq; r.runId=g_mlRunId;
   r.tradeId=g_mlRunId+"_"+StringFormat("%06I64u",r.seq);
   r.initSL=(PositionSelectByTicket(posId)?PositionGetDouble(POSITION_SL):g_pInitSLguess);
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
   // PositionSelectByTicket(posId). On the DEAL_ENTRY_IN transaction the position is
   // not always selectable yet, and on a partial//multi-deal fill POSITION_VOLUME is
   // the AGGREGATE, not this deal's. Either way initRiskMoney silently stayed 0, and
   // because ML_v4_OnExitDeal derives mfe/mae_money from initRiskMoney/initRisk, the
   // ENTIRE money layer for that trade collapsed to 0 with no diagnostic. Fix: prefer
   // the volume passed in from the entry deal itself (DEAL_VOLUME), falling back to
   // the position only if that is unavailable.
   double rvol=(dealVolume>0.0)? dealVolume
                               : (PositionSelectByTicket(posId)? PositionGetDouble(POSITION_VOLUME):0.0);
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
   r.fDatasetVersion="ICC_ML_v4"; r.fSchemaVersion="4.0.2"; r.fModelVersion=ML_v4_ModelVersion(); // v4.2.9: 4.0.1->4.0.2 (added MONEY layer columns)
   r.fP2=InpMLv4IncludeSurrogate?g_pP2:0.0; r.fP3=InpMLv4IncludeSurrogate?g_pP3:0.0;
   r.fP5=InpMLv4IncludeSurrogate?g_pP5:0.0; r.fP10=InpMLv4IncludeSurrogate?g_pP10:0.0;
   r.fRiskMult=g_pRiskMult; r.fRunner=g_pRunner;
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
      if(!PositionSelectByTicket(g_mlv4[i].posId)) continue;
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
   row+=IntegerToString((int)g_mlv4[i].xStructureBreak)+","+IntegerToString((int)g_mlv4[i].xOppositeSignal)+","+IntegerToString(g_mlv4[i].xFVG)+","+IntegerToString(g_mlv4[i].xOB)+","+DoubleToString(g_mlv4[i].xATR,12)+","+ML_v4_CsvField(g_mlv4[i].fModelVersion)+",";
   // v4.2.9 MONEY LAYER (schema 4.0.2): appended AFTER model_version so every
   // pre-existing column index is preserved for already-merged v4 CSVs.
   row+=DoubleToString(g_mlv4[i].initRiskMoney,2)+","+DoubleToString(g_mlv4[i].mfeMoney,2)+","+DoubleToString(g_mlv4[i].maeMoney,2)+"\r\n";

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
   if(PositionSelectByTicket(posId))return;
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
   if(InpMLMode==ML_FILTER_SIZE) risk*=g_mlRiskMult;
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
      RX_StageCloseTag(tk,"OPP-CLOSE"); // AUDIT FIX (v4.0.5/F4, was v4.0.4): this IS a genuine opposite-signal close; now ticket-keyed
      if(trade.PositionClose(tk))
        { TriggerFlash(reason,ColExit,false,0,0,0); DispatchAlert(reason+" | "+_Symbol); }
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
  { for(int i=0;i<ArraySize(g_rxTicket);i++) if(g_rxTicket[i]==tk) return i; return -1; }
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
   if(trade.PositionModify(tk,newSL,tp))
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
      if(!PositionSelectByTicket(g_rxTicket[i]))
        {
         int n=ArraySize(g_rxTicket);
         for(int j=i;j<n-1;j++)
           { g_rxTicket[j]=g_rxTicket[j+1]; g_rxEntry[j]=g_rxEntry[j+1]; g_rxRisk[j]=g_rxRisk[j+1]; g_rxPartial[j]=g_rxPartial[j+1]; }
         ArrayResize(g_rxTicket,n-1); ArrayResize(g_rxEntry,n-1); ArrayResize(g_rxRisk,n-1); ArrayResize(g_rxPartial,n-1);
        }
     }
  }

//--- Register a ticket the first time we see it and capture its 1R.
int RX_Ensure(ulong tk,double entry,double sl)
  {
   int idx=RX_Find(tk); if(idx>=0) return idx;
   double risk=(sl>0.0)? MathAbs(entry-sl) : GetATRStopDistance();
   if(risk<=0.0) risk=GetATRStopDistance();
   int n=ArraySize(g_rxTicket);
   ArrayResize(g_rxTicket,n+1); ArrayResize(g_rxEntry,n+1); ArrayResize(g_rxRisk,n+1); ArrayResize(g_rxPartial,n+1);
   g_rxTicket[n]=tk; g_rxEntry[n]=entry; g_rxRisk[n]=risk; g_rxPartial[n]=false;
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
   double risk=g_rxRisk[idx]; if(risk<=0.0) return false;
   double px  = isLong? symInfo.Bid() : symInfo.Ask();
   if(px<=0.0) return false;   // v3.9.2 guard: never manage on a stale/zero quote
   double curR= isLong? (px-op)/risk : (op-px)/risk;
   ENUM_TREND_HEALTH health = InpUseTrendHealth ? RX_Health(isLong?1:-1) : TH_HEALTHY;

   // (A) confirmed external reversal -> exit the whole position (cuts weak trades too)
   if(InpUseTrendHealth && health==TH_REVERSAL)
     {
      RX_StageCloseTag(tk,"TREND-REV"); // AUDIT FIX (v4.0.5/F4, was v4.0.4): NOT an opposite-ICC-signal close; now ticket-keyed
      if(trade.PositionClose(tk))
        { TriggerFlash("EXIT (ext reversal)",ColExit,false,0,0,0); DispatchAlert("EXIT ext-reversal | "+_Symbol); }
      return true;
     }

   // (B) optional partial at activation (once)
   if(InpUsePartial && !g_rxPartial[idx] && curR>=InpActivateAtR)
     {
      double vol=NormalizeLots(posInfo.Volume()*InpPartialPct/100.0);
      if(vol>0.0 && vol<posInfo.Volume() && (posInfo.Volume()-vol)>=symInfo.LotsMin())
        {
         RX_StageCloseTag(tk,"PARTIAL"); // AUDIT FIX (v4.0.5/F4, was v4.0.4): NOT an opposite-ICC-signal close; now ticket-keyed
         if(trade.PositionClosePartial(tk,vol))
           { g_rxPartial[idx]=true; TriggerFlash("PARTIAL +"+DoubleToString(InpActivateAtR,1)+"R",ColExit,false,0,0,0); }
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
   // v3.5.0 LET WINNERS RUN: open the trade with NO fixed TP so the winner can run;
   // the profit-lock ratchet in ManagePositions rides and protects it.
   if((InpLetWinnersRun || InpUseRexit) && g_mlRunner){ tpPrice=0.0; tpStruct=false; }
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
   // v3.5.0 LET WINNERS RUN: open the trade with NO fixed TP so the winner can run;
   // the profit-lock ratchet in ManagePositions rides and protects it.
   if((InpLetWinnersRun || InpUseRexit) && g_mlRunner){ tpPrice=0.0; tpStruct=false; }
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
   if(CountOpenTrades()>=MaxOpenTrades) return;
   if(dir!=0) return;
   // --- entry when flat: the Sci ICC continuation only (kill-zone gated) ---
   if(!kzEntryOK) return;   // AUDIT FIX: gate NEW entries here, not the whole function
   if(iccBuySig)
     { ML_Evaluate(1); ML_Export("SIGNAL",1); if(!g_mlPass){ if(VerboseLog) Print("[ML] BUY blocked P2=",DoubleToString(g_mlP2,2)); return; } ML_v2_StagePending(1); double anchor=(iccSigSL>0)? iccSigSL : wkLastLo; ExecuteBuy(anchor,"ICC BUY (continuation)",ColBuy); return; }
   if(iccSellSig)
     { ML_Evaluate(-1); ML_Export("SIGNAL",-1); if(!g_mlPass){ if(VerboseLog) Print("[ML] SELL blocked P2=",DoubleToString(g_mlP2,2)); return; } ML_v2_StagePending(-1); double anchor=(iccSigSL>0)? iccSigSL : wkLastHi; ExecuteSell(anchor,"ICC SELL (continuation)",ColSell); return; }
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
   string d ="=== ICC TradesBySci EA v4.3.7 (SMC/ML DATA) ====\n";
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
   d+=" ML: "+(InpMLMode==ML_OFF?"OFF":(g_mlPass?"PASS":"BLOCK"))+"  P2="+DoubleToString(g_mlP2,2)+" P3="+DoubleToString(g_mlP3,2)+" risk=x"+DoubleToString(g_mlRiskMult,2)+" "+(g_mlRunner?"RUN":"FIXED")+"\n";
   d+=" ML regime: "+g_mlRegimeTxt+" session="+IntegerToString(g_mlSession)+" forecast="+IntegerToString(InpMLForecastDir)+"\n";
   d+=" ML feat: OTE="+DoubleToString(g_mlOTEDepth,3)+" FVGdist="+DoubleToString(g_mlFVGMidDistATR,2)+"ATR FVGsize="+DoubleToString(g_mlFVGSizeATR,2)+"ATR risk="+DoubleToString(g_mlRiskDistanceATR,2)+"ATR spread="+DoubleToString(g_mlSpreadPoints,0)+"pt hour="+IntegerToString(g_mlHour)+"\n";
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
   ENUM_ORDER_TYPE_FILLING fillMode;
   if((fillMask & SYMBOL_FILLING_FOK)!=0)      fillMode=ORDER_FILLING_FOK;
   else if((fillMask & SYMBOL_FILLING_IOC)!=0) fillMode=ORDER_FILLING_IOC;
   else                                        fillMode=ORDER_FILLING_RETURN;
   trade.SetTypeFilling(fillMode);
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
   ML_EnsureCSVHeader();         // v3.8.1: header exists even with zero signals (OBSERVE verifiable)
   ML_v2_EnsureHeader();         // v3.9.0 compatibility dataset
   ML_v4_EnsureHeader();         // v4.0 canonical dataset header at startup
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
