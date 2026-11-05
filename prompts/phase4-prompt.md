# Phase 4 CoCo Prompt: DOL MSHA Demo — Mine Safety Early-Warning App (React, Snowflake App Runtime)

> Paste this prompt into a new CoCo session to execute Phase 4.

---

## Prompt

I'm continuing an end-to-end Snowflake demo using **real, public Mine Safety and Health Administration (MSHA) data** from the DOL Open Data Portal (https://data.dol.gov/). Phases 1–3 are complete:
- raw data is loaded and transformed
- `ANALYTICS` views exist
- a Streamlit dashboard (`DOL_MSHA_DEMO.APPS.MSHA_SAFETY_DASHBOARD`) shows industry trends and proves which leading indicators separate risk

This session covers **Phase 4: a React app on Snowflake App Runtime (`snow app`) that applies those indicators to one mine at a time**.

**Why this demo exists:** DOL asked for "ways to identify trends in mine safety accidents using metrics such as methane levels, temperature, etc." The portal has **no methane, temperature, or sensor readings**, and we use portal data only, with no synthetic data. Every methane/ventilation signal in this app is a **compliance proxy** (cited 30 CFR 75 Subpart D sections), and the UI must say so. The audience is technical DOL IT staff (an enterprise architect, IT specialists, and a data engineer) who will take it to MSHA.

Invoke the `snowflake-apps` skill first and follow it for scaffolding, manifests, local run, and deploy.

### Overall Demo Plan (for reference)

| Phase | Deliverable | Key Snowflake Features | Status |
|---|---|---|---|
| 1 | Data extraction + ingestion | Python, portal ZIPs → S3, external stage, COPY INTO | **Done** |
| 2 | Transformation + SQL EDA | CTAS, window functions, incidence rates, lagged features, views | **Done** |
| 3 | Streamlit dashboard | Streamlit in Snowflake (container runtime), Plotly, pydeck | **Done** |
| 4 | **Mine early-warning app** | **Snowflake App Runtime (`snow app`), Next.js, snowflake-sdk** | **This session** |
| 5 | CoWork agent | Cortex Agent, semantic view, Cortex Search over accident narratives | Upcoming |

### How Phase 4 Differs from Phase 3 (stay on this side of the line)

| | Phase 3 Streamlit (done) | **Phase 4 React (this session)** |
|---|---|---|
| Question | "Where and why are miners getting hurt, and what comes first?" | **"What is the risk at *this* mine, and which mines should I visit first?"** |
| User | Analyst / program staff / leadership | **Inspector / field office supervisor / district manager before a visit** |
| Grain | Nation, state, year, hazard category, quartile | **One mine, its quarters, citations, accidents, and peers** |
| Leading indicators | Proved across the population | **Applied to one mine as an early-warning tier, with the Phase 3 evidence shown alongside** |

Do **not** rebuild national trend charts; link to the Streamlit dashboard for those.

### Business Value (shape the landing copy, architecture page, and demo narrative)

| # | Business value | Who benefits | Feature |
|---|---|---|---|
| 1 | **Find any mine in seconds.** Search 92K mines by name, MSHA mine ID, operator, or state. No FOIA request or data pull is needed. | Inspectors, district staff | Search |
| 2 | **Pre-visit briefing on one page.** Recent injuries, citations, serious enforcement actions, open penalties, and accident narratives, in context. | Inspectors preparing an inspection | Mine profile |
| 3 | **Transparent early warning.** A tier (Elevated / Watch / Typical) built only from the four signals Phase 3 showed actually precede injuries, with the evidence behind each signal. | Inspectors, supervisors | Early-warning card |
| 4 | **Prioritize visits.** A ranked watch list per MSHA district and field office. | District managers, field office supervisors | District watch list |
| 5 | **Fair comparison.** Compare a mine with its peer group (same category, mine type, and size band), or put 2–3 mines side by side. | Supervisors, analysts | Peers + Compare |
| 6 | **Platform story.** A product-grade web app running *inside* Snowflake: no data movement, no extra infrastructure, governed by Snowflake RBAC. | CIO/CDO, IT security | Architecture page |

### What Exists in Snowflake

