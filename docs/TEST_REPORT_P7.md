# TEST_REPORT_P7.md — Phase 7 Strategy Tester Validation Campaign

> Companion evidence for `docs/CHECKLIST.md` §Phase 7.
> Build under test: `Straddle_Grid.mq5` **v2.0** (Phases 1–6 complete).
> Environment: MT5 (VT Markets, VTMarkets-Demo), XAUUSD-VIP, M1, "Every tick based on real
> ticks" (`Model=4`), hedging account, deposit $10,000.
> Run date: 2026-07-15.

## Run 05 — 3-month campaign

**Config:** `tools/strategy-tester/configs/hydra_05_phase7_campaign.ini` /
`presets/hydra_05_phase7_campaign.set` — full production defaults, nothing weakened.
**Range:** `2026.04.01`–`2026.07.10` (deinit recorded at `2026.07.09 23:57:59`, i.e. the
full requested range was processed). ~14 weeks — long enough to almost certainly span
multiple NFP days (first Friday of each month) and at least one FOMC day (meets roughly
every 6 weeks), though specific calendar dates were not independently cross-checked against
a real economic calendar; this is a reasonable-confidence inference from window length, not
a verified fact.

**Evidence (from the raw `[HYDRA]` tester journal, cross-checked line-count by line-count):**

| Check | Result |
|---|---|
| Grid deployments (`state ... -> ARMED`) | 484 |
| Full 9+9 grids (`9+9 stops` in the deploy line) | 484 — **matches deployments exactly, zero partial grids** |
| First fills / `ACTIVE` entries | 484 — **matches deployments exactly**, i.e. every single grid within this ~45 min TTL window eventually got at least one fill |
| `grid TTL ... expired with zero fills` | 0 |
| Basket exits (`BASKET EXIT`) | 484 — **matches ACTIVE entries exactly, zero orphaned baskets** |
| — of which basket TP | 33 |
| — of which basket SL | 288 |
| — of which trail floor hit | 163 |
| `post-exit cooldown until ...` lines | 484 |
| `COOLDOWN -> IDLE (cooldown expired)` lines | 484 — **matches exactly, zero stuck cooldowns** |
| Whipsaw firings | 0 — expected under default `OCO_Mode=true` (opposite side cancelled within seconds of first fill); whipsaw mechanics themselves are proven separately (see Run 04, §Known gaps below) |
| `invalid stops` / `error` / `exception` in journal (excluding expected `gates FAIL` lines) | 0 |
| Init/recovery | Exactly one `SIGMA Hydra v2.0 initializing` + one `state IDLE -> IDLE (recovery: clean slate)`, both at `2026.04.01 00:00:00` — clean single init, no mid-run restart artifacts |
| `deinit` | Exactly one, `state=IDLE`, at the range boundary — EA ended cleanly, not stuck mid-cycle |

**P/L / trade-count summary:** not extracted from the `.htm` report in this pass (report
exists at `Hydra_05_phase7_campaign.htm` on the tester machine but its net-profit/
profit-factor summary wasn't pulled into this document). Exit-type mix (7% TP, 59% SL, 34%
trail-floor) is consistent with expectations for a stop-order grid: rare clean quick wins,
frequent early reversals absorbed by SL, and trailing capturing the larger extended moves.

**Verdict: PASS.** No partial grids, no orphaned baskets/cooldowns, no journal errors, clean
single init and clean deinit, full range processed.

## Run 06 — spread stress

**Config:** `tools/strategy-tester/configs/hydra_06_spread_stress.ini` /
`presets/hydra_06_spread_stress.set` — production defaults with `MaxSpreadPoints=1`.
**Range:** `2026.06.01`–`2026.07.10` (~6 weeks).

**Note on methodology:** the first attempt at this test used MT5's tester-level
`[Tester] Spread=40` override to force a fixed elevated spread. That override was silently
ignored by this MT5 build — the run traded normally (1224 fills, 180 baskets, 0 gate-3
failures) instead of being blocked, proving nothing about gate 3's behavior under stress.
The test was corrected to force the block from the EA-input side instead
(`MaxSpreadPoints=1`, below any real XAUUSD-VIP spread), which is reliable regardless of
tester-engine spread-override support and still exercises exactly the intended code path
(gate 3's direct `current spread > MaxSpreadPoints` check).

**Evidence:**

| Check | Result |
|---|---|
| Fills | 0 |
| `ARMED` / `ACTIVE` transitions | 0 |
| `BASKET EXIT` | 0 |
| `gates FAIL - gate 3 (Spread)` | 62, every one showing real spread (29–30 pts) `> max 1` |
| Gate 1 (Session) / Gate 2 (Volatility) failures interleaved | 59 / 10 — expected short-circuit behavior on ticks that never reached gate 3 |
| `invalid stops` / `error` / `exception` | 0 |
| `deinit` | Clean, `state=IDLE`, at the range boundary |

**Verdict: PASS.** Gate 3 blocked every single deployment attempt for the entire window,
using real historical spread data, with zero orders ever placed and zero errors.

## §11 explicit test cases — status

| Case | Status |
|---|---|
| Whipsaw candle piercing both sides in one bar | **Proven** (run 04, 4 firings, correct gap math/cooldowns/daily counter) — but last run on the **v1.9** binary, before the v2.0 Basket Manager bump. Phase 6 touched only basket-management code, not `CheckWhipsawGuard()`, so this should still hold, but a formal rerun on v2.0 was deferred by user decision (2026-07-15) rather than re-verified in this pass. |
| Terminal restart during `ACTIVE`, no duplicate grid | **Deferred.** Needs a live/demo chart restart, not a backtest — not exercised in Phase 7. General restart-recovery mechanics were part of the Phase 1/4 build (state reconstruction from existing orders/positions in `OnInit`), but a Phase-7-specific mid-`ACTIVE` restart rerun on the current build was not performed. |
| Stops-level rejection at deploy → clean abort | **Deferred.** Current defaults never naturally trigger this path — gate 3's own spacing validation (`GridSpacingUSD ≥ stops + spread + buffer`) already prevents an invalid deploy from being attempted under any of the tested configs. Forcing it would need a dedicated preset with a deliberately-too-tight `GridSpacingUSD`; not built in this pass. |
| Trailing floor hit during a retrace, all positions/pendings closed | **Proven** — 163 `trail floor hit` exits in run 05 alone, consistent with the exact-math validation already done in the Phase 6 basket-manager pass. |

## Outstanding before Phase 7 can be marked fully closed per `docs/CHECKLIST.md`

- [ ] Restart mid-`ACTIVE` simulation (live/demo chart or tester re-init) with zero
      orphaned orders after restart.
- [ ] Whipsaw guard reconfirmed specifically on the v2.0 binary (low risk, not yet done).
- [ ] Stops-level-rejection forced test (needs a new preset/config).
- [ ] Foreign-orders-untouched check — not independently exercised; backtests start from a
      clean simulated account by construction, so this is more relevant to the live/demo
      pre-deploy checklist than to Phase 7's tester runs.
- [ ] Full P/L/profit-factor summary pulled from the `.htm` reports into this document.

These are tracked, explicitly deferred items rather than unknowns — the core Phase 7
deliverables (3-month campaign, spread stress) both passed cleanly.
