# Dashboard Self-Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace most of the Phase 8 dashboard's 12-item manual visual checklist with an
always-on, passive read-back guard inside the EA plus an automatic pass/fail summary in the
tester runner, so future dashboard regressions surface in a log line instead of requiring a
human to eyeball a chart.

**Architecture:** Every place `Straddle_Grid.mq5` writes a dashboard chart-object property
(`SetRow()`, the header block, the gate-dot loop, `RemoveDashboard()`) immediately reads the
property back and compares it to the value just written. Mismatches are logged via the
existing `HydraLog()` helper with a grep-able `[DASH-FAIL]` marker; matches produce no output.
`tools/strategy-tester/run_tests.sh` then scans each run's Tester log for that marker and
prints an aggregate PASS/FAIL line instead of telling the user to "send logs back."

**Tech Stack:** MQL5 (single-file EA, no DLLs), bash (`run_tests.sh` cross-platform runner),
MetaEditor64.exe command-line compile via Wine (macOS) / native (Windows).

## Global Constraints

- MQL5 only — no DLLs, no external dependencies (CLAUDE.md §1).
- Zero compile warnings required; never commit a failing or warning build (CLAUDE.md §11).
- `HYDRA_VERSION` stays **v2.0** for this change — this is regression-guard tooling, not the
  dashboard feature itself, which is still awaiting its final visual sign-off (design spec
  `docs/superpowers/specs/2026-07-16-dashboard-selftest-design.md` §4).
- No new EA inputs, no `MQL_TESTER` gating — the guard is a passive read-back that must behave
  identically live, on demo, and in tester; correct code never emits `[DASH-FAIL]` anywhere.
- All new log lines go through the existing `HydraLog()` helper (SIGMA convention #8: `[HYDRA]`
  prefix + timestamp on every line) — never call `Print()` directly for this.
- Never touch trading logic, gates, whipsaw guard, or basket management — this plan touches
  only the dashboard rendering/verification path and test tooling.
- Do not attempt to run an authenticated Strategy Tester backtest in this session — no
  `tools/strategy-tester/configs/common.local.ini` exists locally, and running without it has
  previously (2026-07-14) caused the tester to silently recover a live/demo session instead of
  testing. The compile check has no such risk (no login involved) and IS done directly in this
  plan. The actual backtest run is left for the user to execute themselves (Task 3 documents
  the exact one-line command).

---

## File Structure

- **Modify:** `MQL5/Experts/SIGMA/Straddle_Grid.mq5` — add two verification helpers and wire
  them into the four existing dashboard-writing sites (no new files; this project's convention
  is a single-file EA, CLAUDE.md §9).
- **Modify:** `tools/strategy-tester/run_tests.sh` — add one shared helper function
  (`report_dash_fail_summary`) called once at the end of each platform branch (Windows, macOS).
- **Modify:** `docs/CHECKLIST.md` — shrink the Phase 8 checklist section.
- **Modify:** `docs/PENDING_USER_ACTIONS.md` — replace the 12-item Phase 8 checklist with the
  shrunk 3-item version, and document the single command that now reports pass/fail.

---

### Task 1: Passive read-back guard in the EA

**Files:**
- Modify: `MQL5/Experts/SIGMA/Straddle_Grid.mq5:1168-1173` (`SetRow`)
- Modify: `MQL5/Experts/SIGMA/Straddle_Grid.mq5:1193-1197` (header block inside `UpdateDashboard`)
- Modify: `MQL5/Experts/SIGMA/Straddle_Grid.mq5:1215-1228` (gate-dot loop inside `UpdateDashboard`)
- Modify: `MQL5/Experts/SIGMA/Straddle_Grid.mq5:1298-1302` (`RemoveDashboard`)

**Interfaces:**
- Produces: `void VerifyTextProp(const string rowKey, const string name, const string expected)`
  and `void VerifyColorProp(const string rowKey, const string name, const ENUM_OBJECT_PROPERTY_INTEGER prop, const color expected)`
  — both call the existing `HydraLog(const string msg)` (already defined at line 1333) on
  mismatch, and do nothing on match. No other task depends on these beyond this file.
- Consumes: existing `HydraLog()`, `DASH_PREFIX`, `GATE_COUNT`, `g_gateNames`, `g_gateEvaluated`,
  `g_gatePass` (all already defined earlier in the file — see lines 66-129).

- [ ] **Step 1: Add the two verify helpers right after `SetRow()`**

