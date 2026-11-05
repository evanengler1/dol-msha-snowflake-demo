# Phase 2 CoCo Prompt: DOL MSHA Demo — Transformation, EDA, and SQL Scripts

> Paste this prompt into a new CoCo session to execute Phase 2.

---

## Prompt

I'm continuing an end-to-end Snowflake demo using **real, public Mine Safety and Health Administration (MSHA) data** from the U.S. Department of Labor Open Data Portal (https://data.dol.gov/). Phase 1 is complete: raw data is loaded into Snowflake. This session covers **Phase 2: transformation, SQL EDA, and reproducible SQL scripts**.

**Why this demo exists:** DOL asked for "ways to identify trends in mine safety accidents using metrics such as methane levels, temperature, etc." The portal has **no methane, temperature, or sensor readings**, and DOL confirmed that we use portal data only, with no synthetic data. So the story is **accident trends plus the leading indicators the portal does have**: ventilation/methane citations (30 CFR 75 Subpart D), S&S violations, negligence, inspection intensity, penalties, and prior injuries. Every deliverable must say plainly that these are compliance proxies, not sensor readings.

The audience is technical DOL IT staff (an enterprise architect, IT specialists, and a data engineer) who will take it to MSHA. Keep the SQL clean and explainable.

### Overall Demo Plan (for reference)

| Phase | Deliverable | Key Snowflake Features | Status |
|-------|------------|----------------------|--------|
| 1 | Data extraction + ingestion | Python, portal ZIPs → S3, external stage, COPY INTO | **Done** |
| 2 | **Transformation + SQL EDA** | **CTAS, proper typing, joins, window functions, incidence rates, lagged features, views** | **This session** |
| 3 | Streamlit dashboard | Streamlit in Snowflake, charts, filters, pydeck map | Upcoming |
| 4 | React app (mine safety early-warning profile) | Snowflake App Runtime (snow app), Next.js | Upcoming |
| 5 | CoWork agent | Cortex Agent, semantic view, Cortex Search over accident narratives | Upcoming |

### What Exists from Phase 1

- **Account:** <your account>
- **Database:** `DOL_MSHA_DEMO`, schemas `RAW`, `TRANSFORMED` (empty), `ANALYTICS` (empty)
- **Warehouse:** `DOL_MSHA_WH` (X-Small). **Role:** `DOL_MSHA_DEMO_ROLE` (owns everything)
- **Stage / format:** `RAW.MSHA_RAW_STAGE` (`s3://<your-bucket>/msha-raw/`), `RAW.MSHA_CSV_GZ`; integration `<your_s3_integration>` (shared; do not touch)
- **Scripts:** `sql/01_setup.sql` … `sql/04_verify.sql`, `process_msha_data.py`, `data/manifest.json`
- **RAW tables:** all `VARCHAR`, values exactly as the source provides, plus `_source_file` and `_loaded_at`. Lowercase column names. Fact tables are filtered to 2010+.

