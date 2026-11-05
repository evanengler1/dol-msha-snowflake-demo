# Phase 1 CoCo Prompt: DOL MSHA Demo — Data Extraction and Ingestion

> Paste this prompt into a new CoCo session to execute Phase 1.

---

## Prompt

I'm building an end-to-end Snowflake demo using **real, public Mine Safety and Health Administration (MSHA) data** from the U.S. Department of Labor Open Data Portal (https://data.dol.gov/). The demo shows how to find trends and leading indicators in mine safety accidents, and the full platform story: raw data ingestion → transformation → EDA → Streamlit dashboard → React app (snow app) → CoWork agent (Cortex Agent).

The audience is technical DOL IT staff (an enterprise architect, IT specialists, and a data engineer) who will take it to MSHA, so the ingestion pipeline itself is part of what's being shown. Keep it clean, repeatable, and easy to explain.

**This session focuses on Phase 1 only: data extraction + ingestion into Snowflake.**

### Hard Rules

- **All data must come from the MSHA datasets on data.dol.gov.** No synthetic data, no sample/fake rows, no files from msha.gov or anywhere else.
- **Never use the PUBLIC schema.** Dedicated database, schemas, warehouse, and role only.
- **Raw layer = exactly what the source provides.** All `VARCHAR`, no transformation, no cleanup. Typing happens in Phase 2.

### Overall Demo Plan (for reference — don't execute beyond Phase 1)

| Phase | Deliverable | Key Snowflake Features |
|-------|------------|----------------------|
| 1 | Data extraction + ingestion | Python, portal ZIPs (downloaded manually), S3 external stage, COPY INTO, raw schema |
| 2 | SQL scripts + transformation + EDA | Typed tables, joins on MINE_ID/EVENT_NO, injury incidence rates, views |
| 3 | Streamlit dashboard | Streamlit in Snowflake, charts, filters, pydeck map |
| 4 | React app | Snowflake App Runtime (snow app), Next.js |
| 5 | CoWork agent | Cortex Agent, semantic view, Cortex Search over accident narratives |

### Data Source: Local ZIP Files (downloaded manually from the portal)

I have already downloaded each dataset's "Download Complete Dataset" ZIP from its data.dol.gov page into the project's `data/` folder. **Do not download anything.** Work only from the ZIPs in `data/`.

- 14 ZIPs, named `MSHA_{api_name}.zip` (portal snapshot dated 2026-11-02). Derive `{api_name}` from the file name.
- First step: list `data/*.zip` and confirm all 14 below are present. Stop if anything is missing.
- **Verified file facts (pre-checked):**
  - Each ZIP holds 1-4 CSV chunks named `2026-11-02_chunk_N.csv`; **every chunk repeats the header row**, so write the header once per dataset.
  - Comma-delimited, double-quoted, UTF-8, UPPERCASE headers.
  - Dates are ISO strings like `2006-08-25 00:00:00+00:00`, so string comparison on the first 10 characters works for the date filter.
  - Nulls appear as empty strings and also as the literal `NaT` (pandas export artifact). Keep `NaT` as-is in RAW; Phase 2 will null it.
  - Accident `AI_NARR` (narrative) is free text inside quotes, so use a real CSV parser (Python `csv` module), not line splitting.
  - Sizes are large: `MSHA_violation.zip` ~2.8 GB (4 chunks), `MSHA_inspection.zip` ~1.1 GB, `MSHA_assessed_violations.zip` ~630 MB, `MSHA_accident.zip` ~510 MB. **Stream row-by-row to a local gzip temp file and upload with `boto3` `upload_file` (multipart). Do not build whole files in memory**.

### Datasets to Ingest (14 total)

**Fact tables (large; apply the date filter):**