- **Account:** <your account>. Use `-c <connection>` on every `snow` command.
- **Database:** `DOL_MSHA_DEMO` (`RAW`, `TRANSFORMED`, `ANALYTICS`, `APPS`).
- **Warehouse:** `DOL_MSHA_WH` (X-Small).
- **Role:** `DOL_MSHA_DEMO_ROLE` (owns everything).
- **Scripts:** `sql/01_setup.sql` … `sql/10_dashboard_views.sql`. EDA output: ``eda_output.txt` (from sql/08)`.
- **Read only from `ANALYTICS`.** Add new views in a new `sql/11_app_views.sql` with `CREATE OR REPLACE`. Do not modify `RAW`, `TRANSFORMED`, or the existing views.

| View | Grain | Use in app |
|---|---|---|
| `MINE_PROFILE` | 1 row per mine (92K; ~12.6K with `has_recent_hours`) | Search, profile header, last-4Q indicators, peer percentiles, `peer_group`, `district`, `office_name`, `has_geo_issue`, status, operator/controller, `open_delinquent_penalty_balance_usd`, `*_trend` columns |
| `MINE_QUARTER_TRENDS` | mine × quarter | Profile timeline (injuries, hours, rate, violations, S&S, vent/methane, 104(d)/107(a)). `WHERE mine_id = ?` only |
| `ACCIDENT_DETAIL` | person × accident | Accident list and narratives for one mine (`narrative` is portal-truncated at 384 chars) |
| `VIOLATION_DETAIL` | violation (1.79M) | Per-mine citation breakdown by `hazard_category`, recent serious citations. **Always `WHERE mine_id = ?` and aggregate**; ~1.6s per mine on X-Small |
| `LEADING_INDICATORS` | mine × quarter | Evidence: the pooled next-quarter rate for the quartile a mine falls in (aggregate only) |
| `OPERATOR_PORTFOLIO` | current operator | Operator context on the profile |
| `PENALTY_OUTCOMES` | penalty status | Not needed unless the architecture page cites it |

`mine_id` is a 7-digit **text** code (e.g. `4608151`); keep it as a string, because leading zeros matter.

**Rate rules (must hold everywhere):**
- Pooled rates = `SUM(injuries) * 200000 / SUM(hours)`. Never average per-row rates.
- Label the basis as "operator" (operator injuries / operator hours).
- 2026 is **partial** (hours through 2026 Q2). Mark it in every timeline and exclude it from trend deltas.
- Never sum `persons_injured_in_event`.
- Never show a rate for a period without hours. Mines with < 20K operator hours in the last 4 quarters get **"Not enough recent hours"** instead of a tier.

### The Early-Warning Tier (the core of this phase)

Phase 3 showed that, for **coal**, four prior-year signals separate next-quarter injury risk. Each one rises steadily from the None group to the Highest group, and the Highest group is at least 2× the None group:

| Signal | None → Highest quartile, next-quarter operator injuries per 200K hrs (coal) |
|---|---|
| Prior injury rate | 1.4 → 7.2 |
| Ventilation/methane citations per 200K hrs (compliance proxy) | 1.5 → 5.7 |
| 104(d)/107(a) actions per 200K hrs | 2.8 → 5.8 |
| High-negligence citations per 200K hrs | 2.1 → 5.3 |

For **metal/nonmetal**, only prior injury rate holds up; ventilation/methane is too sparse. S&S share and inspection intensity do **not** hold up and must **not** feed the tier.

**Build it in SQL as `ANALYTICS.MINE_EARLY_WARNING`** (in `sql/11_app_views.sql`), one row per mine with recent hours. The district watch list ranks thousands of mines, so the tier cannot live only in TypeScript.

1. For each mine, compute its last-4-quarter value of each signal, using the same definitions as `LEADING_INDICATORS` (prior 4 quarters, per 200K operator hours).
2. Assign each signal a group using the **Phase 3 quartile definition**: 0 = the signal was zero; 1–4 = quartiles of the non-zero values within mine category. Take the cut points from the comparable rows of `LEADING_INDICATORS`, so a mine's group lines up with the evidence bars on the dashboard. Document how you derive the cut points.
3. Attach the Phase 3 evidence: the pooled next-quarter rate and "% with any injury" for that signal × group × category.
4. **Proposed tier rule (review the distribution before building the UI):**
   - **Elevated:** at least 2 validated signals in the Highest group, **or** prior injury rate in the Highest group plus at least 1 other validated signal in group 3 or higher.
   - **Watch:** any validated signal in group 3 or higher.
   - **Typical:** everything else.
   - **Not enough recent hours:** < 20K operator hours in the last 4 quarters.
   - "Validated signals" for metal/nonmetal = prior injury rate only (so M/NM mines can reach Watch or Elevated only through prior injuries plus a corroborating signal; decide and document how to handle this).
