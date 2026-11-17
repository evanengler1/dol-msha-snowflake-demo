"use client"

import { motion } from "framer-motion"
import { AppWindow, Bot, Database, KeyRound, LayoutDashboard, Lock, ServerCog, ShieldCheck, Warehouse } from "lucide-react"
import { fmt, useApi } from "@/lib/client"
import { CountUp, PageHeader } from "@/components/kit"
import { ArchitectureFlow, type ArchStats } from "@/components/architecture-flow"

const reveal = {
  initial: { opacity: 0, y: 18 },
  whileInView: { opacity: 1, y: 0 },
  viewport: { once: true, margin: "-60px" },
  transition: { duration: 0.5, ease: [0.25, 1, 0.5, 1] as const },
}

const VIEWS: [string, string][] = [
  ["NATIONAL_TRENDS", "Injury, fatality and citation rates by year and mine category, pooled per 200K operator hours."],
  ["STATE_TRENDS", "The same rates by state and year, with an explicit 'All Mines' rollup row."],
  ["HAZARD_TRENDS", "Citations per hazard category (compliance proxies) by year and category."],
  ["ACCIDENT_PATTERNS", "Accidents by classification, equipment, occupation and experience."],
  ["ACCIDENT_DETAIL", "One row per person per accident, with degree of injury and the portal narrative."],
  ["VIOLATION_DETAIL", "Every violation since 2010 with CFR section, hazard category, flags and penalty status."],
  ["MINE_QUARTER_TRENDS", "Per-mine quarterly timeline: hours, injuries, rates and citations, with 2026 marked partial."],
  ["LEADING_INDICATORS", "Prior-4-quarter signals next to next-quarter injuries; the evidence for the early-warning tier."],
  ["MINE_PROFILE", "One row per mine: last-4-quarter indicators, peer group, peer percentiles and trends."],
  ["OPERATOR_PORTFOLIO", "Current operators with their mines, recent rates, fatalities and open balances."],
  ["PENALTY_OUTCOMES", "Proposed vs assessed vs paid penalties by status."],
  ["MINE_EARLY_WARNING", "Dynamic Table: four screened signals, their groups, evidence, an illustrative tier and reasons."],
]

const APPS = [
  {
    Icon: LayoutDashboard,
    name: "MSHA Safety Dashboard",
    runtime: "Streamlit in Snowflake",
    object: "APPS.MSHA_SAFETY_DASHBOARD",
    body: "Industry trends, ventilation and methane proxies, leading-indicator evidence, a state map and operator portfolios.",
    audience: "Analysts, program staff and leadership",
  },
  {
    Icon: AppWindow,
    name: "Mine Early-Warning App",
    runtime: "Snowflake App Runtime",
    object: "APPS.MSHA_EARLY_WARNING_APP",
    body: "Per-mine briefings, the early-warning tier with its evidence, district watch lists and side-by-side comparison.",
    audience: "Inspectors, field office supervisors and district managers",
  },
  {
    Icon: Bot,
    name: "MSHA Safety Agent",
    runtime: "Cortex Agent in Snowflake CoWork",
    object: "APPS.MSHA_SAFETY_AGENT",
    body: "Cortex Analyst over the semantic view plus Cortex Search over narratives: \"Which coal mines in District 4 had the most ventilation citations last year?\" or \"Find roof-fall accidents involving continuous miners.\"",
    audience: "Anyone, in plain English",
  },
]

const GOV = [
  { Icon: KeyRound, title: "Dedicated role", body: "DOL_MSHA_DEMO_ROLE owns every object." },
  { Icon: Warehouse, title: "Dedicated warehouse", body: "DOL_MSHA_WH (X-Small) runs every query." },
  { Icon: Lock, title: "No PUBLIC schema", body: "RAW, TRANSFORMED, ANALYTICS and APPS only." },
  { Icon: Database, title: "Data stays in Snowflake", body: "No extracts, no copies to app servers." },
  { Icon: ServerCog, title: "Apps run inside Snowflake", body: "Streamlit and App Runtime on Snowpark Container Services." },
  { Icon: ShieldCheck, title: "RBAC everywhere", body: "The same grants govern the dashboard, the app and the agent." },
]

