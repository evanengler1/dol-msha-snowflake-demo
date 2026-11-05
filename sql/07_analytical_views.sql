-- =============================================================================
-- 07_analytical_views.sql
-- DOL MSHA Demo - Phase 2: ANALYTICS interface layer.
--
-- Streamlit (Phase 3), the React app (Phase 4) and the Cortex Agent (Phase 5)
-- read ONLY from these views. Column names are spelled out and use labels,
-- not codes, because the agent generates SQL from them.
--
-- Depends on: 05_transformed_tables.sql, 06_mine_quarter_fact.sql
--
-- Reading notes for every view
--   * Rates are per 200,000 hours worked (100 full-time workers for one year).
--   * "operator" rates = operator-employee injuries / operator hours (mine level).
--     "all workers" rates = operator + contractor injuries / operator + contractor
--     hours (national and industry level only; contractor hours have no mine).
--   * Hazard categories are COMPLIANCE PROXIES built from cited CFR sections.
--     The portal has no methane, temperature or other sensor readings.
--   * The latest quarter with hours is partial (late reporting) and is flagged;
--     exclude it from trend comparisons.
-- =============================================================================

USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE DATABASE DOL_MSHA_DEMO;
USE SCHEMA ANALYTICS;

-- -----------------------------------------------------------------------------
-- NATIONAL_TRENDS: year x mine category ('Coal', 'Metal/Nonmetal', 'All Mines')
-- Years 2010 .. latest year with hours. The latest year is partial unless its
-- last quarter of hours is Q4; is_partial_year flags it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW NATIONAL_TRENDS
COMMENT = 'National mine safety trends by year and coal vs metal/nonmetal. Rates per 200,000 hours.'
AS
WITH last_q AS (SELECT MAX(quarter_start) AS q FROM DOL_MSHA_DEMO.TRANSFORMED.MINE_QUARTER_FACT),
mine_side AS (
    SELECT year, coal_metal,
           SUM(injuries) inj, SUM(lost_time_injuries) lt, SUM(fatalities) fat, SUM(contractor_injuries) cinj,
           SUM(days_lost) dl, SUM(ignition_explosion_fire_events) ign,
           SUM(operator_hours) hrs, SUM(inspections) insp, SUM(inspection_hours) insph,
           SUM(violations) v, SUM(ss_violations) ss, SUM(ventilation_methane_violations) vent,
           SUM(unwarrantable_failure_actions) uf, SUM(imminent_danger_orders) idn,
           SUM(proposed_penalties) pen, COUNT(DISTINCT IFF(has_hours, mine_id, NULL)) mines_hrs,
           COUNT(DISTINCT IFF(has_hours, quarter, NULL)) q_with_hours
    FROM DOL_MSHA_DEMO.TRANSFORMED.MINE_QUARTER_FACT
    GROUP BY GROUPING SETS ((year, coal_metal), (year))
),
contractor AS (
    SELECT year, DECODE(commodity_type, 'C', 'Coal', 'M', 'Metal/Nonmetal') coal_metal, SUM(hours_worked) chrs
    FROM DOL_MSHA_DEMO.TRANSFORMED.CONTRACTOR_EMPLOYMENT_QUARTERLY, last_q
    WHERE DATE_FROM_PARTS(year, (quarter - 1) * 3 + 1, 1) BETWEEN '2010-01-01' AND last_q.q
    GROUP BY GROUPING SETS ((year, DECODE(commodity_type, 'C', 'Coal', 'M', 'Metal/Nonmetal')), (year))
)
SELECT
    m.year,
    COALESCE(m.coal_metal, 'All Mines')                                    AS mine_category,
    m.inj                                                                  AS operator_injuries,
    m.lt                                                                   AS operator_lost_time_injuries,
    m.cinj                                                                 AS contractor_injuries,
    m.inj + m.cinj                                                         AS total_injuries,
    m.fat                                                                  AS fatalities,
    m.dl                                                                   AS operator_days_lost,
    m.ign                                                                  AS ignition_explosion_fire_accidents,
    CAST(m.hrs AS NUMBER(16,0))                                            AS operator_hours_worked,
    CAST(c.chrs AS NUMBER(16,0))                                           AS contractor_hours_worked,
    m.mines_hrs                                                            AS mines_reporting_hours,
    CAST(m.inj * 200000 / NULLIF(m.hrs, 0) AS NUMBER(10,4))                AS operator_injury_rate_per_200k_hours,
    CAST(m.lt  * 200000 / NULLIF(m.hrs, 0) AS NUMBER(10,4))                AS operator_lost_time_rate_per_200k_hours,
    CAST((m.inj + m.cinj) * 200000 / NULLIF(m.hrs + COALESCE(c.chrs, 0), 0) AS NUMBER(10,4)) AS all_workers_injury_rate_per_200k_hours,
    CAST(m.fat * 200000000 / NULLIF(m.hrs + COALESCE(c.chrs, 0), 0) AS NUMBER(10,4))         AS fatality_rate_per_200m_hours,
    m.insp                                                                 AS inspections,
    CAST(m.insph AS NUMBER(14,0))                                          AS inspection_hours,
    m.v                                                                    AS violations,
    m.ss                                                                   AS significant_substantial_violations,
    CAST(DIV0NULL(m.ss, m.v) AS NUMBER(10,4))                              AS significant_substantial_rate,
    m.vent                                                                 AS ventilation_methane_violations,
    CAST(m.vent * 200000 / NULLIF(m.hrs, 0) AS NUMBER(10,4))               AS ventilation_methane_violations_per_200k_hours,
    m.uf                                                                   AS unwarrantable_failure_actions,
    m.idn                                                                  AS imminent_danger_orders,
    CAST(m.pen AS NUMBER(14,2))                                            AS proposed_penalties_usd,
    m.q_with_hours                                                         AS quarters_with_hours,
    (m.q_with_hours < 4)                                                   AS is_partial_year