| RAW table | Rows | Grain / key (verified unique) | Notes |
|---|---|---|---|
| `MSHA_ACCIDENT` | 126,171 | `document_no` | One row per **person** in an accident event (see `no_injuries` below). Has `ai_narr`. 2010-01-01 → 2026-10-28 |
| `MSHA_INSPECTION` | 671,793 | `event_no` | 2010-01-02 → 2026-10-29 |
| `MSHA_VIOLATION` | 1,787,409 | `viol_no` | 2010-01-01 → 2026-10-29. No free-text column |
| `MSHA_ASSESSED_VIOLATIONS` | 3,597,464 | `citation_nbr` | Full history (1995+). Joins to `violation.viol_no` |
| `MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY` | 1,667,657 | `petreemine_id` + `subunit_cd` + yr + qtr | `petreemine_id` **is** the mine ID. Latest quarter 2026 Q2 |
| `MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_ANNUAL` | 395,952 | `mine_id` + `subunit_cd` + `calendar_yr` | |
| `MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_QUARTERLY` | 908,704 | `cntctr_id` + `subunit_cd` + yr + qtr + `cmdty_type` | **82 duplicate rows** on that key. **No mine_id** |
| `MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_ANNUAL` | 180,505 | `cntctr_id` + `subunit_cd` + `calendar_yr` + `cmdty_type` | **No mine_id** |
| `MSHA_MINES` | 92,102 | `mine_id` | Lat/long, district, state, status, commodity |
| `MSHA_OPERATOR_HISTORY_AT_MINES` | 136,043 | | `mine_id`, `oper_id`, start/end dates |
| `MSHA_CONTRACTOR_HISTORY_AT_MINES` | 141,821 | | `mine_id`, `cntctr_id`, start/end dates |
| `MSHA_CONTROLLER_HISTORY` | 78,632 | | `oper_id` → `ctrlr_id`, start/end dates |
| `MSHA_COMMODITY_LOOKUP` | 128 | `cmmdty_cd` | |
| `MSHA_CONTRACTOR_NAME_ID_LOOKUP` | 91,067 | `cntctr_id` | |

Phase 1 join coverage: accident→mines 100%, quarterly hours→mines 100%, violation→inspection 99.81%, violation→assessed 97.69%.

### Shape of the Data (read this first)

MSHA is a **relational model around `MINE_ID`**, with three event streams (accidents, inspections, violations) and a denominator (hours worked). The key transformation work is:

1. **Type and decode** each event table.
2. **Compute incidence rates correctly.** The headline metric is the injury rate per 200,000 hours worked (100 full-time workers for a year), not raw counts. Hours exist only in the employment/production tables.
3. **Build a mine × quarter fact** that aligns accidents, violations, inspections, penalties, and hours. Then add **lagged leading-indicator features** next to **next-quarter outcomes**. This is how "leading indicators" becomes concrete and testable.

### Data Quality Notes (profiled from RAW; handle all of these)

