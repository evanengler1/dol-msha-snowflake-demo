import "server-only"
import { BadRequestError, cached, DB, q } from "@/lib/server/db"

export const CATEGORIES = ["Coal", "Metal/Nonmetal"] as const

export interface Lists {
  districts: { district: string; mines: number }[]
  offices: { district: string; officeName: string; mines: number }[]
  states: string[]
}

/** Allow-lists for watch-list and search filters, queried once and cached for an hour. */
export function getLists(): Promise<Lists> {
  return cached("lists", 3_600_000, async () => {
    const [districts, offices, states] = await Promise.all([
      q(`SELECT district, COUNT(*) AS mines FROM ${DB}.MINE_EARLY_WARNING WHERE district IS NOT NULL GROUP BY 1 ORDER BY 1`),
      q(`SELECT district, office_name, COUNT(*) AS mines FROM ${DB}.MINE_EARLY_WARNING
         WHERE district IS NOT NULL AND office_name IS NOT NULL GROUP BY 1, 2 ORDER BY 1, 2`),
      q(`SELECT DISTINCT state FROM ${DB}.MINE_DIRECTORY WHERE state IS NOT NULL ORDER BY 1`),
    ])
    return {
      districts: districts as Lists["districts"],
      offices: offices as Lists["offices"],
      states: states.map((r) => String(r.state)),
    }
  })
}

export async function checkDistrict(v: string | null): Promise<string | null> {
  if (!v) return null
  const { districts } = await getLists()
  if (!districts.some((d) => d.district === v)) throw new BadRequestError("Unknown MSHA district.")
  return v
}

export async function checkOffice(district: string | null, v: string | null): Promise<string | null> {
  if (!v) return null
  const { offices } = await getLists()
  if (!offices.some((o) => o.officeName === v && (!district || o.district === district)))
    throw new BadRequestError("Unknown field office for this district.")
  return v
}

export function checkCategory(v: string | null): string | null {
  if (!v || v === "All") return null
  if (!(CATEGORIES as readonly string[]).includes(v)) throw new BadRequestError("Category must be Coal or Metal/Nonmetal.")
  return v
}

export async function checkState(v: string | null): Promise<string | null> {
  if (!v) return null
  const { states } = await getLists()
  if (!states.includes(v)) throw new BadRequestError("Unknown state.")
  return v
}
