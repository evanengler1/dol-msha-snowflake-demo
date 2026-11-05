# Phase 3 CoCo Prompt: DOL MSHA Demo — Streamlit in Snowflake Dashboard

> Paste this prompt into a new CoCo session to execute Phase 3.

---

## Prompt

I'm continuing an end-to-end Snowflake demo using **real, public Mine Safety and Health Administration (MSHA) data** from the U.S. Department of Labor Open Data Portal (https://data.dol.gov/). Phases 1–2 are complete: raw data is loaded, transformed, and exposed through `ANALYTICS` views. This session covers **Phase 3: a Streamlit in Snowflake dashboard**.

**Why this demo exists:** DOL asked for "ways to identify trends in mine safety accidents using metrics such as methane levels, temperature, etc." The portal has **no methane, temperature, or sensor readings**, and DOL confirmed we use portal data only, with no synthetic data. The story is **accident trends plus the leading indicators the portal does have**: ventilation/methane citations (30 CFR 75 Subpart D), S&S violations, negligence, 104(d)/107(a) actions, penalties, and prior injuries. The dashboard must say plainly that these are **compliance proxies, not sensor readings**.

The audience is technical DOL IT staff (an enterprise architect, IT specialists, and a data engineer) who will take it to MSHA.

### Overall Demo Plan (for reference)

| Phase | Deliverable | Key Snowflake Features | Status |
|-------|------------|----------------------|--------|
| 1 | Data extraction + ingestion | Python, portal ZIPs → S3, external stage, COPY INTO | **Done** |
| 2 | Transformation + SQL EDA | CTAS, typing, window functions, incidence rates, lagged features, views | **Done** |
| 3 | **Streamlit dashboard** | **Streamlit in Snowflake (container runtime), Plotly/Altair, pydeck** | **This session** |
| 4 | React app (mine safety early-warning profile) | Snowflake App Runtime (`snow app`), Next.js | Upcoming |
| 5 | CoWork agent | Cortex Agent, semantic view, Cortex Search over accident narratives | Upcoming |

### How Phase 3 Differs from Phase 4 (stay on this side of the line)

| | **Phase 3 Streamlit (this session)** | Phase 4 React |
|---|---|---|
| Question | "Where and why are miners getting hurt, and what comes first?" across **all mines** | "What is the risk at **this** mine?" |
| User | Analyst / program staff / leadership looking at the industry | Inspector / district manager before a visit |
| Grain | Nation, state, year, hazard category, quartile | One mine, its quarters, its citations and accidents |
| Leading indicators | **Proves** they separate risk across the population (quartile charts), and shows which do not | **Applies** them to one mine as an early-warning risk card |
| Risk score | **None.** Percentiles and quartiles only | Owns the scoring/grade logic |
| Mines | Appear only as ranked rows (top-N tables, map points with tooltips) | Typeahead search, full profile, timeline, narratives, peers |

Do **not** build a mine profile page, a mine search, or any risk score here.

### What Exists from Phases 1–2

- **Account:** <your account> · **Database:** `DOL_MSHA_DEMO` (`RAW`, `TRANSFORMED`, `ANALYTICS`) · **Warehouse:** `DOL_MSHA_WH` (X-Small) · **Role:** `DOL_MSHA_DEMO_ROLE` (owns everything)
- **Scripts:** `sql/01_setup.sql` … `sql/08_eda_queries.sql`. EDA output: ``eda_output.txt` (from sql/08)`
- **Read only from `ANALYTICS`** (the interface layer). If a page needs heavy SQL against `TRANSFORMED`, add or adjust a view in a new script instead.

