# Phase 5 CoCo Prompt: DOL MSHA Demo — MSHA Safety Agent in Snowflake CoWork

> Paste this prompt into a new CoCo session to execute Phase 5.

---

## Prompt

I'm finishing an end-to-end Snowflake demo using **real, public Mine Safety and Health Administration (MSHA) data** from the DOL Open Data Portal (https://data.dol.gov/). Phases 1–4 are complete:
- raw data is loaded and transformed (`RAW`, `TRANSFORMED`)
- `ANALYTICS` views and Dynamic Tables exist, including the per-mine early-warning tier
- a Streamlit dashboard (`DOL_MSHA_DEMO.APPS.MSHA_SAFETY_DASHBOARD`) shows industry trends and proves which leading indicators separate risk
- a React app on Snowflake App Runtime (`DOL_MSHA_DEMO.APPS.MSHA_EARLY_WARNING_APP`) gives per-mine briefings, a district watch list and comparisons

This session covers **Phase 5: a Cortex Agent in Snowflake CoWork that answers MSHA questions in plain English**, combining Cortex Analyst over a semantic view with Cortex Search over accident narratives.

**Why this demo exists:** DOL asked for "ways to identify trends in mine safety accidents using metrics such as methane levels, temperature, etc." The portal has **no methane, temperature, or sensor readings**, and we use portal data only, with no synthetic data. Every methane/ventilation figure is a **compliance proxy** (cited 30 CFR 75 Subpart D sections), and the agent must say so whenever it answers a methane, ventilation or temperature question. The audience is technical DOL IT staff (an enterprise architect, IT specialists, and a data engineer) who will take it to MSHA.

Invoke the `agent-studio` skill first (semantic view + Cortex Analyst + Cortex Agent) and follow it. Use the `search-optimization` skill for the Cortex Search service.

### Overall Demo Plan (for reference)

| Phase | Deliverable | Key Snowflake Features | Status |
|---|---|---|---|
| 1 | Data extraction + ingestion | Python, portal ZIPs → S3, external stage, COPY INTO | **Done** |
| 2 | Transformation + SQL EDA | CTAS, window functions, incidence rates, lagged features, views | **Done** |
| 3 | Streamlit dashboard | Streamlit in Snowflake (container runtime), Plotly, pydeck | **Done** |
| 4 | Mine early-warning app | Snowflake App Runtime, Next.js, snowflake-sdk, Dynamic Tables | **Done** |
| 5 | **CoWork agent** | **Semantic view, Cortex Analyst, Cortex Search, Cortex Agent, Snowflake CoWork** | **This session** |

### How Phase 5 Differs (stay on this side of the line)

| | Dashboard (Phase 3) | App (Phase 4) | **Agent (Phase 5)** |
|---|---|---|---|
| Question | Where and why are miners hurt? | What is the risk at *this* mine? | **Anything, in plain English, with a cited answer** |
| User | Analysts, leadership | Inspectors, supervisors | **Anyone at DOL/MSHA, no SQL** |
| Strength | Curated charts | Per-mine briefing, ranking | **Ad-hoc questions + "find accidents like this" over narratives** |

### What Exists in Snowflake

- **Account:** <your account>. Use `-c <connection>` on every `snow` command.
- **Database:** `DOL_MSHA_DEMO` (`RAW`, `TRANSFORMED`, `ANALYTICS`, `APPS`). **Warehouse:** `DOL_MSHA_WH` (X-Small). **Role:** `DOL_MSHA_DEMO_ROLE` (owns everything).
- **Scripts:** `sql/01_setup.sql` … `sql/11_app_views.sql`. Put Phase 5 DDL in `sql/12_semantic_view.sql`, `sql/13_cortex_search.sql`, `sql/14_agent.sql` (all `CREATE OR REPLACE`, rerunnable). Do not modify `RAW`, `TRANSFORMED`, or existing views/DTs.

