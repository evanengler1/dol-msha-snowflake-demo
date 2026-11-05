-- Phase 5: Semantic view for Cortex Analyst over MSHA portal data.
-- Rerunnable: SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML replaces the view.
-- Debug: add TRUE as the third argument for verify-only.
-- Methane/ventilation fields are compliance proxies (cited 30 CFR 75 Subpart D
-- sections), not sensor readings. The portal has no methane or temperature data.
USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;

CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML('DOL_MSHA_DEMO.ANALYTICS', $$
name: MSHA_SAFETY_SEMANTIC_VIEW
description: >-
  U.S. Department of Labor, Mine Safety and Health Administration (MSHA) data from the DOL Open Data Portal
  (data.dol.gov), 2010 to 2026 Q2. Covers mine-quarter injuries, operator hours, citations (violations),
  104(d) unwarrantable failure actions, 107(a) imminent danger orders, proposed penalties, accidents,
  hazard categories by 30 CFR section, mine attributes, and an illustrative early-warning tier.
  Injury rates are pooled per 200,000 operator hours. 2026 is a partial year (hours through 2026 Q2).
  Ventilation and methane fields are COMPLIANCE PROXIES (citation counts), NOT sensor readings. The portal has
  no methane, gas, temperature or sensor data.

tables:
  - name: MINE_QUARTER
    description: "One row per mine per calendar quarter (2010 to 2026 Q2). Core fact table for injuries, operator hours, inspections, citations, enforcement actions and proposed penalties. Join to MINES for mine name, operator, state, district, category and type."
    base_table: {database: DOL_MSHA_DEMO, schema: ANALYTICS, table: MINE_QUARTER_TRENDS}
    primary_key: {columns: [MINE_ID, YEAR_QUARTER]}
    dimensions:
      - {name: MINE_ID, expr: MINE_ID, data_type: TEXT, description: "7-digit MSHA mine ID stored as text with leading zeros (e.g. 0100851). Always compare as a string."}
      - {name: YEAR_QUARTER, expr: YEAR_QUARTER, data_type: TEXT, description: "Calendar quarter label such as 2025-Q3.", synonyms: [quarter label, period]}
      - {name: REPORT_YEAR, expr: YEAR, data_type: NUMBER, description: "Calendar year of the quarter. 2026 is partial (through Q2). exclude it from year-over-year comparisons unless asked.", synonyms: [year, calendar year]}
      - {name: REPORT_QUARTER, expr: QUARTER, data_type: NUMBER, description: "Calendar quarter number 1 to 4.", synonyms: [quarter]}
      - {name: IS_PARTIAL_PERIOD, expr: IS_PARTIAL_PERIOD, data_type: BOOLEAN, description: "TRUE for the most recent quarter whose data may still be incomplete (2026-Q2)."}
      - {name: IS_PARTIAL_YEAR, expr: "YEAR >= 2026", data_type: BOOLEAN, description: "TRUE for 2026, a partial year with hours only through 2026 Q2.", synonyms: [partial year, incomplete year]}
      - {name: HAS_HOURS, expr: HAS_HOURS, data_type: BOOLEAN, description: "TRUE if the mine reported operator hours in the quarter. Rates need hours."}
    time_dimensions:
      - {name: QUARTER_START, expr: QUARTER_START, data_type: DATE, description: "First day of the calendar quarter.", synonyms: [date, quarter start date]}
    facts:
      - {name: OPERATOR_INJURIES, expr: OPERATOR_INJURIES, data_type: NUMBER, description: "Row-level Operator injuries in the quarter. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: OPERATOR_LOST_TIME_INJURIES, expr: OPERATOR_LOST_TIME_INJURIES, data_type: NUMBER, description: "Row-level Operator lost-time injuries. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: CONTRACTOR_INJURIES, expr: CONTRACTOR_INJURIES, data_type: NUMBER, description: "Row-level Contractor injuries. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: FATALITIES, expr: FATALITIES, data_type: NUMBER, description: "Row-level Fatalities (operator and contractor). Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: OPERATOR_DAYS_LOST, expr: OPERATOR_DAYS_LOST, data_type: NUMBER, description: "Row-level Operator days lost. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: IGNITION_EXPLOSION_FIRE_ACCIDENTS, expr: IGNITION_EXPLOSION_FIRE_ACCIDENTS, data_type: NUMBER, description: "Row-level Ignition/explosion/fire accidents. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: OPERATOR_HOURS_WORKED, expr: OPERATOR_HOURS_WORKED, data_type: NUMBER, description: "Row-level Operator hours worked. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: INSPECTIONS, expr: INSPECTIONS, data_type: NUMBER, description: "Row-level Inspections. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: INSPECTION_HOURS, expr: INSPECTION_HOURS, data_type: NUMBER, description: "Row-level Inspector hours. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: VIOLATIONS, expr: VIOLATIONS, data_type: NUMBER, description: "Row-level Citations issued. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: SIGNIFICANT_SUBSTANTIAL_VIOLATIONS, expr: SIGNIFICANT_SUBSTANTIAL_VIOLATIONS, data_type: NUMBER, description: "Row-level S&S citations. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: VENTILATION_METHANE_VIOLATIONS, expr: VENTILATION_METHANE_VIOLATIONS, data_type: NUMBER, description: "Row-level COMPLIANCE PROXY, not sensor data. Ventilation/methane citations (30 CFR 75 Subpart D). Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: ROCK_DUST_VIOLATIONS, expr: ROCK_DUST_VIOLATIONS, data_type: NUMBER, description: "Row-level COMPLIANCE PROXY. Rock dust citations. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: ELECTRICAL_VIOLATIONS, expr: ELECTRICAL_VIOLATIONS, data_type: NUMBER, description: "Row-level COMPLIANCE PROXY. Electrical citations. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: ROOF_RIB_VIOLATIONS, expr: ROOF_RIB_VIOLATIONS, data_type: NUMBER, description: "Row-level COMPLIANCE PROXY. Roof/rib citations. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: UNWARRANTABLE_FAILURE_ACTIONS, expr: UNWARRANTABLE_FAILURE_ACTIONS, data_type: NUMBER, description: "Row-level 104(d) actions. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: IMMINENT_DANGER_ORDERS, expr: IMMINENT_DANGER_ORDERS, data_type: NUMBER, description: "Row-level 107(a) orders. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: HIGH_NEGLIGENCE_VIOLATIONS, expr: HIGH_NEGLIGENCE_VIOLATIONS, data_type: NUMBER, description: "Row-level High-negligence citations. Aggregate with the TOTAL_ or POOLED_ metrics."}
      - {name: PROPOSED_PENALTIES_USD, expr: PROPOSED_PENALTIES_USD, data_type: NUMBER, description: "Row-level Proposed penalties USD. Aggregate with the TOTAL_ or POOLED_ metrics."}
    metrics:
      - {name: TOTAL_OPERATOR_INJURIES, expr: SUM(OPERATOR_INJURIES), description: "Operator (mine employee) injuries. Basis for the operator injury rate.", synonyms: [injuries, injury count, number of injuries]}
      - {name: TOTAL_OPERATOR_LOST_TIME_INJURIES, expr: SUM(OPERATOR_LOST_TIME_INJURIES), description: "Operator injuries with days away or restricted activity.", synonyms: [lost time injuries, lost-time injuries]}
      - {name: TOTAL_CONTRACTOR_INJURIES, expr: SUM(CONTRACTOR_INJURIES), description: "Contractor employee injuries (not in the operator rate)."}
      - {name: TOTAL_FATALITIES, expr: SUM(FATALITIES), description: "Fatalities at the mine, operator and contractor employees combined.", synonyms: [deaths, fatal injuries, fatalities]}
      - {name: TOTAL_OPERATOR_DAYS_LOST, expr: SUM(OPERATOR_DAYS_LOST), description: "Days away from work for operator injuries."}
      - {name: TOTAL_IGNITION_EXPLOSION_FIRE_ACCIDENTS, expr: SUM(IGNITION_EXPLOSION_FIRE_ACCIDENTS), description: "Accidents classified as ignition or explosion of gas or dust, or mine fire. Accident counts, not gas readings.", synonyms: [ignitions, explosions, mine fires]}
      - {name: TOTAL_OPERATOR_HOURS, expr: SUM(OPERATOR_HOURS_WORKED), description: "Operator employee hours worked. Denominator for operator rates.", synonyms: [hours worked, employee hours, exposure hours]}
      - {name: POOLED_OPERATOR_INJURY_RATE, expr: "SUM(OPERATOR_INJURIES) * 200000 / NULLIF(SUM(OPERATOR_HOURS_WORKED), 0)", description: "Pooled operator injury rate per 200,000 operator hours (operator injuries / operator hours). Always use this. never average per-row rates.", synonyms: [injury rate, incidence rate, IR, injury rate per 200K hours]}
      - {name: POOLED_OPERATOR_LOST_TIME_RATE, expr: "SUM(OPERATOR_LOST_TIME_INJURIES) * 200000 / NULLIF(SUM(OPERATOR_HOURS_WORKED), 0)", description: "Pooled operator lost-time injury rate per 200,000 operator hours.", synonyms: [lost time rate, NFDL rate]}
      - {name: TOTAL_INSPECTIONS, expr: SUM(INSPECTIONS), description: "MSHA inspections.", synonyms: [inspections]}
      - {name: TOTAL_INSPECTION_HOURS, expr: SUM(INSPECTION_HOURS), description: "MSHA inspector hours on site."}
      - {name: TOTAL_CITATIONS, expr: SUM(VIOLATIONS), description: "Citations and orders issued (violations).", synonyms: [violations, citations, number of violations]}
      - {name: TOTAL_SS_CITATIONS, expr: SUM(SIGNIFICANT_SUBSTANTIAL_VIOLATIONS), description: "Significant and substantial (S&S) citations.", synonyms: [S&S citations, significant and substantial, S&S violations]}
      - {name: POOLED_SS_SHARE, expr: "SUM(SIGNIFICANT_SUBSTANTIAL_VIOLATIONS) / NULLIF(SUM(VIOLATIONS), 0)", description: "Share of citations designated S&S (0 to 1)."}
      - {name: TOTAL_VENTILATION_METHANE_CITATIONS, expr: SUM(VENTILATION_METHANE_VIOLATIONS), description: "COMPLIANCE PROXY, not sensor data. Citations under 30 CFR 75 Subpart D (75.300-75.390, ventilation and methane). Counts of cited conditions, not methane readings.", synonyms: [ventilation citations, methane citations, ventilation violations, methane violations, gas citations]}
      - {name: POOLED_VENTILATION_METHANE_CITATIONS_PER_200K_HOURS, expr: "SUM(VENTILATION_METHANE_VIOLATIONS) * 200000 / NULLIF(SUM(OPERATOR_HOURS_WORKED), 0)", description: "COMPLIANCE PROXY, not sensor data. Ventilation/methane citations (30 CFR 75 Subpart D) per 200,000 operator hours.", synonyms: [ventilation citation rate, methane citation rate]}
      - {name: TOTAL_ROCK_DUST_CITATIONS, expr: SUM(ROCK_DUST_VIOLATIONS), description: "COMPLIANCE PROXY. Combustible material and rock dust citations (30 CFR 75 Subpart E)."}
      - {name: TOTAL_ELECTRICAL_CITATIONS, expr: SUM(ELECTRICAL_VIOLATIONS), description: "COMPLIANCE PROXY. Electrical and permissibility citations (30 CFR 75 Subparts F-K)."}
      - {name: TOTAL_ROOF_RIB_CITATIONS, expr: SUM(ROOF_RIB_VIOLATIONS), description: "COMPLIANCE PROXY. Roof and rib control citations (30 CFR 75 Subpart C)."}
      - {name: TOTAL_104D_107A_ACTIONS, expr: "SUM(UNWARRANTABLE_FAILURE_ACTIONS + IMMINENT_DANGER_ORDERS)", description: "Section 104(d) unwarrantable failure citations/orders plus Section 107(a) imminent danger orders.", synonyms: [104(d) and 107(a), 104d/107a, unwarrantable failure and imminent danger, serious enforcement actions]}
      - {name: TOTAL_104D_ACTIONS, expr: SUM(UNWARRANTABLE_FAILURE_ACTIONS), description: "Section 104(d) unwarrantable failure citations and orders.", synonyms: [unwarrantable failure, 104(d)]}
      - {name: TOTAL_107A_ORDERS, expr: SUM(IMMINENT_DANGER_ORDERS), description: "Section 107(a) imminent danger orders.", synonyms: [imminent danger orders, 107(a)]}
      - {name: TOTAL_HIGH_NEGLIGENCE_CITATIONS, expr: SUM(HIGH_NEGLIGENCE_VIOLATIONS), description: "Citations with high or reckless disregard negligence.", synonyms: [high negligence, reckless disregard]}
      - {name: TOTAL_PROPOSED_PENALTIES, expr: SUM(PROPOSED_PENALTIES_USD), description: "Proposed penalties in USD.", synonyms: [penalties, fines, proposed penalty dollars]}
      - {name: TOTAL_MINES_REPORTING_HOURS, expr: "COUNT(DISTINCT IFF(HAS_HOURS, MINE_ID, NULL))", description: "Distinct mines that reported operator hours."}
    filters:
      - {name: COMPLETE_YEARS, expr: "YEAR <= 2025", description: "Complete years 2010 to 2025 (excludes partial 2026). Default for trends and year-over-year comparisons."}

  - name: MINES
    description: "One row per MSHA mine (about 92,000). Mine dimension: name, current operator and controller, state, county, MSHA district, field office, coal vs metal/nonmetal category, mine type, commodity, status, size band and peer group."
    base_table: {database: DOL_MSHA_DEMO, schema: ANALYTICS, table: MINE_DIRECTORY}
    primary_key: {columns: [MINE_ID]}
    dimensions:
      - {name: MINE_ID, expr: MINE_ID, data_type: TEXT, description: "7-digit MSHA mine ID stored as text with leading zeros (e.g. 0100851).", synonyms: [mine number, mine id]}
      - {name: MINE_NAME, expr: MINE_NAME, data_type: TEXT, description: "Mine name. Use ILIKE for partial matches.", synonyms: [mine]}
      - {name: OPERATOR_NAME, expr: OPERATOR_NAME, data_type: TEXT, description: "Current mine operator (company). History is attributed to the current operator.", synonyms: [operator, company, mine operator]}
      - {name: CONTROLLER_NAME, expr: CONTROLLER_NAME, data_type: TEXT, description: "Current controller (parent company).", synonyms: [controller, parent company, owner]}
      - {name: STATE, expr: STATE, data_type: TEXT, description: "2-letter US postal state code (KY, WV, PA, TX).", synonyms: [state]}
      - {name: COUNTY_NAME, expr: COUNTY_NAME, data_type: TEXT, description: "County name.", synonyms: [county]}
      - {name: DISTRICT, expr: DISTRICT, data_type: TEXT, description: "MSHA district code. Coal districts C03-C10 and metal/nonmetal districts M2-M7.", sample_values: [C04, C03, C07, M5], synonyms: [MSHA district, district office]}
      - {name: FIELD_OFFICE, expr: OFFICE_NAME, data_type: TEXT, description: "MSHA field office.", synonyms: [office, field office]}
      - {name: NEAREST_TOWN, expr: NEAREST_TOWN, data_type: TEXT, description: "Nearest town.", synonyms: [town, city]}
      - {name: MINE_CATEGORY, expr: MINE_CATEGORY, data_type: TEXT, description: "Coal or Metal/Nonmetal.", sample_values: [Coal, Metal/Nonmetal], synonyms: [coal or metal, sector]}
      - {name: MINE_TYPE, expr: MINE_TYPE, data_type: TEXT, description: "Underground, Surface or Facility.", sample_values: [Underground, Surface, Facility], synonyms: [mine type, underground or surface]}
      - {name: PRIMARY_COMMODITY, expr: PRIMARY_COMMODITY, data_type: TEXT, description: "Primary commodity mined.", synonyms: [commodity, mineral]}
      - {name: CURRENT_STATUS, expr: CURRENT_STATUS, data_type: TEXT, description: "Current mine status.", sample_values: [Active, Intermittent, TempIdle, Abandoned, AbandonedSealed, NewMine, NonProdActive], synonyms: [status, active]}
      - {name: SIZE_BAND, expr: SIZE_BAND, data_type: TEXT, description: "Employee size band from the last 4 quarters.", sample_values: [1-19 employees, 20-99 employees, 100-499 employees, 500+ employees, No recent hours], synonyms: [size, mine size]}
      - {name: PEER_GROUP, expr: PEER_GROUP, data_type: TEXT, description: "Peer group: category | type | size band (e.g. Coal | Underground | 100-499 employees).", synonyms: [peer group]}
    metrics:
      - {name: TOTAL_MINES, expr: COUNT(DISTINCT MINE_ID), description: "Number of distinct mines.", synonyms: [mines, number of mines, mine count]}

  - name: EARLY_WARNING
    description: "Illustrative early-warning tier per mine with recent hours (about 12,700 mines). Tier is a demo signal from public citations and injuries, NOT an official MSHA rating and NOT a prediction for any mine."
    base_table: {database: DOL_MSHA_DEMO, schema: ANALYTICS, table: MINE_EARLY_WARNING}
    primary_key: {columns: [MINE_ID]}
    dimensions:
      - {name: MINE_ID, expr: MINE_ID, data_type: TEXT, description: "7-digit MSHA mine ID (text)."}
      - {name: TIER, expr: TIER, data_type: TEXT, description: "Illustrative early-warning tier (not an official MSHA rating, not a prediction).", sample_values: [Elevated, Watch, Typical, Not enough recent hours], synonyms: [risk tier, early warning tier, warning level]}
      - {name: TIER_RANK, expr: TIER_RANK, data_type: NUMBER, description: "Tier order, lower is more concerning."}
      - {name: TIER_REASONS, expr: "ARRAY_TO_STRING(TIER_REASONS, ' | ')", data_type: TEXT, description: "Signals behind the tier (e.g. high ventilation/methane citation proxy vs peers).", synonyms: [reasons, why]}
    time_dimensions:
      - {name: LAST_INSPECTION_DATE, expr: LAST_INSPECTION_DATE, data_type: DATE, description: "Most recent MSHA inspection date."}
    facts:
      - {name: EW_LAST_4Q_OPERATOR_HOURS, expr: LAST_4Q_OPERATOR_HOURS, data_type: NUMBER, description: "Operator hours in the last 4 quarters."}
      - {name: EW_LAST_4Q_INJURIES, expr: LAST_4Q_INJURIES, data_type: NUMBER, description: "Operator injuries in the last 4 quarters."}
      - {name: EW_OPEN_DELINQUENT_BALANCE, expr: OPEN_DELINQUENT_PENALTY_BALANCE_USD, data_type: NUMBER, description: "Open delinquent penalty balance (USD)."}
    metrics:
      - {name: TOTAL_TIERED_MINES, expr: COUNT(MINE_ID), description: "Mines with an early-warning tier.", synonyms: [tiered mines]}

  - name: ACCIDENTS
    description: "One row per reported accident or injury document (2010 to 2026). Accident classification, degree of injury, occupation, equipment, activity. Narratives are searched with the Cortex Search tool, not here. Never sum persons injured in event."
    base_table: {database: DOL_MSHA_DEMO, schema: ANALYTICS, table: ACCIDENT_DETAIL}
    primary_key: {columns: [ACCIDENT_DOCUMENT_NUMBER]}
    dimensions:
      - {name: ACCIDENT_DOCUMENT_NUMBER, expr: ACCIDENT_DOCUMENT_NUMBER, data_type: TEXT, description: "MSHA accident document number. Cite it.", synonyms: [document number, document no]}
      - {name: MINE_ID, expr: MINE_ID, data_type: TEXT, description: "7-digit MSHA mine ID (text)."}
      - {name: ACCIDENT_YEAR, expr: ACCIDENT_YEAR, data_type: NUMBER, description: "Accident year. 2026 is partial.", synonyms: [year of accident]}
      - {name: ACCIDENT_QUARTER, expr: ACCIDENT_QUARTER, data_type: NUMBER, description: "Accident quarter 1 to 4."}
      - {name: ACCIDENT_CLASSIFICATION, expr: ACCIDENT_CLASSIFICATION, data_type: TEXT, description: "MSHA accident classification (uppercase).", sample_values: [POWERED HAULAGE, FALL OF ROOF OR BACK, HANDLING OF MATERIALS, MACHINERY, SLIP OR FALL OF PERSON, IGNITION OR EXPLOSION OF GAS OR DUST], synonyms: [accident type, classification, cause]}
      - {name: ACCIDENT_TYPE, expr: ACCIDENT_TYPE, data_type: TEXT, description: "Accident type (e.g. caught in, struck by)."}
      - {name: DEGREE_OF_INJURY, expr: DEGREE_OF_INJURY, data_type: TEXT, description: "Degree of injury.", sample_values: [Fatality, Days away from work only, Days restricted activity only, "No days away, no restriction"], synonyms: [severity, injury degree]}
      - {name: IS_FATAL, expr: IS_FATAL, data_type: BOOLEAN, description: "TRUE if the accident was fatal.", synonyms: [fatal]}
      - {name: IS_LOST_TIME_INJURY, expr: IS_LOST_TIME_INJURY, data_type: BOOLEAN, description: "TRUE for lost-time injuries."}
      - {name: IS_CONTRACTOR_EMPLOYEE, expr: IS_CONTRACTOR_EMPLOYEE, data_type: BOOLEAN, description: "TRUE if the injured person was a contractor employee."}
      - {name: IS_IGNITION_EXPLOSION_FIRE, expr: IS_IGNITION_EXPLOSION_FIRE, data_type: BOOLEAN, description: "TRUE for ignition/explosion of gas or dust or mine fire accidents (accident records, not gas readings)."}
      - {name: MINING_EQUIPMENT, expr: MINING_EQUIPMENT, data_type: TEXT, description: "Equipment involved (e.g. continuous miner, shuttle car, conveyor).", synonyms: [equipment, machine]}
      - {name: OCCUPATION, expr: OCCUPATION, data_type: TEXT, description: "Injured person's occupation.", synonyms: [job, job title]}
      - {name: ACTIVITY_AT_TIME_OF_ACCIDENT, expr: ACTIVITY_AT_TIME_OF_ACCIDENT, data_type: TEXT, description: "Activity at time of accident."}
      - {name: NATURE_OF_INJURY, expr: NATURE_OF_INJURY, data_type: TEXT, description: "Nature of injury."}
      - {name: BODY_PART_INJURED, expr: BODY_PART_INJURED, data_type: TEXT, description: "Body part injured."}
    time_dimensions:
      - {name: ACCIDENT_DATE, expr: ACCIDENT_DATE, data_type: DATE, description: "Accident date.", synonyms: [date of accident]}
    facts:
      - {name: ACCIDENT_DAYS_LOST, expr: DAYS_LOST, data_type: NUMBER, description: "Days lost for the injury."}
    metrics:
      - {name: TOTAL_ACCIDENTS, expr: COUNT(DISTINCT ACCIDENT_DOCUMENT_NUMBER), description: "Number of accident documents.", synonyms: [accidents, number of accidents, accident count]}
      - {name: TOTAL_FATAL_ACCIDENTS, expr: "COUNT(DISTINCT IFF(IS_FATAL, ACCIDENT_DOCUMENT_NUMBER, NULL))", description: "Number of fatal accident documents.", synonyms: [fatal accidents]}

  - name: HAZARD_TRENDS
    description: "Citations by year, mine category and hazard category (30 CFR section groups). All hazard categories are COMPLIANCE PROXIES (cited conditions), not sensor readings. MINE_CATEGORY includes an 'All Mines' rollup row: always filter to Coal, Metal/Nonmetal, or All Mines. never sum across them."
    base_table: {database: DOL_MSHA_DEMO, schema: ANALYTICS, table: HAZARD_TRENDS}
    dimensions:
      - {name: HAZARD_YEAR, expr: YEAR, data_type: NUMBER, description: "Citation year. 2026 is partial."}
      - {name: HAZARD_MINE_CATEGORY, expr: MINE_CATEGORY, data_type: TEXT, description: "Coal, Metal/Nonmetal, or the All Mines rollup. Always filter one value.", sample_values: [Coal, Metal/Nonmetal, All Mines]}
      - {name: HAZARD_CATEGORY, expr: HAZARD_CATEGORY, data_type: TEXT, description: "Hazard category (compliance proxy) grouped by 30 CFR section.", sample_values: [Ventilation & Methane, Roof & Rib Control, Combustible Material & Rock Dust, Electrical / Permissibility, Respirable Dust, Surface Coal, Metal/Nonmetal Surface, Metal/Nonmetal Underground, Reporting & Training], synonyms: [hazard, hazard type, CFR category]}
      - {name: CFR_REFERENCE, expr: CFR_REFERENCE, data_type: TEXT, description: "30 CFR sections in the hazard category.", synonyms: [CFR section, regulation]}
      - {name: HAZARD_IS_PARTIAL_YEAR, expr: IS_PARTIAL_YEAR, data_type: BOOLEAN, description: "TRUE for partial 2026."}
    facts:
      - {name: VIOLATIONS, expr: VIOLATIONS, data_type: NUMBER, description: "Row-level hazard violations (compliance proxy)."}
      - {name: SIGNIFICANT_SUBSTANTIAL_VIOLATIONS, expr: SIGNIFICANT_SUBSTANTIAL_VIOLATIONS, data_type: NUMBER, description: "Row-level hazard significant substantial violations (compliance proxy)."}
      - {name: PROPOSED_PENALTIES_USD, expr: PROPOSED_PENALTIES_USD, data_type: NUMBER, description: "Row-level hazard proposed penalties usd (compliance proxy)."}
      - {name: HAZARD_CITATIONS_PER_200K_HOURS, expr: VIOLATIONS_PER_200K_OPERATOR_HOURS, data_type: NUMBER, description: "Precomputed citations per 200,000 operator hours for one year, category and hazard row. Do not sum or average across rows."}
    metrics:
      - {name: TOTAL_HAZARD_CITATIONS, expr: SUM(VIOLATIONS), description: "Citations in the hazard category (compliance proxy).", synonyms: [hazard citations]}
      - {name: TOTAL_HAZARD_SS_CITATIONS, expr: SUM(SIGNIFICANT_SUBSTANTIAL_VIOLATIONS), description: "S&S citations in the hazard category."}
      - {name: TOTAL_HAZARD_PROPOSED_PENALTIES, expr: SUM(PROPOSED_PENALTIES_USD), description: "Proposed penalties (USD) in the hazard category."}

relationships:
  - name: MINE_QUARTER_TO_MINES
    left_table: MINE_QUARTER
    right_table: MINES
    relationship_columns: [{left_column: MINE_ID, right_column: MINE_ID}]
    join_type: inner
    relationship_type: many_to_one
  - name: ACCIDENTS_TO_MINES
    left_table: ACCIDENTS
    right_table: MINES
    relationship_columns: [{left_column: MINE_ID, right_column: MINE_ID}]
    join_type: inner
    relationship_type: many_to_one
  - name: EARLY_WARNING_TO_MINES
    left_table: EARLY_WARNING
    right_table: MINES
    relationship_columns: [{left_column: MINE_ID, right_column: MINE_ID}]
    join_type: inner
    relationship_type: many_to_one

module_custom_instructions:
  sql_generation: >-
    Compute injury rates only with POOLED_OPERATOR_INJURY_RATE or POOLED_OPERATOR_LOST_TIME_RATE (SUM injuries * 200000 / SUM hours). never average row rates.
    Never report a rate for a period with no hours. Treat MINE_ID as text with leading zeros.
    When grouping by year include whether the year is partial (2026 is partial, through Q2). For year-over-year trends default to 2010-2025 unless 2026 is requested.
    "Last year" means 2025. For HAZARD_TRENDS always filter HAZARD_MINE_CATEGORY to one value.
    Ventilation and methane metrics are citation counts (compliance proxy), not sensor readings.

verified_queries:
  - name: c04_coal_ventilation_last_year
    question: Which coal mines in District C04 had the most ventilation citations last year?
    use_as_onboarding_question: true
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT d.MINE_ID, d.MINE_NAME, d.OPERATOR_NAME,
             SUM(q.VENTILATION_METHANE_VIOLATIONS) AS ventilation_methane_citations
      FROM __mine_quarter q
      JOIN __mines d ON q.MINE_ID = d.MINE_ID
      WHERE d.DISTRICT = 'C04' AND d.MINE_CATEGORY = 'Coal' AND q.REPORT_YEAR = 2025
      GROUP BY d.MINE_ID, d.MINE_NAME, d.OPERATOR_NAME
      ORDER BY ventilation_methane_citations DESC
      LIMIT 10
  - name: coal_injury_rate_by_year
    question: What is the coal operator injury rate by year since 2015?
    use_as_onboarding_question: true
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT q.REPORT_YEAR, q.IS_PARTIAL_YEAR,
             SUM(q.OPERATOR_INJURIES) * 200000 / NULLIF(SUM(q.OPERATOR_HOURS_WORKED), 0) AS operator_injury_rate_per_200k_hours,
             SUM(q.OPERATOR_INJURIES) AS operator_injuries,
             SUM(q.OPERATOR_HOURS_WORKED) AS operator_hours
      FROM __mine_quarter q
      JOIN __mines d ON q.MINE_ID = d.MINE_ID
      WHERE d.MINE_CATEGORY = 'Coal' AND q.REPORT_YEAR >= 2015
      GROUP BY q.REPORT_YEAR, q.IS_PARTIAL_YEAR
      ORDER BY q.REPORT_YEAR
  - name: elevated_mines_kentucky
    question: Which Elevated mines are in Kentucky?
    use_as_onboarding_question: true
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT e.MINE_ID, d.MINE_NAME, d.OPERATOR_NAME, d.MINE_CATEGORY, d.MINE_TYPE, d.DISTRICT,
             e.TIER_REASONS
      FROM __early_warning e
      JOIN __mines d ON e.MINE_ID = d.MINE_ID
      WHERE e.TIER = 'Elevated' AND d.STATE = 'KY'
      ORDER BY d.MINE_NAME
  - name: top_operators_fatalities_since_2020
    question: Top 10 operators by fatalities since 2020
    use_as_onboarding_question: true
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT d.OPERATOR_NAME, SUM(q.FATALITIES) AS fatalities
      FROM __mine_quarter q
      JOIN __mines d ON q.MINE_ID = d.MINE_ID
      WHERE q.REPORT_YEAR >= 2020
      GROUP BY d.OPERATOR_NAME
      HAVING SUM(q.FATALITIES) > 0
      ORDER BY fatalities DESC
      LIMIT 10
  - name: wv_104d_107a_2025
    question: How many 104(d)/107(a) actions were issued in West Virginia in 2025?
    use_as_onboarding_question: true
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT SUM(q.UNWARRANTABLE_FAILURE_ACTIONS) AS actions_104d,
             SUM(q.IMMINENT_DANGER_ORDERS) AS orders_107a,
             SUM(q.UNWARRANTABLE_FAILURE_ACTIONS + q.IMMINENT_DANGER_ORDERS) AS total_104d_107a_actions
      FROM __mine_quarter q
      JOIN __mines d ON q.MINE_ID = d.MINE_ID
      WHERE d.STATE = 'WV' AND q.REPORT_YEAR = 2025
  - name: underground_vs_surface_coal_rates
    question: Compare injury rates for underground vs surface coal mines
    use_as_onboarding_question: true
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT d.MINE_TYPE,
             SUM(q.OPERATOR_INJURIES) * 200000 / NULLIF(SUM(q.OPERATOR_HOURS_WORKED), 0) AS operator_injury_rate_per_200k_hours,
             SUM(q.OPERATOR_INJURIES) AS operator_injuries,
             SUM(q.OPERATOR_HOURS_WORKED) AS operator_hours
      FROM __mine_quarter q
      JOIN __mines d ON q.MINE_ID = d.MINE_ID
      WHERE d.MINE_CATEGORY = 'Coal' AND d.MINE_TYPE IN ('Underground', 'Surface') AND q.REPORT_YEAR BETWEEN 2021 AND 2025
      GROUP BY d.MINE_TYPE
      ORDER BY d.MINE_TYPE
  - name: fatal_accidents_by_classification_2025
    question: How many fatal accidents were there in 2025 by accident classification?
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT a.ACCIDENT_CLASSIFICATION, COUNT(DISTINCT a.ACCIDENT_DOCUMENT_NUMBER) AS fatal_accidents
      FROM __accidents a
      WHERE a.IS_FATAL AND a.ACCIDENT_YEAR = 2025
      GROUP BY a.ACCIDENT_CLASSIFICATION
      ORDER BY fatal_accidents DESC
  - name: coal_ventilation_rate_trend
    question: What is the trend in coal ventilation/methane citations per 200,000 hours?
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT q.REPORT_YEAR, q.IS_PARTIAL_YEAR,
             SUM(q.VENTILATION_METHANE_VIOLATIONS) AS ventilation_methane_citations,
             SUM(q.VENTILATION_METHANE_VIOLATIONS) * 200000 / NULLIF(SUM(q.OPERATOR_HOURS_WORKED), 0) AS ventilation_methane_citations_per_200k_hours
      FROM __mine_quarter q
      JOIN __mines d ON q.MINE_ID = d.MINE_ID
      WHERE d.MINE_CATEGORY = 'Coal' AND q.REPORT_YEAR <= 2025
      GROUP BY q.REPORT_YEAR
      ORDER BY q.REPORT_YEAR
  - name: coal_hazard_ss_2025
    question: Which hazard categories had the most S&S citations at coal mines in 2025?
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT HAZARD_CATEGORY, CFR_REFERENCE,
             SUM(SIGNIFICANT_SUBSTANTIAL_VIOLATIONS) AS ss_citations,
             SUM(VIOLATIONS) AS citations
      FROM __hazard_trends
      WHERE HAZARD_MINE_CATEGORY = 'Coal' AND HAZARD_YEAR = 2025
      GROUP BY HAZARD_CATEGORY, CFR_REFERENCE
      ORDER BY ss_citations DESC
  - name: coal_mines_by_tier
    question: How many coal mines are in each early-warning tier?
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT e.TIER, COUNT(e.MINE_ID) AS mines
      FROM __early_warning e
      JOIN __mines d ON e.MINE_ID = d.MINE_ID
      WHERE d.MINE_CATEGORY = 'Coal'
      GROUP BY e.TIER, e.TIER_RANK
      ORDER BY e.TIER_RANK
  - name: top_coal_penalties_2025
    question: Which coal mines had the highest proposed penalties in 2025?
    verified_at: 1793750400
    verified_by: Evan Engler
    sql: |
      SELECT d.MINE_ID, d.MINE_NAME, d.OPERATOR_NAME, d.STATE,
             SUM(q.PROPOSED_PENALTIES_USD) AS proposed_penalties_usd
      FROM __mine_quarter q
      JOIN __mines d ON q.MINE_ID = d.MINE_ID
      WHERE d.MINE_CATEGORY = 'Coal' AND q.REPORT_YEAR = 2025
      GROUP BY d.MINE_ID, d.MINE_NAME, d.OPERATOR_NAME, d.STATE
      ORDER BY proposed_penalties_usd DESC
      LIMIT 10
$$);