| Pattern | Observed | Handling |
|---|---|---|
| **Dates with offset** | `2006-08-25 00:00:00+00:00` | `TRY_TO_TIMESTAMP_TZ(NULLIF(NULLIF(TRIM(col),''),'NaT'))::DATE` |
| **Null markers** | `''` and `NaT` everywhere; `nan` in `mines.latitude`/`longitude` (44,298 rows) | Treat `''`, `NaT`, `nan` as NULL before every cast. **Note:** `TRY_TO_DOUBLE('nan')` returns NaN, not NULL, so null `nan` explicitly |
| **Longitude sign** | 92,096 mines have **positive** longitude for U.S. sites; only 6 are negative | Store `longitude = -ABS(value)` for U.S. mines and comment why. Validate lat/long ranges (CONUS, AK, HI, PR) and flag out-of-range values as `has_geo_issue` |
| **`no_injuries` is event-level** | Repeated on each person's row (36 rows each say `36`) | **Never SUM it.** Count injured persons as rows. Keep it as an attribute only |
| **Accident-only rows** | `degree_injury_cd = '00'` (12,641) and `no_injuries = 0` (12,640) | Reportable accidents without an injury. Keep them; exclude them from injury rates |
| **Degree of injury codes** | `00` accident only · `01` fatality · `02` perm disability · `03` days away only · `04` days away & restricted · `05` restricted only · `06` no days away/no restriction · `07` occupational illness · `08` natural causes · `09` non-employees · `10` other incl. first aid | Decode to labels. Derive `is_fatal`, `is_lost_time` (02–05), `is_reportable_injury`. **Verify the NFDL definition against MSHA's published incidence-rate methodology** before finalizing; state the definition you used in a SQL comment |
| **Time sentinel** | `accident_time = '9999'` (~10K rows) | NULL, not a time |
| **`days_lost` blank** | 9,636 rows | NULL, not zero |
| **Operator vs contractor injuries** | 14,069 accidents have a `cntctr_id`; 112,102 are operator employees | Contractor hours have no `mine_id`, so **mine-level rates use operator hours and operator-employee injuries only**. National/industry rates may use operator + contractor hours with all injuries. Label each rate with its basis |
| **Hours lag accidents** | Hours end at **2026 Q2**; accidents run to Oct 2026. A naive 2026 rate is 2.89 vs 1.73 in 2025 | Only compute rates for periods where hours exist. Flag `is_partial_period` and exclude it from trend comparisons |
| **Hours sanity** | National operator hours ≈ 453M (2024), quarterly = annual | Use **quarterly** hours (finer grain); reconcile to annual in EDA |
| **Coded violation fields** | `sig_sub` Y/N; `likelihood` NoLikelihood/Unlikely/Reasonably/Highly/Occurred; `inj_illness` NoLostDays/LostDays/Permanent/Fatal; `negligence` NoNegligence/Low/Mod/High/Reckless; `cit_ord_safe` Citation/Order/Safeguard; blanks in 26,745 rows | Keep codes; add ordinal scores (likelihood 0–4, negligence 0–4) and booleans (`is_sig_sub`, `is_order`, `is_high_negligence` = High or Reckless). Blanks → NULL |
| **Unwarrantable failure / orders** | `type_of_actn_1` contains `104(d)(1)`, `104(d)(2)`, `104(b)`, `107(a)` imminent danger, `103(k)` | Derive `is_unwarrantable_failure` (104(d)) and `is_imminent_danger` (107(a)). Verify these meanings and state them in comments |
| **`part_section` blank** | 22,525 rows | NULL; hazard category `Unknown` |
| **Assessed status** | `last_action_code` is mostly `Paid`; also `Uncollectable`, `Treasury`, bankruptcy codes, `Vacated…` | Keep the code; derive `penalty_status_group` (Paid / Open-Delinquent / Uncollectable-Bankrupt / Vacated / Contested-Other) |
| **IDs keep leading zeros** | `mine_id = '0200024'`, `event_no = '0912095'` | IDs stay `VARCHAR`. Never cast them to numbers |
| **Contractor quarterly duplicates** | 82 duplicate key rows | Deduplicate with `QUALIFY ROW_NUMBER()`, and report how many rows were removed |

### Hazard Category Reference (the methane/ventilation proxy)

Classify each violation by `part_section` into a `hazard_category`. Store the mapping as `TRANSFORMED.HAZARD_CATEGORY_REF` (`category_code`, `label`, `cfr_reference`, `match_rule`, `description`) so the labels live in one place. Starting map (the part prefixes and counts are verified; **confirm the section ranges against 30 CFR** and sample a few rows per category):

| Category | Match on `part_section` | Why it matters |
|---|---|---|
| **Ventilation & Methane** | `75.3xx` (30 CFR 75 Subpart D; 137,845 violations, 7.7%) | Closest proxy for methane/air quality. **Headline proxy** |
| Combustible Material & Rock Dust | `75.4xx` (Subpart E) | Coal dust explosion risk |
| Electrical / Permissibility | `75.5xx`–`75.10xx` electrical subparts | Ignition sources |
| Roof & Rib Control | `75.2xx` (Subpart C) | The leading underground fatality cause historically |
| Respirable Dust | Part `70`, `71`, `72`, `90` | Black lung |
| Other Underground Coal | other `75.*` | |
| Surface Coal | Part `77` | |
| Metal/Nonmetal Surface | Part `56` (726K, the largest) | |
| Metal/Nonmetal Underground | Part `57` | |
| Reporting & Training | Parts `50`, `46`, `48`, `62` | |
| Other / Unknown | everything else, blank | |