5. **Calibration check:** report the tier distribution by category. The target is roughly Elevated 8–15% and Watch 20–35% of mines with recent hours. **Ask me before changing the rule.**
6. Include a `tier_reasons` array/string, e.g. "Prior injury rate: Highest group (7.2 vs 1.4 for mines with none)", so the UI can explain the tier without recomputing it.
7. Mirror the labels and thresholds in `lib/early-warning.ts`, with **vitest** tests covering the reason text and the boundary cases. Add a parity check that the SQL tier matches the TS rule for ~20 sampled mines.

**Framing (show it on the card):** "An illustrative early-warning indicator built from public MSHA data. It shows which mines look like the groups that had more injuries the next quarter. It is not an official MSHA rating or a prediction for this mine." The Streamlit dashboard has **no** risk score; this app is the only place it appears.

### What to Build

A **Next.js (App Router) app** in `react-app/`, deployed as `DOL_MSHA_DEMO.APPS.MSHA_EARLY_WARNING_APP`. It is **read-only**: no write-back tables.

**Five routes.** The left rail has Overview (`/`), Watch list (`/watchlist`), Compare (`/compare`), and Architecture (`/architecture`). The mine profile (`/mine?id=`) is reached from search, the watch list, and compare. Search lives in the header and the landing hero, not on its own page.

#### `/` Landing
- Hero: headline (e.g. "Know which mines need attention before the next injury."), a search bar, and a "Data as of" chip showing the latest accident date and hours quarter.
- Live counters from SQL (not hard-coded): mines with recent hours, Elevated mines, operator hours in the last 4 quarters, ventilation/methane citations in the last 4 quarters.
- Feature previews linking to the profile, watch list, compare, and architecture pages.
- A "compliance proxies, not sensor readings" note, and a link to the Streamlit dashboard for industry trends.

#### Search (header + hero)
- Typeahead at 2+ characters with a 300ms debounce. Match on mine name, mine ID, operator, and controller.
- Each row shows mine name, ID, state, category/type, operator, a tier chip, and status.
- Rank active mines with recent hours first. Bind every value.

#### `/mine?id=…` Mine profile (the hero page)
- **Header:** name, ID, status, category/type, commodity, state/county, nearest town, district/field office, operator and controller, peer group.
- **Early-warning card:** the tier, the four signals with their group (None/Low/Med-low/Med-high/Highest), and the Phase 3 evidence bar for each ("mines in this group: 5.7 injuries per 200K hrs next quarter vs 1.5 with none"). Include the framing disclaimer.
- **Quick stats:** last-4Q hours, injuries, rate, violations, S&S, vent/methane, 104(d)/107(a), proposed penalties, open/delinquent balance.
- **Timeline** from `MINE_QUARTER_TRENDS`: quarterly injury rate and citation counts since 2010, with 2026 marked partial.
- **Citations by hazard category** (compliance proxies), plus the most recent serious citations: 104(d)/107(a), high negligence, S&S, with date, CFR section, and penalty.
- **Accidents:** list, most recent first, with degree of injury, classification, and an expandable narrative (note the 384-char truncation).
- **Peers:** this mine vs its `peer_group` on the last-4Q metrics, using **per-mine pooled** peer values and showing the peer count.
- **Map pin** of the mine's location, if `NOT has_geo_issue`.

#### `/watchlist` District watch list
- District, then optional field office, filter; category filter.
- Ranked table: tier first, then the number of validated signals in the Highest group, then prior injury rate. Columns: mine, operator, last inspection date, the four signal groups as chips, last-4Q injuries, and open balance.
- Rows link to the profile. Allow CSV export of the current view (client-side).

