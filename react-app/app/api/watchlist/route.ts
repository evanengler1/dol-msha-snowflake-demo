import { cached, DB, handle, q } from "@/lib/server/db"
import { checkCategory, checkDistrict, checkOffice } from "@/lib/server/lists"

export const dynamic = "force-dynamic"

/**
 * District watch list from MINE_EARLY_WARNING: tier first, then validated signals in
 * the Highest group, then prior injury rate. Cached 10 minutes per filter combination.
 */
export async function GET(req: Request) {
  return handle(async () => {
    const url = new URL(req.url)
    const district = await checkDistrict(url.searchParams.get("district"))
    const office = await checkOffice(district, url.searchParams.get("office"))
    const category = checkCategory(url.searchParams.get("category"))
    return cached(`watch:${district}:${office}:${category}`, 600_000, async () => {
      const rows = await q(
        `SELECT mine_id, mine_name, mine_category, mine_type, state, district, office_name, current_status,
                operator_name, last_inspection_date, tier, tier_rank, validated_highest_count,
                prior_injury_rate_group, ventilation_methane_group, unwarrantable_imminent_group, high_negligence_group,
                prior_injury_rate_value, last_4q_injuries, last_4q_operator_hours, open_delinquent_penalty_balance_usd,
                tier_reasons
         FROM ${DB}.MINE_EARLY_WARNING
         WHERE (? IS NULL OR district = ?)
           AND (? IS NULL OR office_name = ?)
           AND (? IS NULL OR mine_category = ?)
         ORDER BY tier_rank DESC, validated_highest_count DESC NULLS LAST, prior_injury_rate_value DESC NULLS LAST, mine_name
         LIMIT 2000`,
        [district, district, office, office, category, category],
      )
      return { rows, district, office, category }
    })
  })
}