| Object | Grain | Use in Phase 5 |
|---|---|---|
| `ANALYTICS.NATIONAL_TRENDS` / `STATE_TRENDS` / `HAZARD_TRENDS` | year × category (× state / hazard) | Trend questions. `STATE_TRENDS` and `HAZARD_TRENDS` include an `'All Mines'` rollup row; always filter category |
| `ANALYTICS.MINE_QUARTER_TRENDS` | mine × quarter | Core fact for the semantic view: injuries, hours, citations by category, 104(d)/107(a), penalties, `is_partial_period` |
| `ANALYTICS.MINE_DIRECTORY` (DT) | 1 row per mine (92K) | Mine dimension: name, state, county, district, field office, operator, controller, category, type, status, peer group, tier |
| `ANALYTICS.MINE_EARLY_WARNING` (DT) | 1 row per mine with recent hours | Tier questions ("Which Elevated mines are in District C04?") |
| `ANALYTICS.ACCIDENT_DETAIL` | person × accident (126K, every row has a narrative, avg ~200 chars, portal-truncated at 384) | Cortex Search source + accident facts |
| `ANALYTICS.VIOLATION_DETAIL` | violation (1.79M) | Citation facts by hazard category/CFR section. Un-pruned LEFT JOINs make broad scans slow; prefer `MINE_QUARTER_TRENDS` / `HAZARD_TRENDS` for aggregates |
| `ANALYTICS.LEADING_INDICATORS` / `EARLY_WARNING_REFERENCE` (DT) | mine × quarter / evidence | "Which signals precede injuries?" questions |
| `ANALYTICS.OPERATOR_PORTFOLIO` | current operator | Operator questions |

`mine_id` is a 7-digit **text** code (e.g. `0100851`); keep it a string.

**Rate rules (must hold in every metric and answer):**
- Pooled rates = `SUM(injuries) * 200000 / SUM(hours)`. Never average per-row rates.
- Label the basis as "operator" (operator injuries / operator hours).
- 2026 is **partial** (hours through 2026 Q2). The agent must say so for any 2026 answer and exclude it from year-over-year comparisons unless asked.
- Never sum `persons_injured_in_event`.
- Never show a rate for a period without hours.

### What to Build

#### 1. Semantic view `ANALYTICS.MSHA_SAFETY_SEMANTIC_VIEW` (`sql/12_semantic_view.sql`)
- **Logical tables:** mine-quarter fact (`MINE_QUARTER_TRENDS`), mine dimension (`MINE_DIRECTORY`), early warning (`MINE_EARLY_WARNING`), accidents (`ACCIDENT_DETAIL`), and hazard trends (`HAZARD_TRENDS`) if it fits. Relationships on `mine_id`.
- **Metrics (names must not collide with physical columns; prefix `TOTAL_`/`POOLED_`):** pooled operator injury rate, lost-time rate, total injuries, fatalities, operator hours, citations, S&S citations, ventilation/methane citations (compliance proxy) and per 200K hours, 104(d)/107(a) actions, high-negligence citations, proposed penalties, mines, accidents.
- **Dimensions:** mine (name, ID), operator, controller, state, county, district, field office, mine category, mine type, commodity, status, size band, peer group, tier, year, quarter, `year_quarter`, partial-period flag, accident classification, degree of injury, occupation, equipment.
- Synonyms and descriptions that say "compliance proxy" on every ventilation/methane field, and "not sensor data".
- **Verified queries (8–12),** including:
  - "Which coal mines in District C04 had the most ventilation citations last year?"
  - "What is the coal operator injury rate by year since 2015?" (2026 flagged partial)
  - "Which Elevated mines are in Kentucky?"
  - "Top 10 operators by fatalities since 2020"
  - "How many 104(d)/107(a) actions were issued in West Virginia in 2025?"
  - "Compare injury rates for underground vs surface coal mines"
- Validate with `reflect_semantic_model` / verify-only creation, then `evaluate_semantic_view` on the VQRs. Report pass/fail and fix failures.

#### 2. Cortex Search service `ANALYTICS.ACCIDENT_NARRATIVE_SEARCH` (`sql/13_cortex_search.sql`)
- Over `ACCIDENT_DETAIL.narrative`, `TARGET_LAG = '7 days'`, `WAREHOUSE = DOL_MSHA_WH`.
- Attributes for filtering: `mine_id`, `mine_name`, `state`, `mine_category`, `mine_type`, `accident_classification`, `degree_of_injury`, `accident_year`, `is_fatal`, `mining_equipment`, `occupation`. Return the accident date and document number so answers can cite them.
- Smoke-test with `SEARCH_PREVIEW`: "roof fall continuous miner", "methane ignition", "conveyor belt entanglement", "fatal powered haulage". Report the top hits.

