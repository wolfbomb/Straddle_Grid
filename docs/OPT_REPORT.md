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

## Sweep 02 — entry-side (session windows x GridSpacingUSD), REAL TICKS (2026-07-18)

Following directly from the recommendation above: since MT5's native optimizer can't
sweep string inputs (`Session1`/`Session2`), this ran as 9 independent real-tick single
passes via `tools/strategy-tester/entry_sweep.py` (Model=4, same window
`2026.04.01`–`2026.07.10` as run 05) — no OHLC-model shortcut this time, every number
below is real-tick from the start. `entry_ctrl_sp070` (current production settings) is
the control and reproduces run 05 exactly (−1,770.44 / PF 0.95 / eqDD 36.59%), confirming
the harness is sound.

| Session window | Spacing | Profit | PF | eqDD % | Trades |
|---|---|---|---|---|---|
| current (3h/3h) | 0.70 (ctrl) | **−1,770.44** | 0.95 | 36.6 | 3,290 |
| current (3h/3h) | 1.00 | **−1,604.85** | 0.95 | 35.5 | 3,042 |
| current (3h/3h) | 1.40 | −5,227.29 | 0.78 | 59.0 | 2,156 |
| narrow (1h/1h) | 0.70 | −4,337.58 | 0.74 | 53.3 | 1,352 |
| narrow (1h/1h) | 1.00 | −2,935.57 | 0.80 | 37.5 | 1,273 |
| narrow (1h/1h) | 1.40 | −3,954.61 | 0.67 | 41.8 | 1,027 |
| open30 (30m/30m) | 0.70 | −2,688.77 | 0.80 | 37.1 | 1,125 |
| open30 (30m/30m) | 1.00 | −2,627.72 | 0.77 | 32.5 | 977 |
| open30 (30m/30m) | 1.40 | −3,708.82 | 0.60 | 41.9 | 777 |

Full data: `docs/opt/entry_sweep_results.csv`.

**Verdict: every single combination lost money.** The least-bad result
(`entry_ctrl_sp100`, current sessions + slightly wider spacing) is only marginally better
than production defaults and still clearly unprofitable (PF 0.95). Two findings stand
out:

1. **Narrowing the session window made things systematically worse, not better** — the
   opposite of the "less chop exposure = better" intuition. Fewer trades under a
   negative-edge system just means higher variance per trade (see the jump in eqDD% at
   low trade counts), not a cleaner signal. This is evidence *against* the idea that the
   loss is caused by trading too much low-quality time — the edge problem is present
   throughout the window, not concentrated in a chop-heavy sub-segment these particular
   cuts happened to isolate.
2. **Wider spacing (1.40) was uniformly worse** across all three session variants —
   PF dropped and eqDD spiked every time. Spacing narrower than production (already
   floored by gate 3's stops/spread requirement, ~0.60–0.65) wasn't testable here.

## News-day probe (NFP only, n=4) — proof of concept, REAL TICKS (2026-07-18)

Before committing to a full news-calendar-gated rework (new EA input schema, a new gate,
its own validation campaign), tested the underlying hypothesis directly and cheaply: does
Hydra actually have edge on **known high-impact days**, independent of the always-on
session-window trigger that just failed 18/18 times?

**Method:** `Session1`/`Session2` are time-of-day only — the EA has no calendar-date
concept, so isolating specific days means running short, independent backtests whose
`FromDate`/`ToDate` bracket just one event day (no EA code change). Scope: **NFP only**
(first Friday of the month) — the one category of "known high-impact day" computable by
pure calendar rule for this window; real FOMC meeting dates for this fictional 2026
aren't independently verifiable and are **not** included (same caveat as run 05's
NFP/FOMC note). Each probe: production defaults unchanged, 3-day window (day before
through day after the NFP Friday), one independent real-tick pass.

| NFP date | Profit | PF | eqDD | Trades |
|---|---|---|---|---|
| 2026.04.03 | −442.94 | 0.39 | 4.43% | 51 |
| 2026.05.01 | **+404.29** | **1.41** | 4.19% | 126 |
| 2026.06.05 | **+167.25** | **1.16** | 6.98% | 93 |
| 2026.07.03 | −656.54 | 0.00 | 6.60% | 28 |

Full data: `docs/opt/news_day_probe_results.csv`. Aggregate across all 4: **−527.94**,
still net negative — but **2 of 4 individual days were genuinely profitable** (PF 1.41,
1.16), a hit rate the two systematic sweeps never produced once across 18 configurations.

**Honest read: inconclusive, not a finding.** n=4 is anecdotal — a coin-flip pattern with
two good and two bad outcomes proves nothing statistically on its own, and the aggregate
is still negative. What it *does* show is that the day-to-day variance on known
high-impact days looks qualitatively different from the uniform failure seen everywhere
else tested. That's a reason to look further, not a reason to build the full gate yet.

