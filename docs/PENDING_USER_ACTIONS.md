# PENDING_USER_ACTIONS.md — Your Test Queue

> Everything currently waiting on you (the user, at your MT5 PC/Mac).
> Current build: `Straddle_Grid.mq5` **v2.0** (Phases 1–6 complete: skeleton, gates, grid
> deploy/expiry, direction lock & OCO, Whipsaw Guard, **Basket Manager**).
>
> ✅ **Validated so far** (tester, real ticks, VTMarkets-Demo, 2026-07-15): compile clean ·
> gates + short-circuit · grid deploy 9+9 with correct prices/lots · OCO cancel · sequential
> fills · TTL expiry/redeploy (no partial grids) · whipsaw guard (4 firings across two runs,
> reproducible, correct cooldowns, 2/2 daily lockout) · **Basket Manager**: basket TP/SL
> scaling verified exact across every observed volume (0.01…0.24 lots), trailing floor
> monotonic-only with correct activate/floor math, `trail floor hit` exits, 60 s post-exit
> cooldown on every single exit with zero exceptions, whipsaw guard still wins over basket
> logic on the same tick.
>
> 🚀 Shortcut: `tools/strategy-tester/run_tests.sh` — works from Windows Git Bash (auto-detects
> `D:\Straddle_Grid` as terminal + data folder) and requires `configs/common.local.ini` (your
> own demo login, gitignored — copy `common.local.ini.example` and fill it in). See its README.

## Phase 6 — CLOSED (2026-07-15)

Full four-scenario suite passed. Summary of what the tester logs proved (see chat history
for the line-by-line evidence if needed):

- **Run 01 (defaults smoke):** zero state transitions/trades for the entire range — gate 5
  correctly blocks everything while `AUTO_TRADING_ENABLED=false`.
- **Run 02 (deploy & fills):** grid deploys 9+9, direction lock + OCO cancel, sequential
  fills at correct prices/lots, basket TP/SL fired repeatedly with scaling matching
  `input USD × (filled volume ÷ 0.01)` exactly every time, trailing activate → floor-raise
  (strictly increasing) → floor-hit sequence confirmed with exact math, 60 s cooldown → IDLE
  → clean re-entry.
- **Run 03 (TTL expiry):** clean 2-minute expire/redeploy cycling, always a full 9+9 grid
  (no partial grids ever observed), occasional in-window fills handled by the same basket
  logic with the same correct scaling.
- **Run 04 (whipsaw guard):** 4 firings, reproduced identically across reruns (gaps 627 s /
  8 s / 35 s / 90 s), correct 1/2 → 2/2 daily counter and cooldown durations, whipsaw always
  wins — no `BASKET EXIT` line ever interleaves with a `WHIPSAW DETECTED` line.

**Not yet exercised (optional, still open):** restart mid-trailing on a demo chart — recovery
of `ACTIVE` state + the persisted trail floor from `SIGMA.Hydra.XAUUSD-VIP.trail_floor` (F3)
after a terminal restart. Low risk since the general restart-recovery path was already proven
in earlier phases, but worth doing before the pre-live soak.

**Documentation gap noticed, not a defect:** the tester log showed a
`state ARMED -> ACTIVE (fill detected via polling fallback - direction X)` message — a
graceful-degradation path for when `OnTradeTransaction` delivery is missed. It worked
correctly in the run 04 whipsaw scenario, but CLAUDE.md doesn't currently describe this
fallback. Worth a spec note in a future pass.

Version bumped to **v2.0** and committed as `Phase 6 complete`.

## Next: Phase 7 — full validation campaign

Two new tester configs are ready in `tools/strategy-tester/` (git pull to get them):

- [ ] **Run 05 — Phase 7 campaign:** `./run_tests.sh hydra_05` (filter arg runs only this
      one, skips re-running the already-passed 01–04). Full production defaults, no gates
      weakened, `2026.04.01`–`2026.07.10` (~3 months). This range should contain multiple
      NFP days (first Friday of each month) and, since FOMC meets roughly every 6 weeks, at
      least one FOMC day — no guarantee though, so eyeball the equity curve for a couple of
      obvious high-volatility spikes and cross-check the dates against your broker's
      economic calendar if you want certainty. Expect: no journal errors, zero partial
      grids, and gates/deploy/fills/whipsaw/basket all interacting correctly over the long
      window. This run will take noticeably longer than 01–04 and the first pass downloads
      3+ months of tick data — be patient.
- [ ] **Run 06 — spread stress:** `./run_tests.sh hydra_06`. Same production defaults but
      with a fixed `Spread=40` tester override (above the `MaxSpreadPoints=35` cap) for the
      whole `2026.06.01`–`2026.07.10` window. Expect **zero orders placed at all** — only
      clean `gates FAIL - gate 3 (Spread): 40 > max 35` lines, no "invalid stops" broker
      errors. If you see even one order, that's a real bug (gate 3 not blocking correctly).

Still outstanding after those two runs, per CLAUDE.md §11 (harder to automate, need a plan
before doing them):
- [ ] Terminal restart during `ACTIVE` with no duplicate grid — needs a live/demo chart
      restart, not a backtest; can piggyback on the optional restart-mid-trailing test from
      Phase 6.
- [ ] Stops-level rejection at deploy → clean abort — gate 3's own spacing check
      (`GridSpacingUSD ≥ stops + spread + buffer`) already prevents this under current
      defaults (0.70 spacing clears the 35-pt spread cap with room to spare), so it isn't
      naturally exercised by 01–06. Would need a deliberately-too-tight `GridSpacingUSD`
      preset to force it — ask if you want that added as a run 07.

## Upcoming (for awareness)

| When | Task |
|---|---|
| Phase 7 | 3-month real-tick backtest incl. NFP + FOMC; spread-stress rerun; test report review |
| Phase 8 | Dashboard panel implementation, then visual checks on a live chart (collapse, colors, rows) |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` (final checklist in `docs/CHECKLIST.md`); also close the optional restart-mid-trailing test above |