Also flag accidents in `ai_class_desc IN ('IGNITION OR EXPLOSION OF GAS OR DUST', 'FIRE', 'EXPLODING VESSELS UNDER PRESSURE')` as `is_ignition_explosion_fire`. There are 531 gas/dust ignitions since 2010. This is the outcome side of the methane story.

### What I Need You to Do (Phase 2)

All work goes into script files in `sql/`, continuing the numbering (`05_`, `06_`, `07_`, …), so the whole demo can be rebuilt from a repo. Use `DOL_MSHA_DEMO_ROLE` and `DOL_MSHA_WH`.

#### 1. TRANSFORMED — typed, decoded tables (`sql/05_transformed_tables.sql`)

One table per entity, typed and with readable column names. Keep `_loaded_at`.

- **`MINE`**: one row per `mine_id`. Name, `coal_metal` (C/M decoded), mine type, current status and status date, operator/controller IDs and names, state, county, district, office, primary SIC/canvass/commodity, employee count, `mine_gas_category_cd` and `methn_librtn` (methane liberation: **investigate this column; if it is populated, it is the only methane-related measure in the portal**), lat/long fixed per the notes, `has_geo_issue`.
- **`ACCIDENT`**: one row per `document_no`. Typed dates, decoded degree, `is_fatal`, `is_lost_time`, `is_reportable_injury`, `is_contractor` (has `cntctr_id`), classification, accident type, injury source/nature/body part, mining equipment, experience (years, `NUMBER(6,2)`), `days_lost`, `days_restricted`, `is_ignition_explosion_fire`, `accident_year`, `accident_quarter`, and **`narrative` (`ai_narr`, kept verbatim for Cortex Search in Phase 5)**.
- **`INSPECTION`**: one row per `event_no`. Activity code/description, begin/end dates, `inspection_days`, `total_insp_hours`, `total_on_site_hours`, `nbr_inspectors`, sample counts (air, respirable dust, noise, …), `coal_metal`, and `is_regular_inspection` (verify against `acty_desc`).
- **`VIOLATION`**: one row per `viol_no`. Typed dates, decoded and ordinal gravity/negligence fields, the booleans above, `hazard_category`, `violator_type` (Operator/Contractor), `cntctr_id`, and termination dates. Join the **assessed penalty** on `citation_nbr = viol_no` (LEFT JOIN): `proposed_penalty`, `current_assessment`, `amount_paid` (`NUMBER(14,2)`), and `penalty_status_group`.
- **`EMPLOYMENT_QUARTERLY`**: `mine_id` (from `petreemine_id`) × subunit × year × quarter: hours, average employees, coal production.
- **`CONTRACTOR_EMPLOYMENT_QUARTERLY`**: deduplicated; contractor × subunit × year × quarter × commodity.
- **History tables** (operator, contractor, controller) with typed start/end dates and `is_current`.
- **`HAZARD_CATEGORY_REF`** and a **`DEGREE_OF_INJURY_REF`** lookup.

Rules:
- `CREATE OR REPLACE TABLE … AS SELECT` for idempotency.
- **CTAS width trap:** expressions produce `VARCHAR(16777216)`, so `CAST(… AS VARCHAR(N))` every string column.
- `TRY_TO_*` everywhere; count conversion failures in EDA rather than letting them break the build.
- Do not modify RAW.

#### 2. TRANSFORMED — mine × quarter fact and leading-indicator features (`sql/06_mine_quarter_fact.sql`)

**`MINE_QUARTER_FACT`**: one row per mine × calendar quarter, 2010 Q1 → latest quarter with hours. Build a mine × quarter spine from mines that have hours, accidents, or inspections in the period.
- **Outcomes:** reportable injuries (operator employees), lost-time injuries, fatalities, days lost, ignition/explosion/fire events, contractor injuries (attributed to the mine, but not in the mine rate).
- **Exposure:** operator hours, average employees, coal production.
- **Rates (per 200,000 hours, NULL when hours = 0):** `injury_rate`, `lost_time_rate`.
- **Enforcement activity:** inspections, inspection hours, violations, S&S violations, orders, 104(d) and 107(a) actions, high-negligence violations, ventilation/methane violations, rock-dust and electrical violations, average likelihood score, proposed penalties.
- **Normalized indicators:** S&S rate (`ss_violations / violations`), violations per inspection hour, ventilation violations per 200K hours.
- `is_partial_period` and `has_hours`.

