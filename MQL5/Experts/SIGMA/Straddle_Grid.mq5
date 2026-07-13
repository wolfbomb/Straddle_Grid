//+------------------------------------------------------------------+
//|                                                Straddle_Grid.mq5 |
//|                              SIGMA Suite — Hydra                 |
//|                 https://github.com/wolfbomb/Straddle_Grid        |
//+------------------------------------------------------------------+
//| Bidirectional stop-order grid (straddle) with pyramiding lot     |
//| progression. Spec: CLAUDE.md (repo root). Build plan:            |
//| PHASE_PROMPTS.md. Tests: docs/CHECKLIST.md.                      |
//|                                                                  |
//| Phase 1 — Skeleton & State Machine.                              |
//| This build compiles clean and trades NOTHING.                    |
//|                                                                  |
//| Section order (SIGMA convention, CLAUDE.md §9):                  |
//|   Inputs → Globals/State → OnInit (state recovery) →             |
//|   OnTick (state dispatch) → Gates → GridDeploy → WhipsawGuard →  |
//|   BasketManager → Dashboard → Utils                              |
//+------------------------------------------------------------------+
#property copyright "SIGMA"
#property link      "https://github.com/wolfbomb/Straddle_Grid"

//+------------------------------------------------------------------+
//| ======================== INPUTS ================================ |
//| Canonical names per CLAUDE.md §8 — do not rename.                |
//+------------------------------------------------------------------+
input group "── Master ──"
input bool    AUTO_TRADING_ENABLED = false;    // SIGMA rule: defaults false, never flip in code
input long    MagicNumber          = 20260713;

input group "── Grid ──"
input int     GridLevels           = 9;        // per side
input double  GridSpacingUSD       = 0.42;     // $ between levels
input double  FirstLevelOffsetUSD  = 0.50;     // $ from anchor to level 1
input string  LotProgressionCSV    = "0.01,0.01,0.02,0.02,0.02,0.03,0.04,0.04,0.05";
input bool    OCO_Mode             = true;
input int     GridTTLMin           = 45;

input group "── Basket Exit ──"
input double  BasketTP_USD         = 15.0;
input double  BasketSL_USD         = 10.0;
input double  TrailActivate_USD    = 8.0;
input double  TrailDistance_USD    = 4.0;

input group "── Gates ──"
input string  Session1             = "07:00-10:00";  // GMT
input string  Session2             = "12:00-15:00";
input double  ATR_Min_USD          = 1.5;
input double  ATR_Max_USD          = 8.0;
input int     MaxSpreadPoints      = 35;
input double  MinMarginLevelPct    = 500.0;
input double  MaxDailyLossPct     = 3.0;

input group "── Whipsaw Guard ──"
input int     WhipsawWindowSec     = 300;
input int     WhipsawCooldownMin   = 60;
input int     MaxWhipsawsPerDay    = 2;

//+------------------------------------------------------------------+
//| ===================== GLOBALS / STATE =========================== |
//+------------------------------------------------------------------+
#define HYDRA_VERSION        "v1.0"          // single source of truth — dashboard header reads this
#define HYDRA_COMMENT_PREFIX "SIGMA.Hydra"   // order comment prefix (SIGMA convention)

// Persistent global-variable keys (namespaced SIGMA.Hydra.<symbol>.<key>,
// built by GVKey()). Survive terminal restart.
#define GV_WHIPSAW_COUNT   "whipsaw_count"   // whipsaws fired today
#define GV_WHIPSAW_DAY     "whipsaw_day"     // server day-stamp the counter belongs to
#define GV_COOLDOWN_UNTIL  "cooldown_until"  // epoch time cooldown ends

enum EHydraState
  {
   STATE_IDLE     = 0,  // no grid, no positions; evaluating gates (throttled 1x/sec)
   STATE_ARMED    = 1,  // full pending grid placed, zero fills yet
   STATE_ACTIVE   = 2,  // >=1 fill, direction locked
   STATE_COOLDOWN = 3   // post-exit / post-whipsaw lockout, timer only
  };

EHydraState g_state        = STATE_IDLE;
double      g_lots[];                       // parsed LotProgressionCSV
datetime    g_lastGateEval = 0;             // 1 Hz throttle for IDLE gate checks