Current code at `MQL5/Experts/SIGMA/Straddle_Grid.mq5:1166-1173`:

```mql5
//--- Update one body row's text + color (Gates row is handled separately
//    in UpdateDashboard() since it's five independently-colored dots)
void SetRow(const string rowKey, const string text, const color clr)
  {
   string name = DASH_PREFIX + "Row_" + rowKey;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }
```

Replace with:

```mql5
//--- Passive read-back guard: confirms a just-written object property
//    actually holds the value we intended. Silent on match; on mismatch,
//    logs a grep-able [DASH-FAIL] line via the existing HydraLog(). Never
//    fires on correct code, live or in tester — this is a regression
//    guard, not a synthetic/injected test, so it needs no gating.
void VerifyTextProp(const string rowKey, const string name, const string expected)
  {
   string actual = ObjectGetString(0, name, OBJPROP_TEXT);
   if(actual != expected)
      HydraLog(StringFormat("[DASH-FAIL] row=%s field=text expected=\"%s\" actual=\"%s\"",
                             rowKey, expected, actual));
  }

void VerifyColorProp(const string rowKey, const string name,
                      const ENUM_OBJECT_PROPERTY_INTEGER prop, const color expected)
  {
   color actual = (color)ObjectGetInteger(0, name, prop);
   if(actual != expected)
      HydraLog(StringFormat("[DASH-FAIL] row=%s field=%s expected=%d actual=%d",
                             rowKey, EnumToString(prop), (int)expected, (int)actual));
  }

//--- Update one body row's text + color (Gates row is handled separately
//    in UpdateDashboard() since it's five independently-colored dots)
void SetRow(const string rowKey, const string text, const color clr)
  {
   string name = DASH_PREFIX + "Row_" + rowKey;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   VerifyTextProp(rowKey, name, text);
   VerifyColorProp(rowKey, name, OBJPROP_COLOR, clr);
  }
```

- [ ] **Step 2: Wire the header block into the guard**

Current code at `MQL5/Experts/SIGMA/Straddle_Grid.mq5:1193-1197`:

```mql5
   color accent = DashAccentColor();
   ObjectSetInteger(0, DASH_PREFIX + "Header", OBJPROP_BGCOLOR, accent);
   ObjectSetInteger(0, DASH_PREFIX + "Header", OBJPROP_COLOR, accent);
   ObjectSetString(0, DASH_PREFIX + "HeaderText", OBJPROP_TEXT,
                   StringFormat("SIGMA Hydra %s  %s", HYDRA_VERSION, g_dashCollapsed ? "▲" : "▼"));
```

Replace with:

```mql5
   color accent = DashAccentColor();
   ObjectSetInteger(0, DASH_PREFIX + "Header", OBJPROP_BGCOLOR, accent);
   ObjectSetInteger(0, DASH_PREFIX + "Header", OBJPROP_COLOR, accent);
   VerifyColorProp("Header", DASH_PREFIX + "Header", OBJPROP_BGCOLOR, accent);
   VerifyColorProp("Header", DASH_PREFIX + "Header", OBJPROP_COLOR, accent);
   string headerTxt = StringFormat("SIGMA Hydra %s  %s", HYDRA_VERSION, g_dashCollapsed ? "▲" : "▼");
   ObjectSetString(0, DASH_PREFIX + "HeaderText", OBJPROP_TEXT, headerTxt);
   VerifyTextProp("HeaderText", DASH_PREFIX + "HeaderText", headerTxt);
```

- [ ] **Step 3: Wire the gate-dot loop into the guard**

Current code at `MQL5/Experts/SIGMA/Straddle_Grid.mq5:1215-1228`:

```mql5
   // Row: Gates — 5 independently-colored dots + the failing gate's name
   string failName = "";
   for(int g = 0; g < GATE_COUNT; g++)
     {
      color dot = clrGray;   // not yet evaluated this session
      if(g_gateEvaluated[g])
         dot = g_gatePass[g] ? clrLimeGreen : clrRed;
      ObjectSetString(0, DASH_PREFIX + "Gate" + IntegerToString(g), OBJPROP_TEXT, "●");
      ObjectSetInteger(0, DASH_PREFIX + "Gate" + IntegerToString(g), OBJPROP_COLOR, dot);
      if(g_gateEvaluated[g] && !g_gatePass[g] && failName == "")
         failName = g_gateNames[g];
     }
   ObjectSetString(0, DASH_PREFIX + "GateFailName", OBJPROP_TEXT, failName);
   ObjectSetInteger(0, DASH_PREFIX + "GateFailName", OBJPROP_COLOR, clrRed);
```

