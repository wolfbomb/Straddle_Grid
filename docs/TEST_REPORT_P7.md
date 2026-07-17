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

**P/L / trade-count summary** (extracted from `Hydra_05_phase7_campaign.htm`, 2026-07-17;
history quality 100% real ticks, 97,197 bars / 46,537,448 ticks):

| Metric | Value |
|---|---|
| Total Net Profit | **−$1,770.44** (on $10,000 deposit, −17.7%) |
| Gross Profit / Gross Loss | $34,664.81 / −$36,435.25 |
| Profit Factor | **0.95** |
| Expected Payoff | −$0.54 per trade |
| Balance Drawdown Maximal | $4,169.77 (35.23%) |
| Equity Drawdown Maximal | $4,356.82 (36.59%) |
| Recovery Factor / Sharpe | −0.41 / −1.87 |
| Total Trades (deals) | 3,290 (6,580) — 1,641 long (52.22% won), 1,649 short (49.79% won) |
| Profit / Loss trades | 1,678 (51.00%) / 1,612 (49.00%) |
| Largest profit / loss trade | $70.25 / −$69.45 |

⚠ **Interpretation (important):** Phase 7's pass criteria are *mechanical* — no partial
grids, no orphaned baskets, no journal errors — and those all passed. But on this 3-month
window the strategy at production defaults was **net negative** (PF 0.95, −17.7%) with a
~36% max equity drawdown. The exit mix (7% TP, 59% SL, 34% trail-floor) shows losses from
frequent early reversals slightly outweighing what trailing captured on extended moves.
This is a parameter/edge problem, not a code-correctness problem, and it must be addressed
(session/gate tightening, exit tuning, or spacing/progression rework + re-test) **before
any live deployment** — see `docs/CHECKLIST.md` Final Pre-Deploy section. Exit-type mix
itself is consistent with expectations for a stop-order grid: rare clean quick wins,
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
(`.htm` report cross-check, 2026-07-17: Total Net Profit $0.00, Total Trades 0 — confirms
the journal evidence from the account side.)

## Run 04 (re-run) — whipsaw guard on the v2.0 binary (2026-07-17)

**Config:** unchanged `hydra_04_whipsaw_guard.ini` / `.set`; binary recompiled from the
current source (post-Phase-8 dashboard code) with 0 errors / 0 warnings.
**Range:** `2026.07.02`–`2026.07.04`.

| Check | Result |
|---|---|
| Whipsaw firings | 4 — identical pattern to the v1.9 baseline (2 on 07-02, 2 on 07-03) |
| Gap math | 627 s / 8 s / 35 s / 90 s, all ≤ test window 3600 s, logged explicitly |
| Daily counter / lockout | 1/2 then 2/2 on both days; 2/2 → `COOLDOWN` until next trading day, both times |
| Counter reset | `whipsaw counter reset for the new trading day` at 07-03 01:00:06 |
| deinit | Clean, `state=COOLDOWN` (correct — range ends inside the 07-03 daily lockout) |

**Verdict: PASS.** The deferred "reconfirm whipsaw on v2.0" item is closed — guard behavior
is bit-for-bit consistent with the v1.9 validation.

## Run 07 — stops-level rejection at deploy (2026-07-17)

**Config:** `tools/strategy-tester/configs/hydra_07_stops_rejection.ini` /
`presets/hydra_07_stops_rejection.set` — production defaults except test-only
`FirstLevelOffsetUSD=0.10`. Gate 3 only validates `GridSpacingUSD` (0.70, untouched), so
all five gates pass — but buy level 0 lands at mid+0.10 ≈ ask−0.05, inside the 20-pt
`SYMBOL_TRADE_STOPS_LEVEL` distance, forcing `DeployGrid()`'s pre-flight abort every time.
**Range:** `2026.07.09`–`2026.07.10`.

| Check | Result |
|---|---|
| `deployment ABORTED — buy level 0 ... violates min distance` | 19,868 lines — every in-session deploy attempt, level price / ask / min-distance all logged and arithmetically correct (e.g. `buy level 0 @ 4064.32` vs `ask 4064.37 + stops/freeze 0.20`) |
| `IDLE -> ARMED` transitions | 0 for the whole run |
| Orders placed / fills | 0 — abort happens in pre-flight, before any `OrderSend` |
| `invalid stops` broker errors | 0 (the point of pre-flight validation: the broker never sees an invalid order) |
| deinit | Clean, `state=IDLE` |

**Verdict: PASS.** The abort-entire-deployment path (CLAUDE.md §7 "no partial grids") is
proven: gates green, every deployment attempt cleanly refused pre-send, zero residue.

## Dashboard self-test note (2026-07-17)

The `run_tests.sh` `Dashboard self-test: PASS` line from this session was initially
unreliable: MT5 tester logs on this build are **UTF-16LE**, and the script's plain `grep`
scan read 0 matches from any of them — it would have printed PASS even with real failures.
Fixed in `run_tests.sh` (`count_in_log()`: BOM detection + iconv/PowerShell decode;
undecodable logs now report INCONCLUSIVE, never PASS). Re-verified against the raw journal
with a UTF-16-aware search: the read-back guard ran on every tick of all three runs
(hydra_02/04/07) with genuinely **0 `[DASH-FAIL]` lines**, and a positive-control pattern
counted exactly (19,868) through the same decode path.

## §11 explicit test cases — status

| Case | Status |
|---|---|
| Whipsaw candle piercing both sides in one bar | **Proven on v2.0** (run 04 re-run 2026-07-17: 4 firings, correct gap math/cooldowns/daily counter, identical to the v1.9 baseline — see §Run 04 re-run above). |
| Terminal restart during `ACTIVE`, no duplicate grid | **Deferred.** Needs a live/demo chart restart, not a backtest — not exercised in Phase 7. General restart-recovery mechanics were part of the Phase 1/4 build (state reconstruction from existing orders/positions in `OnInit`), but a Phase-7-specific mid-`ACTIVE` restart rerun on the current build was not performed. |
| Stops-level rejection at deploy → clean abort | **Proven** (run 07, 2026-07-17: forced via test-only `FirstLevelOffsetUSD=0.10` since gate 3 pre-validates spacing but not the first-level offset; 19,868 clean pre-send aborts, zero orders, zero broker errors — see §Run 07 above). |
| Trailing floor hit during a retrace, all positions/pendings closed | **Proven** — 163 `trail floor hit` exits in run 05 alone, consistent with the exact-math validation already done in the Phase 6 basket-manager pass. |

## Outstanding before Phase 7 can be marked fully closed per `docs/CHECKLIST.md`

- [ ] Restart mid-`ACTIVE` simulation (live/demo chart or tester re-init) with zero
      orphaned orders after restart.
- [x] Whipsaw guard reconfirmed specifically on the v2.0 binary (done 2026-07-17, run 04
      re-run — identical to v1.9 baseline).
- [x] Stops-level-rejection forced test (done 2026-07-17, run 07 — clean abort proven,
      zero orders).
- [ ] Foreign-orders-untouched check — not independently exercised; backtests start from a
      clean simulated account by construction, so this is more relevant to the live/demo
      pre-deploy checklist than to Phase 7's tester runs.
- [x] Full P/L/profit-factor summary pulled from the `.htm` reports into this document
      (done 2026-07-17 — see Run 05 summary table above; **flags a profitability problem
      that must be resolved before live**, separate from the mechanical pass).

These are tracked, explicitly deferred items rather than unknowns — the core Phase 7
deliverables (3-month campaign, spread stress) both passed cleanly.
