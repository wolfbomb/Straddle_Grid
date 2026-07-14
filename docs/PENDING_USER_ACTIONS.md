# PENDING_USER_ACTIONS.md — Your Test Queue

> Everything currently waiting on you (the user, at your MT5 PC/Mac).
> Current build: `Straddle_Grid.mq5` **v1.9** (Phases 1–6: skeleton, gates, grid deploy/expiry,
> direction lock & OCO, Whipsaw Guard, **Basket Manager**).
>
> ✅ **Validated so far** (tester, real ticks, 2026-07-13): compile clean · gates + short-circuit ·
> grid deploy 9+9 with correct prices/lots · OCO cancel · sequential fills · TTL expiry/redeploy ·
> whipsaw guard (4 firings, cooldowns, 2/2 daily lockout, day-roll reset).
>
> 🚀 Shortcut: `tools/strategy-tester/run_tests.sh` — now works from Windows Git Bash too
> (auto-detects `D:\Straddle_Grid` as terminal + data folder); see its README.

## 1. Recompile (required) — ✅ done 2026-07-14

`git pull`, open MetaEditor, compile `Straddle_Grid.mq5` → must be **0 errors / 0 warnings**.
The build must log `SIGMA Hydra v1.9` — your last run still used the v1.6 binary.

Confirmed via `MQL5/logs/20260714.log`: `SIGMA Hydra v1.9 initializing on XAUUSD-VIP` present.
**Note:** every run since has `AUTO_TRADING_ENABLED=false` → gate 5 fails immediately each tick,
so no grid has deployed yet. Section 2 below is still fully outstanding — flip
`AUTO_TRADING_ENABLED=true` in the tester inputs before rerunning the suite.

## 2. Phase 6 — Basket Manager tests

Full list in `docs/CHECKLIST.md` §Phase 6. The automated suite covers most of it:

- [ ] **Basket TP (rerun 02):** on a trending day the run should now end each cycle with
      `BASKET EXIT — basket TP — P/L X >= Y (Z lots)`, all positions closed, all pendings
      deleted, `post-exit cooldown until …` (60 s), then IDLE and possible re-entry.
      Spot-check the scaling: with e.g. 0.09 lots filled, the TP threshold ≈ 15 × 9 = $135.
- [ ] **Basket SL:** any losing basket must close at −BasketSL_USD × (volume/0.01) — look for
      `BASKET EXIT — basket SL — …` and verify the account is flat after.
- [ ] **Trailing (§11 retrace case):** look for `trailing activated: … floor …`, rising
      `trail floor raised to …` lines (floor must only ever increase), same-direction pendings
      deleted at activation, then `BASKET EXIT — trail floor hit — …` when price retraces.
- [ ] **Whipsaw still first (rerun 04):** guard behavior unchanged — whipsaw kill must win over
      any basket logic on the same tick.
- [ ] **Restart mid-trailing (demo chart, optional):** with trailing active, re-attach the EA →
      recovery keeps ACTIVE and the floor (check `SIGMA.Hydra.XAUUSD-VIP.trail_floor` in F3).

## 3. Report back

Send the `[HYDRA]` grep output (same command as before) + the `Hydra_0*.htm` reports.
On pass: I bump to v2.0, commit `Phase 6 complete`, and proceed to **Phase 7 — the full
3-month validation campaign** (you'll need tick history for ~3 months incl. one NFP + one
FOMC day) and then **Phase 8 — dashboard panel**.

## Upcoming (for awareness)

| When | Task |
|---|---|
| Phase 7 | 3-month real-tick backtest incl. NFP + FOMC; spread-stress rerun; test report review |
| Phase 8 done | Dashboard visual checks on a live chart (collapse, colors, rows) |
| Pre-live | 1-week demo soak with `AUTO_TRADING_ENABLED=true` (final checklist in `docs/CHECKLIST.md`) |
