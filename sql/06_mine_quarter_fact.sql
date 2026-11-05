-- =============================================================================
-- 06_mine_quarter_fact.sql
-- DOL MSHA Demo - Phase 2: mine x quarter fact + leading-indicator features.
--
-- Depends on: 05_transformed_tables.sql
--
-- SPINE LOGIC
--   * Calendar quarters from 2010 Q1 through the LATEST quarter that has
--     operator hours (EMPLOYMENT_QUARTERLY). Accidents/violations after that
--     quarter are excluded here because no rate can be computed for them.
--   * A mine enters the spine at its FIRST quarter with hours, an accident, or
--     an inspection (2010+), and stays in it through the latest quarter.
--     Every quarter in between gets a row even with no activity, so the spine
--     is gap-free per mine. That is what lets ROWS BETWEEN 4 PRECEDING AND
--     1 PRECEDING mean "the prior four calendar quarters".
--
-- RATE BASIS (mine level)
--   * Mine rates use OPERATOR hours and OPERATOR-employee injuries only
--     (contractor hours carry no mine_id). Contractor injuries are counted
--     separately and are NOT in the mine rate.
--   * Rates are per 200,000 hours (100 full-time workers x 1 year); NULL when
--     hours = 0 or missing. Never compute a rate for a period without hours.
--   * injury_rate   = reportable injuries (degree 01-06) * 200000 / hours
--   * lost_time_rate = NFDL injuries (degree 02-05)       * 200000 / hours
--
-- ENFORCEMENT ATTRIBUTION
--   * Violations by issue_date quarter; all violator types at the mine
--     (operator and contractor citations both describe conditions at the mine).
--   * Inspections by begin_date quarter.
--   * Proposed penalties by the violation's issue quarter (assessment lags, so
--     the most recent quarters are understated).
--
-- is_partial_period = the latest hours quarter itself. Hours are reported late,
--   so the newest quarter is typically under-reported. Exclude it from trends.
-- =============================================================================

USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE DATABASE DOL_MSHA_DEMO;
USE SCHEMA TRANSFORMED;

