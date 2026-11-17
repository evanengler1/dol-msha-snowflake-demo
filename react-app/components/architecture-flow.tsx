"use client"

import { memo, useMemo, useState } from "react"
import { AnimatePresence, motion, useReducedMotion } from "framer-motion"
import { X } from "lucide-react"
import { fmt, useApi } from "@/lib/client"
import { CountUp, Skeleton } from "@/components/kit"

export interface ArchStats {
  counts: Record<string, number>
  exists: { semanticView: boolean; searchService: boolean; agent: boolean; dashboard: boolean; stage: boolean }
  viewCount: number
  narratives: number
}

type Col = 0 | 1 | 2 | 3 | 4 | 5
/** A stat is either a live count (shown only when > 0) or a static description. */
type Stat = { k: string; live?: (s: ArchStats) => number | undefined; text: string }

interface N {
  id: string
  col: Col
  title: string
  sub: string
  what: string
  why: string
  objects: string[]
  stats: Stat[]
  code: string
}

const c = (key: string) => (s: ArchStats) => s.counts[key]
const sum = (...keys: string[]) => (s: ArchStats) => keys.reduce((a, k) => a + Number(s.counts[k] ?? 0), 0)

export const NODES: N[] = [
  {
    id: "portal",
    col: 0,
    title: "DOL Open Data Portal",
    sub: "14 MSHA datasets",
    what: "Fourteen public MSHA datasets: Accident, Mines, Inspection, Violation, Assessed Violations, Operator and Contractor Employment/Production (quarterly and annual), operator, contractor and controller history, and lookups.",
    why: "The single public source of record for mine safety enforcement. It refreshes weekly. It has no methane, temperature or sensor readings, so the platform answers with compliance proxies.",
    objects: ["Accident (10341)", "Mines (10350)", "Inspection (10349)", "Violation (10355)", "Assessed Violations (10343)", "Operator Employment/Production (10353, 10348)"],
    stats: [
      { k: "Datasets", text: "14 MSHA datasets" },
      { k: "Refresh", text: "Weekly on the portal" },
      { k: "Sensor data", text: "None in the portal; compliance proxies instead" },
    ],
    code: "https://data.dol.gov/data-catalog/MSHA/{name}/MSHA_{name}.zip",
  },
  {
    id: "extract",
    col: 1,
    title: "Python extractor",
    sub: "Portal ZIPs → gzip CSV",
    what: "Streams every CSV inside each portal ZIP, filters the seven fact tables to 2010 and later, lowercases column names and writes one gzip CSV per dataset.",
    why: "Keeps the load reproducible and portal-only: no hand edits, no synthetic rows.",
    objects: ["process_msha_data.py"],
    stats: [
      { k: "Facts", text: "Filtered to 2010+" },
      { k: "Output", text: "One gzip CSV per dataset" },
    ],
    code: "# process_msha_data.py\n# 1. read each CSV chunk in data/MSHA_{api_name}.zip\n# 2. keep 2010+ for the 7 fact tables\n# 3. write output/msha-raw/{api_name}/{api_name}.csv.gz (or upload to S3)",
  },
  {
    id: "s3",
    col: 1,
    title: "Stage",
    sub: "Internal stage or S3",
    what: "Landing area for the compressed extracts, one folder per dataset. An internal stage needs no cloud setup; S3 works through a storage integration.",
    why: "Snowflake reads the files in place, so no credentials live in SQL.",
    objects: ["msha-raw/accident/", "msha-raw/violation/", "msha-raw/mines/"],
    stats: [{ k: "Format", text: "gzip CSV with header row" }],
    code: "PUT file://output/msha-raw/accident/accident.csv.gz\n    @MSHA_RAW_STAGE/accident/ AUTO_COMPRESS = FALSE;",
  },
  {
    id: "stage",
    col: 1,
    title: "COPY INTO",
    sub: "MSHA_RAW_STAGE",
    what: "COPY INTO each RAW.MSHA_* table from the stage, matched by column name with load metadata. Accounts that already hold MSHA tables fill RAW with a column-matching procedure instead.",
    why: "Bulk loads are rerunnable and auditable: every row carries its source file and load time.",
    objects: ["RAW.MSHA_RAW_STAGE", "RAW.MSHA_CSV_GZ", "RAW.LOAD_RAW_FROM_TABLE"],
    stats: [{ k: "Raw tables", text: "14 RAW.MSHA_* tables" }],
    code: "CREATE STAGE IF NOT EXISTS MSHA_RAW_STAGE\n    FILE_FORMAT = MSHA_CSV_GZ;\n\nCOPY INTO MSHA_ACCIDENT\n    FROM @MSHA_RAW_STAGE/accident/\n    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE\n    INCLUDE_METADATA = (_source_file = METADATA$FILENAME,\n                        _loaded_at = METADATA$START_SCAN_TIME);",
  },
  {
    id: "raw",
    col: 1,
    title: "RAW schema",
    sub: "RAW.MSHA_* · 14 tables",
    what: "Portal columns as text, exactly as published, plus _source_file and _loaded_at.",
    why: "An untouched copy of the source makes every downstream number traceable.",
    objects: ["RAW.MSHA_ACCIDENT", "RAW.MSHA_VIOLATION", "RAW.MSHA_INSPECTION", "RAW.MSHA_MINES", "RAW.MSHA_ASSESSED_VIOLATIONS"],
    stats: [
      { k: "RAW.MSHA_VIOLATION", live: c("RAW.MSHA_VIOLATION"), text: "1.79M violations" },
      { k: "RAW.MSHA_ASSESSED_VIOLATIONS", live: c("RAW.MSHA_ASSESSED_VIOLATIONS"), text: "Assessed penalties" },
      { k: "RAW.MSHA_ACCIDENT", live: c("RAW.MSHA_ACCIDENT"), text: "Accident reports" },
      { k: "RAW.MSHA_MINES", live: c("RAW.MSHA_MINES"), text: "92K mines" },
    ],
    code: "SELECT COUNT(*) FROM DOL_MSHA_DEMO.RAW.MSHA_VIOLATION;",
  },
  {
    id: "typed",
    col: 2,
    title: "Typed tables + UDFs",
    sub: "MINE, ACCIDENT, VIOLATION",
    what: "Cleaned, typed tables for mines, accidents, inspections, violations, employment and history, built with small SQL UDFs that normalize the portal's null markers, dates and numbers.",
    why: "One consistent, typed model every view reads from.",
    objects: ["TRANSFORMED.MINE", "TRANSFORMED.ACCIDENT", "TRANSFORMED.VIOLATION", "TRANSFORMED.EMPLOYMENT_QUARTERLY", "CLEAN_STR / CLEAN_DATE / CLEAN_NUM"],
    stats: [
      { k: "TRANSFORMED.VIOLATION", live: c("TRANSFORMED.VIOLATION"), text: "Typed violations" },
      { k: "TRANSFORMED.EMPLOYMENT_QUARTERLY", live: c("TRANSFORMED.EMPLOYMENT_QUARTERLY"), text: "Quarterly hours" },
      { k: "TRANSFORMED.MINE", live: c("TRANSFORMED.MINE"), text: "Mines" },
    ],
    code: "CREATE OR REPLACE FUNCTION CLEAN_STR(s VARCHAR)\nRETURNS VARCHAR\nAS $$ NULLIF(NULLIF(NULLIF(TRIM(s), ''), 'NaT'), 'nan') $$;",
  },
  {
    id: "hazard",
    col: 2,
    title: "Hazard-category reference",
    sub: "30 CFR → compliance proxy",
    what: "Maps each cited 30 CFR part and section to a hazard category: ventilation and methane (75 Subpart D), combustible material and rock dust, electrical and permissibility, roof and rib, respirable dust, and more.",
    why: "It turns citations into the methane and ventilation proxies DOL asked about, and says plainly that they are compliance proxies.",
    objects: ["TRANSFORMED.HAZARD_CATEGORY_REF"],
    stats: [{ k: "TRANSFORMED.HAZARD_CATEGORY_REF", live: c("TRANSFORMED.HAZARD_CATEGORY_REF"), text: "Hazard categories" }],
    code: "CREATE OR REPLACE TABLE HAZARD_CATEGORY_REF (\n    category_code VARCHAR(30),\n    label         VARCHAR(60),\n    cfr_reference VARCHAR(80),\n    match_rule    VARCHAR(120),\n    description   VARCHAR(300),\n    sort_order    NUMBER(3)\n) AS SELECT * FROM VALUES ...;",
  },
  {
    id: "mqf",
    col: 2,
    title: "MINE_QUARTER_FACT",
    sub: "Mine × quarter, lagged",
    what: "One row per mine per quarter from 2010 Q1 to 2026 Q2: injuries, hours, citations by category, serious enforcement and penalties, with trailing-4-quarter features and the next quarter's outcome.",
    why: "The grain for pooled rates (SUM(injuries) × 200,000 / SUM(hours)) and for testing which signals come before injuries.",
    objects: ["TRANSFORMED.MINE_QUARTER_FACT", "TRANSFORMED.MINE_QUARTER_FEATURES"],
    stats: [
      { k: "TRANSFORMED.MINE_QUARTER_FACT", live: c("TRANSFORMED.MINE_QUARTER_FACT"), text: "Mine-quarters" },
      { k: "Range", text: "2010 Q1 to 2026 Q2 (2026 partial)" },
    ],
    code: "-- 06_mine_quarter_fact.sql: MINE_QUARTER_FEATURES\nSUM(ventilation_methane_violations) OVER (\n    PARTITION BY mine_id ORDER BY quarter_start\n    ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING)\n  AS t4q_ventilation_methane_violations,\nSUM(unwarrantable_failure_actions + imminent_danger_orders) OVER (\n    PARTITION BY mine_id ORDER BY quarter_start\n    ROWS BETWEEN 4 PRECEDING AND 1 PRECEDING)\n  AS t4q_104d_107a_actions",
  },
  {
    id: "trends",
    col: 3,
    title: "Trend views",
    sub: "National, state, hazard",
    what: "Industry trends by year, state, hazard category and accident pattern, with an explicit category filter on every rollup.",
    why: "Feeds the dashboard's national picture and the agent's trend questions.",
    objects: ["ANALYTICS.NATIONAL_TRENDS", "ANALYTICS.STATE_TRENDS", "ANALYTICS.HAZARD_TRENDS", "ANALYTICS.ACCIDENT_PATTERNS"],
    stats: [{ k: "Basis", text: "Pooled operator rates per 200K hours" }],
    code: "SELECT year, mine_category, operator_injury_rate_per_200k_hours\nFROM DOL_MSHA_DEMO.ANALYTICS.NATIONAL_TRENDS\nWHERE mine_category = 'Coal';",
  },
  {
    id: "detail",
    col: 3,
    title: "Detail views",
    sub: "Accidents, violations",
    what: "Person-level accidents with narratives, every violation with its hazard category and penalty status, and the per-mine quarterly timeline.",
    why: "The evidence behind every briefing: what happened, what was cited, and when.",
    objects: ["ANALYTICS.ACCIDENT_DETAIL", "ANALYTICS.VIOLATION_DETAIL", "ANALYTICS.MINE_QUARTER_TRENDS"],
    stats: [
      { k: "Accident narratives", live: (s) => s.narratives, text: "Accident narratives" },
      { k: "Violations", live: c("TRANSFORMED.VIOLATION"), text: "1.79M violations" },
    ],
    code: "SELECT hazard_category, COUNT(*)\nFROM DOL_MSHA_DEMO.ANALYTICS.VIOLATION_DETAIL\nWHERE mine_id = ?\nGROUP BY 1;",
  },
  {
    id: "leading",
    col: 3,
    title: "LEADING_INDICATORS",
    sub: "Prior 4Q vs next quarter",
    what: "Each mine-quarter's trailing signals next to the following quarter's injuries, grouped into None plus quartiles within mine category.",
    why: "It shows which past signals are associated with next-quarter injuries. For coal, four rise steadily from None to Highest; S&S share and inspection intensity do not. Associations only, not causal or tested out of sample.",
    objects: ["ANALYTICS.LEADING_INDICATORS"],
    stats: [
      { k: "Coal: prior injury rate", text: "1.4 → 7.2 next-quarter injuries per 200K hrs" },
      { k: "Coal: vent/methane citations", text: "1.5 → 5.7" },
    ],
    code: "IFF(t4q_ventilation_per_200k_hours = 0, 0,\n    NTILE(4) OVER (PARTITION BY is_comparable, coal_metal,\n        t4q_ventilation_per_200k_hours > 0\n        ORDER BY t4q_ventilation_per_200k_hours))\n    AS ventilation_methane_quartile",
  },
  {
    id: "profile",
    col: 3,
    title: "Mine profile + portfolio",
    sub: "Profile, peers, operators",
    what: "One row per mine with last-4-quarter indicators, peer group, peer percentiles and trends; operator portfolios; penalty outcomes.",
    why: "Every mine's inputs in one place, with fair peer groups: same category, mine type and size band.",
    objects: ["ANALYTICS.MINE_PROFILE", "ANALYTICS.OPERATOR_PORTFOLIO", "ANALYTICS.PENALTY_OUTCOMES", "ANALYTICS.MINE_DIRECTORY", "ANALYTICS.PEER_GROUP_BENCHMARK"],
    stats: [
      { k: "ANALYTICS.MINE_DIRECTORY", live: c("ANALYTICS.MINE_DIRECTORY"), text: "92K mines" },
      { k: "ANALYTICS.PEER_GROUP_BENCHMARK", live: c("ANALYTICS.PEER_GROUP_BENCHMARK"), text: "Peer groups" },
    ],
    code: "SELECT peer_group,\n       SUM(last_4q_injuries) * 200000\n         / NULLIF(SUM(last_4q_operator_hours), 0) AS pooled_injury_rate\nFROM DOL_MSHA_DEMO.ANALYTICS.MINE_PROFILE\nWHERE last_4q_operator_hours > 0\nGROUP BY peer_group;",
  },
  {
    id: "ew",
    col: 3,
    title: "MINE_EARLY_WARNING",
    sub: "Dynamic Table · weekly",
    what: "One row per mine with recent hours: the four screened signals, their leading-indicator group, the evidence behind each group, an illustrative tier and plain-English reasons.",
    why: "The tier lives in SQL so the watch list can rank thousands of mines in milliseconds, and every app reads the same answer.",
    objects: ["ANALYTICS.MINE_EARLY_WARNING", "ANALYTICS.EARLY_WARNING_REFERENCE"],
    stats: [
      { k: "Mines rated or screened", live: c("ANALYTICS.MINE_EARLY_WARNING"), text: "Mines with recent hours" },
      { k: "Evidence rows", live: c("ANALYTICS.EARLY_WARNING_REFERENCE"), text: "Category × signal × group" },
    ],
    code: "CREATE OR REPLACE DYNAMIC TABLE MINE_EARLY_WARNING\nTARGET_LAG = '7 days' WAREHOUSE = DOL_MSHA_WH REFRESH_MODE = FULL\nAS ...\n  CASE WHEN NOT enough_hours THEN 'Not enough recent hours'\n       WHEN validated_highest_count >= 2\n         OR (g_inj = 4 AND other_ge3_count >= 1) THEN 'Elevated'\n       WHEN any_validated_ge3 THEN 'Watch'\n       ELSE 'Typical' END AS tier",
  },
  {
    id: "sv",
    col: 4,
    title: "Semantic view",
    sub: "MSHA_SAFETY_SEMANTIC_VIEW",
    what: "Business definitions over the analytics views: metrics such as pooled injury rate, fatalities and citations per 200K hours; dimensions such as mine, operator, state, district, hazard category and quarter.",
    why: "Cortex Analyst turns plain-English questions into governed SQL that uses the same rate rules as the apps.",
    objects: ["ANALYTICS.MSHA_SAFETY_SEMANTIC_VIEW"],
    stats: [
      { k: "Metrics", text: "Pooled injury rate, fatalities, citations per 200K hrs" },
      { k: "Dimensions", text: "Mine, operator, state, district, hazard category, quarter" },
    ],
    code: "CREATE SEMANTIC VIEW ANALYTICS.MSHA_SAFETY_SEMANTIC_VIEW\n  TABLES (...)\n  METRICS (\n    injury_rate AS SUM(injuries) * 200000 / NULLIF(SUM(hours), 0), ...)\n  DIMENSIONS (mine, operator, state, district, hazard_category, quarter);",
  },
  {
    id: "search",
    col: 4,
    title: "Cortex Search",
    sub: "Accident narratives",
    what: "A hybrid keyword and vector search service over accident narratives, filterable by mine, state, category and classification.",
    why: "Finds accidents by what happened, such as roof falls involving continuous miners, not just by code.",
    objects: ["ANALYTICS.ACCIDENT_NARRATIVE_SEARCH"],
    stats: [{ k: "Indexed narratives", live: (s) => s.narratives, text: "Accident narratives indexed for search" }],
    code: "CREATE CORTEX SEARCH SERVICE ANALYTICS.ACCIDENT_NARRATIVE_SEARCH\n  ON narrative\n  ATTRIBUTES mine_id, state, mine_category, accident_classification\n  WAREHOUSE = DOL_MSHA_WH TARGET_LAG = '7 days'\n  AS SELECT ... FROM ANALYTICS.ACCIDENT_DETAIL;",
  },
  {
    id: "dash",
    col: 5,
    title: "MSHA Safety Dashboard",
    sub: "Streamlit in Snowflake",
    what: "Industry trends, ventilation and methane proxies, leading-indicator evidence, a state map and operator portfolios.",
    why: "Answers where and why miners are getting hurt, and what comes first.",
    objects: ["APPS.MSHA_SAFETY_DASHBOARD"],
    stats: [
      { k: "Runtime", text: "Streamlit in Snowflake, container runtime" },
      { k: "Pages", text: "Overview, Vent/Methane proxy, Leading Indicators, Map + Operators" },
    ],
    code: "snow streamlit deploy --replace\n  # DOL_MSHA_DEMO.APPS.MSHA_SAFETY_DASHBOARD",
  },
  {
    id: "app",
    col: 5,
    title: "Mine Early-Warning App",
    sub: "Snowflake App Runtime",
    what: "This app: per-mine briefings, the early-warning tier with its evidence, district watch lists and side-by-side comparison. Next.js running inside Snowflake.",
    why: "Puts the screened indicators in an inspector's hands before a visit, with no data leaving Snowflake.",
    objects: ["APPS.MSHA_EARLY_WARNING_APP"],
    stats: [
      { k: "Runtime", text: "Next.js on Snowflake App Runtime (SPCS)" },
      { k: "Access", text: "Read-only, snowflake-sdk with bound parameters" },
    ],
    code: "SELECT * FROM DOL_MSHA_DEMO.ANALYTICS.MINE_EARLY_WARNING\nWHERE (? IS NULL OR district = ?)\nORDER BY tier_rank DESC, validated_highest_count DESC;",
  },
  {
    id: "agent",
    col: 5,
    title: "MSHA Safety Agent",
    sub: "Cortex Agent · CoWork",
    what: "A Cortex Agent in Snowflake CoWork that combines Cortex Analyst over the semantic view with Cortex Search over accident narratives.",
    why: "Anyone can ask \"Which coal mines in District 4 had the most ventilation citations last year?\" or \"Find roof-fall accidents involving continuous miners\" and get a governed, cited answer.",
    objects: ["APPS.MSHA_SAFETY_AGENT"],
    stats: [
      { k: "Tools", text: "Cortex Analyst + Cortex Search" },
      { k: "Surface", text: "Snowflake CoWork" },
    ],
    code: "CREATE AGENT APPS.MSHA_SAFETY_AGENT\n  FROM SPECIFICATION $$\n  tools:\n    - analyst: ANALYTICS.MSHA_SAFETY_SEMANTIC_VIEW\n    - search:  ANALYTICS.ACCIDENT_NARRATIVE_SEARCH\n  $$;",
  },
]

