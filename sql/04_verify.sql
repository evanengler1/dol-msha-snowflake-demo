-- Phase 1: verify the raw load. Compare 1) to rows_kept in data/manifest.json.
USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE SCHEMA DOL_MSHA_DEMO.RAW;

-- 1) Row counts per raw table
SELECT 'accident' AS dataset, COUNT(*) AS row_count FROM MSHA_ACCIDENT
UNION ALL SELECT 'inspection', COUNT(*) FROM MSHA_INSPECTION
UNION ALL SELECT 'violation', COUNT(*) FROM MSHA_VIOLATION
UNION ALL SELECT 'operator_employment_production_quarterly', COUNT(*) FROM MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY
UNION ALL SELECT 'operator_employment_production_annual', COUNT(*) FROM MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_ANNUAL
UNION ALL SELECT 'contractor_employment_production_quarterly', COUNT(*) FROM MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_QUARTERLY
UNION ALL SELECT 'contractor_employment_production_annual', COUNT(*) FROM MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_ANNUAL
UNION ALL SELECT 'assessed_violations', COUNT(*) FROM MSHA_ASSESSED_VIOLATIONS
UNION ALL SELECT 'mines', COUNT(*) FROM MSHA_MINES
UNION ALL SELECT 'operator_history_at_mines', COUNT(*) FROM MSHA_OPERATOR_HISTORY_AT_MINES
UNION ALL SELECT 'contractor_history_at_mines', COUNT(*) FROM MSHA_CONTRACTOR_HISTORY_AT_MINES
UNION ALL SELECT 'controller_history', COUNT(*) FROM MSHA_CONTROLLER_HISTORY
UNION ALL SELECT 'commodity_lookup', COUNT(*) FROM MSHA_COMMODITY_LOOKUP
UNION ALL SELECT 'contractor_name_id_lookup', COUNT(*) FROM MSHA_CONTRACTOR_NAME_ID_LOOKUP
ORDER BY dataset;

-- 2) Date range of the filter field for each fact table
SELECT 'accident' AS dataset, MIN(LEFT(ai_dt, 10)) AS min_val, MAX(LEFT(ai_dt, 10)) AS max_val FROM MSHA_ACCIDENT
UNION ALL SELECT 'inspection', MIN(LEFT(beg_dt, 10)), MAX(LEFT(beg_dt, 10)) FROM MSHA_INSPECTION
UNION ALL SELECT 'violation', MIN(LEFT(iss_dt, 10)), MAX(LEFT(iss_dt, 10)) FROM MSHA_VIOLATION
UNION ALL SELECT 'operator_empl_prod_quarterly', MIN(empl_prod_yr), MAX(empl_prod_yr) FROM MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY
UNION ALL SELECT 'operator_empl_prod_annual', MIN(calendar_yr), MAX(calendar_yr) FROM MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_ANNUAL
UNION ALL SELECT 'contractor_empl_prod_quarterly', MIN(empl_prod_yr), MAX(empl_prod_yr) FROM MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_QUARTERLY
UNION ALL SELECT 'contractor_empl_prod_annual', MIN(calendar_yr), MAX(calendar_yr) FROM MSHA_CONTRACTOR_EMPLOYMENT_PRODUCTION_ANNUAL;

-- 3) Join-key coverage
SELECT 'accident.mine_id in mines' AS check_name,
       ROUND(100 * COUNT_IF(m.mine_id IS NOT NULL) / COUNT(*), 2) AS pct_found
FROM MSHA_ACCIDENT a LEFT JOIN (SELECT DISTINCT mine_id FROM MSHA_MINES) m ON a.mine_id = m.mine_id
UNION ALL
SELECT 'violation.event_no in inspection',
       ROUND(100 * COUNT_IF(i.event_no IS NOT NULL) / COUNT(*), 2)
FROM MSHA_VIOLATION v LEFT JOIN (SELECT DISTINCT event_no FROM MSHA_INSPECTION) i ON v.event_no = i.event_no
UNION ALL
SELECT 'violation.viol_no in assessed_violations.citation_nbr',
       ROUND(100 * COUNT_IF(av.citation_nbr IS NOT NULL) / COUNT(*), 2)
FROM MSHA_VIOLATION v LEFT JOIN (SELECT DISTINCT citation_nbr FROM MSHA_ASSESSED_VIOLATIONS) av ON v.viol_no = av.citation_nbr
UNION ALL
SELECT 'oper_empl_prod_quarterly.petreemine_id in mines',
       ROUND(100 * COUNT_IF(m.mine_id IS NOT NULL) / COUNT(*), 2)
FROM MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY q LEFT JOIN (SELECT DISTINCT mine_id FROM MSHA_MINES) m ON q.petreemine_id = m.mine_id;

-- 4) Accident narrative coverage by year
SELECT LEFT(ai_dt, 4) AS yr, COUNT(*) AS accidents,
       ROUND(100 * COUNT_IF(TRIM(ai_narr) <> '' AND ai_narr IS NOT NULL) / COUNT(*), 1) AS pct_with_narrative
FROM MSHA_ACCIDENT GROUP BY 1 ORDER BY 1;

-- 5) Violation has no free-text condition/practice column (expect 0 rows)
SELECT column_name FROM DOL_MSHA_DEMO.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'RAW' AND table_name = 'MSHA_VIOLATION'
  AND (column_name ILIKE '%narr%' OR column_name ILIKE '%condition%' OR column_name ILIKE '%practice%' OR column_name ILIKE '%desc%');

-- 6) Ventilation/methane proxy: 30 CFR 75 Subpart D (75.3xx)
SELECT COUNT(*) AS viol_75_3xx, ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM MSHA_VIOLATION), 2) AS pct_of_violations
FROM MSHA_VIOLATION WHERE part_section LIKE '75.3%';

-- 7) Spot checks
SELECT document_no, mine_id, ai_dt, inj_degr_desc, accident_type, LEFT(ai_narr, 120) AS narr FROM MSHA_ACCIDENT SAMPLE (5 ROWS);
SELECT event_no, mine_id, acty_desc, beg_dt, total_insp_hours FROM MSHA_INSPECTION SAMPLE (5 ROWS);
SELECT viol_no, event_no, mine_id, iss_dt, sig_sub, part_section, likelihood, negligence FROM MSHA_VIOLATION SAMPLE (5 ROWS);
SELECT * FROM MSHA_ASSESSED_VIOLATIONS SAMPLE (3 ROWS);
SELECT mine_id, curr_mine_nm, c_m_ind, state_abbr, latitude, longitude FROM MSHA_MINES SAMPLE (5 ROWS);
SELECT * FROM MSHA_OPERATOR_EMPLOYMENT_PRODUCTION_QUARTERLY SAMPLE (3 ROWS);
SELECT * FROM MSHA_COMMODITY_LOOKUP LIMIT 3;