Replace with:

```mql5
   // Row: Gates — 5 independently-colored dots + the failing gate's name
   string failName = "";
   for(int g = 0; g < GATE_COUNT; g++)
     {
      color dot = clrGray;   // not yet evaluated this session
      if(g_gateEvaluated[g])
         dot = g_gatePass[g] ? clrLimeGreen : clrRed;
      string gateName = DASH_PREFIX + "Gate" + IntegerToString(g);
      ObjectSetString(0, gateName, OBJPROP_TEXT, "●");
      ObjectSetInteger(0, gateName, OBJPROP_COLOR, dot);
      VerifyColorProp(StringFormat("Gate%d", g), gateName, OBJPROP_COLOR, dot);
      if(g_gateEvaluated[g] && !g_gatePass[g] && failName == "")
         failName = g_gateNames[g];
     }
   ObjectSetString(0, DASH_PREFIX + "GateFailName", OBJPROP_TEXT, failName);
   ObjectSetInteger(0, DASH_PREFIX + "GateFailName", OBJPROP_COLOR, clrRed);
   VerifyTextProp("GateFailName", DASH_PREFIX + "GateFailName", failName);
```

- [ ] **Step 4: Add the leftover-object check to `RemoveDashboard()`**

Current code at `MQL5/Experts/SIGMA/Straddle_Grid.mq5:1296-1302`:

```mql5
//--- Remove every dashboard object — EA removal must leave no leftover
//    chart objects (CLAUDE.md §10.1 / docs/CHECKLIST.md Phase 8).
void RemoveDashboard()
  {
   ObjectsDeleteAll(0, DASH_PREFIX);
   g_dashBuilt = false;
  }
```

Replace with:

```mql5
//--- Remove every dashboard object — EA removal must leave no leftover
//    chart objects (CLAUDE.md §10.1 / docs/CHECKLIST.md Phase 8).
void RemoveDashboard()
  {
   ObjectsDeleteAll(0, DASH_PREFIX);
   int leftover = 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = 0; i < total; i++)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, DASH_PREFIX) == 0)
         leftover++;
     }
   if(leftover > 0)
      HydraLog(StringFormat("[DASH-FAIL] row=cleanup field=leftover_objects expected=0 actual=%d",
                             leftover));
   g_dashBuilt = false;
  }
```

- [ ] **Step 5: Sync the edited file into the local Wine MT5 data folder and compile headlessly**

This machine has MT5 installed via Wine at
`~/Library/Application Support/net.metaquotes.wine.metatrader5`. The compiler there works
without any account login, so this step is safe to run directly (unlike a Strategy Tester run).

```bash
DATA_DIR_C="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5"
cp "MQL5/Experts/SIGMA/Straddle_Grid.mq5" "$DATA_DIR_C/MQL5/Experts/SIGMA/Straddle_Grid.mq5"

cd "$DATA_DIR_C"
WINEPREFIX="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5" \
  "/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64" MetaEditor64.exe \
  /compile:"MQL5\\Experts\\SIGMA\\Straddle_Grid.mq5" \
  /log:"hydra_compile_check.log"

iconv -f UTF-16LE -t UTF-8 "hydra_compile_check.log" | tail -5
rm -f "hydra_compile_check.log"
cd -
```

Expected: last line reads `Result: 0 errors, 0 warnings, ... elapsed`. If it shows any errors
or warnings, fix them before continuing — do not proceed to Task 2 with a non-clean compile.

- [ ] **Step 6: Commit**