#### `/compare?ids=a,b,c`
- 2–3 mines side by side (shareable URL): tier, the four signals, last-4Q metrics, and peer percentiles, with the higher-risk value in each row highlighted amber.
- A "Try an example" button with 3 hard-coded mines from the same peer group, picked via SQL (one Elevated, one Watch, one Typical).

#### `/architecture` End-to-end demo architecture
This page describes the **entire demo, Phases 1–5**, as one finished platform.
- **Write it in present tense, as if everything exists.** No "coming soon", "planned", "upcoming", "Phase 5", or roadmap wording. The CoWork agent gets the same visual weight and detail as the other apps.
- **Layout:** an `architecture-flow.tsx` component, interactive and animated throughout, with **no "Play the story" stepper or guided walkthrough**. It must include:
  - an SVG lineage diagram with moving dots flowing continuously along the connectors
  - hover on a node to highlight its full upstream and downstream lineage and dim the rest
  - click a node to spring open a side panel showing what it is, why it exists, its key objects, live row counts (for objects that exist), and a real SQL snippet
  - layers that fade and slide in on scroll, with count-up stats in the panels and subtle hover lift on the cards
  - `prefers-reduced-motion` honored
- **Layers and nodes:**
  1. **Source:** DOL Open Data Portal, MSHA datasets: Accident, Mines, Inspection, Violation, Assessed Violations, Operator and Contractor Employment/Production, plus lookups. Note: weekly refresh, portal data only, no sensor data.
  2. **Ingestion:** a Python extractor (portal ZIPs, facts filtered to 2010+) → S3 → external stage via storage integration `<your_s3_integration>` → `COPY INTO RAW.MSHA_*` (14 datasets).
  3. **Transformation (`TRANSFORMED`):** typed tables, the hazard-category reference (30 CFR → compliance proxy), UDFs, and `MINE_QUARTER_FACT` (gap-free mine × quarter, 2010 Q1–2026 Q2) with lagged features.
  4. **Analytics (`ANALYTICS`):** the interface views as cards (hover reveals each description): `NATIONAL_TRENDS`, `STATE_TRENDS`, `HAZARD_TRENDS`, `ACCIDENT_PATTERNS`, `ACCIDENT_DETAIL`, `VIOLATION_DETAIL`, `MINE_QUARTER_TRENDS`, `LEADING_INDICATORS`, `MINE_PROFILE`, `OPERATOR_PORTFOLIO`, `PENALTY_OUTCOMES`, `MINE_EARLY_WARNING`.
  5. **Semantic & AI layer:** semantic view `ANALYTICS.MSHA_SAFETY_SEMANTIC_VIEW` (metrics such as pooled injury rate, fatalities, citations per 200K hours; dimensions such as mine, operator, state, district, hazard category, quarter) and Cortex Search service `ANALYTICS.ACCIDENT_NARRATIVE_SEARCH` over accident narratives.
  6. **Applications**, shown as equal cards:
     - **MSHA Safety Dashboard:** Streamlit in Snowflake, `APPS.MSHA_SAFETY_DASHBOARD`; industry trends, ventilation/methane proxies, leading-indicator evidence, map and operators.
     - **Mine Early-Warning App:** this app, on Snowflake App Runtime, `APPS.MSHA_EARLY_WARNING_APP`; per-mine briefing, early-warning tier, district watch list, compare.
     - **MSHA Safety Agent in Snowflake CoWork:** Cortex Agent `APPS.MSHA_SAFETY_AGENT`, combining Cortex Analyst over the semantic view (questions like "Which coal mines in District 4 had the most ventilation citations last year?") with Cortex Search over narratives ("Find roof-fall accidents involving continuous miners").
  7. **Governance & platform strip:** a dedicated role and warehouse, no PUBLIC schema, data that never leaves Snowflake, apps running inside Snowflake (SPCS), and RBAC carried through to every app.
  8. **Tech stack badges.**
- **Object names:** use the names above exactly. Phase 5 will create the semantic view, search service, and agent with these names, so the page stays accurate.
- **Live counts:** `/api/architecture` returns row counts only for objects that exist. Static nodes (Python extractor, S3, and the Phase 5 objects until they exist) show descriptive stats instead (e.g. "92K mines · 1.79M violations indexed for search"). **Never show an error, a "not found" state, or a zero.** Query existence with `SHOW … LIKE` inside a try/catch and fall back silently to the static description.
- **Demo story callout:** one short paragraph: DOL asked for trends using methane and temperature; the portal has none; the platform answers with compliance proxies, validated leading indicators, and per-mine early warning, all from public data inside Snowflake.