FROM mine_side m
LEFT JOIN contractor c
       ON c.year = m.year AND COALESCE(c.coal_metal, 'All') = COALESCE(m.coal_metal, 'All')
WHERE m.year IS NOT NULL;

-- -----------------------------------------------------------------------------
-- STATE_TRENDS: state x year x mine category (operator basis only).
-- state_latitude/longitude = mean of valid mine coordinates (for map centroids).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW STATE_TRENDS
COMMENT = 'State mine safety trends by year and coal vs metal/nonmetal (operator injuries / operator hours).'
AS
WITH centroid AS (
    SELECT state_abbr, AVG(latitude) lat, AVG(longitude) lon
    FROM DOL_MSHA_DEMO.TRANSFORMED.MINE WHERE NOT has_geo_issue GROUP BY 1
),
s AS (
    SELECT state_abbr, year, coal_metal,
           SUM(injuries) inj, SUM(lost_time_injuries) lt, SUM(fatalities) fat,
           SUM(ignition_explosion_fire_events) ign, SUM(operator_hours) hrs,
           SUM(violations) v, SUM(ss_violations) ss, SUM(ventilation_methane_violations) vent,
           SUM(proposed_penalties) pen, COUNT(DISTINCT IFF(has_hours, mine_id, NULL)) mines,
           COUNT(DISTINCT IFF(has_hours, quarter, NULL)) qh
    FROM DOL_MSHA_DEMO.TRANSFORMED.MINE_QUARTER_FACT
    GROUP BY GROUPING SETS ((state_abbr, year, coal_metal), (state_abbr, year))
)
SELECT
    s.state_abbr                                               AS state,
    s.year,
    COALESCE(s.coal_metal, 'All Mines')                        AS mine_category,
    s.mines                                                    AS mines_reporting_hours,
    s.inj                                                      AS operator_injuries,
    s.lt                                                       AS operator_lost_time_injuries,
    s.fat                                                      AS fatalities,
    s.ign                                                      AS ignition_explosion_fire_accidents,
    CAST(s.hrs AS NUMBER(16,0))                                AS operator_hours_worked,
    CAST(s.inj * 200000 / NULLIF(s.hrs, 0) AS NUMBER(10,4))    AS operator_injury_rate_per_200k_hours,
    CAST(s.lt  * 200000 / NULLIF(s.hrs, 0) AS NUMBER(10,4))    AS operator_lost_time_rate_per_200k_hours,
    s.v                                                        AS violations,
    s.ss                                                       AS significant_substantial_violations,
    CAST(DIV0NULL(s.ss, s.v) AS NUMBER(10,4))                  AS significant_substantial_rate,
    s.vent                                                     AS ventilation_methane_violations,
    CAST(s.pen AS NUMBER(14,2))                                AS proposed_penalties_usd,
    CAST(c.lat AS NUMBER(9,6))                                 AS state_latitude,
    CAST(c.lon AS NUMBER(10,6))                                AS state_longitude,
    (s.qh < 4)                                                 AS is_partial_year
FROM s
LEFT JOIN centroid c ON c.state_abbr = s.state_abbr
WHERE s.year IS NOT NULL AND s.state_abbr IS NOT NULL;

-- -----------------------------------------------------------------------------
-- ACCIDENT_DETAIL: one row per accident record (one person per accident event).
-- narrative = verbatim portal text; Cortex Search source in Phase 5.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW ACCIDENT_DETAIL
COMMENT = 'One row per person involved in a reportable MSHA accident, with labels and the verbatim narrative.'
AS
SELECT
    a.document_no                         AS accident_document_number,
    a.mine_id,
    m.mine_name,
    m.state_abbr                          AS state,
    m.county_name,
    m.coal_metal                          AS mine_category,
    m.mine_type,
    a.operator_name,
    a.controller_name,
    a.accident_date,
    a.accident_year,
    a.accident_quarter,
    a.accident_time,
    a.degree_label                        AS degree_of_injury,
    a.is_fatal,
    a.is_lost_time                        AS is_lost_time_injury,
    a.is_reportable_injury,
    a.is_contractor                       AS is_contractor_employee,
    ct.contractor_name,
    a.classification                      AS accident_classification,
    a.accident_type,
    a.injury_source,
    a.nature_of_injury,
    a.body_part                           AS body_part_injured,
    a.mining_equipment,
    a.equipment_manufacturer,
    a.occupation,
    a.activity                            AS activity_at_time_of_accident,
    a.subunit_desc                        AS mine_subunit,
    a.ug_location                         AS underground_location,
    a.ug_mining_method                    AS underground_mining_method,
    a.experience_total_years              AS total_mining_experience_years,
    a.experience_mine_years               AS experience_at_this_mine_years,
    a.experience_job_years                AS experience_in_job_years,
    a.days_lost,
    a.days_restricted,
    a.is_ignition_explosion_fire,
    a.event_no_injuries                   AS persons_injured_in_event,  -- event-level; do not SUM
    a.narrative,
    m.latitude,
    m.longitude