const EDGES: [string, string][] = [
  ["portal", "extract"], ["extract", "s3"], ["s3", "stage"], ["stage", "raw"],
  ["raw", "typed"], ["raw", "hazard"], ["typed", "mqf"], ["hazard", "mqf"],
  ["typed", "detail"], ["hazard", "detail"], ["mqf", "trends"], ["mqf", "leading"], ["mqf", "profile"], ["mqf", "detail"],
  ["leading", "ew"], ["profile", "ew"],
  ["trends", "sv"], ["profile", "sv"], ["detail", "sv"], ["detail", "search"],
  ["trends", "dash"], ["leading", "dash"], ["profile", "dash"],
  ["ew", "app"], ["profile", "app"], ["detail", "app"],
  ["sv", "agent"], ["search", "agent"],
]

const LAYERS = ["SOURCE", "INGESTION", "TRANSFORMED", "ANALYTICS", "SEMANTIC & AI", "APPLICATIONS"]

/* ---------- layout ---------- */

const W = 1240
const COLX = [12, 216, 420, 624, 840, 1040]
const NODE_W = 188
const NODE_H = 58
const GAP = 14
const TOP = 40

function layout() {
  const pos: Record<string, { x: number; y: number; w: number; h: number }> = {}
  const tallest = Math.max(...[0, 1, 2, 3, 4, 5].map((col) => NODES.filter((n) => n.col === col).length))
  const fullH = tallest * NODE_H + (tallest - 1) * GAP
  for (const col of [0, 1, 2, 3, 4, 5] as Col[]) {
    const items = NODES.filter((n) => n.col === col)
    const h = items.length * NODE_H + (items.length - 1) * GAP
    let y = TOP + (fullH - h) / 2
    for (const n of items) {
      pos[n.id] = { x: COLX[col], y, w: NODE_W, h: NODE_H }
      y += NODE_H + GAP
    }
  }
  return { pos, height: TOP + fullH + 24 }
}