//+------------------------------------------------------------------+
//| ================== ONINIT (STATE RECOVERY) ====================== |
//+------------------------------------------------------------------+
int OnInit()
  {
   HydraLog(StringFormat("SIGMA Hydra %s initializing on %s (magic %I64d)",
                         HYDRA_VERSION, _Symbol, MagicNumber));

   if(GridLevels <= 0)
     {
      HydraLog(StringFormat("INIT FAIL: GridLevels must be > 0 (got %d)", GridLevels));
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(!ParseLotProgression(LotProgressionCSV, g_lots))
      return(INIT_PARAMETERS_INCORRECT);     // reason already logged

   double total = 0.0;
   for(int i = 0; i < ArraySize(g_lots); i++)
      total += g_lots[i];
   HydraLog(StringFormat("lot progression OK: %d levels/side, %.2f lots/side if fully filled",
                         ArraySize(g_lots), total));

   // Contract context (informational in Phase 1; Phase 3 validates against it)
   HydraLog(StringFormat("symbol spec: minLot=%.2f lotStep=%.2f stopsLevel=%d pts, tickSize=%.5f tickValue=%.2f",
                         SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                         SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
                         (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE),
                         SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)));

   if(!AUTO_TRADING_ENABLED)
      HydraLog("AUTO_TRADING_ENABLED is false — EA will never place orders until enabled (gate 5)");

   RecoverState();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Reconstruct state from existing orders/positions (CLAUDE.md §4). |
//| Never assume a clean slate.                                      |
//+------------------------------------------------------------------+
void RecoverState()
  {
   int      positions     = CountHydraPositions();
   int      pendings      = CountHydraOrders();
   datetime cooldownUntil = (datetime)(long)GVGet(GV_COOLDOWN_UNTIL, 0.0);

   if(positions > 0)
      SetState(STATE_ACTIVE, StringFormat("recovery: %d open position(s), %d pending(s) found", positions, pendings));
   else if(pendings > 0)
      SetState(STATE_ARMED, StringFormat("recovery: %d pending order(s) found, zero fills", pendings));
   else if(cooldownUntil > TimeCurrent())
      SetState(STATE_COOLDOWN, StringFormat("recovery: cooldown active until %s",
                                            TimeToString(cooldownUntil, TIME_DATE|TIME_SECONDS)));
   else
      SetState(STATE_IDLE, "recovery: clean slate");
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   HydraLog(StringFormat("deinit (reason %d), state=%s", reason, StateName(g_state)));
  }

//+------------------------------------------------------------------+
//| ================== ONTICK (STATE DISPATCH) ====================== |
//+------------------------------------------------------------------+
void OnTick()
  {
   switch(g_state)
     {
      case STATE_IDLE:
        {
         // Gate evaluation throttled to at most once per second
         if(TimeCurrent() == g_lastGateEval)
            break;
         g_lastGateEval = TimeCurrent();

         string failReason = "";
         if(EvaluateGates(failReason))
           {
            // Phase 3 will call DeployGrid() here. Phase 1/2: log only.
            HydraLog("gates PASS — deployment deferred (Phase 3)");
           }
         break;
        }

      case STATE_ARMED:
        {
         // Phase 3: TTL expiry + gate re-check + fill monitoring
         break;
        }

      case STATE_ACTIVE:
        {
         // MANDATORY ordering (CLAUDE.md §6): whipsaw guard runs FIRST,
         // before any other management logic. Never reorder.
         if(CheckWhipsawGuard())
            break;                            // guard fired — state already moved to COOLDOWN
         ManageBasket();                      // Phase 6
         break;
        }

      case STATE_COOLDOWN:
        {
         datetime until = (datetime)(long)GVGet(GV_COOLDOWN_UNTIL, 0.0);
         if(TimeCurrent() >= until)
            SetState(STATE_IDLE, "cooldown expired");
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| ========================= GATES ================================ |
//| Phase 2 implements the five ordered, short-circuiting gates      |
//| (CLAUDE.md §5). Phase 1 stub: always fails, logs each evaluation |
//| so the 1 Hz throttle is verifiable in the journal.               |
//+------------------------------------------------------------------+
bool EvaluateGates(string &failReason)
  {
   failReason = "gates not implemented until Phase 2";
   HydraLog("gate evaluation (Phase 1 stub) — " + failReason);
   return(false);
  }

//+------------------------------------------------------------------+
//| ======================= GRID DEPLOY ============================= |
//| Phase 3: validated deployment, abort-on-partial, rollback, TTL.  |
//+------------------------------------------------------------------+
bool DeployGrid()
  {
   HydraLog("DeployGrid: not implemented (Phase 3)");
   return(false);
  }

//+------------------------------------------------------------------+
//| ====================== WHIPSAW GUARD ============================ |
//| Phase 5: MANDATORY kill switch (CLAUDE.md §6). Called at the top |
//| of OnTick in ACTIVE state, before any other management logic.    |
//| Returns true when the guard fired. Never weaken or remove.       |
//+------------------------------------------------------------------+
bool CheckWhipsawGuard()
  {
   return(false);   // Phase 5
  }

//+------------------------------------------------------------------+
//| ====================== BASKET MANAGER =========================== |
//| Phase 6: basket TP / SL / trailing, pending cleanup on trail.    |
//+------------------------------------------------------------------+
void ManageBasket()
  {
   // Phase 6
  }

//+------------------------------------------------------------------+
//| ======================== DASHBOARD ============================== |
//| Phase 8: collapsible panel per CLAUDE.md §10.1. Header sources   |
//| its version from HYDRA_VERSION — never hardcode it twice.        |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   // Phase 8
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // Phase 8: header click collapse/expand, rebuild on timeframe switch
  }

//+------------------------------------------------------------------+
//| ========================== UTILS ================================ |
//+------------------------------------------------------------------+

//--- Logging: every log line carries the [HYDRA] prefix + timestamp (SIGMA convention #8)
void HydraLog(const string msg)
  {
   Print("[HYDRA] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " ", msg);
  }

string StateName(const EHydraState s)
  {
   switch(s)
     {
      case STATE_IDLE:     return("IDLE");
      case STATE_ARMED:    return("ARMED");
      case STATE_ACTIVE:   return("ACTIVE");
      case STATE_COOLDOWN: return("COOLDOWN");
     }
   return("UNKNOWN");
  }

//--- Single choke point for state transitions: every transition is logged
void SetState(const EHydraState newState, const string reason)
  {
   HydraLog(StringFormat("state %s -> %s (%s)", StateName(g_state), StateName(newState), reason));
   g_state = newState;
  }

//--- Persistent global variables, namespaced per symbol
string GVKey(const string key)
  {
   return("SIGMA.Hydra." + _Symbol + "." + key);
  }

double GVGet(const string key, const double fallback)
  {
   string k = GVKey(key);
   if(!GlobalVariableCheck(k))
      return(fallback);
   return(GlobalVariableGet(k));
  }

void GVSet(const string key, const double value)
  {
   GlobalVariableSet(GVKey(key), value);
  }

//--- Ownership filter: Hydra manages ONLY this symbol + this magic (SIGMA convention #4)
bool IsHydraPosition()
  {
   return(PositionGetString(POSITION_SYMBOL) == _Symbol &&
          PositionGetInteger(POSITION_MAGIC) == MagicNumber);
  }

bool IsHydraOrder()
  {
   return(OrderGetString(ORDER_SYMBOL) == _Symbol &&
          OrderGetInteger(ORDER_MAGIC) == MagicNumber);
  }

int CountHydraPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(IsHydraPosition())
         count++;
     }
   return(count);
  }

int CountHydraOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      if(IsHydraOrder())
         count++;
     }
   return(count);
  }

//--- Parse and validate LotProgressionCSV (CLAUDE.md §8):
//    element count must equal GridLevels; every lot >= symbol min lot
//    and aligned to the symbol lot step. Failure -> init aborts.
bool ParseLotProgression(const string csv, double &lots[])
  {
   string parts[];
   int n = StringSplit(csv, ',', parts);
   if(n != GridLevels)
     {
      HydraLog(StringFormat("INIT FAIL: LotProgressionCSV has %d entries but GridLevels=%d", n, GridLevels));
      return(false);
     }

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   ArrayResize(lots, n);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      double lot = StringToDouble(s);

      if(lot < minLot || lot <= 0.0)
        {
         HydraLog(StringFormat("INIT FAIL: lot[%d]='%s' invalid (min lot %.2f)", i, s, minLot));
         return(false);
        }
      if(lotStep > 0.0 && MathAbs(MathRound(lot / lotStep) * lotStep - lot) > 0.0000001)
        {
         HydraLog(StringFormat("INIT FAIL: lot[%d]=%.4f not aligned to lot step %.4f", i, lot, lotStep));
         return(false);
        }
      lots[i] = lot;
     }
   return(true);
  }
//+------------------------------------------------------------------+
