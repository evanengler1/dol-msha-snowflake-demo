-- =============================================================================
-- 11_app_views.sql  -  Phase 4: views for the Mine Early-Warning App (SAR)
-- Role: DOL_MSHA_DEMO_ROLE  |  Warehouse: DOL_MSHA_WH  |  Schema: ANALYTICS
-- Read-only additions. Does not modify RAW, TRANSFORMED or existing views.
-- The two early-warning objects are Dynamic Tables (FULL refresh, weekly lag to
-- match the portal refresh): as plain views they recompute LEADING_INDICATORS'
-- window functions on every query (~7-10s on X-Small); materialized, profile and
-- watch-list lookups are sub-second.
-- Calibration (2026-11-04, mines with >= 20K l4q hours): Coal Elevated 7.0%,
-- Watch 30.5%; M/NM Elevated 1.0%, Watch 13.9% (only prior injury rate is
-- validated for M/NM). ~70% of mines with recent hours are < 20K hours.
-- =============================================================================
USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE SCHEMA DOL_MSHA_DEMO.ANALYTICS;

-- -----------------------------------------------------------------------------
-- EARLY_WARNING_REFERENCE: Phase 3 evidence, one row per
--   mine category x signal x group (0 = none, 1-4 = quartiles of non-zero values).
-- Cut points: LEADING_INDICATORS assigns quartiles with NTILE(4) over the
--   comparable, non-zero rows within mine category. We take the MAX value of
--   each quartile as its upper bound (ub). A mine's current value v > 0 is
--   placed in the first group whose ub >= v; values above the group-3 ub are 4.
--   This lines a mine up with the evidence bars on the dashboard.
-- Evidence: pooled next-quarter operator injury rate
--   (SUM(injuries) * 200000 / SUM(hours)) and % of mine-quarters with any injury.
-- Validated signals (Phase 3 "holds up" verdicts):
--   Coal: all four.  Metal/Nonmetal: prior injury rate only.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE DYNAMIC TABLE EARLY_WARNING_REFERENCE
TARGET_LAG = DOWNSTREAM
WAREHOUSE = DOL_MSHA_WH
REFRESH_MODE = FULL
COMMENT = 'Phase 3 leading-indicator evidence and quartile cut points by mine category, signal and group. Feeds MINE_EARLY_WARNING.'
AS
WITH li AS (
    SELECT * FROM DOL_MSHA_DEMO.ANALYTICS.LEADING_INDICATORS WHERE is_comparable
),
u AS (
    SELECT mine_category, 'PRIOR_INJURY_RATE' AS signal, prior_injury_rate_quartile AS grp,
           prior_4q_injury_rate_per_200k_hours AS v,
           next_quarter_operator_injuries AS ni, next_quarter_operator_hours AS nh, had_injury_next_quarter AS hi
    FROM li
    UNION ALL
    SELECT mine_category, 'VENTILATION_METHANE', ventilation_methane_quartile,
           prior_4q_ventilation_methane_per_200k_hours,
           next_quarter_operator_injuries, next_quarter_operator_hours, had_injury_next_quarter
    FROM li
    UNION ALL
    SELECT mine_category, 'UNWARRANTABLE_IMMINENT', unwarrantable_imminent_quartile,
           prior_4q_unwarrantable_imminent_per_200k_hours,
           next_quarter_operator_injuries, next_quarter_operator_hours, had_injury_next_quarter
    FROM li
    UNION ALL
    SELECT mine_category, 'HIGH_NEGLIGENCE', high_negligence_quartile,
           prior_4q_high_negligence_per_200k_hours,
           next_quarter_operator_injuries, next_quarter_operator_hours, had_injury_next_quarter
    FROM li
)
SELECT
    mine_category,
    signal,
    grp                                                        AS signal_group,
    COUNT(*)                                                   AS mine_quarters,
    MIN(v)                                                     AS group_min_value,
    MAX(v)                                                     AS group_max_value,
    CAST(SUM(ni) * 200000 / NULLIF(SUM(nh), 0) AS NUMBER(10,2)) AS next_quarter_injury_rate,
    CAST(100 * AVG(IFF(hi, 1, 0)) AS NUMBER(5,1))              AS pct_with_any_injury_next_quarter,
    (signal = 'PRIOR_INJURY_RATE' OR mine_category = 'Coal')   AS is_validated
