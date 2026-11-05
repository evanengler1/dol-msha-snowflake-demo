-- Phase 1: external stage, file format, and COPY INTO each raw table.
USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE SCHEMA DOL_MSHA_DEMO.RAW;

CREATE OR REPLACE FILE FORMAT MSHA_CSV_GZ
    TYPE = CSV COMPRESSION = GZIP PARSE_HEADER = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"' FIELD_DELIMITER = ','
    EMPTY_FIELD_AS_NULL = FALSE
    -- Must be FALSE: tables carry 2 extra metadata columns (_source_file, _loaded_at), so file vs table
    -- column counts always differ. Per-row field counts are already enforced by process_msha_data.py.
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

-- Option B1 (default): internal stage. Upload the files process_msha_data.py wrote, from the repo root:
--   snow sql -c <connection> -f sql/03a_put_files.sql
-- (files land under @MSHA_RAW_STAGE/<api_name>/, which is what the COPY statements below read)
CREATE STAGE IF NOT EXISTS MSHA_RAW_STAGE
    FILE_FORMAT = MSHA_CSV_GZ
    COMMENT = 'Portal extracts from process_msha_data.py';

-- Option B2: S3. Use this instead of the internal stage if you ran process_msha_data.py --target s3.
-- Needs a storage integration (see 01_setup.sql); replace <your-bucket> and <your_s3_integration>.
-- CREATE OR REPLACE STAGE MSHA_RAW_STAGE
--     URL = 's3://<your-bucket>/msha-raw/'
--     STORAGE_INTEGRATION = <your_s3_integration>
--     FILE_FORMAT = MSHA_CSV_GZ;

LIST @MSHA_RAW_STAGE;

-- COPY with MATCH_BY_COLUMN_NAME does not apply column DEFAULTs, so _loaded_at is set from load metadata.

TRUNCATE TABLE MSHA_ACCIDENT;  -- rerunnable: clears rows and load history
COPY INTO MSHA_ACCIDENT
    FROM @MSHA_RAW_STAGE/accident/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_INSPECTION;  -- rerunnable: clears rows and load history
COPY INTO MSHA_INSPECTION
    FROM @MSHA_RAW_STAGE/inspection/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_VIOLATION;  -- rerunnable: clears rows and load history
COPY INTO MSHA_VIOLATION
    FROM @MSHA_RAW_STAGE/violation/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY;  -- rerunnable: clears rows and load history
COPY INTO MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY
    FROM @MSHA_RAW_STAGE/operator_employment_production_quarterly/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_ANNUAL;  -- rerunnable: clears rows and load history
COPY INTO MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_ANNUAL
    FROM @MSHA_RAW_STAGE/operator_employment_production_annual/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_QUARTERLY;  -- rerunnable: clears rows and load history
COPY INTO MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_QUARTERLY
    FROM @MSHA_RAW_STAGE/contractor_employment_production_quarterly/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_ANNUAL;  -- rerunnable: clears rows and load history
COPY INTO MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_ANNUAL
    FROM @MSHA_RAW_STAGE/contractor_employment_production_annual/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_ASSESSED_VIOLATIONS;  -- rerunnable: clears rows and load history
COPY INTO MSHA_ASSESSED_VIOLATIONS
    FROM @MSHA_RAW_STAGE/assessed_violations/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_MINES;  -- rerunnable: clears rows and load history
COPY INTO MSHA_MINES
    FROM @MSHA_RAW_STAGE/mines/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_OPERATOR_HISTORY_AT_MINES;  -- rerunnable: clears rows and load history
COPY INTO MSHA_OPERATOR_HISTORY_AT_MINES
    FROM @MSHA_RAW_STAGE/operator_history_at_mines/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_CONTRACTOR_HISTORY_AT_MINES;  -- rerunnable: clears rows and load history
COPY INTO MSHA_CONTRACTOR_HISTORY_AT_MINES
    FROM @MSHA_RAW_STAGE/contractor_history_at_mines/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_CONTROLLER_HISTORY;  -- rerunnable: clears rows and load history
COPY INTO MSHA_CONTROLLER_HISTORY
    FROM @MSHA_RAW_STAGE/controller_history/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_COMMODITY_LOOKUP;  -- rerunnable: clears rows and load history
COPY INTO MSHA_COMMODITY_LOOKUP
    FROM @MSHA_RAW_STAGE/commodity_lookup/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;

TRUNCATE TABLE MSHA_CONTRACTOR_NAME_ID_LOOKUP;  -- rerunnable: clears rows and load history
COPY INTO MSHA_CONTRACTOR_NAME_ID_LOOKUP
    FROM @MSHA_RAW_STAGE/contractor_name_id_lookup/
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_source_file = METADATA$FILENAME, _loaded_at = METADATA$START_SCAN_TIME)
    ON_ERROR = ABORT_STATEMENT;
