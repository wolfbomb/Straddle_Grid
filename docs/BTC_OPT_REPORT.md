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

**Config:** launched via `run_opt.sh` (sweep config removed after review — see note at
end of report). **Model=4 real ticks throughout** — no OHLC shortcut, unlike
`OPT_REPORT.md` Sweep 01 (that shortcut is what produced a winner that later collapsed
from +$1,673 to -$5,496 under real-tick re-validation for gold; not repeated here).
Grid: `BasketTP_USD` ∈ {3,6,9,12,15}, `BasketSL_USD` ∈ {2,4,6,8,10}.
`TrailActivate_USD`/`TrailDistance_USD` held fixed at the smoke-test preset's values
(3.0/1.5) to keep the grid 2D. Everything else at the `hydra_15_btcusd_smoke.set`
first-pass BTCUSD geometry. Full 25-combo grid reproduced in the table below.

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

**Method:** a custom Python driver (native MT5 optimizer can't sweep the string-typed
`Session1`/`Session2` inputs — same reason `OPT_REPORT.md`'s Sweep 02 used a custom
driver; script removed after review, see note at end of report). Exits fixed at
Sweep 1's validated candidate B (TP=6/SL=2). Grid: 4 session variants ×
`GridSpacingUSD` ∈ {40,45,60}. Full 12-combo grid reproduced in the table below.

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

## Sweep 3 — joint (exits × spacing, per session), 225 combinations, real ticks

