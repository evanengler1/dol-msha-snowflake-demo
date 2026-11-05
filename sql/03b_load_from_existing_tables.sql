-- =============================================================================
-- 03b_load_from_existing_tables.sql   (Option A in the README)
-- Fill the RAW layer from MSHA tables that already exist in your account,
-- instead of loading portal ZIPs from a stage (03_load.sql).
--
-- How it works
--   LOAD_RAW_FROM_TABLE copies every column whose name matches a RAW column
--   (case-insensitive), casts it to VARCHAR, and applies the same 2010+ filter
--   that process_msha_data.py applies to fact tables. Columns your source does
--   not have stay NULL; extra source columns are ignored. It returns a summary
--   of matched and missing columns so you can spot naming differences.
--
-- Before you run it
--   1. Run 01_setup.sql and 02_raw_tables.sql.
--   2. Grant DOL_MSHA_DEMO_ROLE SELECT on your source tables.
--   3. Replace every <SOURCE_DB>.<SOURCE_SCHEMA>.<TABLE> below with your table.
--      Comment out any dataset you do not have.
--   4. Column names must match the portal names (for example MINE_ID, AI_DT,
--      VIOL_NO). If yours differ, create a view that renames them and point
--      the CALL at the view.
--   5. IDs must keep leading zeros (MINE_ID is 7 characters, e.g. '0100851').
--      If your source stores IDs as numbers, LPAD them in a view first.
-- =============================================================================
USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE SCHEMA DOL_MSHA_DEMO.RAW;