| View | Grain | Key columns / notes |
|---|---|---|
| `NATIONAL_TRENDS` | year × `mine_category` (`Coal`, `Metal/Nonmetal`, `All Mines`) | `operator_injury_rate_per_200k_hours`, `operator_lost_time_rate_per_200k_hours`, `all_workers_injury_rate_per_200k_hours`, `fatalities`, `fatality_rate_per_200m_hours`, hours, violations, `significant_substantial_rate`, `ventilation_methane_violations(_per_200k_hours)`, `proposed_penalties_usd`, `is_partial_year` |
| `STATE_TRENDS` | state × year × `mine_category` | operator rates, fatalities, ignition events, violations, `state_latitude/longitude` centroids, `is_partial_year` |
| `ACCIDENT_DETAIL` | 1 row per person per accident | labels, `is_fatal`, `is_lost_time_injury`, `is_ignition_explosion_fire`, `narrative` (max 384 chars; portal-truncated), mine lat/long |
| `VIOLATION_DETAIL` | 1 row per violation (1.79M) | `hazard_category` label, S&S, 104(d)/107(a), negligence, penalties, `penalty_status`. **Always aggregate in SQL; never pull to pandas** |
| `HAZARD_TRENDS` | hazard category × year × `mine_category` | counts, S&S / high-negligence rates, `violations_per_200k_operator_hours`, `is_partial_year` |
| `ACCIDENT_PATTERNS` | year × category × classification × injury source | `reportable_injuries`, `lost_time_injuries`, `fatalities`, experience |
| `MINE_QUARTER_TRENDS` | mine × quarter (1.38M) | aggregate only |
| `LEADING_INDICATORS` | mine × quarter (1.38M) | `is_comparable` (4 prior quarters, ≥20K prior hours, known outcome; 214K rows), six `*_quartile` columns (**0 = indicator was zero; 1–4 = quartiles of non-zero values within mine category**), `next_quarter_operator_injuries`, `next_quarter_operator_hours`, `had_injury_next_quarter` |
| `MINE_PROFILE` | 1 row per mine (92K) | lat/long, `has_geo_issue`, status, last-4Q indicators, peer percentiles. Use for map points and top-N only |
| `OPERATOR_PORTFOLIO` | current operator | mines, last-4Q rate, fatalities, enforcement, `open_delinquent_penalty_balance_usd` |

**Rate rules (must hold on every page):**
- Pooled rates = `SUM(injuries) * 200000 / SUM(hours)`. **Never average per-row rates.**
- Label the basis: "operator" (operator injuries / operator hours; mine and state level) vs "all workers" (operator + contractor; national only).
- 2026 is **partial** (hours through 2026 Q2). Show it as hollow or dashed, exclude it from trend deltas, and say so.
- Apply a minimum-hours threshold to any mine or state ranking (≥ 200K hours/year for mines, ≥ 2M hours over the period for states).

### Pages (traditional `pages/` layout; **4 pages maximum**)

Keep the app to these four pages. Use `st.tabs` within a page rather than adding pages.

