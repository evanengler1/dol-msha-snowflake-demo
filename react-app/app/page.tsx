"use client"

import Link from "next/link"
import { motion } from "framer-motion"
import { ArrowRight, ExternalLink, GitCompareArrows, ListOrdered, Mountain, Workflow } from "lucide-react"
import { fmt, useApi } from "@/lib/client"
import { Kpi, ProxyNote, Skeleton, stagger, TierChip, Tip } from "@/components/kit"
import { MineSearch } from "@/components/mine-search"
import { COMPARE_EXAMPLE, DASHBOARD_URL } from "@/lib/constants"

interface Stats {
  mines: number
  minesWithRecentHours: number
  elevated: number
  last4qOperatorHours: number
  last4qVentMethane: number
  last4qInjuries: number
  latestAccidentDate: string
  latestHoursQuarter: string
  l4qFirstQuarter: string
  tiers: { mineCategory: string; tier: string; mines: number }[]
}

const FEATURES = [
  {
    href: `/mine?id=${COMPARE_EXAMPLE[0]}`,
    Icon: Mountain,
    title: "Pre-visit briefing",
    body: "One page per mine: injuries, citations, serious enforcement, open penalties and accident narratives, with its early-warning tier.",
    cta: "Open an example mine",
  },
  {
    href: "/watchlist",
    Icon: ListOrdered,
    title: "District watch list",
    body: "Mines ranked by tier and signal strength for each MSHA district and field office. Export the view to CSV.",
    cta: "Open the watch list",
  },
  {
    href: `/compare?ids=${COMPARE_EXAMPLE.join(",")}`,
    Icon: GitCompareArrows,
    title: "Fair comparison",
    body: "Put 2-3 mines side by side, or compare one mine with its peer group: same category, mine type and size band.",
    cta: "Try an example",
  },
  {
    href: "/architecture",
    Icon: Workflow,
    title: "Built inside Snowflake",
    body: "From the DOL portal to this app, the dashboard and the CoWork agent: no data movement, governed by Snowflake RBAC.",
    cta: "See the architecture",
  },
]

const TIER_ORDER = ["Elevated", "Watch", "Typical", "Not enough recent hours"]