FROM DOL_MSHA_DEMO.TRANSFORMED.ACCIDENT a
LEFT JOIN DOL_MSHA_DEMO.TRANSFORMED.MINE m        ON m.mine_id = a.mine_id
LEFT JOIN DOL_MSHA_DEMO.TRANSFORMED.CONTRACTOR ct ON ct.cntctr_id = a.cntctr_id;

-- -----------------------------------------------------------------------------
-- VIOLATION_DETAIL: one row per violation with hazard label and penalty.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VIOLATION_DETAIL
COMMENT = 'One row per MSHA citation/order with hazard category (compliance proxy), gravity, negligence and penalty.'
AS
SELECT
    v.viol_no                             AS violation_number,
    v.event_no                            AS inspection_event_number,
    v.mine_id,
    m.mine_name,
    m.state_abbr                          AS state,
    m.coal_metal                          AS mine_category,
    m.mine_type,
    v.violator_type,
    v.violator_name,
    v.issue_date,
    v.issue_year,
    v.issue_quarter,
    v.part_section                        AS cfr_part_section,
    v.cfr_part,
    h.label                               AS hazard_category,
    v.enforcement_action,
    v.citation_order_safeguard            AS citation_or_order,
    v.is_sig_sub                          AS is_significant_substantial,
    v.is_order,
    v.is_unwarrantable_failure,
    v.is_imminent_danger,
    v.likelihood,
    v.likelihood_score,
    v.injury_illness_expected,
    v.negligence,
    v.negligence_score,
    v.is_high_negligence,
    v.persons_affected,
    v.termination_date,
    v.termination_type,
    v.is_contested,
    i.activity_desc                       AS inspection_type,
    v.proposed_penalty                    AS proposed_penalty_usd,
    v.current_assessment                  AS current_assessment_usd,
    v.amount_paid                         AS amount_paid_usd,
    v.penalty_status_group                AS penalty_status,
    v.penalty_last_action
FROM DOL_MSHA_DEMO.TRANSFORMED.VIOLATION v
LEFT JOIN DOL_MSHA_DEMO.TRANSFORMED.HAZARD_CATEGORY_REF h ON h.category_code = v.hazard_category
LEFT JOIN DOL_MSHA_DEMO.TRANSFORMED.MINE m               ON m.mine_id = v.mine_id
LEFT JOIN DOL_MSHA_DEMO.TRANSFORMED.INSPECTION i         ON i.event_no = v.event_no;

-- -----------------------------------------------------------------------------
-- HAZARD_TRENDS: hazard category x year x mine category.
-- Per-200K normalization uses operator hours for the same year and category.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW HAZARD_TRENDS
COMMENT = 'Violation trends by hazard category (compliance proxies, not sensor readings) by year and coal vs metal/nonmetal.'
AS
WITH last_q AS (SELECT MAX(quarter_start) q FROM DOL_MSHA_DEMO.TRANSFORMED.MINE_QUARTER_FACT),
hrs AS (
    SELECT year, COALESCE(coal_metal, 'All Mines') mine_category, SUM(operator_hours) hrs,
           COUNT(DISTINCT IFF(has_hours, quarter, NULL)) qh
    FROM DOL_MSHA_DEMO.TRANSFORMED.MINE_QUARTER_FACT
    GROUP BY GROUPING SETS ((year, coal_metal), (year))
),
v AS (
    SELECT v.issue_year year, COALESCE(m.coal_metal, 'All Mines') mine_category, v.hazard_category,
           COUNT(*) n, COUNT_IF(v.is_sig_sub) ss, COUNT_IF(v.is_high_negligence) hn,
           COUNT_IF(v.is_unwarrantable_failure OR v.is_imminent_danger) uf_id,
           AVG(v.likelihood_score) lk, AVG(v.negligence_score) ng, SUM(v.proposed_penalty) pen
    FROM DOL_MSHA_DEMO.TRANSFORMED.VIOLATION v
    LEFT JOIN DOL_MSHA_DEMO.TRANSFORMED.MINE m ON m.mine_id = v.mine_id, last_q
    WHERE v.issue_date BETWEEN '2010-01-01' AND DATEADD(day, -1, DATEADD(quarter, 1, last_q.q))
    GROUP BY GROUPING SETS ((v.issue_year, m.coal_metal, v.hazard_category), (v.issue_year, v.hazard_category))
)
SELECT
    v.year,
    v.mine_category,
    r.label                                                    AS hazard_category,
    r.cfr_reference,
    r.sort_order                                               AS hazard_sort_order,
    v.n                                                        AS violations,
    v.ss                                                       AS significant_substantial_violations,
    CAST(DIV0NULL(v.ss, v.n) AS NUMBER(10,4))                  AS significant_substantial_rate,
    v.hn                                                       AS high_negligence_violations,
    CAST(DIV0NULL(v.hn, v.n) AS NUMBER(10,4))                  AS high_negligence_rate,
    v.uf_id                                                    AS unwarrantable_failure_or_imminent_danger_actions,
    CAST(v.lk AS NUMBER(10,4))                                 AS avg_likelihood_score,
    CAST(v.ng AS NUMBER(10,4))                                 AS avg_negligence_score,
    CAST(v.pen AS NUMBER(14,2))                                AS proposed_penalties_usd,
    CAST(v.n * 200000 / NULLIF(h.hrs, 0) AS NUMBER(10,4))      AS violations_per_200k_operator_hours,
    (h.qh < 4)                                                 AS is_partial_year
