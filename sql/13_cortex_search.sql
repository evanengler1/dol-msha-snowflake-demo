-- Phase 5: Cortex Search over MSHA accident narratives.
-- ACCIDENT_DETAIL is a view over TRANSFORMED tables without change tracking, so a
-- narrow FULL-refresh Dynamic Table feeds the service (REFRESH_MODE = FULL to match).
-- CITATION_TITLE (mine, ID, state, date) is the agent's title column so answers can cite dates.
-- IS_FATAL is TEXT 'Yes'/'No' so agent filters stay string-typed; ACCIDENT_YEAR is NUMBER.
USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;

CREATE OR REPLACE DYNAMIC TABLE DOL_MSHA_DEMO.ANALYTICS.ACCIDENT_NARRATIVE_SOURCE
  TARGET_LAG = '7 days'
  WAREHOUSE = DOL_MSHA_WH
  REFRESH_MODE = FULL
  COMMENT = 'Narrow copy of ACCIDENT_DETAIL narratives for ACCIDENT_NARRATIVE_SEARCH. Portal narratives are truncated at 384 characters.'
AS
SELECT
    accident_document_number,
    mine_name || ' (' || mine_id || ', ' || state || '), ' || TO_VARCHAR(accident_date, 'YYYY-MM-DD') AS citation_title,
    TO_VARCHAR(accident_date, 'YYYY-MM-DD')        AS accident_date,
    accident_year,
    mine_id,
    mine_name,
    state,
    mine_category,
    mine_type,
    accident_classification,
    degree_of_injury,
    IFF(is_fatal, 'Yes', 'No')                     AS is_fatal,
    COALESCE(mining_equipment, 'Not reported')     AS mining_equipment,
    COALESCE(occupation, 'Not reported')           AS occupation,
    narrative
FROM DOL_MSHA_DEMO.ANALYTICS.ACCIDENT_DETAIL
WHERE narrative IS NOT NULL;

CREATE OR REPLACE CORTEX SEARCH SERVICE DOL_MSHA_DEMO.ANALYTICS.ACCIDENT_NARRATIVE_SEARCH
  ON narrative
  ATTRIBUTES mine_id, mine_name, state, mine_category, mine_type, accident_classification,
             degree_of_injury, accident_year, is_fatal, mining_equipment, occupation
  WAREHOUSE = DOL_MSHA_WH
  TARGET_LAG = '7 days'
  REFRESH_MODE = FULL
  COMMENT = 'Semantic search over MSHA accident narratives (DOL Open Data Portal). Returns accident document number and date for citation.'
AS
SELECT narrative, accident_document_number, citation_title, accident_date, accident_year, mine_id, mine_name, state,
       mine_category, mine_type, accident_classification, degree_of_injury, is_fatal,
       mining_equipment, occupation
FROM DOL_MSHA_DEMO.ANALYTICS.ACCIDENT_NARRATIVE_SOURCE;