**`MINE_QUARTER_FEATURES`**: the leading-indicator view of the same grain. For each mine × quarter:
- **Trailing features (no leakage; prior quarters only):** trailing 4-quarter totals for violations, S&S, ventilation/methane, 104(d)/107(a), high negligence, penalties, inspection hours, prior injuries, and the trailing 4-quarter injury rate. Use window frames like `ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING`, and keep the spine gap-free so the frames mean quarters.
- **Outcome:** next-quarter injuries, next-quarter lost-time injuries, `had_injury_next_q`, and `had_lost_time_next_q`.
- **No model training in this phase.** This table is the input for a later phase. Prove it is useful with EDA (below).

Document the leakage rule and the spine logic in comments; the data engineer will read them.

#### 3. ANALYTICS — views for Phases 3–5 (`sql/07_analytical_views.sql`)

These views are the **interface layer**. Streamlit, the React app, and the Cortex Agent read only from `ANALYTICS`. Use human-readable column names (`injury_rate_per_200k_hours`, not `inj_rt`) and labels, not codes, because Phase 5's agent generates SQL from these names.

| View | Grain | Feeds |
|---|---|---|
| `NATIONAL_TRENDS` | year (+ coal/metal) | Streamlit overview: injuries, fatalities, hours, incidence rate, violations, S&S rate, penalties, with the partial-year flag |
| `STATE_TRENDS` | state × year (+ coal/metal) | Streamlit map/trends |
| `ACCIDENT_DETAIL` | 1 row per accident | Drill-down tables, React accident history, Cortex Search source (includes `narrative`, mine name, state, labels) |
| `VIOLATION_DETAIL` | 1 row per violation | React citation history, hazard breakdowns, agent |
| `HAZARD_TRENDS` | hazard category × year (+ coal/metal) | Streamlit "ventilation & methane proxy" page |
| `ACCIDENT_PATTERNS` | classification × injury source × year | Streamlit "what is hurting miners" page |
| `MINE_PROFILE` | 1 row per mine | React search + profile header, risk card inputs |
| `MINE_QUARTER_TRENDS` | mine × quarter | React mine trend chart (outcomes and indicators on one timeline) |
| `LEADING_INDICATORS` | mine × quarter | Streamlit leading-indicator page; React early-warning panel |
| `OPERATOR_PORTFOLIO` | current operator (and controller) | Streamlit/agent: "which companies' mines carry the most risk" |

**`MINE_PROFILE`** must pre-compute the inputs for Phase 4's **early-warning risk card**:
- Lifetime and last-4-quarter injury rate, plus the mine's percentile within peers (same coal/metal, mine type, and size band, using `PERCENT_RANK`).
- Last-4-quarter S&S rate, ventilation/methane violations, 104(d)/107(a) count, high-negligence count, penalties, and open/delinquent penalty balance.
- Each indicator's percentile vs peers, and the trend direction vs the prior 4 quarters.
- Fatalities (ever / since 2020), last accident date, last inspection date, current operator/controller, status, lat/long.

**Do not compute a risk score or grade here.** Phase 4 owns that logic; expose only the inputs and percentiles.

#### 4. EDA (`sql/08_eda_queries.sql`): run these and show me the results