#### 3. Cortex Agent `APPS.MSHA_SAFETY_AGENT` (`sql/14_agent.sql`)
- Tools: Cortex Analyst over the semantic view; Cortex Search over the narrative service (state the attribute types in the tool description so filters are well-formed).
- **Instructions:**
  - Answer only from MSHA portal data; cite the view or the accident document numbers used.
  - Say "compliance proxy (citations), not sensor readings" for any methane, ventilation, gas or temperature question. Say the portal has no temperature data.
  - Apply the rate rules above; flag 2026 as partial.
  - The early-warning tier is illustrative, not an official MSHA rating or a prediction for any mine.
  - Prefer charts for trends; keep answers short and in plain English.
- **Sample questions** (shown in CoWork): the six VQRs above plus "Find roof-fall accidents involving continuous miners" and "Show fatal accidents involving powered haulage in 2025".
- Make it visible in CoWork (`ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT DOL_MSHA_DEMO.APPS.MSHA_SAFETY_AGENT`, needs ACCOUNTADMIN; give me the exact statement if the demo role can't run it).

#### 4. Close the loop with the other apps
- The React app's architecture page already describes these three objects by these exact names and probes them with `SHOW … LIKE`. After creation, confirm `/api/architecture` reports them as existing, and that no node shows an error or zero. Redeploy the React app only if a code change is needed (ask me first).
- The Streamlit dashboard needs no change.

### Testing (before calling it done)
1. `evaluate_semantic_view`: all VQRs pass (or failures explained and fixed).
2. Run each sample question through `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` and check: the right tool was chosen, numbers match a direct SQL check against `ANALYTICS`, rate rules held, 2026 flagged, the compliance-proxy caveat appears for methane/ventilation questions.
3. Adversarial checks: "What were methane levels at Oak Grove Mine last month?" (must say there are no sensor readings and offer the citation proxy); "Is mine 0100851 going to have an accident?" (must refuse to predict and explain the tier is illustrative); a multi-turn follow-up (resend prior content including tool_use/tool_result).
4. Report a short results table (question, tool, pass/fail, note).
5. Hand off: give me the CoWork URL (https://ai.snowflake.com) and ask me to try the sample questions; the browser panel isn't signed in to Snowsight.

### Gotchas (read first, record as you go)

**Known items before writing DDL:**
- SV DDL: FACTS before DIMENSIONS; relationship targets need PRIMARY KEY/UNIQUE; metric names that match a physical column cause "cyclic reference" or "a fact cannot refer to another aggregate"; prefix metrics.
- SV YAML: use `SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('DB.SCHEMA', $$ ... $$)` (tagged `$yaml$` quoting is not valid Snowflake; keep `;` out of the body); quote any value with a comma; `verified_at` is epoch seconds; VQR field is `sql:`. Debug with the verify-only flag (`TRUE`).
- Relationship columns must be logical dimension names present in both tables.
- Agent DDL: `CREATE AGENT ... FROM SPECIFICATION $$ ... $$`; COMMENT/PROFILE before `FROM SPECIFICATION`; no `QUERY_WAREHOUSE`; `tool_resources` is top-level keyed by tool name; spec changes need DROP + CREATE.
- `evaluate_semantic_view`'s judge may call a model that doesn't exist in this account; review the generated SQL manually if so.
- Search filters: `@eq` on a VARCHAR attribute with a boolean value returns 400; keep `is_fatal` typed consistently and say so in the tool description.
- Cortex Search over a view: confirm change tracking works on the source; if not, materialize a narrow table/DT first (`REFRESH_MODE = FULL` if the source DT is FULL).
- Never use the PUBLIC schema; `DOL_MSHA_DEMO_ROLE` owns all new objects.

**Record new gotchas** as you hit them and list them in the final summary.


### Important Notes
- Portal data only; no synthetic data, no sensor data. Call hazard categories "compliance proxies", everywhere.
- Read-only: the agent writes nothing.
- If a number in this prompt doesn't match what the views return, trust the views and tell me; don't silently change the copy.
- Ask me before changing anything in the deployed React app or the Streamlit dashboard.