CREATE OR REPLACE PROCEDURE LOAD_RAW_FROM_TABLE(
    target_table VARCHAR,     -- RAW table name, e.g. 'MSHA_ACCIDENT'
    source_table VARCHAR,     -- fully qualified source table or view
    filter_col   VARCHAR,     -- column for the 2010+ filter, NULL = load all rows
    filter_kind  VARCHAR      -- 'date' or 'year', NULL when filter_col is NULL
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    target_cols VARCHAR;
    select_cols VARCHAR;
    matched     INTEGER;
    missing     VARCHAR;
    where_sql   VARCHAR DEFAULT '';
    loaded      INTEGER;
BEGIN
    -- Source columns via DESCRIBE (works for tables and views in any database)
    EXECUTE IMMEDIATE 'DESCRIBE TABLE ' || :source_table;
    CREATE OR REPLACE TEMPORARY TABLE _src_cols AS
        SELECT UPPER("name") AS col FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- RAW columns (metadata columns excluded); INFORMATION_SCHEMA of the current database
    CREATE OR REPLACE TEMPORARY TABLE _tgt_cols AS
        SELECT column_name AS col, ordinal_position AS pos
          FROM INFORMATION_SCHEMA.COLUMNS
         WHERE table_schema = 'RAW' AND table_name = UPPER(:target_table)
           AND column_name NOT IN ('_SOURCE_FILE', '_LOADED_AT');

    SELECT LISTAGG(t.col, ', ') WITHIN GROUP (ORDER BY t.pos),
           LISTAGG('TO_VARCHAR("' || s.col || '")', ', ') WITHIN GROUP (ORDER BY t.pos),
           COUNT(*)
      INTO :target_cols, :select_cols, :matched
      FROM _tgt_cols t JOIN _src_cols s ON s.col = UPPER(t.col);

    SELECT LISTAGG(t.col, ', ') WITHIN GROUP (ORDER BY t.pos)
      INTO :missing
      FROM _tgt_cols t LEFT JOIN _src_cols s ON s.col = UPPER(t.col)
     WHERE s.col IS NULL;

    IF (matched = 0) THEN
        RETURN target_table || ': no matching columns in ' || source_table || ' - nothing loaded';
    END IF;

    IF (filter_col IS NOT NULL) THEN
        IF (filter_kind = 'year') THEN
            where_sql := ' WHERE TRY_TO_NUMBER(LEFT(TO_VARCHAR("' || UPPER(filter_col) || '"), 4)) >= 2010';
        ELSE
            where_sql := ' WHERE TRY_TO_DATE(LEFT(TO_VARCHAR("' || UPPER(filter_col) || '"), 10)) >= ''2010-01-01''';
        END IF;
    END IF;

    EXECUTE IMMEDIATE 'TRUNCATE TABLE RAW.' || target_table;
    EXECUTE IMMEDIATE
        'INSERT INTO RAW.' || target_table || ' (' || target_cols || ', _source_file, _loaded_at) ' ||
        'SELECT ' || select_cols || ', ''' || source_table || ''', CURRENT_TIMESTAMP()::TIMESTAMP_NTZ ' ||
        'FROM ' || source_table || where_sql;
    loaded := SQLROWCOUNT;

    RETURN target_table || ': ' || loaded || ' rows, ' || matched || ' columns matched' ||
           IFF(COALESCE(missing, '') = '', '; all columns present', '; missing (left NULL): ' || missing);
END;
$$;

-- Fact tables (2010+ filter)
CALL LOAD_RAW_FROM_TABLE('MSHA_ACCIDENT',  '<SOURCE_DB>.<SOURCE_SCHEMA>.<ACCIDENT_TABLE>',   'AI_DT',  'date');
CALL LOAD_RAW_FROM_TABLE('MSHA_INSPECTION','<SOURCE_DB>.<SOURCE_SCHEMA>.<INSPECTION_TABLE>', 'BEG_DT', 'date');
CALL LOAD_RAW_FROM_TABLE('MSHA_VIOLATION', '<SOURCE_DB>.<SOURCE_SCHEMA>.<VIOLATION_TABLE>',  'ISS_DT', 'date');
CALL LOAD_RAW_FROM_TABLE('MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY',   '<SOURCE_DB>.<SOURCE_SCHEMA>.<OPERATOR_EMPL_PROD_QTR_TABLE>',   'EMPL_PROD_YR', 'year');
CALL LOAD_RAW_FROM_TABLE('MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_ANNUAL',      '<SOURCE_DB>.<SOURCE_SCHEMA>.<OPERATOR_EMPL_PROD_ANNUAL_TABLE>', 'CALENDAR_YR',  'year');
CALL LOAD_RAW_FROM_TABLE('MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_QUARTERLY', '<SOURCE_DB>.<SOURCE_SCHEMA>.<CONTRACTOR_EMPL_PROD_QTR_TABLE>', 'EMPL_PROD_YR', 'year');
CALL LOAD_RAW_FROM_TABLE('MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_ANNUAL',    '<SOURCE_DB>.<SOURCE_SCHEMA>.<CONTRACTOR_EMPL_PROD_ANNUAL_TABLE>','CALENDAR_YR', 'year');

-- Load in full
CALL LOAD_RAW_FROM_TABLE('MSHA_ASSESSED_VIOLATIONS',        '<SOURCE_DB>.<SOURCE_SCHEMA>.<ASSESSED_VIOLATIONS_TABLE>', NULL, NULL);
CALL LOAD_RAW_FROM_TABLE('MSHA_MINES',                      '<SOURCE_DB>.<SOURCE_SCHEMA>.<MINES_TABLE>',               NULL, NULL);
CALL LOAD_RAW_FROM_TABLE('MSHA_OPERATOR_HISTORY_AT_MINES',  '<SOURCE_DB>.<SOURCE_SCHEMA>.<OPERATOR_HISTORY_TABLE>',    NULL, NULL);
CALL LOAD_RAW_FROM_TABLE('MSHA_CONTRACTOR_HISTORY_AT_MINES','<SOURCE_DB>.<SOURCE_SCHEMA>.<CONTRACTOR_HISTORY_TABLE>',  NULL, NULL);
CALL LOAD_RAW_FROM_TABLE('MSHA_CONTROLLER_HISTORY',         '<SOURCE_DB>.<SOURCE_SCHEMA>.<CONTROLLER_HISTORY_TABLE>',  NULL, NULL);
CALL LOAD_RAW_FROM_TABLE('MSHA_COMMODITY_LOOKUP',           '<SOURCE_DB>.<SOURCE_SCHEMA>.<COMMODITY_LOOKUP_TABLE>',    NULL, NULL);
CALL LOAD_RAW_FROM_TABLE('MSHA_CONTRACTOR_NAME_ID_LOOKUP',  '<SOURCE_DB>.<SOURCE_SCHEMA>.<CONTRACTOR_NAME_TABLE>',     NULL, NULL);

-- Then run 04_verify.sql. Its manifest reconciliation does not apply to this
-- path; the join-coverage and date-range checks still do.