**Validation**
- RAW vs TRANSFORMED row counts per table (and rows removed by deduplication).
- Conversion-failure counts per typed column.
- Date range per date column; rows flagged for date or geo issues.
- Mine coverage: % of accidents, violations, and inspections whose `mine_id` is in `MINE`; % of mine-quarters with hours.
- Hours reconciliation: quarterly sum vs annual by year.
- Penalty join: % of violations with an assessed penalty, by year (recent years should be lower because assessment lags).
- `methn_librtn` and `mine_gas_category_cd`: population rate and value distribution. Is either usable?

**Findings** (what an MSHA analyst would want to see)
- National injury rate, lost-time rate, and fatalities by year, coal vs metal/nonmetal, with the partial-year caveat stated explicitly.
- Top accident classifications and injury sources; how the mix has changed since 2010.
- Ventilation/methane violation trend (count and per 200K hours), and their S&S and negligence profile vs all violations.
- Ignition/explosion/fire accidents by year and state.
- Top 10 states and top 10 mines by injury rate (with a minimum-hours threshold, e.g. ≥ 200K hours per year) and by fatalities.
- **Leading-indicator evidence:** using `MINE_QUARTER_FEATURES`, compare next-quarter injury rates across quartiles of each trailing indicator (S&S, ventilation/methane, 104(d)/107(a), high negligence, prior injuries, inspection hours). Use `CORR` where it helps. Which indicators separate high-risk from low-risk mine-quarters? Be honest if any don't.
- Penalty outcomes: share of proposed penalties paid vs uncollectable/vacated, and the top operators by open balance.
- Narrative check: length distribution, and a few narratives from fatal and ignition accidents (Phase 5 preview).

After running, summarize the **5–8 most demo-worthy findings** as talking points for the Phase 3 dashboard and the Phase 4 app. Name at least one leading indicator that holds up and one that doesn't.

#### 5. Ownership

`DOL_MSHA_DEMO_ROLE` must own every table and view in `TRANSFORMED` and `ANALYTICS`.

### How Phases 3–5 Will Use This (design target)

- **Phase 3 Streamlit, "Where and why are miners getting hurt, and what comes first?"** Pages:
  - National overview: incidence rate, fatalities, and hours by year, coal vs metal.
  - Accident patterns (classification, source, equipment).
  - Ventilation & methane proxy (hazard trends, ignition events, with the explicit "no sensor data in the portal" note).
  - Leading indicators (quartile charts from `LEADING_INDICATORS`).
  - State/mine map (pydeck, fixed longitudes).
- **Phase 4 React, Mine Safety Early-Warning Profile.** Mine typeahead search, then:
  - Profile header and map.
  - Accident and injury-rate timeline with citations and inspections overlaid (`MINE_QUARTER_TRENDS`).
  - Early-warning risk card built from `MINE_PROFILE` percentiles.
  - Recent citations by hazard category.
  - Accident history with narratives.
  - Peer comparison.
- **Phase 5 CoWork agent:** a semantic view over the ANALYTICS views, plus Cortex Search over `ACCIDENT_DETAIL.narrative`.

Use these consumers to test whether a view is shaped right. If a page or feature would need heavy SQL against `TRANSFORMED`, add or adjust a view instead.


### Important Notes

- All SQL goes into numbered scripts under `sql/`; every object must be recreatable from them. `CREATE OR REPLACE` throughout.
- Never use the PUBLIC schema. Do not modify RAW.
- IDs, ZIPs, SIC/NAICS, and `part_section` stay strings. Amounts are `NUMBER(14,2)`. Rates are `NUMBER(10,4)`.
- Never sum `no_injuries`. Never compute a rate for a period without hours.
- Methane and temperature readings are **not** in the portal. Do not imply they are. Call the hazard categories "compliance proxies."
- **Stay in Phase 2 scope:** no Streamlit, React, semantic view, Cortex Search, Cortex Agent, or ML model in this session, and no risk-score logic (inputs and percentiles only).
- If a field, code meaning, or regulation range in this prompt turns out to be wrong when you check the data or 30 CFR, tell me; don't silently work around it.
