-- =============================================================================
-- 08_eda_queries.sql
-- DOL MSHA Demo - Phase 2: validation + exploratory findings.
-- Each query is labelled [V#] validation or [F#] finding. Read-only.
-- Reminder: hazard categories are compliance proxies; the portal has no
-- methane, temperature or sensor readings.
-- =============================================================================

USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE DATABASE DOL_MSHA_DEMO;

-- [V1] RAW vs TRANSFORMED row counts (rows_removed should be 0 except dedup)
SELECT 'MINE' t, (SELECT COUNT(*) FROM RAW.MSHA_MINES) raw_rows, (SELECT COUNT(*) FROM TRANSFORMED.MINE) xf_rows
UNION ALL SELECT 'ACCIDENT', (SELECT COUNT(*) FROM RAW.MSHA_ACCIDENT), (SELECT COUNT(*) FROM TRANSFORMED.ACCIDENT)
UNION ALL SELECT 'INSPECTION', (SELECT COUNT(*) FROM RAW.MSHA_INSPECTION), (SELECT COUNT(*) FROM TRANSFORMED.INSPECTION)
UNION ALL SELECT 'VIOLATION', (SELECT COUNT(*) FROM RAW.MSHA_VIOLATION), (SELECT COUNT(*) FROM TRANSFORMED.VIOLATION)
UNION ALL SELECT 'EMPLOYMENT_QUARTERLY', (SELECT COUNT(*) FROM RAW.MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY), (SELECT COUNT(*) FROM TRANSFORMED.EMPLOYMENT_QUARTERLY)
UNION ALL SELECT 'EMPLOYMENT_ANNUAL', (SELECT COUNT(*) FROM RAW.MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_ANNUAL), (SELECT COUNT(*) FROM TRANSFORMED.EMPLOYMENT_ANNUAL)
UNION ALL SELECT 'CONTRACTOR_EMPLOYMENT_QUARTERLY (dedup)', (SELECT COUNT(*) FROM RAW.MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_QUARTERLY), (SELECT COUNT(*) FROM TRANSFORMED.CONTRACTOR_EMPLOYMENT_QUARTERLY)
UNION ALL SELECT 'OPERATOR_HISTORY', (SELECT COUNT(*) FROM RAW.MSHA_OPERATOR_HISTORY_AT_MINES), (SELECT COUNT(*) FROM TRANSFORMED.OPERATOR_HISTORY)
UNION ALL SELECT 'CONTRACTOR_HISTORY', (SELECT COUNT(*) FROM RAW.MSHA_CONTRACTOR_HISTORY_AT_MINES), (SELECT COUNT(*) FROM TRANSFORMED.CONTRACTOR_HISTORY)
UNION ALL SELECT 'CONTROLLER_HISTORY', (SELECT COUNT(*) FROM RAW.MSHA_CONTROLLER_HISTORY), (SELECT COUNT(*) FROM TRANSFORMED.CONTROLLER_HISTORY)
UNION ALL SELECT 'COMMODITY', (SELECT COUNT(*) FROM RAW.MSHA_COMMODITY_LOOKUP), (SELECT COUNT(*) FROM TRANSFORMED.COMMODITY)
UNION ALL SELECT 'CONTRACTOR', (SELECT COUNT(*) FROM RAW.MSHA_CONTRACTOR_NAME_ID_LOOKUP), (SELECT COUNT(*) FROM TRANSFORMED.CONTRACTOR);

-- [V2] Conversion failures: source populated (after null-marker cleanup) but typed value NULL
SELECT 'accident.accident_date' col, COUNT_IF(TRANSFORMED.CLEAN_STR(r.ai_dt) IS NOT NULL AND t.accident_date IS NULL) failures FROM RAW.MSHA_ACCIDENT r JOIN TRANSFORMED.ACCIDENT t ON t.document_no = r.document_no
UNION ALL SELECT 'accident.accident_time (excl 99xx sentinels)', COUNT_IF(TRANSFORMED.CLEAN_STR(r.accident_time) < '9900' AND t.accident_time IS NULL) FROM RAW.MSHA_ACCIDENT r JOIN TRANSFORMED.ACCIDENT t ON t.document_no = r.document_no
UNION ALL SELECT 'accident.days_lost', COUNT_IF(TRANSFORMED.CLEAN_STR(r.days_lost) IS NOT NULL AND t.days_lost IS NULL) FROM RAW.MSHA_ACCIDENT r JOIN TRANSFORMED.ACCIDENT t ON t.document_no = r.document_no
UNION ALL SELECT 'accident.experience_total_years', COUNT_IF(TRANSFORMED.CLEAN_STR(r.exper_tot_calc) IS NOT NULL AND t.experience_total_years IS NULL) FROM RAW.MSHA_ACCIDENT r JOIN TRANSFORMED.ACCIDENT t ON t.document_no = r.document_no
UNION ALL SELECT 'accident.degree (unmapped code)', COUNT_IF(t.degree_label IS NULL) FROM TRANSFORMED.ACCIDENT t
UNION ALL SELECT 'inspection.begin_date', COUNT_IF(TRANSFORMED.CLEAN_STR(r.beg_dt) IS NOT NULL AND t.begin_date IS NULL) FROM RAW.MSHA_INSPECTION r JOIN TRANSFORMED.INSPECTION t ON t.event_no = r.event_no
UNION ALL SELECT 'inspection.total_insp_hours', COUNT_IF(TRANSFORMED.CLEAN_STR(r.total_insp_hours) IS NOT NULL AND t.total_insp_hours IS NULL) FROM RAW.MSHA_INSPECTION r JOIN TRANSFORMED.INSPECTION t ON t.event_no = r.event_no
UNION ALL SELECT 'violation.issue_date', COUNT_IF(TRANSFORMED.CLEAN_STR(r.iss_dt) IS NOT NULL AND t.issue_date IS NULL) FROM RAW.MSHA_VIOLATION r JOIN TRANSFORMED.VIOLATION t ON t.viol_no = r.viol_no
UNION ALL SELECT 'violation.termination_date', COUNT_IF(TRANSFORMED.CLEAN_STR(r.term_dt) IS NOT NULL AND t.termination_date IS NULL) FROM RAW.MSHA_VIOLATION r JOIN TRANSFORMED.VIOLATION t ON t.viol_no = r.viol_no
UNION ALL SELECT 'violation.likelihood_score (unmapped)', COUNT_IF(t.likelihood IS NOT NULL AND t.likelihood_score IS NULL) FROM TRANSFORMED.VIOLATION t
UNION ALL SELECT 'violation.negligence_score (unmapped)', COUNT_IF(t.negligence IS NOT NULL AND t.negligence_score IS NULL) FROM TRANSFORMED.VIOLATION t
UNION ALL SELECT 'assessed.proposed_penalty', COUNT_IF(TRANSFORMED.CLEAN_STR(proposed_penalty_amt) IS NOT NULL AND TRANSFORMED.CLEAN_NUM(proposed_penalty_amt) IS NULL) FROM RAW.MSHA_ASSESSED_VIOLATIONS
UNION ALL SELECT 'employment_q.hours_worked', COUNT_IF(TRANSFORMED.CLEAN_STR(r.empl_hrs) IS NOT NULL AND TRANSFORMED.CLEAN_NUM(r.empl_hrs) IS NULL) FROM RAW.MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY r
UNION ALL SELECT 'mine.latitude', COUNT_IF(TRANSFORMED.CLEAN_STR(r.latitude) IS NOT NULL AND TRANSFORMED.CLEAN_NUM(r.latitude) IS NULL) FROM RAW.MSHA_MINES r;

-- [V3] Date ranges and flagged rows
SELECT 'accident_date' col, MIN(accident_date)::varchar mn, MAX(accident_date)::varchar mx, COUNT_IF(accident_date IS NULL) nulls FROM TRANSFORMED.ACCIDENT
UNION ALL SELECT 'inspection.begin_date', MIN(begin_date), MAX(begin_date), COUNT_IF(begin_date IS NULL) FROM TRANSFORMED.INSPECTION
UNION ALL SELECT 'inspection end < begin', NULL, NULL, COUNT_IF(end_date < begin_date) FROM TRANSFORMED.INSPECTION
UNION ALL SELECT 'violation.issue_date', MIN(issue_date), MAX(issue_date), COUNT_IF(issue_date IS NULL) FROM TRANSFORMED.VIOLATION
UNION ALL SELECT 'violation term < issue', NULL, NULL, COUNT_IF(termination_date < issue_date) FROM TRANSFORMED.VIOLATION
UNION ALL SELECT 'accident.accident_time sentinel/NULL', NULL, NULL, COUNT_IF(accident_time IS NULL) FROM TRANSFORMED.ACCIDENT
UNION ALL SELECT 'accident.days_lost NULL', NULL, NULL, COUNT_IF(days_lost IS NULL) FROM TRANSFORMED.ACCIDENT
UNION ALL SELECT 'mine.has_geo_issue', NULL, NULL, COUNT_IF(has_geo_issue) FROM TRANSFORMED.MINE
UNION ALL SELECT 'mine.has_geo_issue (coords present)', NULL, NULL, COUNT_IF(has_geo_issue AND latitude IS NOT NULL) FROM TRANSFORMED.MINE
UNION ALL SELECT 'mine geo issue among mines w/ 2024 hours', NULL, NULL, COUNT_IF(m.has_geo_issue) FROM TRANSFORMED.MINE m WHERE m.mine_id IN (SELECT mine_id FROM TRANSFORMED.EMPLOYMENT_QUARTERLY WHERE year = 2024 AND hours_worked > 0);

-- [V4] Mine coverage
SELECT 'accident' src, ROUND(100 * COUNT_IF(m.mine_id IS NOT NULL) / COUNT(*), 2) pct_in_mine FROM TRANSFORMED.ACCIDENT a LEFT JOIN TRANSFORMED.MINE m USING (mine_id)
UNION ALL SELECT 'violation', ROUND(100 * COUNT_IF(m.mine_id IS NOT NULL) / COUNT(*), 2) FROM TRANSFORMED.VIOLATION v LEFT JOIN TRANSFORMED.MINE m USING (mine_id)
UNION ALL SELECT 'inspection', ROUND(100 * COUNT_IF(m.mine_id IS NOT NULL) / COUNT(*), 2) FROM TRANSFORMED.INSPECTION i LEFT JOIN TRANSFORMED.MINE m USING (mine_id)
UNION ALL SELECT 'mine-quarters with hours', ROUND(100 * COUNT_IF(has_hours) / COUNT(*), 2) FROM TRANSFORMED.MINE_QUARTER_FACT
UNION ALL SELECT 'operator injuries in mine-quarters WITHOUT hours (pct)', ROUND(100 * SUM(IFF(NOT has_hours, injuries, 0)) / SUM(injuries), 2) FROM TRANSFORMED.MINE_QUARTER_FACT;

-- [V5] Hours reconciliation: quarterly vs annual
SELECT q.year, ROUND(q.hrs / 1e6, 1) quarterly_m, ROUND(a.hrs / 1e6, 1) annual_m, ROUND(100 * (q.hrs - a.hrs) / a.hrs, 2) pct_diff
FROM (SELECT year, SUM(hours_worked) hrs FROM TRANSFORMED.EMPLOYMENT_QUARTERLY WHERE year >= 2010 GROUP BY 1) q
LEFT JOIN (SELECT year, SUM(hours_worked) hrs FROM TRANSFORMED.EMPLOYMENT_ANNUAL WHERE year >= 2010 GROUP BY 1) a USING (year)
ORDER BY 1;

-- [V6] Penalty join coverage by year (assessment lags, so recent years drop)
SELECT issue_year, COUNT(*) violations,
       ROUND(100 * COUNT_IF(penalty_status_group <> 'Not Assessed') / COUNT(*), 2) pct_assessed
FROM TRANSFORMED.VIOLATION GROUP BY 1 ORDER BY 1;

-- [V7] Methane liberation and gas category: are they usable?
SELECT 'methane_liberation > 0' k, COUNT_IF(methane_liberation > 0) n, ROUND(100 * COUNT_IF(methane_liberation > 0) / COUNT(*), 2) pct FROM TRANSFORMED.MINE
UNION ALL SELECT 'methane_liberation = 0', COUNT_IF(methane_liberation = 0), ROUND(100 * COUNT_IF(methane_liberation = 0) / COUNT(*), 2) FROM TRANSFORMED.MINE
UNION ALL SELECT 'gas category populated', COUNT_IF(mine_gas_category_cd IS NOT NULL), ROUND(100 * COUNT_IF(mine_gas_category_cd IS NOT NULL) / COUNT(*), 2) FROM TRANSFORMED.MINE
UNION ALL SELECT 'active UG coal mines', COUNT(*), NULL FROM TRANSFORMED.MINE WHERE coal_metal = 'Coal' AND mine_type = 'Underground' AND current_status = 'Active'
UNION ALL SELECT 'active UG coal w/ methane_liberation > 0', COUNT_IF(methane_liberation > 0), ROUND(100 * COUNT_IF(methane_liberation > 0) / COUNT(*), 2) FROM TRANSFORMED.MINE WHERE coal_metal = 'Coal' AND mine_type = 'Underground' AND current_status = 'Active';

SELECT coal_metal, mine_type, current_status, COUNT(*) n, MIN(methane_liberation) mn, MEDIAN(methane_liberation) med, MAX(methane_liberation) mx
FROM TRANSFORMED.MINE WHERE methane_liberation > 0 GROUP BY 1, 2, 3 ORDER BY n DESC;

-- [F1] National rates by year x coal/metal (2026 is a PARTIAL year: hours through Q2 only)
SELECT year, mine_category, operator_injuries, fatalities,
       operator_injury_rate_per_200k_hours, operator_lost_time_rate_per_200k_hours,
       all_workers_injury_rate_per_200k_hours, is_partial_year
FROM ANALYTICS.NATIONAL_TRENDS WHERE mine_category <> 'All Mines' ORDER BY mine_category, year;

-- [F2] Top accident classifications: 2010-12 vs 2023-25 share of reportable injuries
WITH p AS (
    SELECT accident_classification,
           SUM(IFF(year BETWEEN 2010 AND 2012, reportable_injuries, 0)) early,
           SUM(IFF(year BETWEEN 2023 AND 2025, reportable_injuries, 0)) recent
    FROM ANALYTICS.ACCIDENT_PATTERNS GROUP BY 1)
SELECT accident_classification, early, recent,
       ROUND(100 * early / SUM(early) OVER (), 1) early_pct,
       ROUND(100 * recent / SUM(recent) OVER (), 1) recent_pct
FROM p QUALIFY ROW_NUMBER() OVER (ORDER BY early + recent DESC) <= 10 ORDER BY early + recent DESC;

-- [F2b] Top injury sources (2023-2025)
SELECT injury_source, SUM(reportable_injuries) injuries, SUM(fatalities) fatalities
FROM ANALYTICS.ACCIDENT_PATTERNS WHERE year BETWEEN 2023 AND 2025
GROUP BY 1 ORDER BY injuries DESC LIMIT 10;

-- [F3] Ventilation & methane proxy: trend (count, per 200K hours, coal only)
SELECT year, violations, violations_per_200k_operator_hours, significant_substantial_rate, high_negligence_rate, is_partial_year
FROM ANALYTICS.HAZARD_TRENDS WHERE hazard_category = 'Ventilation & Methane' AND mine_category = 'Coal' ORDER BY year;

-- [F3b] Gravity/negligence profile: ventilation vs all violations (2010+)
SELECT IFF(hazard_category = 'Ventilation & Methane', 'Ventilation & Methane', 'All other') grp,
       COUNT(*) n,
       ROUND(AVG(is_significant_substantial::int), 4) ss_rate,
       ROUND(AVG(is_high_negligence::int), 4) high_neg_rate,
       ROUND(AVG(likelihood_score), 3) avg_likelihood,
       ROUND(AVG((is_unwarrantable_failure OR is_imminent_danger)::int), 4) uf_id_rate,
       ROUND(AVG(proposed_penalty_usd), 0) avg_penalty
FROM ANALYTICS.VIOLATION_DETAIL WHERE mine_category = 'Coal' GROUP BY 1;

-- [F4] Ignition / explosion / fire accidents by year and classification
SELECT accident_year, accident_classification, COUNT(*) records, COUNT_IF(is_fatal) fatalities
FROM ANALYTICS.ACCIDENT_DETAIL WHERE is_ignition_explosion_fire
GROUP BY 1, 2 ORDER BY 1, 2;

SELECT state, COUNT(*) records, COUNT_IF(accident_classification = 'IGNITION OR EXPLOSION OF GAS OR DUST') gas_dust, COUNT_IF(is_fatal) fatalities
FROM ANALYTICS.ACCIDENT_DETAIL WHERE is_ignition_explosion_fire
GROUP BY 1 ORDER BY records DESC LIMIT 10;

-- [F5] Top 10 states by injury rate, 2023-2025, >= 2M operator hours
SELECT state, SUM(operator_injuries) injuries, ROUND(SUM(operator_hours_worked) / 1e6, 1) hours_m,
       ROUND(SUM(operator_injuries) * 200000 / SUM(operator_hours_worked), 3) injury_rate, SUM(fatalities) fatalities
FROM ANALYTICS.STATE_TRENDS WHERE mine_category = 'All Mines' AND year BETWEEN 2023 AND 2025
GROUP BY 1 HAVING SUM(operator_hours_worked) >= 2000000 ORDER BY injury_rate DESC LIMIT 10;

-- [F5b] Top 10 states by fatalities since 2010
SELECT state, SUM(fatalities) fatalities, SUM(operator_injuries) injuries
FROM ANALYTICS.STATE_TRENDS WHERE mine_category = 'All Mines' GROUP BY 1 ORDER BY fatalities DESC LIMIT 10;

-- [F5c] Top 10 mines by injury rate, 2025, >= 200K operator hours in the year
SELECT mine_id, ANY_VALUE(mine_name) mine_name, ANY_VALUE(state) state, ANY_VALUE(mine_category) cat, ANY_VALUE(mine_type) type,
       SUM(operator_injuries) injuries, ROUND(SUM(operator_hours_worked)) hours,
       ROUND(SUM(operator_injuries) * 200000 / SUM(operator_hours_worked), 2) injury_rate
FROM ANALYTICS.MINE_QUARTER_TRENDS WHERE year = 2025
GROUP BY 1 HAVING SUM(operator_hours_worked) >= 200000 ORDER BY injury_rate DESC LIMIT 10;

-- [F5d] Top 10 mines by fatalities since 2010
SELECT mine_id, mine_name, state, mine_category, mine_type, fatalities_since_2010, fatalities_since_2020, current_status
FROM ANALYTICS.MINE_PROFILE ORDER BY fatalities_since_2010 DESC LIMIT 10;

-- [F6] LEADING-INDICATOR EVIDENCE
-- Pooled next-quarter injury rate by quartile (0 = indicator zero; 1-4 = quartiles
-- of non-zero values within coal/metal). Comparable rows only.
WITH li AS (SELECT * FROM ANALYTICS.LEADING_INDICATORS WHERE is_comparable),
u AS (
    SELECT 'S&S per 200K hrs' ind, mine_category, significant_substantial_quartile q, next_quarter_operator_injuries inj, next_quarter_operator_hours hrs FROM li
    UNION ALL SELECT 'Ventilation/methane per 200K hrs', mine_category, ventilation_methane_quartile, next_quarter_operator_injuries, next_quarter_operator_hours FROM li
    UNION ALL SELECT '104(d)/107(a) per 200K hrs', mine_category, unwarrantable_imminent_quartile, next_quarter_operator_injuries, next_quarter_operator_hours FROM li
    UNION ALL SELECT 'High negligence per 200K hrs', mine_category, high_negligence_quartile, next_quarter_operator_injuries, next_quarter_operator_hours FROM li
    UNION ALL SELECT 'Prior injury rate', mine_category, prior_injury_rate_quartile, next_quarter_operator_injuries, next_quarter_operator_hours FROM li
    UNION ALL SELECT 'Inspection hrs per 200K hrs', mine_category, inspection_intensity_quartile, next_quarter_operator_injuries, next_quarter_operator_hours FROM li
)
SELECT ind, mine_category, q quartile, COUNT(*) mine_quarters,
       ROUND(SUM(inj) * 200000 / SUM(hrs), 3) next_q_injury_rate
FROM u GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

-- [F6b] Lift: top quartile vs zero group, and correlations (mine-quarter level)
SELECT mine_category,
       ROUND(CORR(prior_4q_significant_substantial_per_200k_hours, next_quarter_injury_rate_per_200k_hours), 4) corr_ss,
       ROUND(CORR(prior_4q_ventilation_methane_per_200k_hours, next_quarter_injury_rate_per_200k_hours), 4) corr_vent,
       ROUND(CORR(prior_4q_unwarrantable_imminent_per_200k_hours, next_quarter_injury_rate_per_200k_hours), 4) corr_ufid,
       ROUND(CORR(prior_4q_high_negligence_per_200k_hours, next_quarter_injury_rate_per_200k_hours), 4) corr_hn,
       ROUND(CORR(prior_4q_injury_rate_per_200k_hours, next_quarter_injury_rate_per_200k_hours), 4) corr_prior_inj,
       ROUND(CORR(prior_4q_inspection_hours_per_200k_hours, next_quarter_injury_rate_per_200k_hours), 4) corr_insp,
       ROUND(CORR(prior_4q_significant_substantial_rate, next_quarter_injury_rate_per_200k_hours), 4) corr_ss_share
FROM ANALYTICS.LEADING_INDICATORS WHERE is_comparable GROUP BY 1;

-- [F6c] Rank correlation proxy: share of mine-quarters with any injury next quarter, by quartile
SELECT mine_category, significant_substantial_quartile q,
       ROUND(AVG(had_injury_next_quarter::int), 4) p_injury_next_q,
       ROUND(AVG(had_lost_time_injury_next_quarter::int), 4) p_lost_time_next_q, COUNT(*) n
FROM ANALYTICS.LEADING_INDICATORS WHERE is_comparable GROUP BY 1, 2 ORDER BY 1, 2;

-- [F7] Penalty outcomes: share of proposed dollars by status (assessed violations, 2010+)
SELECT penalty_status, COUNT(*) violations, ROUND(SUM(proposed_penalty_usd) / 1e6, 1) proposed_m,
       ROUND(100 * SUM(proposed_penalty_usd) / SUM(SUM(proposed_penalty_usd)) OVER (), 2) pct_of_proposed,
       ROUND(SUM(amount_paid_usd) / 1e6, 1) paid_m
FROM ANALYTICS.VIOLATION_DETAIL WHERE penalty_status <> 'Not Assessed' GROUP BY 1 ORDER BY proposed_m DESC;

SELECT operator_name, controller_name, mines, active_mines, ROUND(open_delinquent_penalty_balance_usd) open_balance, fatalities_since_2010
FROM ANALYTICS.OPERATOR_PORTFOLIO ORDER BY open_delinquent_penalty_balance_usd DESC LIMIT 10;

-- [F8] Narrative check: length distribution and samples
SELECT COUNT(*) n, COUNT_IF(narrative IS NULL OR narrative = '') empty,
       MIN(LEN(narrative)) mn, APPROX_PERCENTILE(LEN(narrative), 0.5) p50, APPROX_PERCENTILE(LEN(narrative), 0.9) p90,
       MAX(LEN(narrative)) mx, COUNT_IF(LEN(narrative) >= 380) at_or_near_max
FROM ANALYTICS.ACCIDENT_DETAIL;

SELECT accident_date, mine_name, state, accident_classification, degree_of_injury, narrative
FROM ANALYTICS.ACCIDENT_DETAIL
WHERE is_fatal OR accident_classification = 'IGNITION OR EXPLOSION OF GAS OR DUST'
QUALIFY ROW_NUMBER() OVER (PARTITION BY is_fatal ORDER BY accident_date DESC) <= 3;