CREATE OR REPLACE TABLE MINE_QUARTER_FACT AS
WITH bounds AS (
    SELECT DATE '2010-01-01' AS first_q,
           MAX(DATE_FROM_PARTS(year, (quarter - 1) * 3 + 1, 1)) AS last_q
    FROM EMPLOYMENT_QUARTERLY
    WHERE hours_worked > 0
),
quarters AS (
    SELECT DATEADD(quarter, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, b.first_q) AS quarter_start
    FROM TABLE(GENERATOR(ROWCOUNT => 200)), bounds b
    QUALIFY quarter_start <= (SELECT last_q FROM bounds)
),
hours AS (
    SELECT mine_id,
           DATE_FROM_PARTS(year, (quarter - 1) * 3 + 1, 1) AS quarter_start,
           SUM(hours_worked)         AS operator_hours,
           SUM(avg_employees)        AS avg_employees,
           SUM(coal_production_tons) AS coal_production_tons
    FROM EMPLOYMENT_QUARTERLY
    WHERE year >= 2010
    GROUP BY 1, 2
),
acc AS (
    SELECT mine_id,
           DATE_TRUNC(quarter, accident_date) AS quarter_start,
           COUNT_IF(is_reportable_injury AND NOT is_contractor) AS injuries,
           COUNT_IF(is_lost_time        AND NOT is_contractor) AS lost_time_injuries,
           COUNT_IF(is_fatal)                                  AS fatalities,          -- operator + contractor
           COUNT_IF(is_fatal            AND NOT is_contractor) AS operator_fatalities,
           SUM(IFF(NOT is_contractor, days_lost, 0))           AS days_lost,
           COUNT_IF(is_ignition_explosion_fire)                AS ignition_explosion_fire_events,
           COUNT_IF(is_reportable_injury AND is_contractor)    AS contractor_injuries,
           COUNT(*)                                            AS accident_records
    FROM ACCIDENT
    WHERE accident_date IS NOT NULL
    GROUP BY 1, 2
),
insp AS (
    SELECT mine_id,
           DATE_TRUNC(quarter, begin_date) AS quarter_start,
           COUNT(*)                        AS inspections,
           COUNT_IF(is_regular_inspection) AS regular_inspections,
           SUM(total_insp_hours)           AS inspection_hours
    FROM INSPECTION
    WHERE begin_date IS NOT NULL
    GROUP BY 1, 2
),
viol AS (
    SELECT mine_id,
           DATE_TRUNC(quarter, issue_date)              AS quarter_start,
           COUNT(*)                                     AS violations,
           COUNT_IF(is_sig_sub)                         AS ss_violations,
           COUNT_IF(is_order)                           AS orders,
           COUNT_IF(is_unwarrantable_failure)           AS unwarrantable_failure_actions,
           COUNT_IF(is_imminent_danger)                 AS imminent_danger_orders,
           COUNT_IF(is_high_negligence)                 AS high_negligence_violations,
           COUNT_IF(hazard_category = 'VENT_METHANE')   AS ventilation_methane_violations,
           COUNT_IF(hazard_category = 'COMBUST_ROCKDUST') AS rock_dust_violations,
           COUNT_IF(hazard_category = 'ELECTRICAL')     AS electrical_violations,
           COUNT_IF(hazard_category = 'ROOF_RIB')       AS roof_rib_violations,
           AVG(likelihood_score)                        AS avg_likelihood_score,
           SUM(proposed_penalty)                        AS proposed_penalties
    FROM VIOLATION
    WHERE issue_date IS NOT NULL
    GROUP BY 1, 2
),
mine_start AS (
    SELECT mine_id, MIN(quarter_start) AS first_q
    FROM (SELECT mine_id, quarter_start FROM hours WHERE operator_hours > 0
          UNION ALL SELECT mine_id, quarter_start FROM acc
          UNION ALL SELECT mine_id, quarter_start FROM insp)
    WHERE quarter_start >= DATE '2010-01-01'
      AND quarter_start <= (SELECT last_q FROM bounds)
    GROUP BY 1
),
spine AS (
    SELECT s.mine_id, q.quarter_start
    FROM mine_start s
    JOIN quarters q ON q.quarter_start >= s.first_q
)
SELECT
    sp.mine_id,
    sp.quarter_start,
    YEAR(sp.quarter_start)                                       AS year,
    QUARTER(sp.quarter_start)                                    AS quarter,
    CAST(YEAR(sp.quarter_start) || '-Q' || QUARTER(sp.quarter_start) AS VARCHAR(7)) AS year_quarter,
    m.coal_metal,
    m.mine_type,
    m.state_abbr,
    -- outcomes
    COALESCE(a.injuries, 0)                       AS injuries,
    COALESCE(a.lost_time_injuries, 0)             AS lost_time_injuries,
    COALESCE(a.fatalities, 0)                     AS fatalities,
    COALESCE(a.operator_fatalities, 0)            AS operator_fatalities,
    COALESCE(a.days_lost, 0)                      AS days_lost,
    COALESCE(a.ignition_explosion_fire_events, 0) AS ignition_explosion_fire_events,
    COALESCE(a.contractor_injuries, 0)            AS contractor_injuries,
    -- exposure
    COALESCE(h.operator_hours, 0)                 AS operator_hours,
    h.avg_employees,
    h.coal_production_tons,
    (COALESCE(h.operator_hours, 0) > 0)           AS has_hours,
    -- rates per 200K operator hours
    CAST(IFF(h.operator_hours > 0, COALESCE(a.injuries, 0) * 200000 / h.operator_hours, NULL) AS NUMBER(10,4)) AS injury_rate,
    CAST(IFF(h.operator_hours > 0, COALESCE(a.lost_time_injuries, 0) * 200000 / h.operator_hours, NULL) AS NUMBER(10,4)) AS lost_time_rate,
    -- enforcement activity
    COALESCE(i.inspections, 0)                    AS inspections,
    COALESCE(i.regular_inspections, 0)            AS regular_inspections,
    COALESCE(i.inspection_hours, 0)               AS inspection_hours,
    COALESCE(v.violations, 0)                     AS violations,
    COALESCE(v.ss_violations, 0)                  AS ss_violations,
    COALESCE(v.orders, 0)                         AS orders,
    COALESCE(v.unwarrantable_failure_actions, 0)  AS unwarrantable_failure_actions,
    COALESCE(v.imminent_danger_orders, 0)         AS imminent_danger_orders,
    COALESCE(v.high_negligence_violations, 0)     AS high_negligence_violations,
    COALESCE(v.ventilation_methane_violations, 0) AS ventilation_methane_violations,
    COALESCE(v.rock_dust_violations, 0)           AS rock_dust_violations,
    COALESCE(v.electrical_violations, 0)          AS electrical_violations,
    COALESCE(v.roof_rib_violations, 0)            AS roof_rib_violations,
    CAST(v.avg_likelihood_score AS NUMBER(10,4))  AS avg_likelihood_score,
    CAST(COALESCE(v.proposed_penalties, 0) AS NUMBER(14,2)) AS proposed_penalties,
    -- normalized indicators
    CAST(DIV0NULL(v.ss_violations, v.violations) AS NUMBER(10,4))                      AS ss_rate,
    CAST(IFF(i.inspection_hours > 0, COALESCE(v.violations, 0) / i.inspection_hours, NULL) AS NUMBER(10,4)) AS violations_per_inspection_hour,
    CAST(IFF(h.operator_hours > 0, COALESCE(v.ventilation_methane_violations, 0) * 200000 / h.operator_hours, NULL) AS NUMBER(10,4)) AS ventilation_violations_per_200k_hours,
    (sp.quarter_start = (SELECT last_q FROM bounds))  AS is_partial_period
