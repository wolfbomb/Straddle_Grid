# PHASE_PROMPTS.md — Hydra (Straddle_Grid) Build Plan

> Phased build prompts for Claude Code sessions.
> Source of truth for behavior is `CLAUDE.md` — read it fully before starting any phase.
> Each phase below is a self-contained prompt: scope, deliverables, tests, and exit criteria.
>
> **Non-negotiable per-phase workflow (from CLAUDE.md §10):**
> 1. Implement only the scope of the current phase (later-phase stubs are fine but must be inert).
> 2. Run the phase's test suite from `docs/CHECKLIST.md`. All tests must pass with **zero compile warnings**.
> 3. On full pass: bump `HYDRA_VERSION` (last digit +1), update the dashboard header source constant.
> 4. Commit with message `Phase N complete — <summary> (vX.Y)`, then automatically merge to `main` and push (standing user directive — no per-phase approval needed).
> 5. If any behavior deviates from `CLAUDE.md`, update `CLAUDE.md` **first**, then implement.
> 6. Never commit a failing or warning build. Deliver complete files, not diffs.

---

## Version Ladder

| Phase | Version on completion |
|---|---|
| 1 — Skeleton & State Machine | v1.1 |
| 2 — Gates | v1.2 |
| 3 — Grid Deploy & Expiry | v1.3 |
| 4 — Direction Lock & OCO | v1.4 |
| 5 — Whipsaw Guard | v1.5 |
| 6 — Basket Manager | v1.6 |
| 7 — Strategy Tester Validation | v1.7 |
| 8 — Dashboard Panel | v1.8 |

(Phase 1 starts the file at `v1.0` and bumps to `v1.1` on passing its tests.)

---

## Phase 1 — Skeleton & State Machine

**Prompt:**

Create `MQL5/Experts/SIGMA/Straddle_Grid.mq5` as a single-file EA organized into the
commented sections mandated by CLAUDE.md §9:
`Inputs → Globals/State → OnInit (state recovery) → OnTick (state dispatch) → Gates → GridDeploy → WhipsawGuard → BasketManager → Dashboard → Utils`.

Scope:
- Full canonical inputs block from CLAUDE.md §8, verbatim names and defaults.
  `AUTO_TRADING_ENABLED` **must default to `false`**.
- `#define`/`const string HYDRA_VERSION = "v1.0"` — single constant, never duplicated.
- Magic number `20260713`, order comment prefix `"SIGMA.Hydra"` as constants.
- `enum EHydraState { STATE_IDLE, STATE_ARMED, STATE_ACTIVE, STATE_COOLDOWN }` and a
  global state variable.
- Parse `LotProgressionCSV` into a double array in `OnInit`; validate count == `GridLevels`,
  every lot ≥ symbol min lot and lot-step aligned. On failure: log and return `INIT_PARAMETERS_INCORRECT`.
- **State recovery in `OnInit`** (CLAUDE.md §4): scan positions and pending orders filtered by
  *this symbol + magic number only*:
  - ≥1 open position → `ACTIVE`
  - 0 positions, ≥1 pending → `ARMED`
  - whipsaw cooldown global variable still in force → `COOLDOWN`
  - else → `IDLE`
  Never assume a clean slate.
- Persistent storage scaffolding: `GlobalVariable` keys namespaced
  `SIGMA.Hydra.<symbol>.<key>` for whipsaw counter, whipsaw day-stamp, cooldown-until.
- `OnTick` dispatches on state via `switch`; all branches are empty stubs except logging.
  Gate evaluation in `IDLE` is throttled to once per second.
- Logging util: `void HydraLog(string msg)` → `Print("[HYDRA] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " ", msg)`.
  Log every state transition through a single `SetState()` function.
- The EA must place **no orders** in this phase, regardless of inputs.

Tests: run `docs/CHECKLIST.md` §Phase 1.
Exit: zero warnings, all Phase 1 checks pass → bump to v1.1, commit
`Phase 1 complete — skeleton, inputs, state machine, state recovery (v1.1)`.

---

## Phase 2 — Gates

**Prompt:**

Implement the five ordered safety gates (CLAUDE.md §5) inside the `Gates` section.