### Design: light command-center

**Read these files before writing UI code:** `app/globals.css`, `components/kit.tsx`, `components/shell.tsx`, `components/architecture-flow.tsx`, `lib/snowflake.ts`, `lib/client.tsx`, `snowflake.yml`, `app.yml`, `package.json`. Reuse the structure, design system, and deploy config, and adapt the domain.

- **Palette:** light only. Canvas `#fafafa`, white cards, 1px `#eaeaea` hairlines, 12px radius. Navy `#0b2545` for the brand, teal `#0e7c7b` for Typical/declining, amber `#d97706` only for Elevated/risk.
  - Coal = navy, Metal/Nonmetal = teal, matching the Phase 3 dashboard.
- **Typography:** Geist + Geist Mono, tabular numbers, mono mine IDs, 11px uppercase eyebrows.
- **Shell:** left rail with a sliding active pill, sticky translucent header with search, a "Data as of" pulse dot, and a Cmd+K palette.
- **KPIs:** every KPI tile gets a provenance badge (source view) and count-up numbers.
- **Interaction:** hairline tables with hover tint and j/k keyboard navigation; shimmer skeletons; friendly empty and error states (never raw SQL errors); `prefers-reduced-motion` honored.
- **Tooltips:** clear and easy to read (white, bordered, 14px, plain-English labels). This was a Phase 3 feedback item.
- **Footer:** "Source: U.S. Department of Labor, MSHA datasets on the DOL Open Data Portal (data.dol.gov)" and "Powered by Snowflake".

### Technical Requirements

- **Stack:** Next.js App Router (standalone output), React 19, Tailwind v4, Framer Motion, Recharts, TanStack Query, lucide-react.
  - For the mine pin and any map, bundle all assets (no CDN; SPCS has no outbound network).
- **Manifests:** follow the `snowflake-apps` skill for `snowflake.yml` / `app.yml`.
  - Deploy to `DOL_MSHA_DEMO.APPS` (not `USER$`), query warehouse `DOL_MSHA_WH`.
  - Code stage/workspace lives in `APPS`.