| ZIP (`api_name`) | Dataset | Key fields (actual headers) | Filter field |
|---|---|---|---|
| `accident` | Accident (10341) | `DOCUMENT_NO` (PK), `MINE_ID`, `CNTCTR_ID`, `AI_DT`, `SUBUNIT_CD`, `INJ_DEGR_DESC`, `AI_CLASS_DESC`, `ACCIDENT_TYPE`, `INJURY_SOURCE`, `NATURE_INJURY`, `DAYS_LOST`, `NO_INJURIES`, **`AI_NARR`** | `AI_DT` |
| `inspection` | Inspection (10349) | `EVENT_NO` (PK), `MINE_ID`, `ACTY_CD`, `ACTY_DESC`, `BEG_DT`, `END_DT`, `SAMPLE_CNT_AIR`, `SAMPLE_CNT_RESPDUST`, `TOTAL_INSP_HOURS`, `COAL_METAL_IND` | `BEG_DT` |
| `violation` | Violation (10355) | `VIOL_NO` (PK), `EVENT_NO`, `MINE_ID`, `ISS_DT`, `SIG_SUB`, `PART_SECTION`, `CIT_ORD_SAFE`, `LIKELIHOOD`, `INJ_ILLNESS`, `NO_AFFECTED`, `NEGLIGENCE`, `COAL_METAL_IND` | `ISS_DT` |
| `operator_employment_production_quarterly` | Operator Empl/Prod Quarterly (10353) | **`PETREEMINE_ID`** (this is the mine ID; keep the source name in RAW), `SUBUNIT_CD`, `EMPL_PROD_YR`, `EMPL_PROD_QTR`, `AVG_EMPL_CNT`, `EMPL_HRS`, `COAL_PROD` | `EMPL_PROD_YR >= 2010` |
| `operator_employment_production_annual` | Operator Empl/Prod Annual (10348) | `MINE_ID`, `SUBUNIT_CD`, `CALENDAR_YR`, `ANNUAL_HRS`, `ANNUAL_COAL_PROD`, `AVG_ANNUAL_EMPL` | `CALENDAR_YR >= 2010` |
| `contractor_employment_production_quarterly` | Contractor Empl/Prod Quarterly (10354) | `CNTCTR_ID`, `SUBUNIT_CD`, `EMPL_PROD_YR`, `EMPL_PROD_QTR`, `CMDTY_TYPE`, `AVG_EMPL_CNT`, `EMPL_HRS` (**no MINE_ID**: contractor-level only) | `EMPL_PROD_YR >= 2010` |
| `contractor_employment_production_annual` | Contractor Empl/Prod Annual (10345) | `CNTCTR_ID`, `SUBUNIT_CD`, `CMDTY_TYPE`, `CALENDAR_YR`, `ANNUAL_HRS`, `AVG_ANNUAL_EMPL` (**no MINE_ID**) | `CALENDAR_YR >= 2010` |

**Assessed Violations (`assessed_violations`, 10343): load in full, no filter.** It has no issue date (only `CITATION_NBR`, penalty amounts, `FINAL_ORDER_DATE`, `BILL_PRINT_DATE`, `LAST_ACTION_DATE`), and it is already 1995+. Phase 2 joins it to Violation on `CITATION_NBR` = `VIOL_NO`.

**Dimension / history / lookup tables (small; load in full, no filter):**

| ZIP (`api_name`) | Dataset | Key fields (actual headers) |
|---|---|---|
| `mines` | Mines (10350) | `MINE_ID` (PK), `CURR_MINE_NM`, `C_M_IND`, `MINE_TYPE_CD`, `CURR_STAT_CD`, `OPER_ID`, `CONTROLLER_ID`, `STATE_ABBR`, `FIPS_CNTY_NM`, `DISTRICT`, `PRIMARY_CANVASS_DESC`, `LATITUDE`, `LONGITUDE` |
| `operator_history_at_mines` | Operator History (10352) | `MINE_ID`, `OPER_ID`, `OPER_START_DT`, `OPER_END_DT`, `OPER_NM` |
| `contractor_history_at_mines` | Contractor History (10351) | `MINE_ID`, `CNTCTR_ID`, `CNTCTR_NM`, `CNTCTR_START_DT`, `CNTCTR_END_DT` |
| `controller_history` | Controller History (10359) | `OPER_ID`, `CTRLR_ID`, `CTRLR_NM`, `CTRLR_START_DT`, `CTRLR_END_DT` |
| `commodity_lookup` | Commodity Lookup (10360) | `CMMDTY_CD`, `CMMDTY_DESC`, `NAICS_CD`, `SIC_CD` |
| `contractor_name_id_lookup` | Contractor Name ID Lookup (10344) | `CNTCTR_ID`, `CNTCTR_NM` |

Skip **Address of Records - Mines (10358)**; it isn't needed for this demo.

**Date filter:** keep fact-table rows from **2010-01-01 onward** (about 16 years), using the filter field in the table above. That covers the period with well-populated accident narratives and keeps the load fast. Rows with a blank or `NaT` filter value are dropped and counted separately in the manifest.

### Snowflake Target