Scope:
- `bool EvaluateGates(string &failReason)` evaluating **sequentially, short-circuit on first failure**
  (a gate failure means later gates are *not evaluated*):
  1. **Session/Killzone** — parse `Session1`/`Session2` (`"HH:MM-HH:MM"`, server time treated per
     spec as GMT windows). Handle malformed strings by failing the gate with a logged reason.
  2. **Volatility** — `iATR(symbol, PERIOD_M5, 14)` converted to USD; must be within
     `[ATR_Min_USD, ATR_Max_USD]`. Handle `INVALID_HANDLE` / not-enough-bars as gate failure, not crash.
  3. **Spread** — current spread (points) ≤ `MaxSpreadPoints`, **and** validate
     `GridSpacingUSD ≥ (SYMBOL_TRADE_STOPS_LEVEL + spread + buffer)` converted to USD.
  4. **Exposure** — no existing Hydra positions/orders (symbol+magic), margin level >
     `MinMarginLevelPct`, daily realized+floating loss < `MaxDailyLossPct` of day-start balance
     (day-start balance snapshotted once per server day in a global variable).
  5. **Master switch** — `AUTO_TRADING_ENABLED == true` AND `TERMINAL_TRADE_ALLOWED`
     AND `MQL_TRADE_ALLOWED`.
- Cache last gate results (pass/fail + reason per gate) in globals for the future dashboard (Phase 8).
- In `IDLE`, log gate status only on *change* (avoid log spam at 1 Hz).
- Still no order placement: when all gates pass, log `"[HYDRA] gates PASS — deployment deferred (Phase 3)"`.

Tests: `docs/CHECKLIST.md` §Phase 2.
Exit: v1.2, commit `Phase 2 complete — five sequential safety gates (v1.2)`.

---

## Phase 3 — Grid Deploy & Expiry

**Prompt:**

Implement grid deployment (IDLE → ARMED) and TTL expiry (CLAUDE.md §7).

Scope:
- **Pre-flight (before sending anything):** compute anchor = current mid price; compute all
  `2 × GridLevels` prices: BuyStop_i = `anchor + FirstLevelOffsetUSD + i·GridSpacingUSD`,
  SellStop_i = `anchor − FirstLevelOffsetUSD − i·GridSpacingUSD` (i = 0..N−1); normalize to tick
  size; validate **every** level against `SYMBOL_TRADE_STOPS_LEVEL` and freeze level. If *any*
  level is invalid → **abort the entire deployment**, log reason, stay IDLE. No partial grids.
- Placement: `ORDER_FILLING_IOC`, magic `20260713`, comment `"SIGMA.Hydra.B<i>"` / `"SIGMA.Hydra.S<i>"`,
  lots from the parsed progression. Set order expiration to `now + GridTTLMin` via
  `ORDER_TIME_SPECIFIED` where the broker supports it; regardless, enforce TTL in code.
- **Rollback on mid-deploy failure:** if any `OrderSend` fails after some succeeded, delete every
  order already placed in this deployment, log the retcode, return to IDLE. Zero orders left behind.
- On success: record `armedAt`, transition to `ARMED`.
- **ARMED management:** every tick, (a) if `TimeCurrent() − armedAt ≥ GridTTLMin·60` with zero
  fills → delete all pendings → IDLE; (b) re-check gates 1, 3 (session, spread) and 5; on failure →
  cancel grid → IDLE, logged.
- Verify VT Markets XAUUSD-VIP contract spec at first run (stops level, tick value/size,
  min lot, lot step) — log them in `OnInit` so defaults can be tuned. If
  `SYMBOL_TRADE_STOPS_LEVEL` makes the default `GridSpacingUSD 0.42` invalid, the gate-3
  validation from Phase 2 must already have blocked deployment.

Tests: `docs/CHECKLIST.md` §Phase 3 (includes stops-level rejection → clean abort case from §11).
Exit: v1.3, commit `Phase 3 complete — validated grid deploy, rollback, TTL expiry (v1.3)`.

---

## Phase 4 — Direction Lock & OCO

**Prompt:**