FROM v
JOIN DOL_MSHA_DEMO.TRANSFORMED.HAZARD_CATEGORY_REF r ON r.category_code = v.hazard_category
LEFT JOIN hrs h ON h.year = v.year AND h.mine_category = v.mine_category;

-- -----------------------------------------------------------------------------
-- ACCIDENT_PATTERNS: classification x injury source x year x mine category.
-- Counts persons (rows), never no_injuries.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW ACCIDENT_PATTERNS
COMMENT = 'What is hurting miners: accident counts by classification, injury source, year and coal vs metal/nonmetal.'
AS
SELECT
    a.accident_year                                   AS year,
    COALESCE(m.coal_metal, 'Unknown')                 AS mine_category,
    COALESCE(a.classification, 'Not classified')      AS accident_classification,
    COALESCE(a.injury_source, 'Not recorded')         AS injury_source,
    COUNT(*)                                          AS accident_records,
    COUNT_IF(a.is_reportable_injury)                  AS reportable_injuries,
    COUNT_IF(a.is_lost_time)                          AS lost_time_injuries,
    COUNT_IF(a.is_fatal)                              AS fatalities,
    COUNT_IF(a.is_contractor AND a.is_reportable_injury) AS contractor_injuries,
    SUM(a.days_lost)                                  AS days_lost,
    CAST(AVG(a.experience_total_years) AS NUMBER(6,2)) AS avg_total_experience_years,
    CAST(MEDIAN(a.experience_job_years) AS NUMBER(6,2)) AS median_job_experience_years
FROM DOL_MSHA_DEMO.TRANSFORMED.ACCIDENT a
LEFT JOIN DOL_MSHA_DEMO.TRANSFORMED.MINE m ON m.mine_id = a.mine_id
WHERE a.accident_year IS NOT NULL
GROUP BY 1, 2, 3, 4;

-- -----------------------------------------------------------------------------
-- MINE_QUARTER_TRENDS: mine x quarter timeline (outcomes + indicators).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW MINE_QUARTER_TRENDS
COMMENT = 'One row per mine per calendar quarter: injuries, hours, rates, inspections, violations and penalties.'
AS
SELECT
    f.mine_id,
    m.mine_name,
    f.quarter_start,
    f.year,
    f.quarter,
    f.year_quarter,
    f.coal_metal                                  AS mine_category,
    f.mine_type,
    f.state_abbr                                  AS state,
    f.injuries                                    AS operator_injuries,
    f.lost_time_injuries                          AS operator_lost_time_injuries,
    f.fatalities,
    f.contractor_injuries,
    f.days_lost                                   AS operator_days_lost,
    f.ignition_explosion_fire_events              AS ignition_explosion_fire_accidents,
    f.operator_hours                              AS operator_hours_worked,
    f.avg_employees                               AS average_employees,
    f.coal_production_tons,
    f.injury_rate                                 AS operator_injury_rate_per_200k_hours,
    f.lost_time_rate                              AS operator_lost_time_rate_per_200k_hours,
    f.inspections,
    f.regular_inspections,
    f.inspection_hours,
    f.violations,
    f.ss_violations                               AS significant_substantial_violations,
    f.ss_rate                                     AS significant_substantial_rate,
    f.orders,
    f.unwarrantable_failure_actions,
    f.imminent_danger_orders,
    f.high_negligence_violations,
    f.ventilation_methane_violations,
    f.rock_dust_violations,
    f.electrical_violations,
    f.roof_rib_violations,
    f.avg_likelihood_score,
    f.proposed_penalties                          AS proposed_penalties_usd,
    f.violations_per_inspection_hour,
    f.has_hours,
    f.is_partial_period
FROM DOL_MSHA_DEMO.TRANSFORMED.MINE_QUARTER_FACT f
LEFT JOIN DOL_MSHA_DEMO.TRANSFORMED.MINE m ON m.mine_id = f.mine_id;