FROM u
GROUP BY mine_category, signal, grp;

-- -----------------------------------------------------------------------------
-- MINE_EARLY_WARNING: one row per mine with recent hours (MINE_PROFILE.has_recent_hours).
-- Signals = last 4 complete quarters from MINE_PROFILE, per 200K operator hours
--   (same definitions as LEADING_INDICATORS' trailing-4-quarter features).
-- Tier rule (illustrative, NOT an official MSHA rating):
--   Not enough recent hours : < 20,000 operator hours in the last 4 quarters
--   Elevated : >= 2 validated signals in the Highest group (4), OR
--              prior injury rate Highest + >= 1 other signal in group >= 3
--              (coal: the other signal is validated; M/NM: the other signal is a
--               corroborating enforcement signal - see below)
--   Watch    : any validated signal in group >= 3
--   Typical  : everything else
-- Metal/Nonmetal: only prior injury rate is validated, so rule 1 cannot fire.
--   M/NM reaches Elevated only via prior injury rate Highest + a corroborating
--   104(d)/107(a) or high-negligence signal in group >= 3 (ventilation/methane
--   is all-zero for M/NM). Corroborating signals never create Watch on their own.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE MINE_EARLY_WARNING
TARGET_LAG = '7 days'
WAREHOUSE = DOL_MSHA_WH
REFRESH_MODE = FULL
COMMENT = 'Illustrative per-mine early-warning tier (Elevated / Watch / Typical / Not enough recent hours) from the four Phase 3 leading indicators, with evidence and reasons. Not an official MSHA rating.'
AS
WITH ref AS (
    SELECT * FROM DOL_MSHA_DEMO.ANALYTICS.EARLY_WARNING_REFERENCE
),
cut AS (
    SELECT mine_category, signal,
           MAX(IFF(signal_group = 1, group_max_value, NULL)) AS ub1,
           MAX(IFF(signal_group = 2, group_max_value, NULL)) AS ub2,
           MAX(IFF(signal_group = 3, group_max_value, NULL)) AS ub3
    FROM ref GROUP BY 1, 2
),
m AS (
    SELECT p.mine_id, p.mine_name, p.mine_category, p.mine_type, p.state, p.district, p.office_name,
           p.current_status, p.operator_name, p.controller_name, p.peer_group, p.last_inspection_date,
           p.last_4q_operator_hours                                  AS l4q_hours,
           p.last_4q_injuries                                        AS l4q_injuries,
           p.open_delinquent_penalty_balance_usd                     AS open_balance_usd,
           p.last_4q_injuries * 200000 / NULLIF(p.last_4q_operator_hours, 0)                                   AS v_inj,
           p.last_4q_ventilation_methane_violations * 200000 / NULLIF(p.last_4q_operator_hours, 0)             AS v_vent,
           p.last_4q_unwarrantable_failure_imminent_danger_actions * 200000 / NULLIF(p.last_4q_operator_hours, 0) AS v_ufid,
           p.last_4q_high_negligence_violations * 200000 / NULLIF(p.last_4q_operator_hours, 0)                 AS v_hn
    FROM DOL_MSHA_DEMO.ANALYTICS.MINE_PROFILE p
    WHERE p.has_recent_hours
      AND p.mine_category IN ('Coal', 'Metal/Nonmetal')
),
g AS (
    SELECT m.*,
           (m.l4q_hours >= 20000) AS enough_hours,
           CASE WHEN m.v_inj  IS NULL THEN NULL WHEN m.v_inj  = 0 THEN 0 WHEN m.v_inj  <= ci.ub1 THEN 1 WHEN m.v_inj  <= ci.ub2 THEN 2 WHEN m.v_inj  <= ci.ub3 THEN 3 ELSE 4 END AS g_inj,
           CASE WHEN m.v_vent IS NULL THEN NULL WHEN m.v_vent = 0 OR cv.ub1 IS NULL THEN 0 WHEN m.v_vent <= cv.ub1 THEN 1 WHEN m.v_vent <= cv.ub2 THEN 2 WHEN m.v_vent <= cv.ub3 THEN 3 ELSE 4 END AS g_vent,
           CASE WHEN m.v_ufid IS NULL THEN NULL WHEN m.v_ufid = 0 THEN 0 WHEN m.v_ufid <= cu.ub1 THEN 1 WHEN m.v_ufid <= cu.ub2 THEN 2 WHEN m.v_ufid <= cu.ub3 THEN 3 ELSE 4 END AS g_ufid,
           CASE WHEN m.v_hn   IS NULL THEN NULL WHEN m.v_hn   = 0 THEN 0 WHEN m.v_hn   <= ch.ub1 THEN 1 WHEN m.v_hn   <= ch.ub2 THEN 2 WHEN m.v_hn   <= ch.ub3 THEN 3 ELSE 4 END AS g_hn
    FROM m
    LEFT JOIN cut ci ON ci.mine_category = m.mine_category AND ci.signal = 'PRIOR_INJURY_RATE'
    LEFT JOIN cut cv ON cv.mine_category = m.mine_category AND cv.signal = 'VENTILATION_METHANE'
    LEFT JOIN cut cu ON cu.mine_category = m.mine_category AND cu.signal = 'UNWARRANTABLE_IMMINENT'
    LEFT JOIN cut ch ON ch.mine_category = m.mine_category AND ch.signal = 'HIGH_NEGLIGENCE'
),
t AS (
    SELECT g.*,
           (g.mine_category = 'Coal') AS is_coal,
           -- validated signals in the Highest group
           IFF(g.g_inj = 4, 1, 0)
             + IFF(g.mine_category = 'Coal', IFF(g.g_vent = 4, 1, 0) + IFF(g.g_ufid = 4, 1, 0) + IFF(g.g_hn = 4, 1, 0), 0) AS validated_highest_count,
           -- other signals (besides prior injury) in group >= 3
           IFF(g.mine_category = 'Coal' AND g.g_vent >= 3, 1, 0) + IFF(g.g_ufid >= 3, 1, 0) + IFF(g.g_hn >= 3, 1, 0)   AS other_ge3_count,
           -- any validated signal in group >= 3
           (g.g_inj >= 3 OR (g.mine_category = 'Coal' AND (g.g_vent >= 3 OR g.g_ufid >= 3 OR g.g_hn >= 3)))         AS any_validated_ge3
    FROM g
)
SELECT
    t.mine_id, t.mine_name, t.mine_category, t.mine_type, t.state, t.district, t.office_name,
    t.current_status, t.operator_name, t.controller_name, t.peer_group, t.last_inspection_date,
    t.l4q_hours                                    AS last_4q_operator_hours,
    t.l4q_injuries                                 AS last_4q_injuries,
    t.open_balance_usd                             AS open_delinquent_penalty_balance_usd,
    CAST(t.v_inj  AS NUMBER(12,2))                 AS prior_injury_rate_value,
    CAST(t.v_vent AS NUMBER(12,2))                 AS ventilation_methane_value,
    CAST(t.v_ufid AS NUMBER(12,2))                 AS unwarrantable_imminent_value,
    CAST(t.v_hn   AS NUMBER(12,2))                 AS high_negligence_value,
    IFF(t.enough_hours, t.g_inj,  NULL)            AS prior_injury_rate_group,
    IFF(t.enough_hours, t.g_vent, NULL)            AS ventilation_methane_group,
    IFF(t.enough_hours, t.g_ufid, NULL)            AS unwarrantable_imminent_group,
    IFF(t.enough_hours, t.g_hn,   NULL)            AS high_negligence_group,
    IFF(t.enough_hours, t.validated_highest_count, NULL) AS validated_highest_count,
    CASE
        WHEN NOT t.enough_hours THEN 'Not enough recent hours'
        WHEN t.validated_highest_count >= 2
          OR (t.g_inj = 4 AND t.other_ge3_count >= 1) THEN 'Elevated'
        WHEN t.any_validated_ge3 THEN 'Watch'
        ELSE 'Typical'
    END AS tier,
    CASE
        WHEN NOT t.enough_hours THEN 0
        WHEN t.validated_highest_count >= 2 OR (t.g_inj = 4 AND t.other_ge3_count >= 1) THEN 3
        WHEN t.any_validated_ge3 THEN 2
        ELSE 1
    END AS tier_rank,
    -- Reason text, one entry per signal in group >= 3 (validated) or corroborating (M/NM).
    IFF(NOT t.enough_hours,
        ARRAY_CONSTRUCT('Fewer than 20,000 operator hours in the last 4 quarters'),
        ARRAY_CONSTRUCT_COMPACT(
          IFF(t.g_inj >= 3,
              'Prior injury rate: ' || IFF(t.g_inj = 4, 'Highest', 'Med-high') || ' group ('
                || TO_VARCHAR(ri.next_quarter_injury_rate, 'FM990.0') || ' vs ' || TO_VARCHAR(ri0.next_quarter_injury_rate, 'FM990.0')
                || ' for mines with none)', NULL),
          IFF(t.g_vent >= 3,
              'Ventilation/methane citations: ' || IFF(t.g_vent = 4, 'Highest', 'Med-high') || ' group ('
                || TO_VARCHAR(rv.next_quarter_injury_rate, 'FM990.0') || ' vs ' || TO_VARCHAR(rv0.next_quarter_injury_rate, 'FM990.0')
                || ' for mines with none)', NULL),
          IFF(t.g_ufid >= 3,
              '104(d)/107(a) actions: ' || IFF(t.g_ufid = 4, 'Highest', 'Med-high') || ' group ('
                || TO_VARCHAR(ru.next_quarter_injury_rate, 'FM990.0') || ' vs ' || TO_VARCHAR(ru0.next_quarter_injury_rate, 'FM990.0')
                || ' for mines with none)' || IFF(t.is_coal, '', ' - corroborating only for metal/nonmetal'), NULL),
          IFF(t.g_hn >= 3,
              'High-negligence citations: ' || IFF(t.g_hn = 4, 'Highest', 'Med-high') || ' group ('
                || TO_VARCHAR(rh.next_quarter_injury_rate, 'FM990.0') || ' vs ' || TO_VARCHAR(rh0.next_quarter_injury_rate, 'FM990.0')
                || ' for mines with none)' || IFF(t.is_coal, '', ' - corroborating only for metal/nonmetal'), NULL)
        )) AS tier_reasons,
    -- Evidence for the mine's group, per signal (next-quarter rate, % any injury) and the None baseline.
    ri.next_quarter_injury_rate  AS prior_injury_rate_evidence_rate,  ri.pct_with_any_injury_next_quarter AS prior_injury_rate_evidence_pct,  ri0.next_quarter_injury_rate AS prior_injury_rate_baseline_rate,
    rv.next_quarter_injury_rate  AS ventilation_methane_evidence_rate, rv.pct_with_any_injury_next_quarter AS ventilation_methane_evidence_pct, rv0.next_quarter_injury_rate AS ventilation_methane_baseline_rate,
    ru.next_quarter_injury_rate  AS unwarrantable_imminent_evidence_rate, ru.pct_with_any_injury_next_quarter AS unwarrantable_imminent_evidence_pct, ru0.next_quarter_injury_rate AS unwarrantable_imminent_baseline_rate,
    rh.next_quarter_injury_rate  AS high_negligence_evidence_rate,  rh.pct_with_any_injury_next_quarter AS high_negligence_evidence_pct,  rh0.next_quarter_injury_rate AS high_negligence_baseline_rate
FROM t
LEFT JOIN ref ri  ON ri.mine_category  = t.mine_category AND ri.signal  = 'PRIOR_INJURY_RATE'      AND ri.signal_group  = t.g_inj
LEFT JOIN ref ri0 ON ri0.mine_category = t.mine_category AND ri0.signal = 'PRIOR_INJURY_RATE'      AND ri0.signal_group = 0
LEFT JOIN ref rv  ON rv.mine_category  = t.mine_category AND rv.signal  = 'VENTILATION_METHANE'    AND rv.signal_group  = t.g_vent
LEFT JOIN ref rv0 ON rv0.mine_category = t.mine_category AND rv0.signal = 'VENTILATION_METHANE'    AND rv0.signal_group = 0
LEFT JOIN ref ru  ON ru.mine_category  = t.mine_category AND ru.signal  = 'UNWARRANTABLE_IMMINENT' AND ru.signal_group  = t.g_ufid
LEFT JOIN ref ru0 ON ru0.mine_category = t.mine_category AND ru0.signal = 'UNWARRANTABLE_IMMINENT' AND ru0.signal_group = 0
LEFT JOIN ref rh  ON rh.mine_category  = t.mine_category AND rh.signal  = 'HIGH_NEGLIGENCE'        AND rh.signal_group  = t.g_hn
LEFT JOIN ref rh0 ON rh0.mine_category = t.mine_category AND rh0.signal = 'HIGH_NEGLIGENCE'        AND rh0.signal_group = 0;

-- -----------------------------------------------------------------------------
-- MINE_DIRECTORY: join-free, one row per mine (all ~92K): MINE_PROFILE plus the
-- early-warning tier. Backs search, the profile header/quick stats and compare.
-- MINE_PROFILE is a view with peer-percentile windows (~2.7s for one mine);
-- materialized, point lookups and typeahead are sub-second.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE MINE_DIRECTORY
TARGET_LAG = '7 days'
WAREHOUSE = DOL_MSHA_WH
REFRESH_MODE = FULL
COMMENT = 'One row per mine: MINE_PROFILE plus early-warning tier, for app search and profile lookups.'
AS
SELECT p.*,
       COALESCE(e.tier, 'Not enough recent hours') AS tier,
       COALESCE(e.tier_rank, 0)                    AS tier_rank,
       e.validated_highest_count,
       UPPER(p.mine_name || ' ' || p.mine_id || ' ' || COALESCE(p.operator_name, '') || ' ' || COALESCE(p.controller_name, '')) AS search_text
FROM DOL_MSHA_DEMO.ANALYTICS.MINE_PROFILE p
LEFT JOIN DOL_MSHA_DEMO.ANALYTICS.MINE_EARLY_WARNING e ON e.mine_id = p.mine_id;

-- -----------------------------------------------------------------------------
-- PEER_GROUP_BENCHMARK: one row per peer_group (category | type | size band).
-- Peers = mines in the group with last-4Q operator hours > 0.
-- Rates are pooled across peer mines (SUM(x) * 200000 / SUM(hours));
-- counts and dollars are per-mine averages (SUM / mines), never sums of rates.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE DYNAMIC TABLE PEER_GROUP_BENCHMARK
TARGET_LAG = '7 days'
WAREHOUSE = DOL_MSHA_WH
REFRESH_MODE = FULL
COMMENT = 'Peer group benchmarks: pooled last-4Q rates and per-mine averages among mines with recent hours.'
AS
SELECT peer_group,
       COUNT(*)                                                             AS peer_mines,
       SUM(last_4q_operator_hours) / COUNT(*)                               AS avg_operator_hours,
       SUM(last_4q_injuries) / COUNT(*)                                     AS avg_injuries,
       SUM(last_4q_injuries) * 200000 / NULLIF(SUM(last_4q_operator_hours), 0) AS pooled_injury_rate,
       SUM(last_4q_violations) / COUNT(*)                                   AS avg_violations,
       SUM(last_4q_significant_substantial_violations) / COUNT(*)           AS avg_ss_violations,
       SUM(last_4q_significant_substantial_violations) / NULLIF(SUM(last_4q_violations), 0) AS pooled_ss_share,
       SUM(last_4q_ventilation_methane_violations) / COUNT(*)               AS avg_vent_methane,
       SUM(last_4q_ventilation_methane_violations) * 200000 / NULLIF(SUM(last_4q_operator_hours), 0) AS pooled_vent_methane_per_200k,
       SUM(last_4q_unwarrantable_failure_imminent_danger_actions) / COUNT(*) AS avg_104d_107a,
       SUM(last_4q_unwarrantable_failure_imminent_danger_actions) * 200000 / NULLIF(SUM(last_4q_operator_hours), 0) AS pooled_104d_107a_per_200k,
       SUM(last_4q_high_negligence_violations) / COUNT(*)                   AS avg_high_negligence,
       SUM(last_4q_high_negligence_violations) * 200000 / NULLIF(SUM(last_4q_operator_hours), 0) AS pooled_high_negligence_per_200k,
       SUM(last_4q_proposed_penalties_usd) / COUNT(*)                       AS avg_proposed_penalties_usd,
       SUM(open_delinquent_penalty_balance_usd) / COUNT(*)                  AS avg_open_balance_usd
FROM DOL_MSHA_DEMO.ANALYTICS.MINE_PROFILE
WHERE last_4q_operator_hours > 0
GROUP BY peer_group;