Implement fill detection and direction lock (ARMED → ACTIVE) per CLAUDE.md §7.

Scope:
- `OnTradeTransaction`: react to `TRADE_TRANSACTION_DEAL_ADD` deals matching symbol+magic.
  On **first fill**: record locked direction and fill time, transition ARMED → ACTIVE.
- Record *every* fill with side + time into a small ring buffer / arrays — the Whipsaw Guard
  (Phase 5) needs "buy-side and sell-side fill within `WhipsawWindowSec`".
- `OCO_Mode == true` (default): on first fill, immediately delete **all opposite-side** pendings
  (identified by comment prefix `SIGMA.Hydra.B` / `.S` + magic). Retry deletion next tick for any
  that fail (order may be mid-execution); log each retcode.
- `OCO_Mode == false`: leave the opposite side in place (Reel-style reversal hedge — Whipsaw
  Guard still applies once Phase 5 lands).
- Direction lock, fill count, and per-side fill flags must be **reconstructed in `OnInit` state
  recovery** (from open positions + remaining pendings + deal history for today), so a terminal
  restart mid-ACTIVE does not lose the lock. Extend Phase 1 recovery accordingly.
- Hedging account: use position tickets, never assume netting.

Tests: `docs/CHECKLIST.md` §Phase 4.
Exit: v1.4, commit `Phase 4 complete — fill detection, direction lock, OCO cancel (v1.4)`.

---

## Phase 5 — Whipsaw Guard (test before proceeding to Phase 6)

**Prompt:**

Implement the mandatory kill switch (CLAUDE.md §6). This logic lives in its own function
`CheckWhipsawGuard()`, called **at the top of `OnTick` in `ACTIVE` state, before any other
management logic**. It must never be weakened or removed by later refactors.

Scope:
- Trigger: a buy-side fill **and** a sell-side fill both occurred within `WhipsawWindowSec`
  (default 300 s), using the fill records from Phase 4.
- On trigger, in order:
  1. Close **all** Hydra positions (symbol+magic) at market — loop with retry on transient retcodes.
  2. Delete **all** remaining Hydra pendings.
  3. Enter `COOLDOWN` until `now + WhipsawCooldownMin` (persist cooldown-until as a global variable).
  4. Increment the persistent whipsaw counter global variable (survives restart), stamped with the
     server trading day; reset the counter automatically when the day changes.
- If counter ≥ `MaxWhipsawsPerDay` (default 2): remain in `COOLDOWN` until the next trading day
  regardless of the per-event cooldown timer.
- `COOLDOWN` state does nothing but count down; on expiry → IDLE (logged).
- `OnInit` recovery: if cooldown-until is in the future, restore `COOLDOWN`.
- Also run whipsaw detection when `OCO_Mode == false` even in ARMED→ACTIVE edge cases (both
  sides can fill on the same tick before OCO would have applied — guard wins).

Tests: `docs/CHECKLIST.md` §Phase 5 — including the §11 case "whipsaw candle piercing both sides
in one bar → guard fires, flat, cooldown". **Do not start Phase 6 until these pass.**
Exit: v1.5, commit `Phase 5 complete — whipsaw guard kill switch + persistent counter (v1.5)`.

---

## Phase 6 — Basket Manager

**Prompt:**

Implement basket management in `ACTIVE` (CLAUDE.md §7), running *after* `CheckWhipsawGuard()`.

Scope:
- Aggregate floating P/L (including swap + commission where retrievable) across all Hydra
  positions on this symbol.
- Scaling: spec defaults are "per 0.01 base — scaled by filled volume". Effective
  TP = `BasketTP_USD × (filledVolume / 0.01)`; same for SL, trail activate, trail distance.
  Document the exact formula in code comments and in CLAUDE.md if interpretation is refined.
- **Basket TP:** total P/L ≥ scaled `BasketTP_USD` → close all positions + delete all pendings → COOLDOWN? No — per §4, basket exit → `COOLDOWN` then timer → IDLE. Use a short fixed post-exit cooldown (reuse `COOLDOWN` state with, e.g., 1 min timer distinct from whipsaw cooldown) so re-entry re-passes all gates.
- **Basket SL:** total P/L ≤ −scaled `BasketSL_USD` → same close-all path. `BasketSL_USD` must
  never be widened at runtime (hard rule §12).