## Multi-year NFP/FOMC probe (n=37), REAL TICKS (2026-07-18)

The n=4 NFP pilot above was too small to trust — extended the same method (short
independent real-tick backtests bracketing one event day, no EA code change) to a much
bigger sample via `tools/strategy-tester/news_day_probe_multiyear.py`: every NFP Friday
and FOMC decision day from **2024.03 through 2025.12** (production defaults, unchanged).

**Hard constraint discovered:** real tick history for XAUUSD-VIP on this account only
goes back to **2024.02.20** — 2023 and early 2024 are simply unavailable, capping how far
back this method can reach. 3 dates were auto-skipped for predating this; 37 ran.

⚠ **FOMC dates are recalled from the published Federal Reserve schedule for 2024–2025,
not independently re-verified against an official source in this session** — same
caveat class as the NFP/FOMC inclusion note in run 05. Cross-check against
federalreserve.gov before treating these as ground truth for any real decision. NFP
dates are exact (first Friday of the month, pure calendar rule).

Full data: `docs/opt/news_day_probe_multiyear_results.csv`.

| Category | n | Wins | Win rate | Total | Mean/day |
|---|---|---|---|---|---|
| NFP | 22 | 8 | 36% | **−1,752.05** | −79.64 |
| FOMC | 15 | 8 | 53% | **−44.95** | −3.00 |
| **Combined** | **37** | **16** | **43%** | **−1,797.00** | −48.57 |

**The NFP "hint" from the n=4 pilot did not survive a bigger sample — it reversed.**
Win rate dropped from 50% (2/4) to 36% (8/22), and the aggregate is solidly negative
(−$1,752 over 22 real days, a similar magnitude of damage per unit time to the always-on
sweeps). This is worth stating plainly as a lesson from this whole campaign: a 4-point
sample said "maybe," a 22-point sample said "no." Small samples in this kind of testing
are not just imprecise, they can point the wrong direction entirely.

**FOMC looks genuinely different, but is not a validated edge.** Near-breakeven in
aggregate (mean −$3/day, essentially flat, not clearly losing like everything else
tested), and a 53% win rate — the best hit rate found anywhere in this entire campaign.
However: excluding the single worst day (2025.10.29, −$813.50) flips the remaining 14
days solidly positive (total +$768.55, mean +$54.90/day) — meaning the near-breakeven
result is **fragile to one outlier**, and "the result looks good if I drop the worst
day" is exactly the kind of post-hoc exclusion that should raise suspicion, not
confidence, on n=15. This is a lead worth a narrow follow-up, not a result worth acting
on directly.

## FOMC-only exit sweep (n=15 days x 16 combos), REAL TICKS THROUGHOUT (2026-07-18)

Direct follow-up to the recommendation above: does tuning `BasketTP_USD`/`BasketSL_USD`
*specifically for FOMC-day volatility* find anything, given every exit sweep so far
assumed the always-on trigger? Unlike Sweep 01 (OHLC model, needed real-tick
re-validation), every probe here is already Model=4 real ticks — no shortcut-model risk.

**Method** (`tools/strategy-tester/fomc_exit_sweep.py`): for each of 16
(`BasketTP_USD`, `BasketSL_USD`) combinations — `TP` ∈ {10,15,20,25}, `SL` ∈ {6,8,10,12},
`TrailActivate_USD`/`TrailDistance_USD` held at production defaults (8.0/4.0) to keep
runtime manageable — ran one short real-tick probe per FOMC day (the same 15-day sample
from the multi-year probe above), then combined properly: net profit summed directly
across the 15 days, and profit factor recomputed from **summed Gross Profit ÷ summed
|Gross Loss|** across all 15 days — not an average of 15 separate ratios, which would be
statistically wrong for a ratio metric. (`TP=15/SL=10` is the production default and
reproduces the multi-year probe's FOMC aggregate exactly: −44.95 — a useful consistency
check that the harness is sound.)

| TP | SL | Total profit | Combined PF | Trades |
|---|---|---|---|---|
| **20** | **10** | **+879.71** | **1.256** | 374 |
| 20 | 8 | +535.32 | 1.118 | 501 |
| 25 | 10 | +413.46 | 1.112 | 383 |
| 25 | 8 | +165.25 | 1.035 | 511 |
| 10 | 12 | +120.37 | 1.028 | 404 |
| 20 | 12 | +29.47 | 1.006 | 413 |
| 15 | 10 | −44.95 | 0.988 | 394 |
| 10 | 8 | −152.32 | 0.967 | 536 |
| 25 | 12 | −223.26 | 0.954 | 411 |
| 10 | 10 | −230.36 | 0.938 | 401 |
| 15 | 8 | −558.79 | 0.891 | 520 |
| 15 | 12 | −767.97 | 0.844 | 393 |
| 20 | 6 | −1568.23 | 0.730 | 667 |
| 10 | 6 | −1623.78 | 0.727 | 725 |
| 15 | 6 | −2123.38 | 0.638 | 673 |
| 25 | 6 | −2147.53 | 0.648 | 685 |

