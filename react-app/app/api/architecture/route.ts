import { cached, DB, handle, q } from "@/lib/server/db"

export const dynamic = "force-dynamic"

/**
 * Live row counts for objects that exist, plus existence flags for the apps and AI
 * objects. Every probe is wrapped: a missing object or a failed SHOW silently falls back
 * to the static description in the UI (never an error, a "not found" or a zero).
 */
export async function GET() {
  return handle(() =>
    cached("architecture", 600_000, async () => {
      const counts: Record<string, number> = {}
      try {
        const rows = await q(
          `SELECT table_schema || '.' || table_name AS name, row_count
           FROM DOL_MSHA_DEMO.INFORMATION_SCHEMA.TABLES
           WHERE table_schema IN ('RAW', 'TRANSFORMED', 'ANALYTICS') AND row_count > 0`,
        )
        for (const r of rows) counts[String(r.name)] = Number(r.rowCount)
      } catch (err) {
        console.warn("[architecture] table counts unavailable", err)
      }

      const exists = async (sql: string) => {
        try {
          return (await q(sql)).length > 0
        } catch {
          return false
        }
      }
      const [semanticView, searchService, agent, dashboard, stage] = await Promise.all([
        exists(`SHOW SEMANTIC VIEWS LIKE 'MSHA_SAFETY_SEMANTIC_VIEW' IN SCHEMA DOL_MSHA_DEMO.ANALYTICS`),
        exists(`SHOW CORTEX SEARCH SERVICES LIKE 'ACCIDENT_NARRATIVE_SEARCH' IN SCHEMA DOL_MSHA_DEMO.ANALYTICS`),
        exists(`SHOW AGENTS LIKE 'MSHA_SAFETY_AGENT' IN SCHEMA DOL_MSHA_DEMO.APPS`),
        exists(`SHOW STREAMLITS LIKE 'MSHA_SAFETY_DASHBOARD' IN SCHEMA DOL_MSHA_DEMO.APPS`),
        exists(`SHOW STAGES IN SCHEMA DOL_MSHA_DEMO.RAW`),
      ])

      let viewCount = 0
      try {
        const [v] = await q(`SELECT COUNT(*) AS n FROM DOL_MSHA_DEMO.INFORMATION_SCHEMA.VIEWS WHERE table_schema = 'ANALYTICS'`)
        viewCount = Number(v?.n ?? 0)
      } catch {
        /* static fallback */
      }

      let narratives = 0
      try {
        const [n] = await q(`SELECT COUNT(*) AS n FROM ${DB}.ACCIDENT_DETAIL WHERE narrative IS NOT NULL`)
        narratives = Number(n?.n ?? 0)
      } catch {
        /* static fallback */
      }

      return { counts, exists: { semanticView, searchService, agent, dashboard, stage }, viewCount, narratives }
    }),
  )
}
