# BTC_OPT_REPORT.md — Hydra BTCUSD optimization campaign

> Companion to the BTCUSD viability check (2026-07-19, prior session) and
> `tools/strategy-tester/presets/hydra_15_btcusd_smoke.set` (first-pass, mechanically
> derived BTCUSD geometry — `GridSpacingUSD=45`, `FirstLevelOffsetUSD=35`,
> `ATR_Min/Max_USD=40/250`, `MaxSpreadPoints=3000`). Run date: 2026-07-19. Build: v2.3.
> Follows the same discipline `OPT_REPORT.md` established for XAUUSD-VIP: **real ticks
> only (`Model=4`), no OHLC-model shortcuts, every candidate held to out-of-sample
> validation before it counts as a finding.**

## Data constraint

BTCUSD real tick history on this account only goes back to **2026.01.01** (~6.5
months, vs XAUUSD-VIP's ~16 months). Split up front, before any sweep ran, so every
"winner" would face genuinely unseen data:

- **Training window:** `2026.02.01`–`2026.06.01` (4 months) — both sweeps below.
- **Held-out validation window:** `2026.06.01`–`2026.07.18` (~6.5 weeks) — touched only
  by the 4 single-pass validation runs, never by either sweep.

This is stricter than the original XAUUSD-VIP campaign, which had no true held-out set
(a caveat that report flagged explicitly on its FOMC-only sweep). Every BTC candidate
below was tested against data the sweep that produced it never saw.

## Sweep 1 — basket exits, 25 combinations (complete search, real ticks from the start)

**Config:** `tools/strategy-tester/configs/opt/hydra_opt_04_btcusd_exits.ini`, launched
via `run_opt.sh`. **Model=4 real ticks throughout** — no OHLC shortcut, unlike
`OPT_REPORT.md` Sweep 01 (that shortcut is what produced a winner that later collapsed
from +$1,673 to -$5,496 under real-tick re-validation for gold; not repeated here).
Grid: `BasketTP_USD` ∈ {3,6,9,12,15}, `BasketSL_USD` ∈ {2,4,6,8,10}.
`TrailActivate_USD`/`TrailDistance_USD` held fixed at the smoke-test preset's values
(3.0/1.5) to keep the grid 2D. Everything else at the `hydra_15_btcusd_smoke.set`
first-pass BTCUSD geometry. Full sorted results: `docs/opt/btc_opt_04_exits_all25.csv`.

**Full grid (Profit, TP → columns, SL → rows):**

| SL \ TP | 3 | 6 | 9 | 12 | 15 |
|---|---|---|---|---|---|
| 2 | -548.45 | **+379.80** | +147.59 | +69.65 | +54.65 |
| 4 | -688.01 | -1767.54 | -1508.52 | -1386.66 | -1377.49 |
| 6 | -778.19 | -915.43 | -1590.20 | -1288.31 | -1305.06 |
| 8 | **+487.67** | -412.63 | -855.95 | -1017.46 | -1033.80 |
| 10 | -522.97 | -1035.81 | -988.31 | -875.37 | -876.71 |

**Reading the surface:**
- The raw argmax, **TP=3/SL=8 (+$487.67, PF 1.086)**, is an **isolated spike** — every
  neighbor around it (TP=3/SL=6, TP=3/SL=10, TP=6/SL=8) is solidly negative. No
  coherent block.
- The **SL=2 row** is different in kind: profitable across **all four** other TP
  values tested (TP=6,9,12,15), forming a smooth, interpretable decreasing-profit
  curve as TP widens, backed by high trade counts (3448–3703) — a real, coherent
  pattern, best at **TP=6/SL=2 (+$379.80, PF 1.046)**.
- Everything outside SL∈{2,8} is uniformly and often severely negative (worst:
  -$1,767.54).

### Out-of-sample validation (held-out window)

| Candidate | Training | Held-out | Verdict |
|---|---|---|---|
| A: TP=3/SL=8 (isolated spike) | +487.67, PF 1.086 | **-48.56, PF 0.97, Sharpe -0.36** | **REJECTED** — sign flipped, confirms noise |
| B: TP=6/SL=2 (coherent row) | +379.80, PF 1.046 | **+26.46, PF 1.01, Sharpe 0.22** | Survives, but weak — near-breakeven |

The flagged-as-noise candidate was noise. The coherent candidate held its sign but is
not a real edge on its own (PF 1.01, Sharpe ≈ 0).

## Sweep 2 — entry-side, 12 combinations (real ticks, sequential single passes)

**Method:** `tools/strategy-tester/entry_sweep_btc.py` (native MT5 optimizer can't
sweep the string-typed `Session1`/`Session2` inputs — same reason `OPT_REPORT.md`'s
Sweep 02 used a custom driver). Exits fixed at Sweep 1's validated candidate B
(TP=6/SL=2). Grid: 4 session variants × `GridSpacingUSD` ∈ {40,45,60}. Full data:
`docs/opt/btc_entry_sweep_results.csv`.

| Session | Spacing | Profit | PF | eqDD % | Trades |
|---|---|---|---|---|---|
| ctrl (07-10h/12-15h, current default) | 40 | -734.86 | 0.92 | 14.85 | 3733 |
| ctrl | 45 (control — reproduces Sweep 1's B exactly) | +379.80 | 1.05 | 7.16 | 3500 |
| ctrl | 60 | +580.56 | 1.09 | 5.21 | 2831 |
| narrow (07-08h/12-13h) | 40 | +543.65 | 1.13 | 5.06 | 1751 |
| narrow | 45 | +397.70 | 1.11 | 7.83 | 1613 |
| narrow | 60 | +430.10 | **1.15** | **3.89** | 1318 |
| open30 (07-07:30/12-12:30) | 40 | +289.17 | 1.10 | 3.68 | 1266 |
| open30 | 45 | +321.79 | 1.12 | 5.61 | 1184 |
| open30 | 60 | +170.73 | 1.08 | 3.01 | 972 |
| **always (00:00-23:59, no session gate — BTC-specific hypothesis)** | 40 | -2598.93 | 0.94 | 26.82 | 16254 |
| always | 45 | -1844.02 | 0.95 | 30.94 | 15365 |
| always | 60 | +807.23 | 1.03 | 8.70 | 12366 |

**Reading the surface:**
- **9 of 12 combinations were profitable** — a sharp contrast with the XAUUSD-VIP
  entry sweep, where all 9 combinations lost money. BTCUSD's grid-on-displacement
  concept at least *looks* more promising on training data than gold's ever did.
- **The "always" (no session restriction) hypothesis clearly failed** — despite BTC
  trading 24/7 with no structural session open, removing the session gate produced the
  worst drawdowns in the whole sweep (up to 30.94%) and 2 of 3 negative results. A
  session filter still earns its place even on a 24/7 market.
- **`narrow` is the coherent family**: profitable and PF≥1.11 across all three tested
  spacings — best at spacing=60 (PF 1.15, eqDD 3.89%).
- `ctrl` is *not* coherent within itself: spacing=40 lost -$734.86 (PF 0.92) in the
  same session window where spacing=60 won +$580.56 (PF 1.09) — the same
  isolated-result caution as Sweep 1's rejected TP=3/SL=8.

### Out-of-sample validation (held-out window)

| Candidate | Training | Held-out | Verdict |
|---|---|---|---|
| C: narrow session × spacing=60 (coherent family) | +430.10, PF 1.15 | **-98.11, PF 0.90, Sharpe -1.85** | **REJECTED** |
| D: ctrl session × spacing=60 (less coherent) | +580.56, PF 1.09 | **-366.54, PF 0.83, Sharpe -3.69** | **REJECTED** |

**This is the important finding of the whole campaign:** candidate C looked genuinely
coherent — consistent sign and PF>1.11 across three independent spacing values on the
training window, not a one-off spike — and it *still* didn't survive the held-out
window. Coherence-within-training-data is necessary evidence against overfitting but
is **not sufficient**; it does not guarantee genuine out-of-sample robustness.

## Conclusions (2026-07-19)

1. **No candidate from either sweep survived out-of-sample validation as a real
   edge.** 4 candidates tested (2 exits, 2 entry-side); 3 rejected outright (sign
   flip), 1 survived but only at near-breakeven (PF 1.01, Sharpe ≈ 0). This mirrors
   XAUUSD-VIP's ultimate conclusion despite BTCUSD's training-window surface looking
   considerably more promising along the way (9/12 profitable entry combos vs gold's
   0/9).
2. **41 real-tick backtests ran this session** (25-combo exit sweep + 2 validations +
   12-combo entry sweep + 2 validations) — real ticks throughout, no OHLC-model risk
   anywhere in this campaign.
3. **The strongest lesson: coherence is not the same test as held-out validation.**
   Candidate C would have been reported as "the finding" under the weaker standard
   `OPT_REPORT.md`'s FOMC sweep had to settle for (no held-out data available there).
   Here, with genuine held-out data, it still failed. Any future sweep on this EA
   should keep reserving a real held-out window rather than relying on
   within-training coherence alone.
4. **Live/demo deployment on BTCUSD remains unjustified** by anything found so far —
   nothing tested beats "don't trade" with confidence that survives held-out data.

## Recommended next steps (user decision)

1. **A joint sweep (exits × entry-side together)** hasn't been tried — Sweep 1 fixed
   entry geometry at the smoke-test defaults, Sweep 2 fixed exits at Sweep 1's weak
   winner. It's possible the true combination lives off both axes simultaneously, but
   this multiplies the multiple-comparisons risk further on an already-short (6.5
   month) data history — diminishing returns are a real concern, not just more compute.
2. **`ATR_Min/Max_USD` and the lot progression are still unswept**, same as gold's
   report flagged for its own remaining backlog.
3. **BTCUSD's history is short.** Every months-long window used here overlaps
   substantially with every other — there isn't much genuinely independent data left
   on this account to keep testing against. Prospective (forward/demo) tracking, the
   same conclusion `OPT_REPORT.md` reached for gold's FOMC-only mode, is likely the
   more honest path forward if this is pursued further.
4. Per CLAUDE.md's hard rules, none of this changes any compiled default —
   `AUTO_TRADING_ENABLED` stays `false`, and nothing here has been written into
   CLAUDE.md's canonical Inputs block.