-- -----------------------------------------------------------------------------
-- LEADING_INDICATORS: trailing-4-quarter features vs next-quarter outcome.
-- is_comparable = 4 prior quarters available, >= 20,000 trailing operator
-- hours (~10 FTEs), and a known next-quarter outcome. Quartile columns are
-- computed over comparable rows within mine category:
--   0 = indicator is zero; 1-4 = quartiles of the NON-ZERO values (4 = highest).
-- This keeps zero-heavy indicators (e.g. 104(d)/107(a)) from being split
-- arbitrarily across quartile boundaries.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW LEADING_INDICATORS
COMMENT = 'Leading indicators: prior 4 quarters of enforcement and injury history next to the following quarter outcome, per mine.'
AS
WITH b AS (
    SELECT f.*,
           m.mine_name,
           (f.trailing_quarters = 4 AND f.t4q_operator_hours >= 20000 AND f.next_q_injuries IS NOT NULL) AS is_comparable,
           f.t4q_104d_107a_actions * 200000 / NULLIF(f.t4q_operator_hours, 0)          AS t4q_104d_107a_per_200k,
           f.t4q_high_negligence_violations * 200000 / NULLIF(f.t4q_operator_hours, 0) AS t4q_high_neg_per_200k,
           f.t4q_inspection_hours * 200000 / NULLIF(f.t4q_operator_hours, 0)           AS t4q_insp_hours_per_200k
    FROM DOL_MSHA_DEMO.TRANSFORMED.MINE_QUARTER_FEATURES f
    LEFT JOIN DOL_MSHA_DEMO.TRANSFORMED.MINE m ON m.mine_id = f.mine_id
)
SELECT
    mine_id, mine_name, quarter_start, year, quarter, year_quarter,
    coal_metal AS mine_category, mine_type, state_abbr AS state,
    is_comparable,
    t4q_operator_hours                              AS prior_4q_operator_hours,
    t4q_violations                                  AS prior_4q_violations,
    t4q_ss_violations                               AS prior_4q_significant_substantial_violations,
    t4q_ss_rate                                     AS prior_4q_significant_substantial_rate,
    t4q_ventilation_methane_violations              AS prior_4q_ventilation_methane_violations,
    t4q_104d_107a_actions                           AS prior_4q_unwarrantable_failure_imminent_danger_actions,
    t4q_high_negligence_violations                  AS prior_4q_high_negligence_violations,
    t4q_proposed_penalties                          AS prior_4q_proposed_penalties_usd,
    t4q_inspection_hours                            AS prior_4q_inspection_hours,
    t4q_injuries                                    AS prior_4q_operator_injuries,
    t4q_injury_rate                                 AS prior_4q_injury_rate_per_200k_hours,
    t4q_violations_per_200k_hours                   AS prior_4q_violations_per_200k_hours,
    t4q_ss_per_200k_hours                           AS prior_4q_significant_substantial_per_200k_hours,
    t4q_ventilation_per_200k_hours                  AS prior_4q_ventilation_methane_per_200k_hours,
    CAST(t4q_104d_107a_per_200k AS NUMBER(14,4))    AS prior_4q_unwarrantable_imminent_per_200k_hours,
    CAST(t4q_high_neg_per_200k AS NUMBER(14,4))     AS prior_4q_high_negligence_per_200k_hours,
    CAST(t4q_insp_hours_per_200k AS NUMBER(14,4))   AS prior_4q_inspection_hours_per_200k_hours,
    next_q_operator_hours                           AS next_quarter_operator_hours,
    next_q_injuries                                 AS next_quarter_operator_injuries,
    next_q_lost_time_injuries                       AS next_quarter_lost_time_injuries,
    CAST(next_q_injuries * 200000 / NULLIF(next_q_operator_hours, 0) AS NUMBER(14,4)) AS next_quarter_injury_rate_per_200k_hours,
    had_injury_next_q                               AS had_injury_next_quarter,
    had_lost_time_next_q                            AS had_lost_time_injury_next_quarter,
    IFF(is_comparable, IFF(t4q_ss_per_200k_hours = 0, 0, NTILE(4) OVER (PARTITION BY is_comparable, coal_metal, t4q_ss_per_200k_hours > 0 ORDER BY t4q_ss_per_200k_hours)), NULL) AS significant_substantial_quartile,
    IFF(is_comparable, IFF(t4q_ventilation_per_200k_hours = 0, 0, NTILE(4) OVER (PARTITION BY is_comparable, coal_metal, t4q_ventilation_per_200k_hours > 0 ORDER BY t4q_ventilation_per_200k_hours)), NULL) AS ventilation_methane_quartile,
    IFF(is_comparable, IFF(t4q_104d_107a_per_200k = 0, 0, NTILE(4) OVER (PARTITION BY is_comparable, coal_metal, t4q_104d_107a_per_200k > 0 ORDER BY t4q_104d_107a_per_200k)), NULL) AS unwarrantable_imminent_quartile,
    IFF(is_comparable, IFF(t4q_high_neg_per_200k = 0, 0, NTILE(4) OVER (PARTITION BY is_comparable, coal_metal, t4q_high_neg_per_200k > 0 ORDER BY t4q_high_neg_per_200k)), NULL) AS high_negligence_quartile,
    IFF(is_comparable, IFF(t4q_injury_rate = 0, 0, NTILE(4) OVER (PARTITION BY is_comparable, coal_metal, t4q_injury_rate > 0 ORDER BY t4q_injury_rate)), NULL) AS prior_injury_rate_quartile,
    IFF(is_comparable, IFF(t4q_insp_hours_per_200k = 0, 0, NTILE(4) OVER (PARTITION BY is_comparable, coal_metal, t4q_insp_hours_per_200k > 0 ORDER BY t4q_insp_hours_per_200k)), NULL) AS inspection_intensity_quartile
