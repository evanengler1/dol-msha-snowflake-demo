import { DB, handle, mineId, q } from "@/lib/server/db"

export const dynamic = "force-dynamic"

/** Header, quick stats, early-warning card and peers for one mine. */
export async function GET(req: Request) {
  return handle(async () => {
    const id = mineId(new URL(req.url).searchParams.get("id"))
    const [[mine], [ew]] = await Promise.all([
      q(`SELECT * EXCLUDE (search_text) FROM ${DB}.MINE_DIRECTORY WHERE mine_id = ?`, [id]),
      q(`SELECT * FROM ${DB}.MINE_EARLY_WARNING WHERE mine_id = ?`, [id]),
    ])
    if (!mine) return { found: false, mineId: id }
    const [[peers], [operator]] = await Promise.all([
      q(`SELECT * FROM ${DB}.PEER_GROUP_BENCHMARK WHERE peer_group = ?`, [String(mine.peerGroup ?? "")]),
      mine.operatorId
        ? q(
            `SELECT operator_name, mines, mines_with_recent_hours, active_mines, states, last_4q_injury_rate_per_200k_hours,
                    fatalities_since_2020, open_delinquent_penalty_balance_usd
             FROM ${DB}.OPERATOR_PORTFOLIO WHERE operator_id = ?`,
            [String(mine.operatorId)],
          )
        : Promise.resolve([undefined]),
    ])
    return { found: true, mine, earlyWarning: ew ?? null, peers: peers ?? null, operator: operator ?? null }
  })
}
