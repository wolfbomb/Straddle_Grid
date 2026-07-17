# docs/CHECKLIST.md — Hydra Test & Verification Checklist

> Companion to `CLAUDE.md` §10–11 and `PHASE_PROMPTS.md`.
> A phase is complete only when **every item in its section passes** and the build compiles with
> **zero errors and zero warnings**. Never commit a failing or warning build.
>
> Environment for all tester runs: MT5 (VT Markets), XAUUSD-VIP, M1 chart, hedging account,
> Strategy Tester model **"Every tick based on real ticks"** unless a check says otherwise.

---

## Universal checks (run at the end of every phase)

- [ ] Compiles in MetaEditor with 0 errors / 0 warnings.
- [ ] `AUTO_TRADING_ENABLED` still defaults to `false`; with it `false`, a full tester run places **zero** orders.
- [ ] `HYDRA_VERSION` bumped exactly once; dashboard header (once it exists) shows the same string; the version string appears in exactly one place in code.
- [ ] All new logs use the `[HYDRA]` prefix + timestamp; every state transition is logged.
- [ ] EA only ever queries/modifies orders and positions matching **this symbol + magic 20260713**.
- [ ] No behavior differs from `CLAUDE.md`; if it must, `CLAUDE.md` was updated first.

---

## Phase 1 — Skeleton & State Machine

- [ ] Inputs block matches CLAUDE.md §8 names/defaults verbatim.
- [ ] `LotProgressionCSV` parsing: default string → 9 lots summing 0.24.
- [ ] Malformed CSV (wrong count, zero lot, non-numeric) → `INIT_PARAMETERS_INCORRECT` with a clear `[HYDRA]` log; EA does not run.
- [ ] Tester run (any week): EA loads, logs `IDLE`, places nothing, no errors in journal.
- [ ] Gate stub evaluated at most 1×/sec in IDLE (verify by log timestamps).
- [ ] **State recovery:** manually place a pending order with magic 20260713 (script or debugger), re-init EA → logs recovery to `ARMED`. With an open magic-tagged position → `ACTIVE`. With cooldown global variable in future → `COOLDOWN`. Clean account → `IDLE`.

## Phase 2 — Gates

- [ ] Time inside Session1 or Session2 → gate 1 pass; outside both → fail with reason logged.
- [ ] Malformed session string → gate 1 fails (no crash).
- [ ] ATR below `ATR_Min_USD` → gate 2 fail "too low"; above `ATR_Max_USD` → fail "too high"; inside band → pass. (Force by narrowing the band in inputs.)
- [ ] Spread > `MaxSpreadPoints` (use tester custom spread) → gate 3 fail.
- [ ] `GridSpacingUSD` set below stops-level+spread+buffer equivalent → gate 3 fail with the computed minimum logged.
- [ ] Existing Hydra position → gate 4 fail; margin level below `MinMarginLevelPct` → fail; simulated daily loss ≥ `MaxDailyLossPct` → fail.
- [ ] `AUTO_TRADING_ENABLED=false` → gate 5 fail; terminal AutoTrading button off → gate 5 fail.
- [ ] **Short-circuit:** with gate 1 failing, logs show gates 2–5 were *not* evaluated.
- [ ] Gate status logged on change only — no 1 Hz log spam while status is stable.
- [ ] All gates pass → log `gates PASS — deployment deferred (Phase 3)`, still zero orders.

## Phase 3 — Grid Deploy & Expiry

- [ ] Gates pass → exactly `GridLevels` buy stops above and `GridLevels` sell stops below anchor; prices match the §7 formula (audit journal vs. hand-computed levels); lots match progression; comments `SIGMA.Hydra.B<i>`/`.S<i>`; magic correct.
- [ ] **Stops-level rejection → clean abort:** set `FirstLevelOffsetUSD` below the stops-level distance → deployment aborts *before* any send; zero orders exist; state stays IDLE. (§11 explicit case)
- [ ] **Mid-deploy rollback:** simulate a send failure (e.g. invalid lot on one level) → all already-placed orders deleted, retcode logged, IDLE, zero orders left behind.
- [ ] No partial grids: at no point in any run does the Hydra pending count sit strictly between 1 and 2×GridLevels while state is ARMED-entry.
- [ ] **TTL expiry:** no fill for `GridTTLMin` → all pendings deleted, log, back to IDLE; a foreign manual pending on the same symbol is untouched.
- [ ] ARMED re-check: session ends or spread blows out while ARMED → grid cancelled → IDLE, logged.

## Phase 4 — Direction Lock & OCO

- [ ] First fill (either side) → state ACTIVE, locked direction logged, fill counter `1/N`.
- [ ] `OCO_Mode=true`: all opposite-side pendings deleted within one tick of first fill (journal audit); same-side pendings remain.
- [ ] Failed opposite-side deletion is retried and eventually succeeds (verify via log of retcodes).
- [ ] `OCO_Mode=false`: opposite side remains after first fill.
- [ ] Sequential fills increment fill count; each fill records side + time (needed by Phase 5).
- [ ] **Restart mid-ACTIVE:** stop/restart EA (tester re-init or live-demo restart) → direction lock, fill count, and state ACTIVE fully recovered; no duplicate grid deployed. (§11 explicit case)

## Phase 5 — Whipsaw Guard  ⚠ must pass before Phase 6 begins