**Method:** Sweeps 1–2 each fixed one axis while searching the other (Sweep 1 fixed
entry geometry at smoke-test defaults; Sweep 2 fixed exits at Sweep 1's weak winner).
This sweep searches `BasketTP_USD` × `BasketSL_USD` × `GridSpacingUSD` **jointly**, once
per session variant (native optimizer can't sweep the string session inputs, so one
batch per session, same as before). Grid per session: `BasketTP_USD` ∈ {3,6,9,12,15},
`BasketSL_USD` ∈ {2,4,6,8,10}, `GridSpacingUSD` ∈ {40,50,60} = 75 combos ×
{ctrl, narrow, open30} = **225 combos total** (`always` excluded — already shown clearly
bad in Sweep 2). Sweep configs removed after review (see note at end of report). Same
training window throughout; headline numbers and the full profitable-region breakdown
are reproduced below.

**Headline: 68/225 (30.2%) combinations profitable.** The raw #1 result — **ctrl
session, TP=3/SL=4/spacing=40, +$1,071.54, PF 1.138** — is the single largest profit
number in the entire campaign, and also, on inspection, the clearest **isolated spike**
yet: every immediate neighbor (same SL, same TP, or same spacing) is negative, several
severely so. Rejected as noise before it was even validated (validation below confirms
this).

**The one region that looked genuinely different:** `SL=2` crossed with the two
*selective* session windows:

| Session | SL=2 combos positive | PF range |
|---|---|---|
| ctrl (wide, 3h windows) | 5/15 | 0.83 – 1.09 (inconsistent) |
| **narrow** (1h windows) | **15/15** | 1.10 – 1.16 |
| **open30** (30min windows) | **15/15** | 1.04 – 1.17 |

30 of 30 combinations across `narrow`+`open30` at `SL=2` were profitable, independent of
`BasketTP_USD` or `GridSpacingUSD` — the tightest, most internally consistent positive
region found anywhere in this campaign, and a mechanistically sensible one (a tight
stop pairs badly with a wide, chop-admitting session window, consistent with `ctrl`'s
5/15 hit rate right next to it). Best points: open30/TP=3/SL=2/sp=40 (PF 1.166, the
highest PF in the whole 225-combo grid) and narrow/TP=9/SL=2/sp=40 (+$637.25, the
highest profit within the coherent region).

### Out-of-sample validation (held-out window)

| Candidate | Training | Held-out | Verdict |
|---|---|---|---|
| E: open30/TP=3/SL=2/sp=40 (highest PF in the grid, 1.166) | +486.15, PF 1.166 | **-188.17, PF 0.85, Sharpe -3.48** | **REJECTED** |
| F: narrow/TP=9/SL=2/sp=40 (highest profit in the coherent region) | +637.25, PF 1.155 | **-306.11, PF 0.81, Sharpe -3.95** | **REJECTED** |
| G: ctrl/TP=3/SL=4/sp=40 (isolated spike, sanity check) | +1071.54, PF 1.138 | **-754.06, PF 0.77, Sharpe -5.00** | **REJECTED** (worst of the three — consistent with pure noise) |

**This closes out the SL=2 pattern entirely.** Combined with candidate C from Sweep 2
(narrow/TP=6/SL=2/sp=60, also rejected: -98.11/PF 0.90), **3 of 3** tested points from
what looked like the strongest, most structurally-sensible pattern in the whole
campaign — a 30-cell, 100%-training-positive, mechanistically-explicable region — failed
out-of-sample. This is a stronger rejection than candidate C alone suggested: it isn't
one unlucky point, the entire region doesn't hold.

## Sweep 4 — ATR band (25 combinations), including a caught-and-fixed design flaw

**v1 (flawed):** first attempt fixed exits at `BasketTP_USD=6.0`/`BasketSL_USD=4.0` (the
`hydra_15_btcusd_smoke.set` first-pass values) without checking them against Sweep 1's
own results first — that exact pair was already shown there to be one of the **worst**
combinations in the entire exits grid (-$1,767.54). Result: **0/25 combinations
positive**, every single ATR band tested lost money. This wasn't a finding about the
ATR band — it was the bad fixed exits dragging the whole grid negative. Caught before
any validation was wasted on it, and re-run.

**v2 (corrected):** same 25-combo grid (`ATR_Min_USD` ∈ {20,40,60,80,100},
`ATR_Max_USD` ∈ {150,200,250,300,350}), exits fixed at Sweep 1's actual validated
candidate (TP=6/SL=2) instead. **20/25 combinations positive (80%)** — the highest hit
rate of any sweep in the campaign.

**Full grid (Profit):**

| Min \ Max | 150 | 200 | 250 | 300 | 350 |
|---|---|---|---|---|---|
| 20 | 541.2 | 864.7 | 420.0 | 441.3 | 308.0 |
| 40 | 501.0 | 824.5 | 379.8 | 401.1 | 267.8 |
| **60** | 653.8 | **977.3** | 532.6 | 553.9 | 420.6 |
| 80 | 324.4 | 388.6 | -9.7 | 11.6 | -121.7 |
| 100 | 65.7 | 173.3 | -225.0 | -242.4 | -375.7 |

**This is the cleanest surface in the whole campaign.** `Max=200` beats both its `150`
and `250` neighbors at **every** tested `Min` value — a genuine interior ridge, not a
boundary artifact — and `Min=60` beats both its `40` and `80` neighbors too. The peak
(`Min=60/Max=200`, +$977.27, PF 1.131) sits in the interior of the grid on both axes
simultaneously, the most textbook-clean optimization result found anywhere in this
campaign — better-looking than the SL=2 region from Sweep 3.

### Out-of-sample validation (held-out window)

| Candidate | Training | Held-out | Verdict |
|---|---|---|---|
| H: Min=60/Max=200 (interior peak) | +977.27, PF 1.131 | **-359.98, PF 0.84, Sharpe -3.52** | **REJECTED** |
| I: Min=40/Max=200 (ridge robustness check) | +824.50, PF 1.108 | **-299.37, PF 0.87, Sharpe -2.75** | **REJECTED** |

**Both failed.** This is the third time a within-training pattern that looked
progressively more convincing — an isolated spike, then a 30-cell coherent region, now
a clean interior-maximum ridge — has failed the same way against held-out data. Surface
smoothness and interior-maximum shape are not, on their own, protection against
overfitting either.

## Sweep 5 — lot progression × GridLevels (5 candidates, real ticks)

**Method:** `LotProgressionCSV` is a string input the native optimizer can't sweep, and
`Straddle_Grid.mq5`'s `ParseLotProgression` requires its element count to exactly equal
`GridLevels` (init fails otherwise) — so the two must vary together, one real-tick pass
per pair, via a custom driver (script removed after review). Exits fixed at TP=6/SL=2,
ATR band fixed at the original first-pass default (40/250 — Sweep 4 tested 25
alternatives and none survived validation, so there's no better-known choice to fix at
instead). Five fixed, static (non-adaptive) arrays tested — no runtime martingale,
consistent with CLAUDE.md's hard rule:

| Variant | Levels | Shape | Profit | PF | eqDD % |
|---|---|---|---|---|---|
| **control_9** (current production array) | 9 | ascending pyramid | **+379.80** | 1.05 | 7.16 |
| more_13 | 13 | finer ascending | +323.85 | 1.04 | 7.84 |
| fewer_5 | 5 | steeper ascending | -53.22 | 0.99 | 10.80 |
| flat_9 | 9 | uniform 0.02 | -380.02 | 0.96 | 10.08 |
| frontload_9 | 9 | descending | -882.63 | 0.94 | **21.05** (worst) |

**The current production array won.** None of the four alternatives beat it on
training data — flattening the size distribution, front-loading it, or changing the
level count all did worse, several substantially so (front-loading in particular
produced the worst drawdown of any candidate in this sweep, 21%). `control_9` is
literally Sweep 1's candidate B, so its out-of-sample result is already known: the same
weak, near-breakeven survivor (+$26.46, PF 1.01, Sharpe ≈ 0). No alternative here even
looked promising enough on training data to be worth a fresh validation pass — all four
are dominated by a baseline that itself isn't a real edge.

## Conclusions (2026-07-20, final)

1. **No candidate from any of the five sweeps survived out-of-sample validation as a
   real edge.** 9 candidates tested total (2 exits-only, 2 entry-only, 3 joint, 2 ATR
   band); 8 rejected outright (sign flip), 1 survived at only near-breakeven (PF 1.01,
   Sharpe ≈ 0) — and that one candidate is also the best of everything tried on the
   lot-progression axis, so it isn't superseded by anything else either. Same
   conclusion class as XAUUSD-VIP's campaign, reached with a stricter method (a real
   held-out window reserved from the start, which the gold campaign never had).
