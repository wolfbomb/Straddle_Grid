# OPT_REPORT.md — P/L attack: basket-exit parameter sweep

> Companion to `docs/TEST_REPORT_P7.md` §Run 05, which flagged the strategy as net
> negative at production defaults (−$1,770 / PF 0.95 / eqDD 36.6% over 3 months).
> Run date: 2026-07-17. Build: v2.1.

## Sweep 01 — basket exits, 625 combinations (complete search)

**Config:** `tools/strategy-tester/configs/opt/hydra_opt_01_exits.ini`, launched via
`run_opt.sh`. Window `2026.04.01`–`2026.07.10` (same as run 05), **Model=1 (M1 OHLC)** —
a deliberate speed/accuracy trade-off; see caveats. Grid: `BasketTP_USD` ∈ {10,15,20,25,30},
`BasketSL_USD` ∈ {6,8,10,12,14}, `TrailActivate_USD` ∈ {4,6,8,10,12},
`TrailDistance_USD` ∈ {2,3,4,5,6}. Everything else at production defaults.
Full sorted results: `docs/opt/hydra_opt_01_exits_all625.csv`.

**Headline numbers:**

| Stat | Value |
|---|---|
| Profitable combinations | **18 / 625** (2.9%) |
| Median pass | **−$3,228** (worse than the current defaults) |
| Best pass | **+$1,673** (+16.7%), PF 1.16, Sharpe 5.68, eqDD 20.5%, 1,674 trades |
| Worst pass | −$6,723, PF 0.55, eqDD 72.6% |

**Best combinations (OHLC model):**

| TP | SL | TrailAct | TrailDist | Profit | PF | eqDD % |
|---|---|---|---|---|---|---|
| 10 | 6 | 8 | 4 | +1,673 | 1.16 | 20.5 |
| 10 | 6 | 8 | 5 | +1,371 | 1.14 | 22.2 |
| 10 | 6 | ≥10 | any | +564 | 1.05 | 24.8 |

**Reading the surface:**
- Every profitable pass has `TP=10` and `SL=6` — both the **minimum values tested**. The
  optimum plausibly lies outside the grid (even tighter exits); a follow-up sweep over
  TP ∈ [4..12], SL ∈ [3..8] is the obvious next probe.
- Tight SL is the main lever: the loss distribution is dominated by baskets that reverse
  early; cutting them at $6-scaled instead of $10-scaled flips the sign.
- `TrailActivate=8 < TP=10` matters: rows where trailing activates at/after TP (≥10) all
  collapse into the same weaker result (+564) because trailing effectively never engages.
- The surface is **fragile**: 97% of the space loses money, and the profitable island is
  small. This is not yet a robust edge — treat it as a direction, not an answer.

## Caveats (read before acting)

1. **Model risk:** the sweep ran on M1-OHLC (≈4 ticks/bar). With $6-scaled basket SLs,
   intrabar path approximation materially flatters/distorts results — real-tick
   validation below is the number that counts.
2. **Single-window overfit:** one 3.5-month window, one symbol, parameters chosen at the
   grid edge. Before trusting any set: real-tick validation (done below), an
   out-of-sample window (e.g. `2026.01.01`–`2026.03.31`), and ideally a forward/demo soak.
3. Session/spacing/progression were **not** swept here — they are the next dimensions if
   exits alone can't produce a robust edge.

## Real-tick validation (Model=4, same window) — FAILED

| Candidate | OHLC sweep | Real ticks | Verdict |
|---|---|---|---|
| A: TP10 / SL6 / TA8 / TD4 | +1,673, PF 1.16, eqDD 20.5%, 1,674 trades | **−5,496, PF 0.84, eqDD 67.5%, 3,868 trades** | **REJECTED** |
| B: TP10 / SL6 / TA8 / TD5 | +1,371, PF 1.14, eqDD 22.2% | **−5,646, PF 0.84, eqDD 72.1%, 3,973 trades** | **REJECTED** |

Both winners are **worse than the production defaults** (−1,770 / PF 0.95 / eqDD 36.6%)
when the intrabar path is real. The trade count more than doubling (1,674 → 3,868) tells
the story: on real ticks the tight $6-scaled basket SL is hit constantly by intrabar
noise the 4-tick OHLC model simply doesn't contain. The sweep's entire profitable island
was a **model artifact**, and caveat #1 above was not hypothetical.

## Conclusions (2026-07-17)

1. **Exit tuning cannot fix this strategy.** The full 625-point exit surface contains no
   real-tick-valid profitable region: median −$3,228, best candidates collapse to
   PF 0.84 under real execution, and looser exits were already tested by run 05's
   defaults (PF 0.95). The loss source is upstream of the exits.
2. **OHLC-model sweeps are unusable for this EA.** Basket exits scaled in single-digit
   dollars live entirely inside intrabar noise. Any future optimization must run
   Model=4 real ticks (smaller grids, longer runs — budget accordingly).
3. The productive dimensions to attack next are **entry-side**: session windows (when do
   displacement moves actually pay?), the ATR band, `GridSpacingUSD` /
   `FirstLevelOffsetUSD` geometry, and the lot progression. That is strategy rework, not
   parameter polish — a user-level decision on direction before more compute is spent.

## Recommended next steps (user decision)

1. Direct a **real-tick, entry-side** exploration (sessions × spacing, coarse grid) — the
   scaffolding (`run_opt.sh`, `configs/opt/`) is ready; each real-tick pass over the
   3-month window costs a few minutes.
2. Or pause optimization and reconsider the strategy concept itself (e.g. news-window
   deployment only, as originally envisioned in CLAUDE.md §2's displacement thesis, vs.
   the current always-on session windows).
3. Live deployment remains **blocked** either way — nothing tested so far beats "don't
   trade" on this window.
