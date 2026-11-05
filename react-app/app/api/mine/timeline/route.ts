import { DB, handle, mineId, q } from "@/lib/server/db"

export const dynamic = "force-dynamic"

/** Quarterly timeline since 2010 Q1 from MINE_QUARTER_TRENDS. Rates only where hours exist. */
export async function GET(req: Request) {
  return handle(async () => {
    const id = mineId(new URL(req.url).searchParams.get("id"))
    return q(
      `SELECT year_quarter, quarter_start, year, operator_injuries, operator_hours_worked, has_hours, is_partial_period,
              IFF(has_hours AND operator_hours_worked > 0, operator_injury_rate_per_200k_hours, NULL) AS injury_rate,
              fatalities, violations, significant_substantial_violations, ventilation_methane_violations,
              unwarrantable_failure_actions + imminent_danger_orders AS actions_104d_107a,
              high_negligence_violations, inspections, proposed_penalties_usd
       FROM ${DB}.MINE_QUARTER_TRENDS
       WHERE mine_id = ? AND quarter_start >= '2010-01-01'
       ORDER BY quarter_start`,
      [id],
    )
  })
}