2. **312 real-tick backtests ran across this campaign** (25 + 12 + 225 + 25 + 5 sweep
   combos) + 9 out-of-sample validation passes = **321 real-tick runs total**, `Model=4`
   throughout, no OHLC-model risk anywhere.
3. **The central lesson, reinforced a third time:** within-training coherence — an
   isolated spike, a 30-cell 100%-positive region, and now a clean interior-maximum
   ridge — is not the same test as held-out validation and does not guarantee real
   edge, no matter how statistically clean the training-window shape looks.
4. **A real design-flaw catch mid-campaign is itself worth recording:** Sweep 4's first
   attempt silently confounded an entire 25-combo grid by fixing exits at a
   already-known-bad pair from Sweep 1, producing a uniformly negative (0/25) result
   that would have read as "ATR band doesn't matter" if not checked against prior
   sweep data before use. Always cross-check a sweep's *fixed* parameters against
   earlier results before trusting what varies.
5. **Every parameter axis this EA exposes for BTCUSD has now been searched**: exits,
   entry-timing, exits×spacing jointly, ATR band, and lot progression/GridLevels. None
   produced anything that survives contact with unseen data.
6. **Live/demo deployment on BTCUSD remains unjustified.** Nothing tested across five
   sweeps and nine validations beats "don't trade" with confidence that survives
   held-out data.

## Recommended next steps (user decision)

1. **Parameter tuning is now exhausted for this instrument.** Every axis the EA
   exposes — exits, entry-timing, exits×spacing jointly, ATR band, lot progression —
   has been swept, several ways, with a genuine held-out check every time. Nothing
   survived. There is no remaining parameter-tuning direction left to try in good
   faith; further grid sweeps on this trigger would be re-mining the same
   already-negative result.
2. **A calendar/event-gated trigger** (mirroring FOMC-Only Mode, CLAUDE.md §5.1) is the
   only direction not yet tried — it's the one thing that changed gold's picture, even
   if only to a fragile, unconfirmed lead. This is real EA development (a new CLAUDE.md
   spec section, new inputs/gate logic, its own validation campaign), not a config
   sweep, and would need its own scoping decision before starting.
3. **BTCUSD's history is short and now heavily mined.** Every months-long window used
   across this campaign overlaps substantially with every other; there isn't much
   genuinely independent backtest data left on this account. If BTCUSD is pursued
   further at all, prospective (forward/demo) tracking — the same conclusion
   `OPT_REPORT.md` reached for gold's FOMC-only mode — is more honest than continuing
   to backtest against an increasingly-reused window.
4. Per CLAUDE.md's hard rules, none of this changes any compiled default —
   `AUTO_TRADING_ENABLED` stays `false`, and nothing here has been written into
   CLAUDE.md's canonical Inputs block.

## Note on removed artifacts (2026-07-20)

The per-sweep `.ini` configs (`hydra_opt_04`–`hydra_opt_18`), the custom Python drivers
(`entry_sweep_btc.py`, `lotprogression_sweep_btc.py`), and the raw per-combo result
CSVs (`docs/opt/btc_*.csv`) were deleted after this report was written up — this
document is the sole surviving record of the campaign. Every number needed to
understand what was tried and found is reproduced in the tables above; nothing here
can be re-run without recreating those files from scratch. `hydra_15_btcusd_smoke.set`/
`.ini` (the first-pass, non-optimized geometry) were kept — they're the smoke test, not
part of the optimization campaign.