FROM b;

-- -----------------------------------------------------------------------------
-- MINE_PROFILE: one row per mine; INPUTS for the Phase 4 early-warning card.
-- No risk score or grade here (Phase 4 owns that logic).
--   last 4 quarters ("l4q") = the 4 complete quarters before the partial
--   (latest) quarter; prior 4 ("p4q") = the 4 quarters before those.
--   Peer group = mine category + mine type + size band (avg employees, l4q).
--   Percentiles (PERCENT_RANK, 0 = lowest, 1 = highest) are computed among
--   peers with l4q operator hours > 0; NULL otherwise. Higher = worse for all
--   indicators except inspection hours.
--   trend_* = 'Up' / 'Down' / 'Flat' for l4q vs p4q (+/-10% band for rates).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW MINE_PROFILE
COMMENT = 'One row per mine: profile, last-4-quarter safety and enforcement indicators, peer percentiles and trends. Inputs only, no risk score.'
AS
WITH lq AS (SELECT MAX(quarter_start) q FROM DOL_MSHA_DEMO.TRANSFORMED.MINE_QUARTER_FACT),
agg AS (
    SELECT f.mine_id,
           SUM(f.injuries) life_inj, SUM(f.operator_hours) life_hrs,
           SUM(f.fatalities) fat_ever, SUM(IFF(f.year >= 2020, f.fatalities, 0)) fat_2020,
           MAX(IFF(f.injuries > 0 OR f.contractor_injuries > 0, f.quarter_start, NULL)) last_injury_q,
           -- last 4 complete quarters
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.injuries, 0)) l_inj,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.operator_hours, 0)) l_hrs,
           AVG(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.avg_employees, NULL)) l_emp,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.violations, 0)) l_v,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.ss_violations, 0)) l_ss,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.ventilation_methane_violations, 0)) l_vent,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.unwarrantable_failure_actions + f.imminent_danger_orders, 0)) l_ufid,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.high_negligence_violations, 0)) l_hn,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.proposed_penalties, 0)) l_pen,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-4,lq.q) AND DATEADD(quarter,-1,lq.q), f.inspection_hours, 0)) l_ih,
           -- prior 4 quarters
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-8,lq.q) AND DATEADD(quarter,-5,lq.q), f.injuries, 0)) p_inj,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-8,lq.q) AND DATEADD(quarter,-5,lq.q), f.operator_hours, 0)) p_hrs,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-8,lq.q) AND DATEADD(quarter,-5,lq.q), f.violations, 0)) p_v,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-8,lq.q) AND DATEADD(quarter,-5,lq.q), f.ss_violations, 0)) p_ss,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-8,lq.q) AND DATEADD(quarter,-5,lq.q), f.ventilation_methane_violations, 0)) p_vent,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-8,lq.q) AND DATEADD(quarter,-5,lq.q), f.unwarrantable_failure_actions + f.imminent_danger_orders, 0)) p_ufid,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-8,lq.q) AND DATEADD(quarter,-5,lq.q), f.high_negligence_violations, 0)) p_hn,
           SUM(IFF(f.quarter_start BETWEEN DATEADD(quarter,-8,lq.q) AND DATEADD(quarter,-5,lq.q), f.proposed_penalties, 0)) p_pen
    FROM DOL_MSHA_DEMO.TRANSFORMED.MINE_QUARTER_FACT f, lq
    GROUP BY f.mine_id
),
acc_dates AS (SELECT mine_id, MAX(accident_date) last_acc FROM DOL_MSHA_DEMO.TRANSFORMED.ACCIDENT GROUP BY 1),
insp_dates AS (SELECT mine_id, MAX(begin_date) last_insp FROM DOL_MSHA_DEMO.TRANSFORMED.INSPECTION GROUP BY 1),
open_bal AS (
    SELECT mine_id, SUM(GREATEST(COALESCE(current_assessment, proposed_penalty, 0) - COALESCE(amount_paid, 0), 0)) bal
    FROM DOL_MSHA_DEMO.TRANSFORMED.VIOLATION
    WHERE penalty_status_group = 'Open-Delinquent'
    GROUP BY 1
),
base AS (
    SELECT m.*,
           g.life_inj, g.life_hrs, g.fat_ever, g.fat_2020,
           g.l_inj, g.l_hrs, g.l_emp, g.l_v, g.l_ss, g.l_vent, g.l_ufid, g.l_hn, g.l_pen, g.l_ih,
           g.p_inj, g.p_hrs, g.p_v, g.p_ss, g.p_vent, g.p_ufid, g.p_hn, g.p_pen,
           g.l_inj * 200000 / NULLIF(g.l_hrs, 0) l_rate,
           g.p_inj * 200000 / NULLIF(g.p_hrs, 0) p_rate,
           DIV0NULL(g.l_ss, g.l_v) l_ssr,
           DIV0NULL(g.p_ss, g.p_v) p_ssr,
           ad.last_acc, idt.last_insp, ob.bal,
           (COALESCE(g.l_hrs, 0) > 0) active_l4q,
           CASE WHEN COALESCE(g.l_hrs, 0) = 0 THEN 'No recent hours'
                WHEN g.l_emp < 20  THEN '1-19 employees'
                WHEN g.l_emp < 100 THEN '20-99 employees'
                WHEN g.l_emp < 500 THEN '100-499 employees'
                ELSE '500+ employees' END size_band
    FROM DOL_MSHA_DEMO.TRANSFORMED.MINE m
    LEFT JOIN agg g        ON g.mine_id = m.mine_id
    LEFT JOIN acc_dates ad ON ad.mine_id = m.mine_id
    LEFT JOIN insp_dates idt ON idt.mine_id = m.mine_id
    LEFT JOIN open_bal ob  ON ob.mine_id = m.mine_id
)
SELECT
    mine_id, mine_name,
    coal_metal                                  AS mine_category,
    mine_type,
    current_status, current_status_date,
    state_abbr                                  AS state,
    county_name, district, office_name, nearest_town,
    operator_id, operator_name, controller_id, controller_name,
    primary_sic_desc                            AS primary_commodity,
    employee_count                              AS reported_employee_count,
    latitude, longitude, has_geo_issue,
    size_band,
    CAST(coal_metal || ' | ' || COALESCE(mine_type, 'Unknown') || ' | ' || size_band AS VARCHAR(80)) AS peer_group,
    COUNT(*) OVER (PARTITION BY coal_metal, mine_type, size_band, active_l4q) AS peer_group_size,
    -- lifetime (2010 onward)
    COALESCE(life_inj, 0)                                       AS injuries_since_2010,
    CAST(COALESCE(life_hrs, 0) AS NUMBER(16,0))                 AS operator_hours_since_2010,
    CAST(life_inj * 200000 / NULLIF(life_hrs, 0) AS NUMBER(10,4)) AS lifetime_injury_rate_per_200k_hours,
    COALESCE(fat_ever, 0)                                       AS fatalities_since_2010,
    COALESCE(fat_2020, 0)                                       AS fatalities_since_2020,
    last_acc                                                    AS last_accident_date,
    last_insp                                                   AS last_inspection_date,
    -- last 4 complete quarters
    active_l4q                                                  AS has_recent_hours,
    CAST(COALESCE(l_hrs, 0) AS NUMBER(16,0))                    AS last_4q_operator_hours,
    CAST(l_emp AS NUMBER(10,2))                                 AS last_4q_avg_employees,
    COALESCE(l_inj, 0)                                          AS last_4q_injuries,
    CAST(l_rate AS NUMBER(10,4))                                AS last_4q_injury_rate_per_200k_hours,
    COALESCE(l_v, 0)                                            AS last_4q_violations,
    COALESCE(l_ss, 0)                                           AS last_4q_significant_substantial_violations,
    CAST(l_ssr AS NUMBER(10,4))                                 AS last_4q_significant_substantial_rate,
    COALESCE(l_vent, 0)                                         AS last_4q_ventilation_methane_violations,
    COALESCE(l_ufid, 0)                                         AS last_4q_unwarrantable_failure_imminent_danger_actions,
    COALESCE(l_hn, 0)                                           AS last_4q_high_negligence_violations,
    CAST(COALESCE(l_pen, 0) AS NUMBER(14,2))                    AS last_4q_proposed_penalties_usd,
    CAST(COALESCE(l_ih, 0) AS NUMBER(14,2))                     AS last_4q_inspection_hours,
    CAST(COALESCE(bal, 0) AS NUMBER(14,2))                      AS open_delinquent_penalty_balance_usd,
    -- prior 4 quarters (for trend)
    CAST(p_rate AS NUMBER(10,4))                                AS prior_4q_injury_rate_per_200k_hours,
    CAST(p_ssr AS NUMBER(10,4))                                 AS prior_4q_significant_substantial_rate,
    COALESCE(p_vent, 0)                                         AS prior_4q_ventilation_methane_violations,
    COALESCE(p_ufid, 0)                                         AS prior_4q_unwarrantable_failure_imminent_danger_actions,
    COALESCE(p_hn, 0)                                           AS prior_4q_high_negligence_violations,
    CAST(COALESCE(p_pen, 0) AS NUMBER(14,2))                    AS prior_4q_proposed_penalties_usd,
    -- peer percentiles (among peers with recent hours)
    IFF(active_l4q AND l_rate IS NOT NULL, CAST(PERCENT_RANK() OVER (PARTITION BY coal_metal, mine_type, size_band, active_l4q ORDER BY l_rate) AS NUMBER(6,4)), NULL) AS injury_rate_peer_percentile,
    IFF(active_l4q AND l_ssr IS NOT NULL, CAST(PERCENT_RANK() OVER (PARTITION BY coal_metal, mine_type, size_band, active_l4q, (l_ssr IS NULL) ORDER BY l_ssr) AS NUMBER(6,4)), NULL) AS significant_substantial_rate_peer_percentile,
    IFF(active_l4q, CAST(PERCENT_RANK() OVER (PARTITION BY coal_metal, mine_type, size_band, active_l4q ORDER BY COALESCE(l_vent, 0)) AS NUMBER(6,4)), NULL) AS ventilation_methane_peer_percentile,
    IFF(active_l4q, CAST(PERCENT_RANK() OVER (PARTITION BY coal_metal, mine_type, size_band, active_l4q ORDER BY COALESCE(l_ufid, 0)) AS NUMBER(6,4)), NULL) AS unwarrantable_imminent_peer_percentile,
    IFF(active_l4q, CAST(PERCENT_RANK() OVER (PARTITION BY coal_metal, mine_type, size_band, active_l4q ORDER BY COALESCE(l_hn, 0)) AS NUMBER(6,4)), NULL) AS high_negligence_peer_percentile,
    IFF(active_l4q, CAST(PERCENT_RANK() OVER (PARTITION BY coal_metal, mine_type, size_band, active_l4q ORDER BY COALESCE(l_pen, 0)) AS NUMBER(6,4)), NULL) AS penalties_peer_percentile,
    IFF(active_l4q, CAST(PERCENT_RANK() OVER (PARTITION BY coal_metal, mine_type, size_band, active_l4q ORDER BY COALESCE(bal, 0)) AS NUMBER(6,4)), NULL) AS open_balance_peer_percentile,
    -- trend direction, last 4Q vs prior 4Q
    CASE WHEN l_rate IS NULL OR p_rate IS NULL THEN 'Insufficient data'
         WHEN l_rate > p_rate * 1.1 THEN 'Up' WHEN l_rate < p_rate * 0.9 THEN 'Down' ELSE 'Flat' END AS injury_rate_trend,
    CASE WHEN l_ssr IS NULL OR p_ssr IS NULL THEN 'Insufficient data'
         WHEN l_ssr > p_ssr * 1.1 THEN 'Up' WHEN l_ssr < p_ssr * 0.9 THEN 'Down' ELSE 'Flat' END AS significant_substantial_rate_trend,
    CASE WHEN COALESCE(l_vent,0) > COALESCE(p_vent,0) THEN 'Up' WHEN COALESCE(l_vent,0) < COALESCE(p_vent,0) THEN 'Down' ELSE 'Flat' END AS ventilation_methane_trend,
    CASE WHEN COALESCE(l_ufid,0) > COALESCE(p_ufid,0) THEN 'Up' WHEN COALESCE(l_ufid,0) < COALESCE(p_ufid,0) THEN 'Down' ELSE 'Flat' END AS unwarrantable_imminent_trend,
    CASE WHEN COALESCE(l_hn,0) > COALESCE(p_hn,0) THEN 'Up' WHEN COALESCE(l_hn,0) < COALESCE(p_hn,0) THEN 'Down' ELSE 'Flat' END AS high_negligence_trend,
    CASE WHEN COALESCE(l_pen,0) > COALESCE(p_pen,0) * 1.1 THEN 'Up' WHEN COALESCE(l_pen,0) < COALESCE(p_pen,0) * 0.9 THEN 'Down' ELSE 'Flat' END AS penalties_trend
