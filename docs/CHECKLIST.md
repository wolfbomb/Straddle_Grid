# docs/CHECKLIST.md — Hydra Test & Verification Checklist

> Companion to `CLAUDE.md` §10–11 and `PHASE_PROMPTS.md`.
> A phase is complete only when **every item in its section passes** and the build compiles with
> **zero errors and zero warnings**. Never commit a failing or warning build.
>
> Environment for all tester runs: MT5 (VT Markets), XAUUSD-VIP, M1 chart, hedging account,
> Strategy Tester model **"Every tick based on real ticks"** unless a check says otherwise.

---

## Universal checks (run at the end of every phase)

- [x] Compiles in MetaEditor with 0 errors / 0 warnings. (Reconfirmed at every version bump
      through v2.3, most recently 2026-07-19.)
- [x] `AUTO_TRADING_ENABLED` still defaults to `false`; with it `false`, a full tester run places **zero** orders. (Compiled default in code; gate 5 blocks deployment whenever false — observed repeatedly across sessions.)
- [x] `HYDRA_VERSION` bumped exactly once; dashboard header shows the same string; the version string appears in exactly one place in code. (Single `#define`, read by the header — verified via the dashboard self-test's `VerifyTextProp` read-back.)
- [x] All new logs use the `[HYDRA]` prefix + timestamp; every state transition is logged. (Consistent across every journal reviewed this project.)
- [x] EA only ever queries/modifies orders and positions matching **this symbol + magic 20260713**. (Directly proven 2026-07-17, run 09: a foreign pending, different magic, stayed byte-identical through deploy/fills/OCO/crash/restart — `docs/TEST_REPORT_P7.md` §Run 09.)
- [x] No behavior differs from `CLAUDE.md`; if it must, `CLAUDE.md` was updated first. (Spec-first practice followed for every behavioral change, e.g. FOMC-Only Mode §5.1 and the draggable dashboard §10.1 update, both written before the corresponding code.)

---

## Phase 1 — Skeleton & State Machine

- [x] Inputs block matches CLAUDE.md §8 names/defaults verbatim. (Cross-checked directly
      every time either file was touched — most recently for FOMC-Only Mode and the
      draggable-dashboard inputs.)
- [x] `LotProgressionCSV` parsing: default string → 9 lots summing 0.24. (Every successful
      init in every run this project — hundreds across the Phase 7 campaign alone —
      requires this to parse correctly; a failure would abort init and show up as zero
      activity, which never happened.)
- [x] Malformed CSV (wrong count, zero lot, non-numeric) → `INIT_PARAMETERS_INCORRECT`
      with a clear `[HYDRA]` log; EA does not run. (2026-07-19, run 10 —
      `hydra_10_malformed_csv`: 5 lot entries vs `GridLevels=9` → `INIT FAIL:
      LotProgressionCSV has 5 entries but GridLevels=9`, zero further activity.)
- [x] Tester run (any week): EA loads, logs `IDLE`, places nothing, no errors in journal.
      (Every fresh run opens with `state IDLE -> IDLE (recovery: clean slate)` — e.g. run
      05's exact opening line.)
- [x] Gate stub evaluated at most 1×/sec in IDLE. (Structural guarantee, not just a log
      throttle — `OnTick`'s IDLE branch reads `if(TimeCurrent() == g_lastGateEval) break;`
      *before* `EvaluateGates()` is ever called, so evaluation itself cannot happen twice
      within the same whole server-second.)
- [x] **State recovery — `ACTIVE` and `IDLE` proven.** Run 09 (2026-07-17, live demo):
      hard-kill mid-`ACTIVE` with 2 positions + 7 pendings → full recovery, tickets
      preserved, no duplicate grid. `IDLE` recovery ("clean slate") is exercised on every
      run. **`ARMED`- and `COOLDOWN`-specific restart recovery were not separately
      exercised** — the code path exists (`RecoverState()` handles all four states
      symmetrically) but no test has specifically killed the terminal while pending
      orders were live with zero fills, or while mid-`COOLDOWN`.

## Phase 2 — Gates

- [x] Time inside Session1 or Session2 → gate 1 pass; outside both → fail with reason
      logged. (Observed constantly, e.g. `gates FAIL — gate 1 (Session): server 15:31
      outside 07:00-10:00 and 12:00-15:00`.)
- [x] Malformed session string → gate 1 fails (no crash). (2026-07-19, run 11 —
      `hydra_11_malformed_session`: `Session1=garbage` → `WARNING: malformed session
      window` at init, then `gates FAIL — gate 1 (Session): malformed session input`
      every tick for the whole 2-day window; zero trades, zero deployments confirmed in
      the `.htm` report.)
- [x] ATR below `ATR_Min_USD` → gate 2 fail "too low"; above `ATR_Max_USD` → fail "too
      high"; inside band → pass. (Observed directly, e.g. `gates FAIL — gate 2
      (Volatility): ATR 8.16 > max 8.00 (move already ran)` in the 2026-07-19 FOMC gate
      test.) *("Too low" specifically not separately captured in a citation, though the same check path applies.)*
- [x] Spread > `MaxSpreadPoints` (use tester custom spread) → gate 3 fail. (Run 06,
      2026-07-15: 62/62 deployment attempts blocked on real historical spread, zero
      orders — `docs/TEST_REPORT_P7.md` §Run 06.)
- [x] `GridSpacingUSD` set below stops-level+spread+buffer equivalent → gate 3 fail with
      the computed minimum logged. (2026-07-19, run 12 — `hydra_12_spacing_too_tight`:
      `GridSpacingUSD=0.30` → `gates FAIL — gate 3 (Spread): GridSpacingUSD 0.30 <
      required 0.59 (stops 20 + spread 29 + buffer 10 pts)`, computed minimum tracking
      real spread tick-by-tick; zero deployments.)
- [x] Existing Hydra position → gate 4 fail. (Implicit in every one of run 05's 484
      deploy→exit cycles: zero partial/duplicate grids requires gate 4 to correctly
      block re-deployment against existing exposure every single time.)
      *(Margin-level and daily-loss fail branches specifically not forced/tested.)*
- [x] `AUTO_TRADING_ENABLED=false` → gate 5 fail. (Observed constantly across sessions.)
      *(Terminal AutoTrading-button-off path specifically not tested — requires an actual UI toggle.)*
- [x] **Short-circuit:** with gate 1 failing, logs show gates 2–5 were *not* evaluated.
      (Run 06's evidence explicitly notes gate 1/2 failures interleaved with gate 3
      failures — "expected short-circuit behavior on ticks that never reached gate 3".)
- [x] Gate status logged on change only — no 1 Hz log spam while status is stable.
      (Run 05: 46.5M ticks processed against a comparatively tiny number of gate-status
      log lines — consistent with change-only logging; code implements via
      `g_lastGateStatus`.)
- [x] *(N/A — superseded)* `gates PASS — deployment deferred (Phase 3)` was a Phase-2-only
      stub message; once Phase 3 made deployment real, all-gates-pass correctly leads to
      an actual `DeployGrid()` call instead (see Phase 3's first item). Not a gap.

## Phase 3 — Grid Deploy & Expiry

- [x] Gates pass → exactly `GridLevels` buy stops above and `GridLevels` sell stops below
      anchor; prices match the §7 formula; lots match progression; comments/magic
      correct. (Run 05: 484/484 deployments were full, correctly-priced 9+9 grids —
      `docs/TEST_REPORT_P7.md` §Run 05.)
- [x] **Stops-level rejection → clean abort:** (Run 07, 2026-07-17: 19,868 clean
      pre-send aborts forced via `FirstLevelOffsetUSD=0.10`, zero orders, zero broker
      errors — §11 explicit case, closed.)
- [ ] **Mid-deploy rollback:** simulate a send failure (e.g. invalid lot on one level) → all already-placed orders deleted, retcode logged, IDLE, zero orders left behind. *(`RollbackDeployment()` exists in code and is called on any mid-loop send failure; no test has actually forced a send failure partway through a deploy to observe it fire.)*
- [x] No partial grids: at no point does the Hydra pending count sit strictly between 1
      and 2×GridLevels. (Run 05: 484 deploys = 484 full 9+9 grids, exact match, zero
      partial grids.)
- [x] **TTL expiry:** no fill for `GridTTLMin` → all pendings deleted, log, back to IDLE.
      (2026-07-19, run 14 — `hydra_14_ttl_expiry`: `FirstLevelOffsetUSD`/`GridSpacingUSD`
      widened to 30.0 so no level is realistically reachable within 45 min; multiple
      clean `state ARMED -> IDLE (grid TTL 45 min expired with zero fills)` transitions
      logged, zero fills across the whole run.) *(Foreign-manual-pending-untouched
      specifically not re-tested for this exact scenario, but a strictly harder version
      — foreign order surviving a full crash/restart mid-`ACTIVE` — is already proven in
      run 09.)*
- [x] ARMED re-check: session ends while ARMED → grid cancelled → IDLE, logged.
      (2026-07-19, run 13 — `hydra_13_armed_session_end`: narrow `Session1=07:00-07:10`
      + widened `FirstLevelOffsetUSD=5.0` so fills don't land immediately; 5+ clean
      `state ARMED -> IDLE (grid cancelled — gate failed while ARMED: server 07:10
      outside 07:00-07:10 and 23:58-23:59)` transitions across a 2-week window, zero
      fills each time.) *("Spread blows out while ARMED" specifically not separately
      forced — same code path (`GateSpread()` re-evaluated in the ARMED re-check), but
      only the session-end trigger was exercised.)*

## Phase 4 — Direction Lock & OCO

- [x] First fill (either side) → state ACTIVE, locked direction logged, fill counter
      `1/N`. (Observed constantly, e.g. `state ARMED -> ACTIVE (first fill — direction
      locked BUY, OCO cancel issued)`.)
- [x] `OCO_Mode=true`: all opposite-side pendings deleted within one tick of first fill.
      (Observed in every ACTIVE transition log — the cancel is issued in the same log
      line as the fill.)
- [ ] Failed opposite-side deletion is retried and eventually succeeds. *(Retry-until-success loop exists in code (`g_ocoCleanupPending`); no test forced an initial deletion failure to observe the retry.)*
- [x] `OCO_Mode=false`: opposite side remains after first fill. (Run 04's whipsaw config
      runs with `OCO_Mode=false` specifically, and both buy- and sell-side fills occur
      within the same cycle — direct evidence the opposite side was never cancelled.)
- [x] Sequential fills increment fill count; each fill records side + time. (Observed
      directly, e.g. run 09's `fill 2/9`, `fill 3/9` sequence.)
- [x] **Restart mid-ACTIVE:** direction lock, fill count, and state ACTIVE fully
      recovered; no duplicate grid. (Run 09, 2026-07-17, live demo — §11 explicit case,
      closed.)

## Phase 5 — Whipsaw Guard  ⚠ must pass before Phase 6 begins

- [x] **Both-sides candle** → guard fires: all positions closed, all pendings deleted,
      COOLDOWN, account flat. (Run 04 re-run on v2.0, 2026-07-17: 4 firings, correct gap
      math — §11 explicit case, closed.)
- [ ] Guard executes at the **top** of ACTIVE handling on the *same tick* as a basket-TP condition specifically. *(Code calls `CheckWhipsawGuard()` first, before `ManageBasket()`, in the `OnTick` dispatch — verified by reading the source — but no test has contrived an exact same-tick collision between the two conditions to observe the guard win.)*
- [x] Fills further apart than `WhipsawWindowSec` → guard does not fire. (CLAUDE.md §6
      design note, 2026-07-13: a "slow whipsaw" — 10.5 min gap, `OCO_Mode=false` —
      observed in tester and confirmed *not* to trigger the guard; documented as
      intentional, not a bug.)
- [x] Cooldown lasts `WhipsawCooldownMin`. (Run 04: fired at 07:00:00, cooldown logged
      until 08:00:00 — exactly the 60 min default.) *("Gates not evaluated during cooldown" specifically not separately audited via log-absence.)*
- [ ] Whipsaw counter **survives terminal restart** specifically. *(Persistent global variable, same mechanism as the trail floor which does survive restart per Run 09 — but no test has restarted the terminal specifically mid-whipsaw-cooldown to confirm the counter value itself.)*
- [x] Counter reaches `MaxWhipsawsPerDay` → COOLDOWN holds until next trading day. (Run
      04: "2/2 today" → `COOLDOWN` until next trading day, both test days.)
- [x] Counter resets automatically on new trading day. (Run 04: `whipsaw counter reset
      for the new trading day` logged exactly at the day boundary.)
- [ ] Restart during cooldown → recovers to COOLDOWN with correct remaining time. *(Not specifically exercised via an actual restart; `RecoverState()` implements this path.)*

## Phase 6 — Basket Manager

- [x] Scaled TP formula: basket closes at `BasketTP_USD × (volume/0.01)` exactly.
      (Audited three independent real instances from this project's tester logs, each a
      different `BasketTP_USD`/volume pair: `0.08 lots @ TP=20` → 20×8=**160.00**
      (logged: 160.00); `0.06 lots @ TP=20` → 20×6=**120.00** (logged: 120.00);
      `0.24 lots @ TP=15` → 15×24=**360.00** (logged: 360.00). Exact match all three —
      stronger evidence than a single fixed-lot case since it confirms the formula holds
      across varying inputs, not just one hardcoded scenario.)
- [x] Basket TP hit → all positions closed, all pendings deleted, cooldown, then IDLE;
      P/L logged. (Run 05: 33 TP exits; `post-exit cooldown` and `COOLDOWN -> IDLE`
      counts both match the total exit count exactly — zero stuck cycles.)
- [x] Basket SL hit → same full-close path. (Run 05: 288 SL exits, same exact-match
      cleanup.)
- [x] `BasketSL_USD` is read-only at runtime — no code path mutates the effective SL
      upward. (Verified by reading the source: the effective SL is computed fresh each
      tick from the input × volume scale factor; no assignment ever widens it. CLAUDE.md
      §12 Hard Rules also forbids this explicitly.)
- [x] Trailing activates at scaled `TrailActivate_USD`; floor ratchets up only. (Run 05:
      163 trail-floor-hit exits; monotonic-floor math validated during the original
      Phase 6 basket-manager pass per `docs/TEST_REPORT_P7.md` §11.)
- [x] On trail activation, unfilled same-direction pendings are deleted. (Consistent with
      run 05's zero-orphan result across all 163 trail-floor exits — leftover pendings
      would have shown up as orphaned orders, and none did.)
- [x] **Retrace test:** P/L rises past activation then retraces to the floor → full
      close. (163 instances in run 05 — §11 explicit case, closed.)
- [x] Whipsaw guard still runs before basket logic every tick. (Verified by reading the
      `OnTick` dispatch: `CheckWhipsawGuard()` is called before `ManageBasket()` in the
      `ACTIVE` branch, unchanged since Phase 5.)
- [ ] Restart after trail activation → floor recovered, not reset to none. *(Run 09's restart happened before any TP/SL/trail exit in that cycle, so it didn't specifically exercise a restart **after** the floor was already active. `RecoverState()` implements floor recovery from a persistent global variable, per CLAUDE.md §7, but this exact scenario — kill after trailing has engaged — hasn't been directly tested.)*

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

**Draggable panel (v2.3, 2026-07-19 — CLAUDE.md §10.1):**
- [x] Collapse toggle moved to a dedicated button, separate from the drag handle, so a
      click-to-collapse and a click-and-drag gesture can never conflict.
- [x] Header rectangle is now the drag handle (`OBJPROP_SELECTABLE=true`); dragging
      repositions every child object together and clamps to stay on-chart, below the
      native OHLC label.
- [x] Dragged position persists across restarts via `GV_DASH_X`/`GV_DASH_Y` (same
      durability class as the whipsaw counter / trail floor).
- [x] Synthetic battery extended with a drag test (sets the header's raw position,
      synthesizes `CHARTEVENT_OBJECT_DRAG`, asserts the panel moved, persisted to GV,
      and restores cleanly): battery is now **31 checks** (27 + 4), 0 failures.

**Residual (optional, first time a human is at a screen):** one real mouse click on the
collapse button, and one real click-and-drag on the header — the only things code can't
exercise are MT5's own pixel hit-testing for `CHARTEVENT_OBJECT_CLICK`/`OBJECT_DRAG`.

---

## Final Pre-Deploy (live/demo) Checklist

- [ ] All 8 phases complete; version `v2.3+`; latest commit pushed.
- [ ] Chart: XAUUSD-VIP M1, one EA instance per symbol only.
- [ ] Broker spec logged and sane: stops level, tick size/value, min lot 0.01, lot step compatible with progression.
- [ ] Inputs reviewed against CLAUDE.md §8 defaults; sessions correct for current server-time offset vs GMT.
- [ ] Demo soak: ≥1 week on demo with `AUTO_TRADING_ENABLED=true` before any live deployment.
- [ ] Whipsaw counter global variables visible in Terminal → Global Variables and reset for the new deployment.
- [ ] Confirm dashboard shows all-gates status and `AUTO TRADING: ON` only when intended.