```bash
git add MQL5/Experts/SIGMA/Straddle_Grid.mq5
git commit -m "$(cat <<'EOF'
Add passive read-back guard to the dashboard panel

Every dashboard object write (rows, header, gate dots, cleanup) now
reads its own property back and logs a grep-able [DASH-FAIL] line on
any mismatch. Silent on match, live and in tester alike — this is a
regression guard, not a synthetic test, so it needs no new input or
MQL_TESTER gating.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `run_tests.sh` — automatic DASH-FAIL summary

**Deviation from the design spec:** the spec (§2) describes a "per-config PASS/FAIL line."
MT5's Tester logs aren't reliably attributable to one config within a multi-config invocation
without log-splitting logic this script doesn't have today, so this task implements a single
aggregate summary across the whole `run_tests.sh` invocation instead. This still replaces
manual log-reading with an automatic signal — the goal of §2 — just at invocation granularity
rather than per-config.

**Files:**
- Modify: `tools/strategy-tester/run_tests.sh:26-31` (top-level setup, add a run marker)
- Modify: `tools/strategy-tester/run_tests.sh` Windows branch close-out (currently ends with
  `echo "Send both back for verification."` before `exit 0`)
- Modify: `tools/strategy-tester/run_tests.sh` macOS branch close-out (currently ends with
  `echo "Send both back for verification."` at end of file)

**Interfaces:**
- Produces: shared function `report_dash_fail_summary(<tester_root_dir>)` — greps every
  `*.log` under `<tester_root_dir>/Tester` newer than a marker file for the literal string
  `DASH-FAIL`, prints a PASS/FAIL summary, and removes the marker. Called once per platform
  branch, after the existing run loop, before that branch's final `echo` lines.
- Consumes: `HydraLog()`'s `[DASH-FAIL]` marker string introduced in Task 1 — this task does
  not touch the EA, only reads its log output.

- [ ] **Step 1: Add the marker file and helper function near the other helpers**

Current code at `tools/strategy-tester/run_tests.sh:26-31`:

```bash
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
COMMON_INI="$HERE/configs/common.local.ini"
MERGED_DIR="$HERE/.merged"
FILTERS=("$@")
```

Replace with:

```bash
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
COMMON_INI="$HERE/configs/common.local.ini"
MERGED_DIR="$HERE/.merged"
FILTERS=("$@")

# Marker file so report_dash_fail_summary() can find only *this* run's log
# output (Tester logs otherwise accumulate across every past run).
RUN_MARKER="$(mktemp)"
```

Then, immediately after `merge_config()` (still inside the shared helper section, before the
`case "$(uname -s)" in` platform-detection block), add the new function:

```bash
report_dash_fail_summary() {   # $1 = tester root dir (DATADIR or DATA_DIR)
    local root="$1" hits=0 total=0 report=""
    while IFS= read -r -d '' logfile; do
        hits="$(grep -c 'DASH-FAIL' "$logfile" 2>/dev/null || true)"
        hits="${hits:-0}"
        if [ "$hits" -gt 0 ]; then
            total=$((total + hits))
            report="${report}  $logfile: $hits hit(s)
"
        fi
    done < <(find "$root/Tester" -name '*.log' -newer "$RUN_MARKER" -print0 2>/dev/null)
    echo "------------------------------------------------------------"
    if [ "$total" -eq 0 ]; then
        echo "Dashboard self-test: PASS (0 [DASH-FAIL] lines across this run)"
    else
        echo "Dashboard self-test: FAIL ($total [DASH-FAIL] line(s)):"
        printf '%s' "$report"
    fi
    rm -f "$RUN_MARKER"
}
```

- [ ] **Step 2: Call it at the end of the Windows branch**

Current code (end of the Windows `if` block):

```bash
    echo "------------------------------------------------------------"
    echo "All runs done."
    echo "  Reports:      $DATADIR/Hydra_0*.htm"
    echo "  Tester logs:  $DATADIR/Tester/*/logs/   (the [HYDRA] lines live here)"
    echo "Send both back for verification."
    exit 0
fi
```

Replace with:

```bash
    echo "------------------------------------------------------------"
    echo "All runs done."
    echo "  Reports:      $DATADIR/Hydra_0*.htm"
    echo "  Tester logs:  $DATADIR/Tester/*/logs/   (the [HYDRA] lines live here)"
    report_dash_fail_summary "$DATADIR"
    exit 0
fi
```

- [ ] **Step 3: Call it at the end of the macOS branch**

Current code (end of file):

```bash
echo "------------------------------------------------------------"
echo "All runs done."
echo "  Reports:      $DATA_DIR/Hydra_0*.htm"
echo "  Tester logs:  $DATA_DIR/Tester/*/logs/   (the [HYDRA] lines live here)"
echo "Send both back for verification."
```

Replace with:

```bash
echo "------------------------------------------------------------"
echo "All runs done."
echo "  Reports:      $DATA_DIR/Hydra_0*.htm"
echo "  Tester logs:  $DATA_DIR/Tester/*/logs/   (the [HYDRA] lines live here)"
report_dash_fail_summary "$DATA_DIR"
```

- [ ] **Step 4: Syntax-check the script**

```bash
bash -n tools/strategy-tester/run_tests.sh
echo "exit code: $?"
```

Expected: `exit code: 0`, no syntax errors printed.

- [ ] **Step 5: Commit**

```bash
git add tools/strategy-tester/run_tests.sh
git commit -m "$(cat <<'EOF'
run_tests.sh: report DASH-FAIL hits instead of "send logs back"