- [ ] **Both-sides candle:** run a whipsaw bar with `OCO_Mode=false` (or a same-tick double fill) → buy + sell fills within `WhipsawWindowSec` → guard fires: all positions closed at market, all pendings deleted, state COOLDOWN. Account flat. (§11 explicit case)
- [ ] Guard executes at the **top** of ACTIVE handling — verify a whipsaw on the same tick as a basket-TP condition results in the guard path, not the TP path.
- [ ] Fills further apart than `WhipsawWindowSec` → guard does not fire.
- [ ] Cooldown lasts `WhipsawCooldownMin`; during it, gates are not evaluated and nothing is deployed; expiry → IDLE logged.
- [ ] Whipsaw counter global variable increments and **survives terminal restart**.
- [ ] Counter reaches `MaxWhipsawsPerDay` → COOLDOWN holds until next trading day even after the per-event timer lapses.
- [ ] Counter resets automatically on new trading day.
- [ ] Restart during cooldown → recovers to COOLDOWN with correct remaining time.

## Phase 6 — Basket Manager

- [ ] Scaled TP: with 0.03 lots filled, basket closes at ≈ `BasketTP_USD × 3` (audit exact formula against code comment).
- [ ] Basket TP hit → all positions closed, all pendings deleted, short post-exit cooldown, then IDLE; total P/L logged.
- [ ] Basket SL hit → same full-close path at −scaled `BasketSL_USD`.
- [ ] `BasketSL_USD` is read-only at runtime — no code path mutates the effective SL upward.
- [ ] Trailing activates at scaled `TrailActivate_USD`; floor = P/L − scaled `TrailDistance_USD`; floor only ever ratchets up (log floor updates and audit monotonicity).
- [ ] On trail activation, unfilled same-direction pendings are deleted.
- [ ] **Retrace test:** P/L rises past activation then retraces to the floor → all positions closed, all pendings deleted. (§11 explicit case)
- [ ] Whipsaw guard still runs before basket logic every tick (re-verify Phase 5 ordering check).
- [ ] Restart after trail activation → floor recovered (or conservatively recomputed), not reset to none.

## Phase 7 — Strategy Tester Validation Campaign

- [x] ≥3 months XAUUSD-VIP M1, real ticks — completes with no journal errors. (2026-07-15,
      run 05, `2026.04.01`–`2026.07.10`; NFP/FOMC inclusion is a reasonable-confidence
      inference from window length, not independently checked against a real calendar.)
- [x] Spread-stress rerun — gates block correctly, no invalid-stops errors. (2026-07-15,
      run 06; forced via `MaxSpreadPoints=1` rather than a tester-level spread override,
      which was found to be a no-op on this MT5 build — see `docs/TEST_REPORT_P7.md`.)
- [x] Zero partial grids across the entire run (scripted log audit). (484 deploys = 484
      full 9+9 grids, exact match, run 05.)
- [x] Zero orphaned orders after every simulated restart mid-ACTIVE. (2026-07-17, run 09:
      real hard-kill on a live demo chart with 2 positions + 7 pendings — EA re-attached,
      tickets preserved, zero duplicates; `tools/restart-test/`.)
- [x] All four §11 explicit cases re-verified on this build. (Trailing-floor retrace:
      run 05; whipsaw: run 04 re-run on v2.0, 2026-07-17; stops-level rejection: run 07,
      2026-07-17; restart-recovery: run 09, 2026-07-17.)
- [x] Foreign orders/positions untouched throughout. (2026-07-17, run 09: magic-77777
      pending byte-identical through deploy, fills, OCO, crash, restart, cleanup.)
- [x] `docs/TEST_REPORT_P7.md` written: settings, date ranges, per-case pass/fail, and the
      full P/L summary (pulled 2026-07-17 — flags the pre-live profitability problem).

## Phase 8 — Dashboard Panel

**Automated (checked by `run_tests.sh`'s DASH-FAIL summary on every run — see
`docs/superpowers/specs/2026-07-16-dashboard-selftest-design.md`):** header version text, all
5 accent colors, gate dot colors + failing-gate name, every row's live content (session,
spread/ATR, grid status, basket P/L, scaled TP/SL/trail-floor targets, whipsaw counter +
cooldown countdown, TTL countdown), and leftover-object cleanup on EA removal.

**Automated as of 2026-07-17 (synthetic battery + live-chart pixel review — design-doc addendum):**
- [x] Header click collapses to title bar / re-click expands — synthetic
      `CHARTEVENT_OBJECT_CLICK` battery (`hydra_08_dash_selftest`): 27 checks, 0 failures.
- [x] Timeframe-switch persistence — synthetic `CHARTEVENT_CHART_CHANGE` between/after
      collapse toggles: state survives the rebuild (same battery).
- [x] OHLC-label overlap + general "looks right" — PrintWindow captures of the panel on a
      real demo chart (`tools/restart-test/shots/`), reviewed 2026-07-17: blue-ARMED and
      red-ACTIVE-drawdown accents rendered correctly, no OHLC overlap, rows readable.
      Found + fixed in the same pass: empty `GateFailName` rendered MT5's default "Label"
      string (renderer-only artifact invisible to read-back; now writes `" "`).

**Residual (optional, first time a human is at a screen):** one real mouse click on the
header — the only link code can't exercise is MT5's pixel hit-testing that converts a
physical click into `CHARTEVENT_OBJECT_CLICK`.

---

## Final Pre-Deploy (live/demo) Checklist

- [ ] All 8 phases complete; version `v1.8+`; latest commit pushed.
- [ ] Chart: XAUUSD-VIP M1, one EA instance per symbol only.
- [ ] Broker spec logged and sane: stops level, tick size/value, min lot 0.01, lot step compatible with progression.
- [ ] Inputs reviewed against CLAUDE.md §8 defaults; sessions correct for current server-time offset vs GMT.
- [ ] Demo soak: ≥1 week on demo with `AUTO_TRADING_ENABLED=true` before any live deployment.
- [ ] Whipsaw counter global variables visible in Terminal → Global Variables and reset for the new deployment.
- [ ] Confirm dashboard shows all-gates status and `AUTO TRADING: ON` only when intended.