const STACK = [
  "Snowflake",
  "External stage + COPY INTO",
  "Dynamic Tables",
  "SQL UDFs",
  "Window functions",
  "Semantic Views",
  "Cortex Analyst",
  "Cortex Search",
  "Cortex Agents",
  "Snowflake CoWork",
  "Streamlit in Snowflake",
  "Snowflake App Runtime",
  "Snowpark Container Services",
  "Next.js",
  "React 19",
  "snowflake-sdk",
  "Python",
  "Amazon S3",
]

function Section({ eyebrow, title, children }: { eyebrow: string; title: string; children: React.ReactNode }) {
  return (
    <motion.section {...reveal} className="mt-12">
      <div className="eyebrow mb-1.5">{eyebrow}</div>
      <h2 className="mb-4 text-[22px] font-medium tracking-[-0.025em]">{title}</h2>
      {children}
    </motion.section>
  )
}

export default function Architecture() {
  const stats = useApi<ArchStats>("/api/architecture", { staleTime: 300_000 })
  const cnt = (k: string) => Number(stats.data?.counts[k] ?? 0)
  const headline: [string, number, string][] = [
    ["Mines", cnt("RAW.MSHA_MINES"), "92K mines"],
    ["Violations since 2010", cnt("TRANSFORMED.VIOLATION"), "1.79M violations"],
    ["Mine-quarters", cnt("TRANSFORMED.MINE_QUARTER_FACT"), "Gap-free 2010 Q1 to 2026 Q2"],
    ["Accident narratives", Number(stats.data?.narratives ?? 0), "Indexed for search"],
  ]

  return (
    <div>
      <PageHeader
        eyebrow="Architecture"
        title="One platform, from public portal to three apps."
        sub="Public MSHA data lands in Snowflake, becomes typed tables, screened indicators and a semantic layer, and feeds a dashboard, this app and a CoWork agent. Nothing leaves Snowflake."
      />

      <motion.div {...reveal} className="card mb-6 border-l-4 border-l-teal p-5">
        <div className="eyebrow mb-1.5">The demo story</div>
        <p className="text-[14.5px] leading-relaxed">
          Using only real, public MSHA data from the DOL Open Data Portal, this platform shows where and why miners are getting
          hurt, which signals came before injuries in MSHA&apos;s own records, and which mines look most like the ones that had
          more injuries the next quarter. Inspectors get a one-page briefing for any mine, district managers get a ranked watch
          list, and anyone can ask questions in plain English. Everything runs inside Snowflake, with no data movement.
        </p>
      </motion.div>

      <motion.div {...reveal} className="mb-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {headline.map(([label, v, fallback]) => (
          <div key={label} className="card card-hover p-4 transition-transform duration-200 hover:-translate-y-0.5">
            <div className="text-[12px] text-muted-foreground">{label}</div>
            <div className="mt-2 text-[26px] font-medium leading-none">
              {v > 0 ? <CountUp value={v} format={fmt.int} /> : <span className="text-[16px]">{fallback}</span>}
            </div>
          </div>
        ))}
      </motion.div>

      <motion.div {...reveal}>
        <ArchitectureFlow />
      </motion.div>

      <Section eyebrow="Source · Ingestion · Transformation" title="Portal data, loaded as published, then typed">
        <div className="grid gap-4 md:grid-cols-3">
          {[
            ["DOL Open Data Portal", "Fourteen MSHA datasets: Accident, Mines, Inspection, Violation, Assessed Violations, Operator and Contractor Employment/Production, plus history and lookups. Weekly refresh. Portal data only, no sensor data."],
            ["Load → RAW", "MSHA tables already in the account are copied into RAW by column name, or a Python extractor reads the portal ZIPs, keeps facts from 2010 on, and loads them through a stage with COPY INTO. Either way: 14 RAW.MSHA_* tables."],
            ["TRANSFORMED", "Typed tables, the hazard-category reference (30 CFR → compliance proxy), cleaning UDFs and MINE_QUARTER_FACT: a gap-free mine × quarter grain from 2010 Q1 to 2026 Q2 with lagged features."],
          ].map(([t, b]) => (
            <div key={t} className="card card-hover p-5 transition-transform duration-200 hover:-translate-y-0.5">
              <h3 className="mb-1.5 text-[15px] font-medium">{t}</h3>
              <p className="text-[13px] leading-relaxed text-muted-foreground">{b}</p>
            </div>
          ))}
        </div>
      </Section>

      <Section eyebrow="Analytics layer" title="The interface views every app reads">
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {VIEWS.map(([name, desc], i) => (
            <motion.div
              key={name}
              initial={{ opacity: 0, y: 10 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.03, duration: 0.35 }}
              className="card card-hover group relative min-h-[92px] overflow-hidden p-4 transition-transform duration-200 hover:-translate-y-0.5"
            >
              <div className="mono text-[12px] font-medium text-navy">ANALYTICS.{name}</div>
              <p className="mt-2 text-[12.5px] leading-snug text-muted-foreground opacity-70 transition-opacity duration-200 group-hover:opacity-100">
                {desc}
              </p>
            </motion.div>
          ))}
        </div>
      </Section>

      <Section eyebrow="Semantic & AI layer" title="Questions in plain English, answered with the same rules">
        <div className="grid gap-4 md:grid-cols-2">
          <div className="card card-hover p-5 transition-transform duration-200 hover:-translate-y-0.5">
            <div className="mono mb-1 text-[12px] text-navy">ANALYTICS.MSHA_SAFETY_SEMANTIC_VIEW</div>
            <h3 className="mb-1.5 text-[15px] font-medium">Semantic view</h3>
            <p className="text-[13px] leading-relaxed text-muted-foreground">
              Metrics such as pooled injury rate, fatalities and citations per 200K hours; dimensions such as mine, operator, state,
              district, hazard category and quarter. Cortex Analyst writes governed SQL from it.
            </p>
          </div>
          <div className="card card-hover p-5 transition-transform duration-200 hover:-translate-y-0.5">
            <div className="mono mb-1 text-[12px] text-navy">ANALYTICS.ACCIDENT_NARRATIVE_SEARCH</div>
            <h3 className="mb-1.5 text-[15px] font-medium">Cortex Search over accident narratives</h3>
            <p className="text-[13px] leading-relaxed text-muted-foreground">
              Hybrid keyword and vector search across{" "}
              {stats.data?.narratives ? <b className="num font-medium text-foreground">{fmt.int(stats.data.narratives)}</b> : "the portal's"} accident
              narratives, filterable by mine, state, category and classification.
            </p>
          </div>
        </div>
      </Section>

      <Section eyebrow="Applications" title="Three ways in, one governed platform">
        <div className="grid gap-4 lg:grid-cols-3">
          {APPS.map((a) => (
            <div key={a.name} className="card card-hover flex flex-col gap-3 p-5 transition-transform duration-200 hover:-translate-y-1">
              <span className="flex size-10 items-center justify-center rounded-lg border border-hair bg-[#fbfbfa]">
                <a.Icon className="size-5 text-navy" />
              </span>
              <div>
                <h3 className="text-[16px] font-medium tracking-[-0.01em]">{a.name}</h3>
                <div className="text-[12px] text-teal">{a.runtime}</div>
              </div>
              <p className="flex-1 text-[13px] leading-relaxed text-muted-foreground">{a.body}</p>
              <div className="flex items-center justify-between gap-2 border-t border-hair pt-3 text-[11.5px]">
                <span className="mono text-navy">{a.object}</span>
              </div>
              <div className="text-[11.5px] text-muted-foreground">For: {a.audience}</div>
            </div>
          ))}
        </div>
      </Section>

      <Section eyebrow="Governance & platform" title="Secure by default">
        <div className="card grid gap-px overflow-hidden bg-hair sm:grid-cols-2 xl:grid-cols-6">
          {GOV.map((g) => (
            <div key={g.title} className="bg-white p-4 transition-colors hover:bg-[#fbfbfa]">
              <g.Icon className="mb-2 size-4 text-teal" />
              <div className="text-[13px] font-medium">{g.title}</div>
              <div className="mt-0.5 text-[12px] leading-snug text-muted-foreground">{g.body}</div>
            </div>
          ))}
        </div>
      </Section>

      <Section eyebrow="Tech stack" title="Built with">
        <div className="flex flex-wrap gap-2">
          {STACK.map((t, i) => (
            <motion.span
              key={t}
              initial={{ opacity: 0, scale: 0.95 }}
              whileInView={{ opacity: 1, scale: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.02 }}
              className="inline-flex h-7 items-center rounded-full border border-hair bg-white px-3 text-[12.5px] transition-transform hover:-translate-y-0.5"
            >
              {t}
            </motion.span>
          ))}
        </div>
      </Section>
    </div>
  )
}