Every run now ends with an automatic PASS/FAIL line covering the
whole invocation's Tester logs, closing the loop the Task 1 EA change
opened up — no more manually reading the journal for dashboard bugs.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Shrink the manual checklist in the docs

**Files:**
- Modify: `docs/CHECKLIST.md` (Phase 8 section, currently referenced at line 108)
- Modify: `docs/PENDING_USER_ACTIONS.md` (Phase 8 section, `### 3. What to check off` list)

**Interfaces:** none — documentation only, no code interfaces produced or consumed.

- [ ] **Step 1: Read the current Phase 8 section of `docs/CHECKLIST.md`**

Read `docs/CHECKLIST.md` starting at line 108 (found via `grep -n "Phase 8" docs/CHECKLIST.md`)
to see its exact current item list and formatting before editing, since this plan was written
against `docs/PENDING_USER_ACTIONS.md`'s copy of the checklist and the two may have drifted.

- [ ] **Step 2: Replace the Phase 8 checklist body in `docs/CHECKLIST.md`**

Locate the Phase 8 section (starts at the `## Phase 8 — Dashboard Panel` heading found in
Step 1) and replace its checklist items with:

```markdown
## Phase 8 — Dashboard Panel

**Automated (checked by `run_tests.sh`'s DASH-FAIL summary on every run — see
`docs/superpowers/specs/2026-07-16-dashboard-selftest-design.md`):** header version text, all
5 accent colors, gate dot colors + failing-gate name, every row's live content (session,
spread/ATR, grid status, basket P/L, scaled TP/SL/trail-floor targets, whipsaw counter +
cooldown countdown, TTL countdown), and leftover-object cleanup on EA removal.

**Still manual (requires a screen — run `./run_tests.sh hydra_dash_visual` and watch):**
- [ ] A real header click actually collapses the panel to the title bar; clicking again
      actually expands it.
- [ ] The panel doesn't visually overlap the chart's native top-left OHLC/price label.
- [ ] General "does it look right" pass — fonts, spacing, readability, colors as expected.
```

- [ ] **Step 3: Update `docs/PENDING_USER_ACTIONS.md`'s Phase 8 section**

Replace the entire `### 3. What to check off (`docs/CHECKLIST.md` §Phase 8)` block (currently
the 11 checkbox items starting with "Header reads `SIGMA Hydra v2.0`..." and ending with "...
nudge `DASH_Y` in the source if it does on your setup.") with:

```markdown
### 3. What to check off

Most of the old 12-item checklist is now automatic — every `run_tests.sh` run ends with a
`Dashboard self-test: PASS/FAIL` line covering header text, all 5 accent colors, gate dots,
every row's content, and leftover-object cleanup. Run the headless state-cycling config and
confirm it reports PASS:

```bash
cd tools/strategy-tester
./run_tests.sh hydra_02_deploy_fills
```

Only 3 items still need a screen (see `docs/CHECKLIST.md` §Phase 8) — use the existing Visual
mode command for these:

- [ ] Header click actually collapses/expands the panel.
- [ ] Panel doesn't overlap the chart's native OHLC/price label.
- [ ] General "does it look right" pass.
```

- [ ] **Step 4: Commit**

```bash
git add docs/CHECKLIST.md docs/PENDING_USER_ACTIONS.md
git commit -m "$(cat <<'EOF'
Shrink Phase 8 manual checklist now that DASH-FAIL is automatic

Down from 12 manual items to 3 — only the things that genuinely need
a screen (real click event, pixel overlap, general look) remain.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Final Verification (after all 3 tasks)

- [ ] Confirm `git log --oneline -3` shows the three commits from Tasks 1-3.
- [ ] Confirm the compile check from Task 1 Step 5 reported 0 errors/0 warnings (already done
      during Task 1 — this is a recap, not a re-run).
- [ ] Tell the user: run `./run_tests.sh hydra_02_deploy_fills` and confirm the new
      `Dashboard self-test: PASS` line, then do the shrunk 3-item visual check via
      `./run_tests.sh hydra_dash_visual`. This is the one remaining step that needs their
      demo credentials and a screen — it cannot be done in this session.
- [ ] `HYDRA_VERSION` stays v2.0 until the user confirms both of the above (per Global
      Constraints).