1. **`streamlit_app.py`: Overview ("Where are miners getting hurt?")**
   - KPI tiles: 2025 all-workers injury rate (1.73) vs 2010 (2.83), fatalities 2025, operator hours, ventilation/methane citations. Each tile carries a small provenance caption naming its source view.
   - Line chart: operator injury rate by year, Coal vs Metal/Nonmetal (coal ≈ 2× M/NM), with 2026 marked partial. Secondary chart: fatalities by year (2010 spike = Upper Big Branch, 29 deaths).
   - **Accident patterns** section (filters: mine category, year range): top classifications and injury sources (horizontal bars), and the 2010–12 vs 2023–25 share comparison (e.g. roof falls 4.7% → 2.5%, powered haulage 8.0% → 9.3%).
   - A short "About this data" expander: portal-only, no sensor data, rate definitions (reportable = degree 01–06, lost-time = 02–05; **not yet confirmed against MSHA's published methodology**), and the partial-year rule.
2. **`pages/1_Ventilation_Methane_Proxy.py`**
   - A prominent callout at the top: "The DOL portal contains no methane, temperature, or sensor readings. This page uses cited 30 CFR sections as compliance proxies." Note that `methn_librtn` is populated for only 0.27% of mines.
   - Ventilation & Methane citations per 200K operator hours (coal) by year, and a hazard-category comparison (stacked or small multiples).
   - Profile of ventilation/methane citations vs all other coal citations: S&S share 17% vs 26%, but roughly 2× the high-negligence and 104(d)/107(a) rates.
   - Ignition / explosion / fire accidents by year and classification, the top states (AL leads gas/dust ignitions with 121; WV leads fatalities), and a few recent ignition narratives from `ACCIDENT_DETAIL`.
3. **`pages/2_Leading_Indicators.py`** (the centerpiece)
   - Filters: mine category; indicator selector or a 2×3 small-multiples grid.
   - For each indicator, a bar chart of the pooled next-quarter injury rate by quartile (0, 1–4), computed in SQL from `LEADING_INDICATORS WHERE is_comparable`. Also show `% of mine-quarters with any injury next quarter`.
   - A "holds up / doesn't hold up" panel driven by the data, not hard-coded text where avoidable:
     - **Holds up (coal):** prior injury rate 1.4 → 7.2, ventilation/methane 1.5 → 5.7, 104(d)/107(a) 2.8 → 5.8, high negligence 2.1 → 5.3.
     - **Doesn't hold up:** S&S *share* of violations (correlation ≈ 0); inspection intensity (MSHA targets risky mines, so this is reverse causation); M/NM S&S per 200K hours (small mines inflate the ratio).
   - Methodology expander: no leakage (prior 4 quarters only), outcome = next quarter, comparable-row filter, quartile definition, "associations, not a predictive model."
4. **`pages/3_Map_and_Operators.py`** (tabs: **Map** · **Operators & Penalties**)
   - **Map tab:** a state layer built with **pydeck `GeoJsonLayer` + a bundled `us-states.json`**, colored by operator injury rate (selectable year range and category). Plotly choropleths do **not** work in SiS. Add a mine point layer (`ScatterplotLayer`) from `MINE_PROFILE WHERE NOT has_geo_issue AND has_recent_hours`, sized by last-4Q hours and colored by injury-rate peer percentile. The tooltip shows name, operator, state, and last-4Q rate. No click-through to a profile; that is Phase 4.
   - **Operators & Penalties tab:** an operator leaderboard from `OPERATOR_PORTFOLIO` (min-hours filter; sortable by rate, fatalities, ventilation citations, open balance), and penalty outcomes: 87% of proposed dollars paid, about $70M open/delinquent, about $70M uncollectable/bankrupt (donut or bar chart, plus the top open balances).

### Design

Adapt my preferred light "command-center" look to Streamlit via `.streamlit/config.toml` plus light CSS:
- Light background (`#fafafa`), white cards, hairline borders, navy `#0b2545` primary, teal `#0e7c7b` for "good/declining", amber `#d97706` only for risk/exposure.
- Consistent chart palette: Coal = navy, Metal/Nonmetal = teal; partial periods hollow/dashed.
- Sidebar branding: "DOL · MSHA Mine Safety Analytics", a data-as-of date (max `accident_date`/hours quarter), and the "portal data only" note.
- Every chart gets a one-line takeaway caption above it ("Coal mines run about twice the injury rate of metal/nonmetal mines"). Keep the wording plain.

### Technical Requirements (known SiS gotchas; follow these)

- **Container runtime** (`SYSTEM$ST_CONTAINER_RUNTIME_PY3_11`, compute pool `SYSTEM_COMPUTE_POOL_CPU`). Include a **`pyproject.toml`** (and no `environment.yml`); add the PyPI EAI `PYPI_ACCESS_INTEGRATION` in `snowflake.yml`. First check `SHOW GRANTS ON INTEGRATION PYPI_ACCESS_INTEGRATION`. If `DOL_MSHA_DEMO_ROLE` lacks USAGE, give me the ACCOUNTADMIN `GRANT` to run.
- **Use the `pages/` layout**, not `st.navigation()`. Put `sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))` at the top of every page file so `utils.py` imports work.
- **Maps:** pydeck only (`GeoJsonLayer` with bundled GeoJSON; Carto basemap). No Plotly geo, no CDN fetches.
- **Data access:** a shared `utils.py` with one cached query helper (`st.cache_data(ttl=3600)`) and a `get_session()` that works in SiS (`get_active_session()`) and locally (`st.connection("snowflake")` with no `connection_name` kwarg). Convert `Decimal` columns to float only where they are Decimal-valued, so ID codes keep their leading zeros.
- **Performance:** every query aggregates in Snowflake; nothing pulls `VIOLATION_DETAIL`, `MINE_QUARTER_TRENDS`, or `LEADING_INDICATORS` raw rows. Target < 3s per page on X-Small.
- **Deployment:**
  - Create schema `DOL_MSHA_DEMO.APPS` (never PUBLIC) in a new `sql/09_streamlit_setup.sql`, and deploy with `snow streamlit deploy --replace` as `DOL_MSHA_DEMO_ROLE`, query warehouse `DOL_MSHA_WH`, app name `MSHA_SAFETY_DASHBOARD`.
  - Put the code under `streamlit/` with `snowflake.yml`, `pyproject.toml`, `streamlit_app.py`, `pages/`, `utils.py`, `assets/us-states.json`, and `.streamlit/config.toml`.
- **Verify locally first** (`streamlit run`, with each page loading without errors), then deploy, then confirm the app object exists and give me the Snowsight URL. The Snowsight browser panel isn't signed in, so ask me to check the deployed app visually.


### Important Notes

- Read only from `ANALYTICS`. Do not modify `RAW` or `TRANSFORMED`; any new view goes in a new numbered script (`sql/09_…`, `sql/10_…`) with `CREATE OR REPLACE`.
- Never use the PUBLIC schema. `DOL_MSHA_DEMO_ROLE` owns the schema and the Streamlit object.
- Methane and temperature readings are **not** in the portal. Do not imply they are; call hazard categories "compliance proxies."
- Never sum `persons_injured_in_event`. Never show a rate for a period without hours. Mark 2026 as partial everywhere it appears.
- **Stay in Phase 3 scope:** no React, semantic view, Cortex Search, Cortex Agent, ML model, mine profile page, or risk score.
- If a number in this prompt doesn't match what the views return, trust the views and tell me; don't silently change the copy.