FROM base;

-- -----------------------------------------------------------------------------
-- OPERATOR_PORTFOLIO: one row per CURRENT operator (with current controller).
-- Built on MINE_PROFILE so the windows match.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW OPERATOR_PORTFOLIO
COMMENT = 'One row per current mine operator (and its controller): mines, recent injuries and rate, fatalities, enforcement and open penalties.'
AS
SELECT
    operator_id,
    ANY_VALUE(operator_name)                                         AS operator_name,
    ANY_VALUE(controller_id)                                         AS controller_id,
    ANY_VALUE(controller_name)                                       AS controller_name,
    COUNT(*)                                                         AS mines,
    COUNT_IF(has_recent_hours)                                       AS mines_with_recent_hours,
    COUNT_IF(current_status = 'Active')                              AS active_mines,
    LISTAGG(DISTINCT state, ', ') WITHIN GROUP (ORDER BY state)      AS states,
    LISTAGG(DISTINCT mine_category, ', ')                            AS mine_categories,
    SUM(last_4q_operator_hours)                                      AS last_4q_operator_hours,
    SUM(last_4q_injuries)                                            AS last_4q_injuries,
    CAST(SUM(last_4q_injuries) * 200000 / NULLIF(SUM(last_4q_operator_hours), 0) AS NUMBER(10,4)) AS last_4q_injury_rate_per_200k_hours,
    SUM(fatalities_since_2020)                                       AS fatalities_since_2020,
    SUM(fatalities_since_2010)                                       AS fatalities_since_2010,
    SUM(last_4q_violations)                                          AS last_4q_violations,
    SUM(last_4q_significant_substantial_violations)                  AS last_4q_significant_substantial_violations,
    CAST(DIV0NULL(SUM(last_4q_significant_substantial_violations), SUM(last_4q_violations)) AS NUMBER(10,4)) AS last_4q_significant_substantial_rate,
    SUM(last_4q_ventilation_methane_violations)                      AS last_4q_ventilation_methane_violations,
    SUM(last_4q_unwarrantable_failure_imminent_danger_actions)       AS last_4q_unwarrantable_failure_imminent_danger_actions,
    SUM(last_4q_high_negligence_violations)                          AS last_4q_high_negligence_violations,
    SUM(last_4q_proposed_penalties_usd)                              AS last_4q_proposed_penalties_usd,
    SUM(open_delinquent_penalty_balance_usd)                         AS open_delinquent_penalty_balance_usd
FROM MINE_PROFILE
WHERE operator_id IS NOT NULL
GROUP BY operator_id;
