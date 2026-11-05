import { BadRequestError, DB, handle, q } from "@/lib/server/db"
import { checkState } from "@/lib/server/lists"

export const dynamic = "force-dynamic"

/** Typeahead over mine name, ID, operator and controller (MINE_DIRECTORY.search_text). */
export async function GET(req: Request) {
  return handle(async () => {
    const url = new URL(req.url)
    const raw = (url.searchParams.get("q") ?? "").trim()
    if (raw.length < 2) throw new BadRequestError("Type at least 2 characters.")
    if (raw.length > 100) throw new BadRequestError("Search is limited to 100 characters.")
    const state = await checkState(url.searchParams.get("state"))
    // LIKE wildcards in user text are matched literally
    const term = raw.toUpperCase().replace(/[\\%_]/g, (c) => `\\${c}`)
    return q(
      `SELECT mine_id, mine_name, state, mine_category, mine_type, operator_name, controller_name,
              current_status, tier, has_recent_hours
       FROM ${DB}.MINE_DIRECTORY
       WHERE search_text LIKE '%' || ? || '%' ESCAPE '\\\\'
         AND (? IS NULL OR state = ?)
       ORDER BY (mine_id = ?) DESC,
                (current_status = 'Active' AND has_recent_hours) DESC,
                tier_rank DESC,
                last_4q_operator_hours DESC NULLS LAST,
                mine_name
       LIMIT 12`,
      [term, state, state, raw],
    )
  })
}