- **Data access:** `snowflake-sdk` via `lib/snowflake.ts`, from the Snowflake App Runtime Next.js template. It handles SPCS token auth and supports binds.
  - No REST SQL API.
  - No shelling out to `snow` (it's not available in SPCS).
- **API routes** (`app/api/*/route.ts`), suggested:
  ```
  GET /api/stats                      → landing counters + data-as-of
  GET /api/search?q=&state=           → typeahead (MINE_PROFILE + MINE_EARLY_WARNING)
  GET /api/mine?id=                   → header, quick stats, early-warning card, peers
  GET /api/mine/timeline?id=          → MINE_QUARTER_TRENDS
  GET /api/mine/citations?id=         → VIOLATION_DETAIL aggregates + recent serious citations
  GET /api/mine/accidents?id=&offset= → ACCIDENT_DETAIL (paged)
  GET /api/watchlist?district=&office=&category=
  GET /api/compare?ids=
  GET /api/architecture               → live row counts
  ```
- **Validation:**
  - `id` must match `^\d{7}$`; `ids` is at most 3 of those.
  - `q` ≤ 100 chars; district/office/category from allow-lists queried at startup.
  - Bind every value; never interpolate user input or column names.
  - Validation failures → 400. A 500 returns a generic message plus a ref id, with details logged server-side.
- **Caching:** cache aggregate routes (`stats`, `watchlist`, `architecture`) in memory with a TTL.
- **Performance:** every route aggregates in Snowflake; profile routes stay < 3s on X-Small.
  - If `VIOLATION_DETAIL` per-mine queries are slow, add a join-free per-mine citation view in `sql/11_app_views.sql` (same lesson as Phase 3's `PENALTY_OUTCOMES`).
- **Local dev:** start the dev server with `SNOWFLAKE_CONNECTION_NAME=<connection>`. Set it explicitly rather than relying on the default connection.
- **Grants:** before deploy, confirm the app service role can read `ANALYTICS` and use `DOL_MSHA_WH`, and check the PyPI/npm EAI needs per the skill. If anything needs ACCOUNTADMIN, give me the exact `GRANT`.

### ⚠️ Local first, deploy only on my final OK
**Build and host the app locally only** (`npm run dev` on localhost) so I can review it and give feedback. **Do NOT run `snow app deploy` (or `snow app setup`, or create any APPLICATION SERVICE) until I explicitly say "deploy" / give the final OK.** Iterate on my feedback locally first. Preparing `snowflake.yml` / `app.yml` and checking grants ahead of time is fine.

### Verification (before calling it done)
1. `npm run build` and the vitest suite pass, including the SQL/TS tier parity check.
2. Report the tier distribution by category from the calibration check.
3. **Locally:**
   - search by mine ID and by a partial operator name
   - open an Elevated coal mine and confirm its four signal groups and evidence numbers match the Phase 3 dashboard's Leading Indicators page
   - open an M/NM mine, and a mine under 20K hours ("Not enough recent hours")
   - load the watch list for one district and one office
   - run compare with the example button
4. **Stop and hand off for local review:** give me the localhost URL and ask me to click through landing, search, profile, watch list, compare, architecture. Apply my feedback locally. **Only after my explicit final OK**: deploy, confirm the app object exists, and give me the URL (the browser panel isn't signed in to Snowsight, so ask me to check the deployed app).
5. Search the source for "coming soon", "planned", "upcoming", "roadmap", and "Phase 5", and confirm none appear in user-facing copy. Confirm the architecture page renders with no errors or zero counts while the Phase 5 objects don't exist yet.

### Gotchas (read first, record as you go)

**Known SAR/SPCS gotchas to design around from the start:**
- **No outbound network in SPCS.** Bundle fonts, map/TopoJSON, and icons in `public/`; CDN fetches fail silently.
- **Map data keys.** `us-atlas` TopoJSON has only `properties.name`, not postal codes, so map names to state codes yourself.
- **Map focus outlines.** On `react-simple-maps` shapes, use `tabIndex={-1}` plus global CSS `svg path:focus { outline: none !important }`.
- **VARIANT columns.** The Node `snowflake-sdk` returns them already parsed; check `typeof === 'string'` before `JSON.parse`.
- **No `snow` CLI in SPCS.** Use `snowflake-sdk` via `lib/snowflake.ts`.
- **Deploy location.** `snow app` defaults to `USER$<user>`; override to `DOL_MSHA_DEMO.APPS`.
- **Manifest rules.** `app.yml` secret names must be UPPERCASE, and `NODE_ENV` is a reserved env var. Check egress/EAI handling for your CLI version per the `snowflake-apps` skill.
- **Network policy.** The account policy can block key-pair logins from SPCS egress; the SPCS token path avoids this.
- **Local dev connection.** Set `SNOWFLAKE_CONNECTION_NAME=<connection>` explicitly.
- **Timezone.** Pin the session `TIMEZONE` if any "as of" or recency logic uses `CURRENT_DATE()`.
- **Build checks.** Don't ship with `ignoreBuildErrors: true` unless `tsc --noEmit` passes first.

**Phase 3 carry-overs:**
- `STATE_TRENDS` and `HAZARD_TRENDS` include an `'All Mines'` rollup row and `ACCIDENT_PATTERNS` does not, so always filter category explicitly.
- `VIOLATION_DETAIL`'s un-pruned LEFT JOINs make broad aggregates slow; use `WHERE mine_id = ?` or a join-free view.
- `mine_id` is text with significant leading characters.
- Tooltips must be readable.

**Record new gotchas as you hit them** and list them in your final summary.


### Important Notes
- Read-only app. Do not create write-back tables.
- Never use the PUBLIC schema; `DOL_MSHA_DEMO_ROLE` owns the new views and the app.
- Methane and temperature readings are **not** in the portal. Call hazard categories "compliance proxies", everywhere.
- **Stay in Phase 4 scope:** no semantic view, Cortex Search, Cortex Agent, or ML model. Phase 5 owns those.
- If a number in this prompt doesn't match what the views return, trust the views and tell me; don't silently change the copy.
