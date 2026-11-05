import { DB, handle, mineIds, q } from "@/lib/server/db"

export const dynamic = "force-dynamic"


/** 2-3 mines side by side: tier, signals, last-4Q metrics and peer percentiles. */
export async function GET(req: Request) {
  return handle(async () => {
    const ids = mineIds(new URL(req.url).searchParams.get("ids"))
    const ph = ids.map(() => "?").join(", ")
    const rows = await q(
      `SELECT d.mine_id, d.mine_name, d.mine_category, d.mine_type, d.state, d.current_status, d.operator_name, d.peer_group,
              d.tier, d.tier_rank, d.last_4q_operator_hours, d.last_4q_injuries, d.last_4q_injury_rate_per_200k_hours,
              d.last_4q_violations, d.last_4q_significant_substantial_violations, d.last_4q_ventilation_methane_violations,
              d.last_4q_unwarrantable_failure_imminent_danger_actions, d.last_4q_high_negligence_violations,
              d.last_4q_proposed_penalties_usd, d.open_delinquent_penalty_balance_usd,
              d.injury_rate_peer_percentile, d.ventilation_methane_peer_percentile, d.unwarrantable_imminent_peer_percentile,
              d.high_negligence_peer_percentile, d.penalties_peer_percentile,
              e.prior_injury_rate_group, e.ventilation_methane_group, e.unwarrantable_imminent_group, e.high_negligence_group,
              e.prior_injury_rate_value, e.ventilation_methane_value, e.unwarrantable_imminent_value, e.high_negligence_value,
              e.tier_reasons
       FROM ${DB}.MINE_DIRECTORY d
       LEFT JOIN ${DB}.MINE_EARLY_WARNING e ON e.mine_id = d.mine_id
       WHERE d.mine_id IN (${ph})`,
      ids,
    )
    // Preserve the order in the URL
    return { rows: ids.map((id) => rows.find((r) => r.mineId === id)).filter(Boolean), missing: ids.filter((id) => !rows.some((r) => r.mineId === id)) }
  })
}