FROM spine sp
LEFT JOIN MINE m  ON m.mine_id = sp.mine_id
LEFT JOIN hours h ON h.mine_id = sp.mine_id AND h.quarter_start = sp.quarter_start
LEFT JOIN acc a   ON a.mine_id = sp.mine_id AND a.quarter_start = sp.quarter_start
LEFT JOIN insp i  ON i.mine_id = sp.mine_id AND i.quarter_start = sp.quarter_start
LEFT JOIN viol v  ON v.mine_id = sp.mine_id AND v.quarter_start = sp.quarter_start;

-- =============================================================================
-- MINE_QUARTER_FEATURES: leading indicators for the same grain.
--
-- LEAKAGE RULE: every trailing feature for quarter Q uses ONLY quarters
-- Q-4 .. Q-1 (ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING). Quarter Q itself is
-- excluded, so features are known before the outcome window opens. The
-- outcome columns describe quarter Q+1 (LEAD 1). Because the spine is
-- gap-free, row offsets equal calendar-quarter offsets.
--
-- trailing_quarters = how many prior quarters were available (0-4); use rows
-- with trailing_quarters = 4 for clean comparisons.
-- Per-200K feature columns are NUMBER(14,4), not (10,4): mine-quarters with a
-- handful of hours yield rates above 1,000,000. Apply a minimum-hours filter
-- (e.g. t4q_operator_hours >= 20,000) before comparing rates.
-- Next-quarter outcomes are NULL when Q+1 is outside the spine, has no hours,
-- or is the partial period.
-- =============================================================================
CREATE OR REPLACE TABLE MINE_QUARTER_FEATURES AS
WITH f AS (
    SELECT
        mqf.*,
        COUNT(*)               OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS trailing_quarters,
        SUM(violations)        OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_violations,
        SUM(ss_violations)     OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_ss_violations,
        SUM(ventilation_methane_violations) OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_ventilation_methane_violations,
        SUM(unwarrantable_failure_actions + imminent_danger_orders) OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_104d_107a_actions,
        SUM(high_negligence_violations) OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_high_negligence_violations,
        SUM(proposed_penalties) OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_proposed_penalties,
        SUM(inspection_hours)  OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_inspection_hours,
        SUM(injuries)          OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_injuries,
        SUM(lost_time_injuries) OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_lost_time_injuries,
        SUM(operator_hours)    OVER (PARTITION BY mine_id ORDER BY quarter_start ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING) AS t4q_operator_hours,
        LEAD(injuries)           OVER (PARTITION BY mine_id ORDER BY quarter_start) AS next_q_injuries_raw,
        LEAD(lost_time_injuries) OVER (PARTITION BY mine_id ORDER BY quarter_start) AS next_q_lost_time_raw,
        LEAD(operator_hours)     OVER (PARTITION BY mine_id ORDER BY quarter_start) AS next_q_hours_raw,
        LEAD(is_partial_period)  OVER (PARTITION BY mine_id ORDER BY quarter_start) AS next_q_is_partial
    FROM MINE_QUARTER_FACT mqf
)
SELECT
    mine_id, quarter_start, year, quarter, year_quarter, coal_metal, mine_type, state_abbr,
    -- current-quarter context (not features; for reference only)
    injuries, operator_hours, has_hours, is_partial_period,
    -- trailing 4-quarter features (prior quarters only)
    trailing_quarters,
    COALESCE(t4q_violations, 0)                     AS t4q_violations,
    COALESCE(t4q_ss_violations, 0)                  AS t4q_ss_violations,
    CAST(DIV0NULL(t4q_ss_violations, t4q_violations) AS NUMBER(10,4)) AS t4q_ss_rate,
    COALESCE(t4q_ventilation_methane_violations, 0) AS t4q_ventilation_methane_violations,
    COALESCE(t4q_104d_107a_actions, 0)              AS t4q_104d_107a_actions,
    COALESCE(t4q_high_negligence_violations, 0)     AS t4q_high_negligence_violations,
    CAST(COALESCE(t4q_proposed_penalties, 0) AS NUMBER(14,2)) AS t4q_proposed_penalties,
    COALESCE(t4q_inspection_hours, 0)               AS t4q_inspection_hours,
    COALESCE(t4q_injuries, 0)                       AS t4q_injuries,
    COALESCE(t4q_operator_hours, 0)                 AS t4q_operator_hours,
    CAST(IFF(t4q_operator_hours > 0, t4q_injuries * 200000 / t4q_operator_hours, NULL) AS NUMBER(14,4)) AS t4q_injury_rate,
    CAST(IFF(t4q_operator_hours > 0, t4q_violations * 200000 / t4q_operator_hours, NULL) AS NUMBER(14,4)) AS t4q_violations_per_200k_hours,
    CAST(IFF(t4q_operator_hours > 0, t4q_ss_violations * 200000 / t4q_operator_hours, NULL) AS NUMBER(14,4)) AS t4q_ss_per_200k_hours,
    CAST(IFF(t4q_operator_hours > 0, t4q_ventilation_methane_violations * 200000 / t4q_operator_hours, NULL) AS NUMBER(14,4)) AS t4q_ventilation_per_200k_hours,
    -- next-quarter outcomes
    IFF(next_q_hours_raw > 0 AND NOT next_q_is_partial, next_q_hours_raw, NULL)     AS next_q_operator_hours,
    IFF(next_q_hours_raw > 0 AND NOT next_q_is_partial, next_q_injuries_raw, NULL)  AS next_q_injuries,
    IFF(next_q_hours_raw > 0 AND NOT next_q_is_partial, next_q_lost_time_raw, NULL) AS next_q_lost_time_injuries,
    IFF(next_q_hours_raw > 0 AND NOT next_q_is_partial, next_q_injuries_raw > 0, NULL)  AS had_injury_next_q,
    IFF(next_q_hours_raw > 0 AND NOT next_q_is_partial, next_q_lost_time_raw > 0, NULL) AS had_lost_time_next_q
FROM f;
