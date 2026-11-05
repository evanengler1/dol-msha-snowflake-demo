-- =============================================================================
-- 05_transformed_tables.sql
-- DOL MSHA Demo - Phase 2: typed, decoded TRANSFORMED tables (one per entity).
--
-- Source : DOL_MSHA_DEMO.RAW.MSHA_*  (all VARCHAR, never modified)
-- Target : DOL_MSHA_DEMO.TRANSFORMED.*
-- Idempotent: every object is CREATE OR REPLACE.
--
-- Conventions
--   * Null markers: '', 'NaT', 'nan' are treated as NULL before every cast
--     (helper CLEAN_STR). TRY_TO_DOUBLE('nan') returns NaN, not NULL, so 'nan'
--     must be nulled explicitly.
--   * Dates arrive as '2006-08-25 00:00:00+00:00' -> helper CLEAN_DATE.
--   * IDs (mine_id, event_no, viol_no, ...), SIC/NAICS, part_section stay
--     VARCHAR so leading zeros survive. Never cast IDs to numbers.
--   * CTAS width trap: expressions yield VARCHAR(16777216), so every string
--     column is CAST to an explicit width.
--   * Amounts NUMBER(14,2); rates NUMBER(10,4).
-- =============================================================================

USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE DATABASE DOL_MSHA_DEMO;
USE SCHEMA TRANSFORMED;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION CLEAN_STR(s VARCHAR)
RETURNS VARCHAR
COMMENT = 'Trim and convert portal null markers ('''', NaT, nan) to NULL'
AS $$ NULLIF(NULLIF(NULLIF(TRIM(s), ''), 'NaT'), 'nan') $$;

CREATE OR REPLACE FUNCTION CLEAN_DATE(s VARCHAR)
RETURNS DATE
COMMENT = 'Parse portal timestamp-with-offset strings to DATE; NULL on failure'
AS $$ TRY_TO_TIMESTAMP_TZ(CLEAN_STR(s))::DATE $$;

CREATE OR REPLACE FUNCTION CLEAN_NUM(s VARCHAR)
RETURNS FLOAT
COMMENT = 'Parse numeric strings; NULL for blanks/nan/non-numeric'
AS $$ TRY_TO_DOUBLE(CLEAN_STR(s)) $$;

-- -----------------------------------------------------------------------------
-- Reference: degree of injury
-- Definitions used throughout the demo (state these when presenting):
--   is_fatal             = degree 01
--   is_lost_time (NFDL)  = degree 02-05: permanent disability, days away,
--                          days away + restricted, restricted only.
--   is_reportable_injury = degree 01-06: fatal + NFDL + no-days-lost (06).
--                          Excludes 00 accident-only, 07 occupational illness,
--                          08 natural causes, 09 non-employees, 10 other/first aid.
-- These follow MSHA's Part 50 degree codes and the common MSHA/NIOSH NFDL
-- convention. They could NOT be checked against MSHA's published methodology
-- page during the build (site unreachable); confirm with MSHA before quoting
-- rates as "official".
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DEGREE_OF_INJURY_REF (
    degree_injury_cd     VARCHAR(2),
    degree_label         VARCHAR(60),
    is_fatal             BOOLEAN,
    is_lost_time         BOOLEAN,
    is_reportable_injury BOOLEAN
) AS
SELECT * FROM VALUES
    ('00', 'Accident only (no injury)',               FALSE, FALSE, FALSE),
    ('01', 'Fatality',                                TRUE,  FALSE, TRUE),
    ('02', 'Permanent total or partial disability',   FALSE, TRUE,  TRUE),
    ('03', 'Days away from work only',                FALSE, TRUE,  TRUE),
    ('04', 'Days away from work and restricted',      FALSE, TRUE,  TRUE),
    ('05', 'Days restricted activity only',           FALSE, TRUE,  TRUE),
    ('06', 'No days away, no restriction',            FALSE, FALSE, TRUE),
    ('07', 'Occupational illness',                    FALSE, FALSE, FALSE),
    ('08', 'Injury due to natural causes',            FALSE, FALSE, FALSE),
    ('09', 'Injury involving non-employees',          FALSE, FALSE, FALSE),
    ('10', 'All other cases (incl. first aid)',       FALSE, FALSE, FALSE);

-- -----------------------------------------------------------------------------
-- Reference: hazard category (compliance proxies, NOT sensor readings)
-- Section ranges checked against 30 CFR Part 75 subparts:
--   C 75.200-75.223 roof/rib/face; D 75.300-75.390 ventilation (incl. methane
--   tests/limits, 75.323); E 75.400-75.404 combustible materials & rock dust;
--   F-K 75.500-75.1003 electrical, trailing cables, grounding, high/low/medium
--   voltage, trolley wires. Part 47 (HazCom) is not in the prompt's map -> Other.
-- match_rule is documentation; the CASE in VIOLATION implements it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE HAZARD_CATEGORY_REF (
    category_code VARCHAR(30),
    label         VARCHAR(60),
    cfr_reference VARCHAR(80),
    match_rule    VARCHAR(120),
    description   VARCHAR(300),
    sort_order    NUMBER(3)
) AS
SELECT * FROM VALUES
 ('VENT_METHANE','Ventilation & Methane','30 CFR 75 Subpart D (75.300-75.390)','part 75, section 300-399',
  'Underground coal ventilation, methane examinations and limits. Closest portal proxy for methane/air quality. Headline proxy.',1),
 ('COMBUST_ROCKDUST','Combustible Material & Rock Dust','30 CFR 75 Subpart E (75.400-75.404)','part 75, section 400-499',
  'Accumulations of coal dust and rock dusting; coal dust explosion risk.',2),
 ('ELECTRICAL','Electrical / Permissibility','30 CFR 75 Subparts F-K (75.500-75.1003)','part 75, section 500-1099',
  'Permissible equipment, cables, grounding, high/low voltage, trolley; ignition sources.',3),
 ('ROOF_RIB','Roof & Rib Control','30 CFR 75 Subpart C (75.200-75.223)','part 75, section 200-299',
  'Roof and rib support; historically a leading underground fatality cause.',4),
 ('RESP_DUST','Respirable Dust','30 CFR 70, 71, 72, 90','part IN (70,71,72,90)',
  'Respirable coal mine dust and quartz; black lung.',5),
 ('OTHER_UG_COAL','Other Underground Coal','30 CFR 75 (other subparts)','part 75, any other section',
  'Underground coal standards outside the categories above (fire protection, hoisting, escapeways, diesel, ...).',6),
 ('SURFACE_COAL','Surface Coal','30 CFR 77','part 77','Surface coal mines and surface areas of underground coal mines.',7),
 ('MNM_SURFACE','Metal/Nonmetal Surface','30 CFR 56','part 56','Surface metal and nonmetal mines.',8),
 ('MNM_UNDERGROUND','Metal/Nonmetal Underground','30 CFR 57','part 57','Underground metal and nonmetal mines.',9),
 ('REPORTING_TRAINING','Reporting & Training','30 CFR 46, 48, 50, 62','part IN (46,48,50,62)',
  'Accident/injury reporting (Part 50), training (46/48), occupational noise (62).',10),
 ('OTHER','Other / Unknown','Other parts or blank','everything else, blank',
  'Other parts (e.g. 47 HazCom, 41 legal identity) and violations with no part/section.',11);

-- -----------------------------------------------------------------------------
-- MINE: one row per mine_id
-- Longitude: the portal stores U.S. longitudes as POSITIVE values (92,096 of
-- 92,102 mines). U.S. sites are west of Greenwich, so longitude = -ABS(value).
-- Exception: Guam (GU) and Northern Mariana Islands (MP) lie east of 180 deg
-- and are genuinely positive.
-- has_geo_issue: coordinates missing or outside CONUS / AK / HI / PR-VI / AS /
-- GU-MP boxes, or latitude > 90.
-- methn_librtn / mine_gas_category_cd: kept as-is; EDA shows <0.4% populated,
-- so they are NOT usable as a methane measure (see 08_eda_queries.sql).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE MINE AS
WITH src AS (
    SELECT m.*,
           CLEAN_NUM(latitude)  AS lat_raw,
           CLEAN_NUM(longitude) AS lon_raw,
           CLEAN_STR(state_abbr) AS st
    FROM RAW.MSHA_MINES m
),
geo AS (
    SELECT src.*,
           lat_raw AS lat,
           IFF(st IN ('GU','MP'), ABS(lon_raw), -ABS(lon_raw)) AS lon
    FROM src
)
SELECT
    CAST(CLEAN_STR(mine_id) AS VARCHAR(7))                    AS mine_id,
    CAST(CLEAN_STR(curr_mine_nm) AS VARCHAR(100))             AS mine_name,
    CAST(CLEAN_STR(c_m_ind) AS VARCHAR(1))                    AS coal_metal_ind,
    CAST(DECODE(CLEAN_STR(c_m_ind),'C','Coal','M','Metal/Nonmetal') AS VARCHAR(20)) AS coal_metal,
    CAST(CLEAN_STR(mine_type_cd) AS VARCHAR(20))              AS mine_type,
    CAST(CLEAN_STR(curr_stat_cd) AS VARCHAR(20))              AS current_status,
    CLEAN_DATE(curr_stat_dt)                                  AS current_status_date,
    CAST(CLEAN_STR(oper_id) AS VARCHAR(10))                   AS operator_id,
    CAST(CLEAN_STR(oper_nm) AS VARCHAR(150))                  AS operator_name,
    CAST(CLEAN_STR(controller_id) AS VARCHAR(10))             AS controller_id,
    CAST(CLEAN_STR(controller_nm) AS VARCHAR(150))            AS controller_name,
    CLEAN_DATE(curr_ownr_beg_dt)                              AS current_owner_begin_date,
    CAST(st AS VARCHAR(2))                                    AS state_abbr,
    CAST(CLEAN_STR(fips_cnty_cd) AS VARCHAR(5))               AS fips_county_cd,
    CAST(CLEAN_STR(fips_cnty_nm) AS VARCHAR(60))              AS county_name,
    CAST(CLEAN_STR(district) AS VARCHAR(10))                  AS district,
    CAST(CLEAN_STR(office_cd) AS VARCHAR(10))                 AS office_cd,
    CAST(CLEAN_STR(office_name) AS VARCHAR(60))               AS office_name,
    CAST(CLEAN_STR(full_sic_cd) AS VARCHAR(10))               AS primary_sic_cd,
    CAST(CLEAN_STR(sic_desc) AS VARCHAR(100))                 AS primary_sic_desc,
    CAST(CLEAN_STR(primary_canvass_cd) AS VARCHAR(5))         AS primary_canvass_cd,
    CAST(CLEAN_STR(primary_canvass_desc) AS VARCHAR(60))      AS primary_canvass_desc,
    CAST(CLEAN_STR(company_type) AS VARCHAR(30))              AS company_type,
    TRY_TO_NUMBER(CLEAN_STR(employee_cnt))                    AS employee_count,
    CAST(CLEAN_STR(mine_gas_category_cd) AS VARCHAR(5))       AS mine_gas_category_cd,
    CAST(CLEAN_NUM(methn_librtn) AS NUMBER(14,2))             AS methane_liberation,
    CAST(CLEAN_STR(curr_103i_cd) AS VARCHAR(10))              AS current_103i_cd,
    CAST(CLEAN_STR(mine_103i_desc) AS VARCHAR(60))            AS current_103i_desc,
    CAST(CLEAN_STR(nearest_town) AS VARCHAR(60))              AS nearest_town,
    CAST(lat AS NUMBER(9,6))                                  AS latitude,
    CAST(lon AS NUMBER(10,6))                                 AS longitude,
    ( lat IS NULL OR lon IS NULL
      OR NOT (
           (lat BETWEEN 24 AND 50     AND lon BETWEEN -125 AND -66)    -- CONUS
        OR (lat BETWEEN 51 AND 72     AND lon BETWEEN -180 AND -129)   -- Alaska
        OR (lat BETWEEN 18 AND 23     AND lon BETWEEN -161 AND -154)   -- Hawaii
        OR (lat BETWEEN 17 AND 19     AND lon BETWEEN -68  AND -64)    -- PR / USVI
        OR (lat BETWEEN -15 AND -13   AND lon BETWEEN -172 AND -168)   -- Am. Samoa
        OR (lat BETWEEN 13 AND 21     AND lon BETWEEN 144  AND 146)    -- Guam / CNMI
      ) )                                                      AS has_geo_issue,
    _loaded_at
FROM geo;

-- -----------------------------------------------------------------------------
-- ACCIDENT: one row per document_no (= one injured/involved PERSON).
-- no_injuries is EVENT-level and repeated on each person's row -> never SUM it.
-- Count injured persons as rows (COUNT_IF is_reportable_injury).
-- accident_time 9995-9999 are sentinels -> NULL; 2400 -> 00:00. days_lost blank -> NULL, not 0.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ACCIDENT AS
SELECT
    CAST(CLEAN_STR(a.document_no) AS VARCHAR(12))             AS document_no,
    CAST(CLEAN_STR(a.mine_id) AS VARCHAR(7))                  AS mine_id,
    CAST(CLEAN_STR(a.cntctr_id) AS VARCHAR(10))               AS cntctr_id,
    (CLEAN_STR(a.cntctr_id) IS NOT NULL)                      AS is_contractor,
    CAST(CLEAN_STR(a.operator_id) AS VARCHAR(10))             AS operator_id,
    CAST(CLEAN_STR(a.operator_name) AS VARCHAR(150))          AS operator_name,
    CAST(CLEAN_STR(a.controller_id) AS VARCHAR(10))           AS controller_id,
    CAST(CLEAN_STR(a.controller_name) AS VARCHAR(150))        AS controller_name,
    CAST(CLEAN_STR(a.coal_metal_ind) AS VARCHAR(1))           AS coal_metal_ind,
    CAST(CLEAN_STR(a.subunit_cd) AS VARCHAR(2))               AS subunit_cd,
    CAST(CLEAN_STR(a.subunit_desc) AS VARCHAR(60))            AS subunit_desc,
    CLEAN_DATE(a.ai_dt)                                       AS accident_date,
    YEAR(CLEAN_DATE(a.ai_dt))                                 AS accident_year,
    QUARTER(CLEAN_DATE(a.ai_dt))                              AS accident_quarter,
    -- 9995-9999 are 'unknown' sentinels -> NULL; 2400 = midnight -> 00:00
    CASE WHEN CLEAN_STR(a.accident_time) >= '9900' THEN NULL
         WHEN CLEAN_STR(a.accident_time) = '2400' THEN TIME '00:00:00'
         ELSE TRY_TO_TIME(LPAD(CLEAN_STR(a.accident_time), 4, '0'), 'HH24MI') END AS accident_time,
    CAST(CLEAN_STR(a.degree_injury_cd) AS VARCHAR(2))         AS degree_injury_cd,
    d.degree_label,
    COALESCE(d.is_fatal, FALSE)                               AS is_fatal,
    COALESCE(d.is_lost_time, FALSE)                           AS is_lost_time,
    COALESCE(d.is_reportable_injury, FALSE)                   AS is_reportable_injury,
    TRY_TO_NUMBER(CLEAN_STR(a.no_injuries))                   AS event_no_injuries,  -- attribute only; never SUM
    CAST(CLEAN_STR(a.classification_cd) AS VARCHAR(3))        AS classification_cd,
    CAST(CLEAN_STR(a.ai_class_desc) AS VARCHAR(80))           AS classification,
    (CLEAN_STR(a.ai_class_desc) IN ('IGNITION OR EXPLOSION OF GAS OR DUST','FIRE',
                                    'EXPLODING VESSELS UNDER PRESSURE')) AS is_ignition_explosion_fire,
    CAST(CLEAN_STR(a.accident_type_cd) AS VARCHAR(3))         AS accident_type_cd,
    CAST(CLEAN_STR(a.accident_type) AS VARCHAR(80))           AS accident_type,
    CAST(CLEAN_STR(a.injury_source_cd) AS VARCHAR(4))         AS injury_source_cd,
    CAST(CLEAN_STR(a.injury_source) AS VARCHAR(80))           AS injury_source,
    CAST(CLEAN_STR(a.nature_injury_cd) AS VARCHAR(4))         AS nature_injury_cd,
    CAST(CLEAN_STR(a.nature_injury) AS VARCHAR(80))           AS nature_of_injury,
    CAST(CLEAN_STR(a.inj_body_part_cd) AS VARCHAR(4))         AS body_part_cd,
    CAST(CLEAN_STR(a.inj_body_part) AS VARCHAR(80))           AS body_part,
    CAST(CLEAN_STR(a.mining_equip_cd) AS VARCHAR(4))          AS mining_equipment_cd,
    CAST(CLEAN_STR(a.mining_equip) AS VARCHAR(80))            AS mining_equipment,
    CAST(CLEAN_STR(a.equip_mfr_name) AS VARCHAR(80))          AS equipment_manufacturer,
    CAST(CLEAN_STR(a.ai_occ_desc) AS VARCHAR(120))            AS occupation,
    CAST(CLEAN_STR(a.ai_acty_desc) AS VARCHAR(80))            AS activity,
    CAST(CLEAN_STR(a.ug_location) AS VARCHAR(80))             AS ug_location,
    CAST(CLEAN_STR(a.ug_mining_method) AS VARCHAR(80))        AS ug_mining_method,
    CAST(CLEAN_NUM(a.exper_tot_calc) AS NUMBER(6,2))          AS experience_total_years,
    CAST(CLEAN_NUM(a.exper_mine_calc) AS NUMBER(6,2))         AS experience_mine_years,
    CAST(CLEAN_NUM(a.exper_job_calc) AS NUMBER(6,2))          AS experience_job_years,
    TRY_TO_NUMBER(CLEAN_STR(a.days_lost))                     AS days_lost,
    TRY_TO_NUMBER(CLEAN_STR(a.days_restrict))                 AS days_restricted,
    TRY_TO_NUMBER(CLEAN_STR(a.schedule_charge))               AS schedule_charge,
    CLEAN_DATE(a.return_to_work_dt)                           AS return_to_work_date,
    CLEAN_DATE(a.invest_begin_dt)                             AS investigation_begin_date,
    CAST(TRIM(a.ai_narr) AS VARCHAR(4000))                    AS narrative,  -- verbatim for Cortex Search (Phase 5)
    a._loaded_at
FROM RAW.MSHA_ACCIDENT a
LEFT JOIN DEGREE_OF_INJURY_REF d
       ON d.degree_injury_cd = CLEAN_STR(a.degree_injury_cd);

-- -----------------------------------------------------------------------------
-- INSPECTION: one row per event_no
-- is_regular_inspection = activity E01 "Regular Safety and Health Inspection"
-- (verified against acty_desc; 341,677 rows).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE INSPECTION AS
SELECT
    CAST(CLEAN_STR(event_no) AS VARCHAR(10))                  AS event_no,
    CAST(CLEAN_STR(mine_id) AS VARCHAR(7))                    AS mine_id,
    CAST(CLEAN_STR(acty_cd) AS VARCHAR(4))                    AS activity_cd,
    CAST(CLEAN_STR(acty_desc) AS VARCHAR(80))                 AS activity_desc,
    (CLEAN_STR(acty_cd) = 'E01')                              AS is_regular_inspection,
    CLEAN_DATE(beg_dt)                                        AS begin_date,
    CLEAN_DATE(end_dt)                                        AS end_date,
    YEAR(CLEAN_DATE(beg_dt))                                  AS begin_year,
    QUARTER(CLEAN_DATE(beg_dt))                               AS begin_quarter,
    DATEDIFF(day, CLEAN_DATE(beg_dt), CLEAN_DATE(end_dt)) + 1 AS inspection_days,
    CAST(CLEAN_NUM(total_insp_hours) AS NUMBER(10,2))         AS total_insp_hours,
    CAST(CLEAN_NUM(total_on_site_hours) AS NUMBER(10,2))      AS total_on_site_hours,
    TRY_TO_NUMBER(CLEAN_STR(nbr_inspectors))                  AS nbr_inspectors,
    TRY_TO_NUMBER(CLEAN_STR(sample_cnt_air))                  AS sample_cnt_air,
    TRY_TO_NUMBER(CLEAN_STR(sample_cnt_dustspot))             AS sample_cnt_dust_spot,
    TRY_TO_NUMBER(CLEAN_STR(sample_cnt_dustsurvey))           AS sample_cnt_dust_survey,
    TRY_TO_NUMBER(CLEAN_STR(sample_cnt_respdust))             AS sample_cnt_respirable_dust,
    TRY_TO_NUMBER(CLEAN_STR(sample_cnt_noise))                AS sample_cnt_noise,
    TRY_TO_NUMBER(CLEAN_STR(sample_cnt_other))                AS sample_cnt_other,
    CAST(CLEAN_STR(coal_metal_ind) AS VARCHAR(1))             AS coal_metal_ind,
    CAST(CLEAN_STR(operator_id) AS VARCHAR(10))               AS operator_id,
    CAST(CLEAN_STR(controller_id) AS VARCHAR(10))             AS controller_id,
    CAST(CLEAN_STR(inspect_office_cd) AS VARCHAR(10))         AS inspect_office_cd,
    _loaded_at
FROM RAW.MSHA_INSPECTION;

-- -----------------------------------------------------------------------------
-- VIOLATION: one row per viol_no, with the assessed penalty LEFT JOINed on
-- assessed.citation_nbr = violation.viol_no.
-- Enforcement actions (Federal Mine Safety and Health Act of 1977):
--   104(d)(1)/(d)(2) = unwarrantable failure citation/order -> is_unwarrantable_failure
--   107(a)           = imminent danger order               -> is_imminent_danger
--   104(b) failure to abate; 103(k) accident control order; 104(g)(1) untrained miner.
-- Ordinal scores: likelihood 0 NoLikelihood .. 4 Occurred;
--                 negligence 0 NoNegligence .. 4 Reckless. Blanks -> NULL.
-- penalty_status_group collapses last_action_code; open balance is only
-- meaningful for 'Open-Delinquent'.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE VIOLATION AS
WITH v AS (
    SELECT r.*,
           CLEAN_STR(r.part_section)                                         AS ps,
           TRY_TO_NUMBER(SPLIT_PART(CLEAN_STR(r.part_section), '.', 1))      AS cfr_part,
           TRY_TO_NUMBER(REGEXP_SUBSTR(CLEAN_STR(r.part_section), '^\\d+\\.(\\d+)', 1, 1, 'e')) AS cfr_section_num,
           CLEAN_STR(r.type_of_actn_1)                                       AS actn
    FROM RAW.MSHA_VIOLATION r
),
a AS (
    SELECT CLEAN_STR(citation_nbr)                              AS citation_nbr,
           CAST(CLEAN_NUM(proposed_penalty_amt) AS NUMBER(14,2))  AS proposed_penalty,
           CAST(CLEAN_NUM(current_assessment_amt) AS NUMBER(14,2)) AS current_assessment,
           CAST(CLEAN_NUM(paid_proposed_penalty_amt) AS NUMBER(14,2)) AS amount_paid,
           CLEAN_STR(last_action_code)                          AS last_action_code,
           CLEAN_DATE(final_order_date)                         AS final_order_date,
           CLEAN_DATE(last_action_date)                         AS penalty_last_action_date
    FROM RAW.MSHA_ASSESSED_VIOLATIONS
)
SELECT
    CAST(CLEAN_STR(v.viol_no) AS VARCHAR(10))                 AS viol_no,
    CAST(CLEAN_STR(v.event_no) AS VARCHAR(10))                AS event_no,
    CAST(CLEAN_STR(v.mine_id) AS VARCHAR(7))                  AS mine_id,
    CAST(CLEAN_STR(v.coal_metal_ind) AS VARCHAR(1))           AS coal_metal_ind,
    CAST(CLEAN_STR(v.mine_type) AS VARCHAR(20))               AS mine_type,
    CAST(CLEAN_STR(v.violator_type_cd) AS VARCHAR(20))        AS violator_type,
    CAST(CLEAN_STR(v.violator_id) AS VARCHAR(10))             AS violator_id,
    CAST(CLEAN_STR(v.violator_name) AS VARCHAR(150))          AS violator_name,
    CAST(CLEAN_STR(v.cntctr_id) AS VARCHAR(10))               AS cntctr_id,
    CAST(CLEAN_STR(v.controller_id) AS VARCHAR(10))           AS controller_id,
    CLEAN_DATE(v.iss_dt)                                      AS issue_date,
    YEAR(CLEAN_DATE(v.iss_dt))                                AS issue_year,
    QUARTER(CLEAN_DATE(v.iss_dt))                             AS issue_quarter,
    CLEAN_DATE(v.violation_occur_dt)                          AS occurrence_date,
    CLEAN_DATE(v.orig_term_due_dt)                            AS original_term_due_date,
    CLEAN_DATE(v.latest_term_due_dt)                          AS latest_term_due_date,
    CLEAN_DATE(v.term_dt)                                     AS termination_date,
    CAST(CLEAN_STR(v.termination_type) AS VARCHAR(30))        AS termination_type,
    CAST(v.ps AS VARCHAR(40))                                 AS part_section,
    v.cfr_part,
    CAST(CASE
        WHEN v.cfr_part = 75 AND v.cfr_section_num BETWEEN 300 AND 399  THEN 'VENT_METHANE'
        WHEN v.cfr_part = 75 AND v.cfr_section_num BETWEEN 400 AND 499  THEN 'COMBUST_ROCKDUST'
        WHEN v.cfr_part = 75 AND v.cfr_section_num BETWEEN 500 AND 1099 THEN 'ELECTRICAL'
        WHEN v.cfr_part = 75 AND v.cfr_section_num BETWEEN 200 AND 299  THEN 'ROOF_RIB'
        WHEN v.cfr_part IN (70, 71, 72, 90)                             THEN 'RESP_DUST'
        WHEN v.cfr_part = 75                                            THEN 'OTHER_UG_COAL'
        WHEN v.cfr_part = 77                                            THEN 'SURFACE_COAL'
        WHEN v.cfr_part = 56                                            THEN 'MNM_SURFACE'
        WHEN v.cfr_part = 57                                            THEN 'MNM_UNDERGROUND'
        WHEN v.cfr_part IN (46, 48, 50, 62)                             THEN 'REPORTING_TRAINING'
        ELSE 'OTHER' END AS VARCHAR(30))                      AS hazard_category,
    CAST(CLEAN_STR(v.section_of_act) AS VARCHAR(20))          AS section_of_act,
    CAST(v.actn AS VARCHAR(20))                               AS enforcement_action,
    CAST(CLEAN_STR(v.cit_ord_safe) AS VARCHAR(20))            AS citation_order_safeguard,
    CAST(CLEAN_STR(v.sig_sub) AS VARCHAR(1))                  AS sig_sub,
    IFF(CLEAN_STR(v.sig_sub) IS NULL, NULL, CLEAN_STR(v.sig_sub) = 'Y') AS is_sig_sub,
    (CLEAN_STR(v.cit_ord_safe) = 'Order')                     AS is_order,
    (v.actn LIKE '104(d)%')                                   AS is_unwarrantable_failure,
    (v.actn = '107(a)')                                       AS is_imminent_danger,
    CAST(CLEAN_STR(v.likelihood) AS VARCHAR(20))              AS likelihood,
    DECODE(CLEAN_STR(v.likelihood),'NoLikelihood',0,'Unlikely',1,'Reasonably',2,'Highly',3,'Occurred',4) AS likelihood_score,
    CAST(CLEAN_STR(v.inj_illness) AS VARCHAR(20))             AS injury_illness_expected,
    CAST(CLEAN_STR(v.negligence) AS VARCHAR(20))              AS negligence,
    DECODE(CLEAN_STR(v.negligence),'NoNegligence',0,'LowNegligence',1,'ModNegligence',2,'HighNegligence',3,'Reckless',4) AS negligence_score,
    IFF(CLEAN_STR(v.negligence) IS NULL, NULL, CLEAN_STR(v.negligence) IN ('HighNegligence','Reckless')) AS is_high_negligence,
    TRY_TO_NUMBER(CLEAN_STR(v.no_affected))                   AS persons_affected,
    (CLEAN_STR(v.contested_ind) = 'Y')                        AS is_contested,
    a.proposed_penalty,
    a.current_assessment,
    a.amount_paid,
    CAST(a.last_action_code AS VARCHAR(40))                   AS penalty_last_action,
    a.final_order_date,
    CAST(CASE
        WHEN a.citation_nbr IS NULL THEN 'Not Assessed'
        WHEN a.last_action_code = 'Paid' THEN 'Paid'
        WHEN a.last_action_code IN ('Citation Vacated','Vacate','Vacated','IssuanceVacated')
          OR a.last_action_code ILIKE 'Vacated%' THEN 'Vacated'
        WHEN a.last_action_code ILIKE '%Uncollectable%' OR a.last_action_code ILIKE 'Chapter%'
          OR a.last_action_code ILIKE '%bankrupt%' THEN 'Uncollectable-Bankrupt'
        WHEN a.last_action_code IN ('Treasury','Recalled From Treasury','RecommendTreasury','ApprovedForTreasury',
                                    'Delinquent','1stDemandPrinted','1stDemandReady','2ndDemandPrinted',
                                    'FinalDemandPrinted','Proposed','Final Order Date','Default',
                                    'Received by Justice','Filed in US Dist Court') THEN 'Open-Delinquent'
        ELSE 'Contested-Other' END AS VARCHAR(30))            AS penalty_status_group,
    v._loaded_at
FROM v
LEFT JOIN a ON a.citation_nbr = CLEAN_STR(v.viol_no);

-- -----------------------------------------------------------------------------
-- EMPLOYMENT_QUARTERLY: operator hours. petreemine_id IS the mine_id.
-- Grain mine x subunit x year x quarter (verified unique in Phase 1).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE EMPLOYMENT_QUARTERLY AS
SELECT
    CAST(CLEAN_STR(petreemine_id) AS VARCHAR(7))              AS mine_id,
    CAST(CLEAN_STR(subunit_cd) AS VARCHAR(2))                 AS subunit_cd,
    CAST(CLEAN_STR(subunit_desc) AS VARCHAR(60))              AS subunit_desc,
    TRY_TO_NUMBER(CLEAN_STR(empl_prod_yr))                    AS year,
    TRY_TO_NUMBER(CLEAN_STR(empl_prod_qtr))                   AS quarter,
    CAST(CLEAN_NUM(empl_hrs) AS NUMBER(14,2))                 AS hours_worked,
    CAST(CLEAN_NUM(avg_empl_cnt) AS NUMBER(10,2))             AS avg_employees,
    CAST(CLEAN_NUM(coal_prod) AS NUMBER(16,2))                AS coal_production_tons,
    _loaded_at
FROM RAW.MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY;

-- Annual operator hours, kept only for reconciliation against quarterly.
CREATE OR REPLACE TABLE EMPLOYMENT_ANNUAL AS
SELECT
    CAST(CLEAN_STR(mine_id) AS VARCHAR(7))                    AS mine_id,
    CAST(CLEAN_STR(subunit_cd) AS VARCHAR(2))                 AS subunit_cd,
    TRY_TO_NUMBER(CLEAN_STR(calendar_yr))                     AS year,
    CAST(CLEAN_NUM(annual_hrs) AS NUMBER(14,2))               AS hours_worked,
    CAST(CLEAN_NUM(avg_annual_empl) AS NUMBER(10,2))          AS avg_employees,
    CAST(CLEAN_NUM(annual_coal_prod) AS NUMBER(16,2))         AS coal_production_tons,
    _loaded_at
FROM RAW.MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_ANNUAL;

-- -----------------------------------------------------------------------------
-- CONTRACTOR_EMPLOYMENT_QUARTERLY: contractor hours have NO mine_id, so they
-- feed national/industry rates only. 82 exact-key duplicates in RAW; keep the
-- latest-loaded row per key (EDA reports rows removed).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE CONTRACTOR_EMPLOYMENT_QUARTERLY AS
SELECT
    CAST(CLEAN_STR(cntctr_id) AS VARCHAR(10))                 AS cntctr_id,
    CAST(CLEAN_STR(subunit_cd) AS VARCHAR(2))                 AS subunit_cd,
    CAST(CLEAN_STR(subunit_desc) AS VARCHAR(60))              AS subunit_desc,
    TRY_TO_NUMBER(CLEAN_STR(empl_prod_yr))                    AS year,
    TRY_TO_NUMBER(CLEAN_STR(empl_prod_qtr))                   AS quarter,
    CAST(CLEAN_STR(cmdty_type) AS VARCHAR(20))                AS commodity_type,
    CAST(CLEAN_NUM(empl_hrs) AS NUMBER(14,2))                 AS hours_worked,
    CAST(CLEAN_NUM(avg_empl_cnt) AS NUMBER(10,2))             AS avg_employees,
    CAST(CLEAN_NUM(coal_prod) AS NUMBER(16,2))                AS coal_production_tons,
    _loaded_at
FROM RAW.MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_QUARTERLY
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY cntctr_id, subunit_cd, empl_prod_yr, empl_prod_qtr, cmdty_type
    ORDER BY _loaded_at DESC, TRY_TO_DOUBLE(empl_hrs) DESC NULLS LAST) = 1;

-- -----------------------------------------------------------------------------
-- History tables. is_current = no end date.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE OPERATOR_HISTORY AS
SELECT
    CAST(CLEAN_STR(mine_id) AS VARCHAR(7))                    AS mine_id,
    CAST(CLEAN_STR(oper_id) AS VARCHAR(10))                   AS operator_id,
    CAST(CLEAN_STR(oper_nm) AS VARCHAR(150))                  AS operator_name,
    CLEAN_DATE(oper_start_dt)                                 AS start_date,
    CLEAN_DATE(oper_end_dt)                                   AS end_date,
    (CLEAN_DATE(oper_end_dt) IS NULL)                         AS is_current,
    _loaded_at
FROM RAW.MSHA_OPERATOR_HISTORY_AT_MINES;

CREATE OR REPLACE TABLE CONTRACTOR_HISTORY AS
SELECT
    CAST(CLEAN_STR(mine_id) AS VARCHAR(7))                    AS mine_id,
    CAST(CLEAN_STR(cntctr_id) AS VARCHAR(10))                 AS cntctr_id,
    CAST(CLEAN_STR(cntctr_nm) AS VARCHAR(150))                AS contractor_name,
    CLEAN_DATE(cntctr_start_dt)                               AS start_date,
    CLEAN_DATE(cntctr_end_dt)                                 AS end_date,
    (CLEAN_DATE(cntctr_end_dt) IS NULL)                       AS is_current,
    _loaded_at
FROM RAW.MSHA_CONTRACTOR_HISTORY_AT_MINES;

CREATE OR REPLACE TABLE CONTROLLER_HISTORY AS
SELECT
    CAST(CLEAN_STR(oper_id) AS VARCHAR(10))                   AS operator_id,
    CAST(CLEAN_STR(oper_nm) AS VARCHAR(150))                  AS operator_name,
    CAST(CLEAN_STR(ctrlr_id) AS VARCHAR(10))                  AS controller_id,
    CAST(CLEAN_STR(ctrlr_nm) AS VARCHAR(150))                 AS controller_name,
    CLEAN_DATE(ctrlr_start_dt)                                AS start_date,
    CLEAN_DATE(ctrlr_end_dt)                                  AS end_date,
    (CLEAN_DATE(ctrlr_end_dt) IS NULL)                        AS is_current,
    _loaded_at
FROM RAW.MSHA_CONTROLLER_HISTORY;

CREATE OR REPLACE TABLE COMMODITY AS
SELECT
    CAST(CLEAN_STR(cmmdty_cd) AS VARCHAR(10))                 AS commodity_cd,
    CAST(CLEAN_STR(cmmdty_desc) AS VARCHAR(100))              AS commodity_desc,
    CAST(CLEAN_STR(sic_cd) AS VARCHAR(10))                    AS sic_cd,
    CAST(CLEAN_STR(naics_cd) AS VARCHAR(10))                  AS naics_cd,
    _loaded_at
FROM RAW.MSHA_COMMODITY_LOOKUP;

CREATE OR REPLACE TABLE CONTRACTOR AS
SELECT
    CAST(CLEAN_STR(cntctr_id) AS VARCHAR(10))                 AS cntctr_id,
    CAST(CLEAN_STR(cntctr_nm) AS VARCHAR(150))                AS contractor_name,
    _loaded_at
FROM RAW.MSHA_CONTRACTOR_NAME_ID_LOOKUP;