export default function Landing() {
  const { data, error } = useApi<Stats>("/api/stats", { staleTime: 300_000 })

  return (
    <div>
      <section className="relative mb-10 pt-4">
        <div className="hero-gradient pointer-events-none absolute -inset-x-10 -top-14 h-[360px]" />
        <div className="dot-grid pointer-events-none absolute -inset-x-10 -top-14 h-[360px]" />
        <div className="relative max-w-3xl">
          <div className="mb-4 flex flex-wrap items-center gap-2">
            <span className="eyebrow">Mine Safety and Health Administration · public data</span>
            <span className="inline-flex h-6 items-center gap-1.5 rounded-full border border-hair bg-white px-2.5 text-[11.5px] text-muted-foreground">
              <span className="size-1.5 rounded-full bg-teal" />
              Data as of{" "}
              <span className="num text-foreground">
                {data ? `${fmt.date(data.latestAccidentDate)} · hours through ${data.latestHoursQuarter}` : "loading"}
              </span>
            </span>
          </div>
          <h1 className="headline">Know which mines need attention before the next injury.</h1>
          <p className="mt-4 max-w-2xl text-[16px] text-muted-foreground">
            Find any of 92,000 mines in seconds, get a one-page briefing before an inspection, and see a transparent early-warning
            tier built only from the signals that preceded injuries in MSHA&apos;s own records.
          </p>
          <div className="mt-7 max-w-2xl">
            <MineSearch size="lg" />
            <div className="mt-2.5 flex flex-wrap gap-2 text-[12px] text-muted-foreground">
              Try:
              {[
                ["0100851", "Oak Grove Mine (coal, Elevated)"],
                ["4609533", "Berwind Deep Mine (coal, Elevated)"],
                ["4609192", "Leer Mine (coal, Typical)"],
              ].map(([id, label]) => (
                <Link key={id} href={`/mine?id=${id}`} className="rounded-md border border-hair bg-white px-1.5 hover:text-foreground">
                  <span className="mono">{id}</span> {label}
                </Link>
              ))}
            </div>
          </div>
        </div>
      </section>

      {error ? (
        <div className="card p-6 text-[13px] text-muted-foreground">Live counters are unavailable right now. Search and the pages still work.</div>
      ) : !data ? (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {[0, 1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-[118px]" />
          ))}
        </div>
      ) : (
        <motion.div variants={stagger} initial="hidden" animate="show" className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <Kpi
            label="Mines with recent hours"
            value={Number(data.minesWithRecentHours)}
            format={fmt.int}
            source="ANALYTICS.MINE_PROFILE"
            note="Mines reporting operator hours in the last 4 complete quarters."
            sub={`of ${fmt.int(data.mines)} mines in the portal`}
          />
          <Kpi
            label="Elevated mines"
            value={Number(data.elevated)}
            format={fmt.int}
            tone="alert"
            source="ANALYTICS.MINE_EARLY_WARNING"
            note="Illustrative early-warning tier from the four validated leading indicators."
            sub={<Link href="/watchlist" className="hover:text-foreground">Open the watch list →</Link>}
          />
          <Kpi
            label="Operator hours, last 4 quarters"
            value={Number(data.last4qOperatorHours)}
            format={fmt.compact}
            source="ANALYTICS.MINE_PROFILE"
            note="The denominator for every injury and citation rate (per 200,000 hours)."
            sub={`${fmt.int(data.last4qInjuries)} operator injuries`}
          />
          <Kpi
            label="Ventilation/methane citations, last 4 quarters"
            value={Number(data.last4qVentMethane)}
            format={fmt.int}
            source="ANALYTICS.MINE_PROFILE"
            note="Compliance proxy: citations under 30 CFR 75 Subpart D. Not sensor readings."
            sub="Compliance proxy, not sensor data"
          />
        </motion.div>
      )}

      {data && (
        <div className="card mt-4 flex flex-wrap items-center gap-x-6 gap-y-3 px-5 py-3.5">
          <span className="eyebrow">Tier distribution</span>
          {["Coal", "Metal/Nonmetal"].map((cat) => {
            const n = (t: string) => data.tiers.find((x) => x.mineCategory === cat && x.tier === t)?.mines ?? 0
            return (
              <Tip
                key={cat}
                content={
                  <div className="space-y-1">
                    <div className="font-medium">{cat} mines</div>
                    {TIER_ORDER.map((t) => (
                      <div key={t} className="flex justify-between gap-6">
                        <span className="text-muted-foreground">{t}</span>
                        <span className="num">{fmt.int(n(t))}</span>
                      </div>
                    ))}
                    <div className="pt-1 text-[12.5px] text-muted-foreground">Illustrative tiers, not official MSHA ratings. Too few hours = under 20,000 operator hours in the last 4 quarters.</div>
                  </div>
                }
              >
                <span className="flex cursor-default flex-wrap items-center gap-2 text-[12.5px]">
                  <span className="font-medium">{cat}</span>
                  {TIER_ORDER.map((t) => (
                    <span key={t} className="flex items-center gap-1">
                      <TierChip tier={t} tip={false} />
                      <span className="num text-muted-foreground">{fmt.int(n(t))}</span>
                    </span>
                  ))}
                </span>
              </Tip>
            )
          })}
        </div>
      )}

      <motion.div variants={stagger} initial="hidden" whileInView="show" viewport={{ once: true }} className="mt-10 grid gap-4 md:grid-cols-2">
        {FEATURES.map((f) => (
          <motion.div key={f.title} variants={{ hidden: { opacity: 0, y: 10 }, show: { opacity: 1, y: 0 } }}>
            <Link href={f.href} className="card card-hover group flex h-full flex-col gap-3 p-5 transition-transform duration-200 hover:-translate-y-0.5">
              <span className="flex size-9 items-center justify-center rounded-lg border border-hair bg-[#fbfbfa]">
                <f.Icon className="size-[18px] text-navy" />
              </span>
              <h3 className="text-[16px] font-medium tracking-[-0.01em]">{f.title}</h3>
              <p className="flex-1 text-[13.5px] leading-relaxed text-muted-foreground">{f.body}</p>
              <span className="flex items-center gap-1 text-[13px] font-medium text-navy">
                {f.cta} <ArrowRight className="size-3.5 transition-transform group-hover:translate-x-0.5" />
              </span>
            </Link>
          </motion.div>
        ))}
      </motion.div>

      <div className="mt-6 grid gap-4 md:grid-cols-[1fr_auto]">
        <div className="card p-5">
          <div className="eyebrow mb-2">Compliance proxies, not sensor readings</div>
          <p className="text-[13.5px] leading-relaxed">
            DOL asked for trends using metrics such as methane levels and temperature. The DOL Open Data Portal has no methane,
            temperature or sensor readings. This app uses what the portal does have: citations under the ventilation and methane
            sections of 30 CFR 75 Subpart D, serious enforcement actions and injury history, each validated against the next
            quarter&apos;s injuries.
          </p>
          <ProxyNote className="mt-2" />
        </div>
        <a href={DASHBOARD_URL} target="_blank" rel="noreferrer" className="card card-hover flex flex-col justify-between gap-3 p-5 md:w-[300px]">
          <span className="eyebrow">Industry trends</span>
          <span className="text-[14px] font-medium">National, state and hazard trends live in the MSHA Safety Dashboard.</span>
          <span className="flex items-center gap-1 text-[13px] font-medium text-navy">
            Open in Snowsight <ExternalLink className="size-3.5" />
          </span>
        </a>
      </div>
    </div>
  )
}
