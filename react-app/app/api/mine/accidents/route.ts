import { DB, handle, mineId, offset, q } from "@/lib/server/db"

export const dynamic = "force-dynamic"

const PAGE = 20

/** Accident list for one mine, most recent first, paged. One row per injured person. */
export async function GET(req: Request) {
  return handle(async () => {
    const url = new URL(req.url)
    const id = mineId(url.searchParams.get("id"))
    const off = offset(url.searchParams.get("offset"))
    const [rows, [count]] = await Promise.all([
      q(
        `SELECT accident_document_number, accident_date, degree_of_injury, is_fatal, is_lost_time_injury,
                is_contractor_employee, accident_classification, accident_type, occupation, mining_equipment,
                nature_of_injury, body_part_injured, days_lost, is_ignition_explosion_fire, narrative
         FROM ${DB}.ACCIDENT_DETAIL
         WHERE mine_id = ?
         ORDER BY accident_date DESC, accident_document_number DESC
         LIMIT ${PAGE} OFFSET ?`,
        [id, off],
      ),
      q(`SELECT COUNT(*) AS total FROM ${DB}.ACCIDENT_DETAIL WHERE mine_id = ?`, [id]),
    ])
    return { rows, total: Number(count?.total ?? 0), offset: off, pageSize: PAGE }
  })
}