- **Trailing:** once P/L ≥ scaled `TrailActivate_USD`, set floor = `P/L − scaled TrailDistance_USD`;
  ratchet the floor up as P/L makes new highs (never down); close all if P/L ≤ floor.
  On trail activation, delete all unfilled same-direction pendings (stop adding into an extended move).
- All exits go through one `CloseBasket(string reason)` util: close positions, delete pendings,
  log totals, transition state. Trail floor must survive restart (recover from a global variable
  or recompute conservatively on `OnInit`).

Tests: `docs/CHECKLIST.md` §Phase 6 — including §11 case "trailing floor hit during a retrace →
all positions closed, all pendings deleted".
Exit: v1.6, commit `Phase 6 complete — basket TP/SL/trailing + pending cleanup (v1.6)`.

---

## Phase 7 — Strategy Tester Validation

**Prompt:**

No new features. Run the full CLAUDE.md §11 validation campaign and fix any defects found
(each fix = version bump + spec update if behavioral).

Scope:
- Backtest: XAUUSD-VIP, M1, **"Every tick based on real ticks"**, ≥3 months including ≥1 NFP
  and ≥1 FOMC day. Spread stress: repeat key days with fixed elevated spread.
- Verify explicitly (log-audit each):
  - No partial grids ever placed (count pendings == 2×GridLevels or 0 at all times in ARMED entry).
  - No orphaned orders after restart mid-ACTIVE (tester restart / re-init simulation).
  - Whipsaw day → guard fired, account flat, cooldown honored, counter persisted.
  - TTL expiry cancels exactly the Hydra orders and nothing else.
  - EA never touches foreign orders (run alongside a dummy manual position in tester where possible).
- Produce `docs/TEST_REPORT_P7.md` summarizing runs, settings, and pass/fail per §11 case.
Exit: v1.7, commit `Phase 7 complete — strategy tester validation campaign (v1.7)`.

---

## Phase 8 — Dashboard Panel

**Prompt:**

Implement the collapsible dashboard per CLAUDE.md §10.1. Read that section fully; key points:

- Header `SIGMA Hydra <HYDRA_VERSION>` — version sourced **only** from the constant.
- Anchored top-left; default expanded; header click toggles collapse (title bar + ▲/▼ only when
  collapsed); collapse state persists across timeframe switches (chart-object based, rebuilt in
  `OnChartEvent`).
- Dark translucent background, monospace-aligned rows, state accent colors:
  gray IDLE / blue ARMED / green ACTIVE-profit / red ACTIVE-drawdown / orange COOLDOWN.
- Rows top-to-bottom exactly per the §10.1 table: State, Auto Trading (red warning when OFF),
  Gates (5 pass/fail dots, gate name shown on fail — wire to the Phase 2 gate cache), Session,
  Spread/ATR, Grid (levels armed / direction / fills `n/N`), Basket P/L (color-coded),
  Targets (TP/SL/trail floor, `—` until trailing active), Whipsaw (`n / MaxWhipsawsPerDay` +
  cooldown countdown), Expiry (TTL countdown while ARMED).
- **Read-only** — no trade buttons.
- Throttle redraws (e.g. 2–4 Hz or on-change) to keep OnTick cheap; delete all panel objects in
  `OnDeinit` for reasons other than timeframe switch.

Tests: `docs/CHECKLIST.md` §Phase 8.
Exit: v1.8, commit `Phase 8 complete — collapsible dashboard panel (v1.8)`.

---

## Standing Hard Rules (apply to every phase — CLAUDE.md §12)

- Never remove or weaken the Whipsaw Guard or Gate 5 (master switch).
- Never introduce martingale beyond the fixed `LotProgressionCSV` array.
- Never widen `BasketSL_USD` at runtime.
- Deliver complete files, not diffs.
- Bump `HYDRA_VERSION` on every change; commit + push only after all phase tests pass with zero warnings.
- Update `CLAUDE.md` whenever behavior changes — spec first, then code.