Full data: `docs/opt/fomc_exit_sweep_results.csv`.

**This is the most credible result of the entire campaign — and it's still not enough to
act on.** Two things distinguish it from every earlier "winner" that later collapsed:

1. **A coherent neighborhood, not an isolated spike.** All four `SL=6` combos are
   uniformly disastrous (−1568 to −2148 — a tight stop gets whipsawed by
   pre-announcement noise before the real move develops), while `TP∈{20,25} × SL∈{8,10}`
   forms a contiguous block of 4 positive results. Real effects tend to vary smoothly
   across nearby parameters; noise-driven "winners" tend to be isolated. This is the
   former pattern, which the OHLC exit sweep's winner (Sweep 01) was not.
2. **No OHLC-model risk** — every number above is real-tick from the start, so there's
   no separate validation step left to fail it the way Sweep 01's winners failed.

**But — the caveats that keep this from being a finding:**

- **Every FOMC day this account's real-tick history contains (15 of them) was already
  used to pick the winner.** There is no held-out historical data left to confirm
  against — the multiple-comparisons risk (best of 16 combinations) can't be checked
  the normal way here. The NFP result inverting between n=4 and n=22 earlier in this
  same campaign is a direct demonstration of how fragile small-sample "winners" can be,
  and n=15 FOMC days is not a large sample either.
- **This isn't deployable as-is.** `Session1`/`Session2` are time-of-day only — the EA
  cannot gate on specific calendar dates today. Actually running "FOMC-only, TP=20/SL=10"
  live or on demo would require real EA development (a calendar-aware gate + its own
  validation), not just a config change.
- FOMC dates are recalled, not independently re-verified (see multi-year probe caveat
  above).

## Recommended next steps (user decision)

Five independent real-tick attacks now: 625 exit combos (Sweep 01, OHLC + re-validated),
9 entry combos (Sweep 02), 4-day NFP pilot, 37-day NFP+FOMC sample, 16-combo FOMC-only
exit sweep. The always-on trigger is thoroughly exhausted (zero winners across 18+37
configurations). The FOMC-only exit sweep produced the one genuinely credible positive
pattern in the whole campaign — but it's built on a fully-mined 15-day sample with
nothing held out to confirm it against.

1. **The only real test left is prospective, not retrospective:** if there's appetite to
   pursue this further, the responsible next step is tracking `BasketTP_USD=20,
   BasketSL_USD=10` (FOMC days only) against upcoming *real* FOMC meetings going
   forward — on demo, not live — since every historical FOMC day available has already
   been used to find this combination. That requires building the calendar-aware gate
   first (a real EA change, its own spec update and validation), not just re-running a
   backtest.
2. **Otherwise:** the honest bottom line is that the always-on-trigger version of this
   EA has no validated profitable edge on XAUUSD-VIP over the ~16 months of available
   history, and the one promising lead (FOMC-only) needs real forward-testing time to
   confirm or refute — it cannot be validated further by looking backward.
3. Remaining un-swept knobs (lot progression, `GridLevels`, `ATR_Min/Max_USD` band,
   `GridTTLMin`) are still untested but low-priority given everything above.
4. Live deployment remains **blocked** regardless — nothing tested so far beats "don't
   trade" with the kind of confidence that survives scrutiny.

1. **Before any code investment:** extend the news-day probe to a much larger sample —
   pull NFP (and, if a reliable source is available, FOMC) dates across 2–3 years of
   history instead of 4 days in one quarter, and re-run the same cheap per-day backtest
   method. This is still just picking date ranges, no EA changes, and would turn "2 of 4"
   into a number worth trusting either way.
2. **If that larger sample holds up profitable:** then the calendar-gated rework (new
   EA input schema, dedicated gate, full Phase-7-style validation) is justified.
3. **If it doesn't:** that's a strong signal the grid-on-displacement concept itself
   doesn't have edge on this instrument/period, independent of trigger mechanism —
   the more valuable conversation becomes whether to keep iterating on this EA at all.
4. Remaining un-swept knobs (lot progression, `GridLevels`, `ATR_Min/Max_USD` band,
   `GridTTLMin`) are still untested but low-priority given how uniformly negative both
   swept dimensions were.
5. Live deployment remains **blocked** — nothing tested so far, across any of the three
   probes, beats "don't trade" with statistical confidence.