function edgePath(a: { x: number; y: number; w: number; h: number }, b: { x: number; y: number; w: number; h: number }) {
  if (a.x === b.x) {
    const adjacent = Math.abs(b.y - a.y) <= NODE_H + GAP + 1
    if (adjacent) {
      // Neighbors in a column (ingestion chain): straight down
      const x = a.x + a.w / 2
      return `M${x},${a.y + a.h} L${x},${b.y}`
    }
    // Skip over the node in between: loop out the right side
    const x = a.x + a.w, y1 = a.y + a.h / 2, y2 = b.y + b.h / 2
    const bulge = 22 + Math.abs(y2 - y1) * 0.06
    return `M${x},${y1} C${x + bulge},${y1} ${x + bulge},${y2} ${x},${y2}`
  }
  const x1 = a.x + a.w, y1 = a.y + a.h / 2, x2 = b.x, y2 = b.y + b.h / 2
  const mx = (x1 + x2) / 2
  return `M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}`
}

export function lineage(id: string) {
  const up = new Set<string>(), down = new Set<string>()
  const walk = (cur: string, dir: "up" | "down") => {
    for (const [a, b] of EDGES) {
      const next = dir === "down" ? (a === cur ? b : null) : b === cur ? a : null
      const set = dir === "down" ? down : up
      if (next && !set.has(next)) {
        set.add(next)
        walk(next, dir)
      }
    }
  }
  walk(id, "up")
  walk(id, "down")
  return new Set([id, ...up, ...down])
}

