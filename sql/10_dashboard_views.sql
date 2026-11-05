-- Phase 3: dashboard support view.
-- PENALTY_OUTCOMES pre-aggregates penalty status straight from TRANSFORMED.VIOLATION.
-- VIOLATION_DETAIL's three LEFT JOINs (mine, inspection, hazard ref) are not pruned by the
-- optimizer, which made a status-only aggregate take ~25s on X-Small; this avoids them.
USE ROLE DOL_MSHA_DEMO_ROLE;
USE WAREHOUSE DOL_MSHA_WH;
USE SCHEMA DOL_MSHA_DEMO.ANALYTICS;

CREATE OR REPLACE VIEW PENALTY_OUTCOMES
COMMENT = 'Penalty dollars by current status (Paid, Open-Delinquent, Uncollectable-Bankrupt, ...), 2010+ violations.'
AS
SELECT
    penalty_status_group                                              AS penalty_status,
    COUNT(*)                                                          AS violations,
    SUM(proposed_penalty)                                             AS proposed_penalties_usd,
    SUM(current_assessment)                                           AS current_assessment_usd,
    SUM(amount_paid)                                                  AS amount_paid_usd,
    SUM(GREATEST(current_assessment - COALESCE(amount_paid, 0), 0))   AS unpaid_usd
FROM DOL_MSHA_DEMO.TRANSFORMED.VIOLATION
GROUP BY 1;