- **Account:** <your account>
- **Database:** `DOL_MSHA_DEMO`
- **Raw schema:** `RAW` (also create empty `TRANSFORMED` and `ANALYTICS` schemas for later phases)
- **Warehouse:** `DOL_MSHA_WH` (X-Small, auto-suspend 60s)
- **Role:** `DOL_MSHA_DEMO_ROLE` (owns all demo objects; grant to my user)
- **S3 bucket:** `s3://<your-bucket>/msha-raw/`, one prefix per dataset (`msha-raw/{api_name}/`)
- **Storage integration:** `<your_s3_integration>` already exists (ACCOUNTADMIN-owned, allows the whole `s3://<your-bucket>/` bucket). Do NOT recreate it. Comment its DDL out in the setup SQL with a note, then grant `USAGE` on it to `DOL_MSHA_DEMO_ROLE`.
- **AWS credentials:** standard AWS environment variables or profile for the bucket (never commit them).

### What I Need You to Do (Phase 1)

1. **Snowflake infrastructure** (`sql/01_setup.sql`): role, warehouse, database, the `RAW`/`TRANSFORMED`/`ANALYTICS` schemas, ownership grants, and the `<your_s3_integration>` usage grant.

2. **Python extraction script** (`process_msha_data.py`), It should:
   - Read each dataset's ZIP from the local `data/` folder (no network downloads)
   - Read every chunk CSV inside each ZIP with the `csv` module, streaming (no full-file reads)
   - Apply the 2010+ filter to the 7 filtered fact tables only (see table above)
   - Lowercase the column headers; write the header once per dataset
   - Write values exactly as read (keep `NaT`, blanks, codes like `?` and `NO VALUE FOUND`)
   - Stream to a local gzip temp file, then `upload_file` to `s3://<your-bucket>/msha-raw/{api_name}/{api_name}.csv.gz`; delete the temp file after upload
   - Support `--only accident,mines` to rerun selected datasets
   - Write a small manifest (`data/manifest.json`) with each dataset's ZIP file name, file size, modified time, rows read, rows kept, and column list
   - Log progress and print a final summary table

3. **Raw tables** (`sql/02_raw_tables.sql`): one table per dataset in `RAW`, named `MSHA_{API_NAME}` (e.g., `RAW.MSHA_ACCIDENT`). Columns are all `VARCHAR` and come from the **actual headers the script found**, not from this prompt. Add `_source_file VARCHAR` and `_loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()`.

4. **External stage + file format + load** (`sql/03_load.sql`): an external stage on `s3://<your-bucket>/msha-raw/` using `<your_s3_integration>`, a CSV file format (gzip, header skip, optional double-quote enclosure), then `COPY INTO` each raw table with `MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE`, filling `_source_file` from `METADATA$FILENAME`.

5. **Verify** (`sql/04_verify.sql`):
   - Row count per raw table, reconciled against the manifest's rows-kept counts (they must match)
   - Min/max of the main date field for each fact table
   - Join-key sanity checks: % of `RAW.MSHA_ACCIDENT.mine_id` found in `RAW.MSHA_MINES`; % of `RAW.MSHA_VIOLATION.event_no` found in `RAW.MSHA_INSPECTION`; % of 2010+ `RAW.MSHA_VIOLATION.viol_no` found in `RAW.MSHA_ASSESSED_VIOLATIONS.citation_nbr`; % of `RAW.MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY.petreemine_id` found in `RAW.MSHA_MINES`
   - Accident narrative coverage: % non-blank by year
   - Confirm `RAW.MSHA_VIOLATION` has no free-text condition/practice column (the pre-check found none in the header; just confirm). Accident `AI_NARR` is the only narrative field for Cortex AI.
   - Count of violations whose `part_section` starts with `75.3` (ventilation/methane, 30 CFR 75 Subpart D). This is the methane/ventilation proxy for later phases, since the portal has no methane or temperature readings.
   - A few spot-check rows per table

6. **Short summary** at the end: a table of datasets → rows → date range → load status, plus anything surprising (bad rows, missing columns, low join coverage).

### Important Notes

- I'll run `source .env` before running the script.
- Save every SQL script under `sql/` in this project folder, numbered in run order.
- Use the actual column names from the downloaded files everywhere. If a field I listed above doesn't exist or has a different name, tell me; don't invent it.
- If `COPY INTO` rejects rows, show me the errors (`VALIDATION_MODE` / `VALIDATE`) before changing anything. Don't use `ON_ERROR = CONTINUE` to hide problems.
- Don't build any transformation, dashboard, app, or agent in this session.