/** Live count when the object exists and has rows; otherwise the static text. Never a zero or an error. */
export function statValue(st: Stat, s: ArchStats | undefined): { live: number | null; text: string } {
  const v = s && st.live ? Number(st.live(s) ?? 0) : 0
  return v > 0 ? { live: v, text: st.text } : { live: null, text: st.text }
}

/* ---------- component ---------- */

export const ArchitectureFlow = memo(function ArchitectureFlow() {
  const stats = useApi<ArchStats>("/api/architecture", { staleTime: 300_000 })
  const reduce = useReducedMotion()
  const { pos, height } = useMemo(layout, [])
  const [hover, setHover] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const focus = hover ?? selected
  const active = focus ? lineage(focus) : null
  const node = NODES.find((n) => n.id === selected)

  return (
    <div className="relative">
      <div className="card relative overflow-hidden">
        <div className="dot-grid pointer-events-none absolute inset-0 opacity-40" />
        <div className="overflow-x-auto">
          <svg viewBox={`0 0 ${W} ${height}`} className="relative h-auto w-full min-w-[980px] select-none" role="img" aria-label="End-to-end architecture lineage">
            <defs>
              <linearGradient id="edge-lit" x1="0" x2="1">
                <stop offset="0" stopColor="#0e7c7b" />
                <stop offset="1" stopColor="#0b2545" />
              </linearGradient>
            </defs>
            {LAYERS.map((l, i) => (
              <text key={l} x={COLX[i]} y={22} className="mono" fontSize={10.5} letterSpacing="0.1em" fill="#8a8a90">
                {l}
              </text>
            ))}
            {EDGES.map(([a, b], i) => {
              const pa = pos[a], pb = pos[b]
              const d = edgePath(pa, pb)
              const lit = !!active && active.has(a) && active.has(b)
              const dim = !!active && !lit
              return (
                <g key={`${a}-${b}`} style={{ opacity: dim ? 0.1 : 1, transition: "opacity 250ms" }}>
                  <path d={d} fill="none" stroke={lit ? "url(#edge-lit)" : "#dcdfe4"} strokeWidth={lit ? 1.8 : 1.1} />
                  {!reduce && (!active || lit) && (
                    <circle
                      r={lit ? 3 : 2.2}
                      fill={lit ? "#0e7c7b" : "#9fb3c8"}
                      style={{
                        offsetPath: `path('${d}')`,
                        animation: `flow ${lit ? 1.5 : 3.2}s linear ${(i % 9) * 0.37}s infinite`,
                        willChange: "offset-distance",
                      }}
                    />
                  )}
                </g>
              )
            })}
            {NODES.map((n) => {
              const p = pos[n.id]
              const lit = !active || active.has(n.id)
              const isSel = selected === n.id
              const first = n.stats.map((st) => statValue(st, stats.data)).find((v) => v.live !== null)
              return (
                <g
                  key={n.id}
                  transform={`translate(${p.x},${p.y})`}
                  style={{ opacity: lit ? 1 : 0.22, transition: "opacity 250ms", cursor: "pointer" }}
                  onMouseEnter={() => setHover(n.id)}
                  onMouseLeave={() => setHover(null)}
                  onClick={() => setSelected(n.id)}
                  tabIndex={-1}
                >
                  <rect
                    width={p.w}
                    height={p.h}
                    rx={10}
                    fill="#fff"
                    stroke={isSel ? "#0b2545" : hover === n.id ? "#0e7c7b" : "#e6e6e6"}
                    strokeWidth={isSel || hover === n.id ? 1.6 : 1}
                    style={{ filter: hover === n.id ? "drop-shadow(0 6px 10px rgb(11 37 69 / 0.12))" : undefined, transition: "filter 200ms" }}
                  />
                  <clipPath id={`clip-${n.id}`}>
                    <rect width={p.w - 8} height={p.h} />
                  </clipPath>
                  <g clipPath={`url(#clip-${n.id})`}>
                  <text x={11} y={21} fontSize={12} fontWeight={500} fill="#0a0a0a">
                    {n.title}
                  </text>
                  <text x={11} y={36} fontSize={9.5} fill="#6b6b70" className="mono">
                    {n.sub}
                  </text>
                  <text x={11} y={50} fontSize={9.5} fill="#0b2545" className="num">
                    {first ? `${fmt.compact(first.live)} rows` : ""}
                  </text>
                  </g>
                </g>
              )
            })}
          </svg>
        </div>
        <div className="flex items-center justify-between border-t border-hair px-4 py-2 text-[11.5px] text-muted-foreground">
          <span>Hover a node to trace its lineage. Click it for details, live counts and SQL.</span>
          {!stats.data && <span>Loading live counts...</span>}
        </div>
      </div>

      <AnimatePresence>
        {node && (
          <motion.aside
            key={node.id}
            initial={{ x: 40, opacity: 0 }}
            animate={{ x: 0, opacity: 1 }}
            exit={{ x: 40, opacity: 0 }}
            transition={{ type: "spring", stiffness: 420, damping: 36 }}
            className="fixed bottom-2 right-2 top-16 z-50 flex w-[460px] max-w-[94vw] flex-col overflow-hidden rounded-xl border border-hair bg-white"
            style={{ boxShadow: "var(--shadow-raise)" }}
          >
            <div className="flex items-start justify-between border-b border-hair px-5 py-4">
              <div className="min-w-0">
                <div className="eyebrow mb-1">{LAYERS[node.col]}</div>
                <h3 className="text-[19px] font-medium tracking-[-0.02em]">{node.title}</h3>
                <div className="mono mt-1 text-[11.5px] text-muted-foreground">{node.sub}</div>
              </div>
              <button onClick={() => setSelected(null)} className="rounded-md p-1.5 hover:bg-muted" aria-label="Close">
                <X className="size-4" />
              </button>
            </div>
            <div className="flex-1 space-y-5 overflow-y-auto px-5 py-4">
              <div>
                <div className="eyebrow mb-1.5">What it is</div>
                <p className="text-[13.5px] leading-relaxed">{node.what}</p>
              </div>
              <div>
                <div className="eyebrow mb-1.5">Why it exists</div>
                <p className="text-[13.5px] leading-relaxed">{node.why}</p>
              </div>
              <div>
                <div className="eyebrow mb-1.5">Key objects</div>
                <div className="flex flex-wrap gap-1.5">
                  {node.objects.map((o) => (
                    <span key={o} className="mono rounded-md bg-muted px-2 py-1 text-[11.5px]">
                      {o}
                    </span>
                  ))}
                </div>
              </div>
              <div>
                <div className="eyebrow mb-1.5">In Snowflake now</div>
                {stats.isPending ? (
                  <Skeleton className="h-20" />
                ) : (
                  <div className="rounded-lg border border-hair px-3 py-1">
                    {node.stats.map((st) => {
                      const v = statValue(st, stats.data)
                      return (
                        <div key={st.k} className="flex justify-between gap-4 border-b border-hair py-2 text-[12.5px] last:border-0">
                          <span className="mono text-[11.5px] text-muted-foreground">{st.k}</span>
                          <span className="text-right">
                            {v.live !== null ? (
                              <span className="font-medium text-navy">
                                <CountUp value={v.live} format={fmt.int} /> rows
                              </span>
                            ) : (
                              v.text
                            )}
                          </span>
                        </div>
                      )
                    })}
                  </div>
                )}
              </div>
              <div>
                <div className="eyebrow mb-1.5">SQL</div>
                <pre className="mono overflow-x-auto rounded-lg border border-hair bg-[#fbfbfa] p-3 text-[11.5px] leading-relaxed text-[#13315c]">{node.code}</pre>
              </div>
            </div>
          </motion.aside>
        )}
      </AnimatePresence>
      <style>{`@keyframes flow { from { offset-distance: 0%; opacity: 0 } 10% { opacity: 1 } 90% { opacity: 1 } to { offset-distance: 100%; opacity: 0 } }`}</style>
    </div>
  )
})
