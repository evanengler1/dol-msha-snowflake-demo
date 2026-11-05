# MSHA Mine Early-Warning App

A read-only Next.js app on **Snowflake App Runtime** that applies validated mine-safety leading indicators to one mine at a time. It answers "What is the risk at *this* mine, and which mines should I visit first?" for inspectors, field office supervisors and district managers.

Public MSHA data only (DOL Open Data Portal). Ventilation/methane figures are **compliance proxies** (30 CFR 75 Subpart D citations), not sensor readings. The early-warning tier is illustrative, not an official MSHA rating.

## Pages

| Route | What it does |
|---|---|
| `/` | Hero search, live counters, tier distribution, feature links |
| `/mine?id=0100851` | Pre-visit briefing: header, early-warning card with evidence, quick stats, timeline (2026 partial), citations by hazard category, recent serious citations, accidents with narratives, peers, map pin |
| `/watchlist?district=C04` | Ranked watch list by district / field office / category, j/k navigation, CSV export |
| `/compare?ids=a,b,c` | 2-3 mines side by side, higher-risk value in amber, example trio |
| `/architecture` | Animated end-to-end lineage of the whole demo, with live row counts |

Search (header, hero and Cmd+K) matches mine name, mine ID, operator and controller.

## Data sources (all `DOL_MSHA_DEMO.ANALYTICS`)

| Object | Type | Used for |
|---|---|---|
| `MINE_EARLY_WARNING` | Dynamic Table (sql/11) | Tier, signal groups, evidence, reasons, watch list |
| `EARLY_WARNING_REFERENCE` | Dynamic Table (sql/11) | Quartile cut points + next-quarter evidence by category x signal x group |
| `MINE_DIRECTORY` | Dynamic Table (sql/11) | Search, profile header and quick stats, compare (MINE_PROFILE + tier) |
| `PEER_GROUP_BENCHMARK` | Dynamic Table (sql/11) | Peer comparison (pooled rates, per-mine averages) |
| `MINE_QUARTER_TRENDS` | View | Timeline |
| `VIOLATION_DETAIL` | View | Citations by hazard category, recent serious citations (always `WHERE mine_id = ?`) |
| `ACCIDENT_DETAIL` | View | Accident list and narratives (portal-truncated at 384 chars) |
| `OPERATOR_PORTFOLIO` | View | Operator context |

The early-warning tier lives in SQL (`sql/11_app_views.sql`) and is mirrored in `lib/early-warning.ts`. A parity test checks the two agree.

## Run locally

```bash
npm install
cp .env.local.example .env.local   # set SNOWFLAKE_CONNECTION_NAME
npm run dev
```

`.env.local` names your Snowflake CLI connection and pins `SNOWFLAKE_ROLE=DOL_MSHA_DEMO_ROLE` and `SNOWFLAKE_WAREHOUSE=DOL_MSHA_WH`. Before deploying, set `DASHBOARD_URL` in `lib/constants.ts` to your dashboard's Snowsight URL.

## Test and build

```bash
npm test              # unit tests (tier rule, reason text, boundaries, template SDK tests)
npm run test:parity   # SQL vs TS tier parity on ~20 sampled mines (needs SNOWFLAKE_CONNECTION_NAME)
npx tsc --noEmit && npm run build
```

## Deploy

`app.yml` (version 2) deploys to `DOL_MSHA_DEMO.APPS.MSHA_EARLY_WARNING_APP` with query warehouse `DOL_MSHA_WH`, owned by `DOL_MSHA_DEMO_ROLE`.

```bash
snow app deploy --verbose -c <connection> --role DOL_MSHA_DEMO_ROLE
```

- Owner's rights only; no caller grants, secrets or runtime egress are needed.
- Fonts, map TopoJSON (`public/states-10m.json`) and icons are bundled: SPCS has no outbound network.
- If the build fails downloading npm packages, add `build_eai: NPM_REGISTRY_EAI` to `app.yml` and, as ACCOUNTADMIN, `GRANT USAGE ON INTEGRATION NPM_REGISTRY_EAI TO ROLE DOL_MSHA_DEMO_ROLE;`
- `NODE_ENV` is a reserved env var in SAR; don't set it.

## Code map

- `lib/server/db.ts` — query wrapper (binds only), row mapper (keeps `mine_id` as text), TTL cache, validation, error handling (400 / generic 500 with ref id)
- `lib/server/lists.ts` — district / office / category / state allow-lists
- `lib/early-warning.ts` — tier labels, thresholds and rule (mirror of SQL)
- `app/api/*` — stats, search, mine (+ timeline, citations, accidents), watchlist, compare, architecture, lists
- `components/` — shell (rail, header search, Cmd+K), kit (tooltips, KPIs, chips), early-warning card, map, architecture flow

Source: U.S. Department of Labor, MSHA datasets on the DOL Open Data Portal (data.dol.gov).
