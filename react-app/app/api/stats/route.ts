import { cached, DB, handle, q } from "@/lib/server/db"

export const dynamic = "force-dynamic"

/** Landing counters + data-as-of. Aggregates only; cached 10 minutes. */
export async function GET() {
  return handle(() =>
    cached("stats", 600_000, async () => {
      const [[m], tiers, [asOf]] = await Promise.all([
        q(`SELECT COUNT(*) AS mines,
                  COUNT_IF(has_recent_hours) AS mines_with_recent_hours,
                  SUM(IFF(has_recent_hours, last_4q_operator_hours, 0)) AS last_4q_operator_hours,
                  SUM(IFF(has_recent_hours, last_4q_ventilation_methane_violations, 0)) AS last_4q_vent_methane,
                  SUM(IFF(has_recent_hours, last_4q_injuries, 0)) AS last_4q_injuries
           FROM ${DB}.MINE_DIRECTORY`),
        q(`SELECT mine_category, tier, COUNT(*) AS mines FROM ${DB}.MINE_EARLY_WARNING GROUP BY 1, 2 ORDER BY 1, 2`),
        q(`SELECT (SELECT MAX(accident_date) FROM ${DB}.ACCIDENT_DETAIL) AS latest_accident_date,
                  (SELECT MAX(IFF(has_hours, year_quarter, NULL)) FROM ${DB}.MINE_QUARTER_TRENDS) AS latest_hours_quarter,
                  (SELECT MIN(IFF(has_hours, year_quarter, NULL)) FROM ${DB}.MINE_QUARTER_TRENDS
                    WHERE quarter_start >= DATEADD(quarter, -4, (SELECT MAX(quarter_start) FROM ${DB}.MINE_QUARTER_TRENDS))) AS l4q_first_quarter`),
      ])
      const elevated = tiers.filter((t) => t.tier === "Elevated").reduce((a, t) => a + Number(t.mines), 0)
      return { ...m, elevated, tiers, ...asOf, queriedAt: new Date().toISOString() }
    }),
  )
}
