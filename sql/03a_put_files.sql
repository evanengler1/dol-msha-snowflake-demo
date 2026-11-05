-- Phase 1, Option B1: upload process_msha_data.py output to the internal stage.
-- Run from the repo root (paths are relative):  snow sql -c <connection> -f sql/03a_put_files.sql
-- Run after 03_load.sql has created the stage once, or create it here first.
USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE SCHEMA DOL_MSHA_DEMO.RAW;

CREATE FILE FORMAT IF NOT EXISTS MSHA_CSV_GZ
    TYPE = CSV COMPRESSION = GZIP PARSE_HEADER = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"' FIELD_DELIMITER = ','
    EMPTY_FIELD_AS_NULL = FALSE ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;
CREATE STAGE IF NOT EXISTS MSHA_RAW_STAGE FILE_FORMAT = MSHA_CSV_GZ;

PUT file://output/msha-raw/accident/accident.csv.gz @MSHA_RAW_STAGE/accident/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/inspection/inspection.csv.gz @MSHA_RAW_STAGE/inspection/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/violation/violation.csv.gz @MSHA_RAW_STAGE/violation/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/operator_employment_production_quarterly/operator_employment_production_quarterly.csv.gz @MSHA_RAW_STAGE/operator_employment_production_quarterly/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/operator_employment_production_annual/operator_employment_production_annual.csv.gz @MSHA_RAW_STAGE/operator_employment_production_annual/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/contractor_employment_production_quarterly/contractor_employment_production_quarterly.csv.gz @MSHA_RAW_STAGE/contractor_employment_production_quarterly/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/contractor_employment_production_annual/contractor_employment_production_annual.csv.gz @MSHA_RAW_STAGE/contractor_employment_production_annual/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/assessed_violations/assessed_violations.csv.gz @MSHA_RAW_STAGE/assessed_violations/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/mines/mines.csv.gz @MSHA_RAW_STAGE/mines/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/operator_history_at_mines/operator_history_at_mines.csv.gz @MSHA_RAW_STAGE/operator_history_at_mines/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/contractor_history_at_mines/contractor_history_at_mines.csv.gz @MSHA_RAW_STAGE/contractor_history_at_mines/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/controller_history/controller_history.csv.gz @MSHA_RAW_STAGE/controller_history/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/commodity_lookup/commodity_lookup.csv.gz @MSHA_RAW_STAGE/commodity_lookup/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;
PUT file://output/msha-raw/contractor_name_id_lookup/contractor_name_id_lookup.csv.gz @MSHA_RAW_STAGE/contractor_name_id_lookup/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE PARALLEL = 8;

LIST @MSHA_RAW_STAGE;
