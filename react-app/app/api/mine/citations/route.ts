import { DB, handle, mineId, q } from "@/lib/server/db"

export const dynamic = "force-dynamic"

/**
 * Citations by hazard category (compliance proxies) and the most recent serious
 * citations. VIOLATION_DETAIL is always filtered by mine_id and aggregated here.
 */
export async function GET(req: Request) {
  return handle(async () => {
    const id = mineId(new URL(req.url).searchParams.get("id"))
    const [byCategory, recent] = await Promise.all([
      q(
        `SELECT COALESCE(hazard_category, 'Other / Unknown') AS hazard_category,
                COUNT(*) AS citations,
                COUNT_IF(issue_date >= DATEADD(year, -1, (SELECT MAX(issue_date) FROM ${DB}.VIOLATION_DETAIL WHERE mine_id = ?))) AS last_12_months,
                COUNT_IF(is_significant_substantial) AS significant_substantial,
                COUNT_IF(is_unwarrantable_failure OR is_imminent_danger) AS actions_104d_107a,
                SUM(COALESCE(proposed_penalty_usd, 0)) AS proposed_penalties_usd
         FROM ${DB}.VIOLATION_DETAIL
         WHERE mine_id = ?
         GROUP BY 1
         ORDER BY citations DESC`,
        [id, id],
      ),
      q(
        `SELECT violation_number, issue_date, cfr_part_section, hazard_category, enforcement_action, citation_or_order,
                is_significant_substantial, is_unwarrantable_failure, is_imminent_danger, is_high_negligence,
                negligence, likelihood, proposed_penalty_usd, penalty_status
         FROM ${DB}.VIOLATION_DETAIL
         WHERE mine_id = ?
           AND (is_unwarrantable_failure OR is_imminent_danger OR is_high_negligence OR is_significant_substantial)
         ORDER BY issue_date DESC, violation_number DESC
         LIMIT 15`,
        [id],
      ),
    ])
    return { byCategory, recent }
  })
}
