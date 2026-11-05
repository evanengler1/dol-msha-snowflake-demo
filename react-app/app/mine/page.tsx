"use client"

import Link from "next/link"
import { useSearchParams } from "next/navigation"
import { motion } from "framer-motion"
import { ChevronDown, GitCompareArrows, MapPin } from "lucide-react"
import { useState } from "react"
import { Bar, CartesianGrid, ComposedChart, Line, ReferenceArea, ResponsiveContainer, Tooltip as RTooltip, XAxis, YAxis } from "recharts"
import { CATEGORY_COLOR, displayName, fmt, useApi } from "@/lib/client"
import {
  CategoryDot,
  EmptyState,
  ErrorState,
  Kpi,
  Panel,
  Provenance,
  ProxyNote,
  Skeleton,
  stagger,
  StatusPill,
  Tip,
} from "@/components/kit"
import { EarlyWarningCard, type EarlyWarningRow } from "@/components/early-warning-card"
import { MineMap } from "@/components/mine-map"
import { cn } from "@/lib/utils"

type R = Record<string, unknown>
interface MineResp {
  found: boolean
  mineId: string
  mine: R
  earlyWarning: EarlyWarningRow | null
  peers: R | null
  operator: R | null
}

const num = (v: unknown) => (v === null || v === undefined ? null : Number(v))

export default function MinePage() {
  const id = useSearchParams().get("id") ?? ""
  const valid = /^\d{7}$/.test(id)
  const res = useApi<MineResp>(valid ? `/api/mine?id=${id}` : null)

  if (!valid)
    return (
      <div className="card">
        <EmptyState title="Pick a mine" body="Search by mine name, 7-digit MSHA mine ID, operator or controller in the header." />
      </div>
    )
  if (res.error) return <ErrorState message={res.error.message} onRetry={() => res.refetch()} />
  if (!res.data)
    return (
      <div className="space-y-4">
        <Skeleton className="h-28" />
        <Skeleton className="h-80" />
        <div className="grid gap-4 sm:grid-cols-3">
          <Skeleton className="h-28" />
          <Skeleton className="h-28" />
          <Skeleton className="h-28" />
        </div>
      </div>
    )
  if (!res.data.found)
    return (
      <div className="card">
        <EmptyState title="No mine with that ID" body={`MSHA mine ID ${id} is not in the DOL portal Mines dataset.`} />
      </div>
    )

  const { mine: m, earlyWarning: ew, peers, operator } = res.data
  const hours = num(m.last4qOperatorHours)
  return (
    <div className="space-y-5">
      <ProfileHeader m={m} />
      <div className="grid gap-5 xl:grid-cols-[1.55fr_1fr]">
        <EarlyWarningCard ew={ew} hours={hours} />
        <div className="grid gap-5">
          <Panel eyebrow="Location" title={`${m.countyName ?? "n/a"} County, ${m.state}`} right={<MapPin className="size-4 text-muted-foreground" />}>
            {m.hasGeoIssue || m.latitude === null ? (
              <div className="flex h-[200px] items-center justify-center rounded-lg bg-[#fbfbfa] text-[13px] text-muted-foreground">
                The portal&apos;s coordinates for this mine look unreliable, so no pin is shown.
              </div>
            ) : (
              <MineMap lat={Number(m.latitude)} lon={Number(m.longitude)} label={String(m.mineName)} color={CATEGORY_COLOR[String(m.mineCategory)]} />
            )}
            <div className="mt-2 text-[12px] text-muted-foreground">Nearest town: {String(m.nearestTown ?? "n/a")}</div>
          </Panel>
          {operator && (
            <Panel eyebrow="Operator context" title={displayName(operator.operatorName)} right={<Provenance source="ANALYTICS.OPERATOR_PORTFOLIO" />}>
              <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-[13px]">
                <Stat k="Mines operated" v={fmt.int(operator.mines)} />
                <Stat k="Active mines" v={fmt.int(operator.activeMines)} />
                <Stat k="Operator injury rate, last 4Q" v={fmt.rate(operator.last4qInjuryRatePer200kHours)} />
                <Stat k="Fatalities since 2020" v={fmt.int(operator.fatalitiesSince2020)} />
                <Stat k="States" v={String(operator.states ?? "n/a")} />
                <Stat k="Open/delinquent balance" v={fmt.usd(operator.openDelinquentPenaltyBalanceUsd)} />
              </dl>
            </Panel>
          )}
        </div>
      </div>
      <QuickStats m={m} />
      <Timeline id={id} />
      <Citations id={id} />
      <div className="grid gap-5 xl:grid-cols-[1.4fr_1fr]">
        <Accidents id={id} />
        <Peers m={m} peers={peers} />
      </div>
    </div>
  )
}

function Stat({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="text-[11.5px] text-muted-foreground">{k}</dt>
      <dd className="num truncate">{v}</dd>
    </div>
  )
}

function ProfileHeader({ m }: { m: R }) {
  return (
    <div className="relative">
      <div className="hero-gradient pointer-events-none absolute -inset-x-10 -top-10 h-48" />
      <div className="relative flex flex-wrap items-end justify-between gap-4">
        <div className="min-w-0">
          <div className="eyebrow mb-2 flex flex-wrap items-center gap-2">
            Mine profile · <span className="mono normal-case tracking-normal text-foreground">{String(m.mineId)}</span>
          </div>
          <h1 className="text-[34px] font-medium leading-tight tracking-[-0.035em]">{displayName(m.mineName)}</h1>
          <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1.5 text-[13px] text-muted-foreground">
            <StatusPill status={String(m.currentStatus)} />
            <CategoryDot category={String(m.mineCategory)} />
            <span>{String(m.mineType)}</span>
            <span>{String(m.primaryCommodity ?? "")}</span>
            <span>
              {String(m.countyName ?? "")}, {String(m.state)}
            </span>
            <span>
              District <b className="font-medium text-foreground">{String(m.district ?? "n/a")}</b> · {String(m.officeName ?? "")}
            </span>
          </div>
          <div className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 text-[13px] text-muted-foreground">
            <span>
              Operator <span className="text-foreground">{displayName(m.operatorName) || "n/a"}</span>
            </span>
            <span>
              Controller <span className="text-foreground">{displayName(m.controllerName) || "n/a"}</span>
            </span>
            <span>
              Peer group <span className="text-foreground">{String(m.peerGroup ?? "n/a")}</span>
            </span>
            <span>Last inspection {fmt.date(m.lastInspectionDate)}</span>
          </div>
        </div>
        <Link
          href={`/compare?ids=${m.mineId}`}
          className="flex h-9 items-center gap-2 rounded-full border border-hair bg-white px-4 text-[13px] font-medium hover:bg-muted"
        >
          <GitCompareArrows className="size-4" /> Compare with others
        </Link>
      </div>
    </div>
  )
}

function QuickStats({ m }: { m: R }) {
  const enough = Number(m.last4qOperatorHours ?? 0) >= 20000
  const S = "ANALYTICS.MINE_PROFILE"
  const K = { source: S, compact: true }
  return (
    <div>
      <div className="mb-3 flex items-baseline justify-between">
        <h2 className="text-[15px] font-medium">Last 4 complete quarters</h2>
        <span className="text-[12px] text-muted-foreground">Operator basis: operator injuries / operator hours</span>
      </div>
      <motion.div variants={stagger} initial="hidden" animate="show" className="grid gap-3 sm:grid-cols-3 xl:grid-cols-5">
        <Kpi label="Operator hours" value={num(m.last4qOperatorHours)} format={fmt.int} {...K} />
        <Kpi label="Operator injuries" value={num(m.last4qInjuries)} format={fmt.int} {...K} />
        <Kpi
          label="Injury rate per 200K hrs"
          value={enough && m.last4qInjuryRatePer200kHours !== null ? Number(m.last4qInjuryRatePer200kHours) : null}
          format={(n) => n.toFixed(2)}
          {...K}
          note="SUM(injuries) * 200,000 / SUM(operator hours). Hidden below 20K hours."
          sub={enough ? `Trend vs prior 4Q: ${m.injuryRateTrend ?? "n/a"}` : "Not enough recent hours"}
        />
        <Kpi label="Citations" value={num(m.last4qViolations)} format={fmt.int} {...K} sub={`${fmt.int(m.last4qSignificantSubstantialViolations)} S&S`} />
        <Kpi
          label="Vent/methane citations"
          value={num(m.last4qVentilationMethaneViolations)}
          format={fmt.int}
          {...K}
          note="Compliance proxy: 30 CFR 75 Subpart D citations, not sensor readings."
          sub={`Trend: ${m.ventilationMethaneTrend ?? "n/a"}`}
        />
        <Kpi label="104(d)/107(a) actions" value={num(m.last4qUnwarrantableFailureImminentDangerActions)} format={fmt.int} {...K} note="Unwarrantable failure citations/orders and imminent danger orders." />
        <Kpi label="High-negligence citations" value={num(m.last4qHighNegligenceViolations)} format={fmt.int} {...K} />
        <Kpi label="Proposed penalties" value={num(m.last4qProposedPenaltiesUsd)} format={(n) => fmt.usd(n)} {...K} />
        <Kpi
          label="Open/delinquent balance"
          value={num(m.openDelinquentPenaltyBalanceUsd)}
          format={(n) => fmt.usd(n)}
          {...K}
          tone={Number(m.openDelinquentPenaltyBalanceUsd ?? 0) > 0 ? "alert" : "default"}
          note="Assessed penalties not yet paid, all years."
        />
        <Kpi label="Fatalities since 2010" value={num(m.fatalitiesSince2010)} format={fmt.int} {...K} sub={`Last accident ${fmt.date(m.lastAccidentDate)}`} />
      </motion.div>
    </div>
  )
}

/* ---------- Timeline ---------- */

function ChartTip({ active, payload, label }: { active?: boolean; payload?: { name: string; value: number | null; color: string }[]; label?: string }) {
  if (!active || !payload?.length) return null
  const partial = String(label).startsWith("2026")
  return (
    <div className="rounded-lg border border-hair bg-white px-3.5 py-2.5 text-[14px]" style={{ boxShadow: "var(--shadow-pop)" }}>
      <div className="mb-1 font-medium">
        {label}
        {partial && <span className="ml-2 text-[12px] font-normal text-amber">2026 is partial</span>}
      </div>
      {payload.map((p) => (
        <div key={p.name} className="flex items-center justify-between gap-6">
          <span className="flex items-center gap-1.5 text-muted-foreground">
            <span className="size-2 rounded-full" style={{ background: p.color }} />
            {p.name}
          </span>
          <span className="num">{p.value === null || p.value === undefined ? "no hours" : Number.isInteger(p.value) ? p.value : p.value.toFixed(2)}</span>
        </div>
      ))}
    </div>
  )
}

function Timeline({ id }: { id: string }) {
  const res = useApi<R[]>(`/api/mine/timeline?id=${id}`)
  const [metric, setMetric] = useState<"violations" | "ventilationMethaneViolations" | "actions104d107a">("violations")
  const labels = { violations: "All citations", ventilationMethaneViolations: "Vent/methane (proxy)", actions104d107a: "104(d)/107(a)" }
  const data: R[] = (res.data ?? []).map((r) => ({ ...r, injuryRate: r.injuryRate === null ? null : Number(r.injuryRate) }))
  const first2026 = data.find((d) => String(d.yearQuarter).startsWith("2026"))?.yearQuarter as string | undefined
  const last = data[data.length - 1]?.yearQuarter as string | undefined
  return (
    <Panel
      eyebrow="Quarterly timeline since 2010"
      title="Injury rate and citations"
      right={
        <div className="flex items-center gap-2">
          <div className="flex rounded-full border border-hair bg-white p-0.5 text-[12px]">
            {(Object.keys(labels) as (keyof typeof labels)[]).map((k) => (
              <button
                key={k}
                onClick={() => setMetric(k)}
                className={cn("h-7 rounded-full px-3", metric === k ? "bg-navy text-white" : "text-muted-foreground hover:text-foreground")}
              >
                {labels[k]}
              </button>
            ))}
          </div>
          <Provenance source="ANALYTICS.MINE_QUARTER_TRENDS" />
        </div>
      }
    >
      {res.error ? (
        <ErrorState message={res.error.message} />
      ) : !res.data ? (
        <Skeleton className="h-[300px]" />
      ) : data.length === 0 ? (
        <EmptyState title="No quarterly history" body="This mine has no quarters since 2010 in MINE_QUARTER_TRENDS." />
      ) : (
        <>
          <div className="h-[300px]">
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
                <CartesianGrid stroke="#f0f0f0" vertical={false} />
                <XAxis dataKey="yearQuarter" tick={{ fontSize: 11, fill: "#6b6b70" }} interval={7} tickLine={false} axisLine={{ stroke: "#eaeaea" }} />
                <YAxis yAxisId="c" tick={{ fontSize: 11, fill: "#6b6b70" }} tickLine={false} axisLine={false} width={40} />
                <YAxis yAxisId="r" orientation="right" tick={{ fontSize: 11, fill: "#6b6b70" }} tickLine={false} axisLine={false} width={36} />
                {first2026 && last && (
                  <ReferenceArea yAxisId="c" x1={first2026} x2={last} fill="#fff7ea" fillOpacity={0.9} label={{ value: "2026 partial", fontSize: 11, fill: "#9a5b06", position: "insideTop" }} />
                )}
                <RTooltip content={<ChartTip />} cursor={{ fill: "rgb(11 37 69 / 0.04)" }} />
                <Bar yAxisId="c" dataKey={metric} name={labels[metric]} fill="#c9d4e3" radius={[2, 2, 0, 0]} isAnimationActive />
                <Line yAxisId="r" type="monotone" dataKey="injuryRate" name="Injury rate per 200K hrs" stroke="#d97706" strokeWidth={1.8} dot={false} connectNulls={false} />
              </ComposedChart>
            </ResponsiveContainer>
          </div>
          <div className="mt-2 flex flex-wrap gap-x-5 gap-y-1 text-[12px] text-muted-foreground">
            <span><span className="mr-1.5 inline-block h-2 w-3 rounded-sm bg-[#c9d4e3]" />{labels[metric]} (left axis)</span>
            <span><span className="mr-1.5 inline-block h-0.5 w-3 bg-amber align-middle" />Operator injury rate per 200K hrs (right axis; gaps = no hours)</span>
            <span>2026 has hours through Q2 only and is shaded.</span>
          </div>
        </>
      )}
    </Panel>
  )
}

/* ---------- Citations ---------- */

function Flag({ on, label }: { on: unknown; label: string }) {
  if (!on) return null
  return <span className="mono inline-flex h-5 items-center rounded-[5px] border border-[#cbd5e1] bg-white px-1.5 text-[10.5px] text-[#13315c]">{label}</span>
}

function Citations({ id }: { id: string }) {
  const res = useApi<{ byCategory: R[]; recent: R[] }>(`/api/mine/citations?id=${id}`)
  const max = Math.max(1, ...(res.data?.byCategory ?? []).map((c) => Number(c.citations)))
  return (
    <div className="grid gap-5 2xl:grid-cols-[1fr_1.35fr]">
      <Panel eyebrow="Since 2010" title="Citations by hazard category" right={<Provenance source="ANALYTICS.VIOLATION_DETAIL" note="Hazard categories map 30 CFR sections to compliance proxies." />}>
        {res.error ? (
          <ErrorState message={res.error.message} />
        ) : !res.data ? (
          <Skeleton className="h-64" />
        ) : res.data.byCategory.length === 0 ? (
          <EmptyState title="No citations" body="No violations are recorded for this mine since 2010." />
        ) : (
          <div className="space-y-2.5">
            {res.data.byCategory.map((c) => {
              const vent = String(c.hazardCategory).startsWith("Ventilation")
              return (
                <Tip
                  key={String(c.hazardCategory)}
                  content={
                    <span>
                      <b>{String(c.hazardCategory)}</b>: {fmt.int(c.citations)} citations ({fmt.int(c.last12Months)} in the last 12 months),{" "}
                      {fmt.int(c.significantSubstantial)} S&amp;S, {fmt.int(c.actions104d107a)} 104(d)/107(a), {fmt.usd(c.proposedPenaltiesUsd)} proposed.
                    </span>
                  }
                >
                  <div className="grid grid-cols-[minmax(0,180px)_1fr_56px] items-center gap-3 text-[12.5px]">
                    <span className="truncate">{String(c.hazardCategory)}</span>
                    <div className="h-2 overflow-hidden rounded-full bg-[#f1f2f4]">
                      <motion.div
                        className="h-full rounded-full"
                        style={{ background: vent ? "#d97706" : "#0b2545" }}
                        initial={{ width: 0 }}
                        animate={{ width: `${(Number(c.citations) / max) * 100}%` }}
                        transition={{ duration: 0.8, ease: [0.25, 1, 0.5, 1] }}
                      />
                    </div>
                    <span className="num text-right">{fmt.int(c.citations)}</span>
                  </div>
                </Tip>
              )
            })}
            <ProxyNote className="pt-2" />
          </div>
        )}
      </Panel>
      <Panel eyebrow="Most recent serious citations" title="104(d)/107(a), high negligence and S&S">
        {res.error ? null : !res.data ? (
          <Skeleton className="h-64" />
        ) : res.data.recent.length === 0 ? (
          <EmptyState title="No serious citations" body="No 104(d), 107(a), high-negligence or S&S citations on record." />
        ) : (
          <div className="-mx-5 overflow-x-auto">
            <table className="w-full min-w-[620px] text-[12.5px]">
              <thead>
                <tr className="border-b border-hair text-left">
                  {["Date", "CFR section", "Category", "Flags", "Penalty"].map((h) => (
                    <th key={h} className={cn("eyebrow px-5 py-2 font-medium", h === "Penalty" && "text-right")}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {res.data.recent.map((v) => (
                  <tr key={String(v.violationNumber)} className="border-b border-hair last:border-0 hover:bg-[#fafbfc]">
                    <td className="num whitespace-nowrap px-5 py-2">{fmt.date(v.issueDate)}</td>
                    <td className="mono whitespace-nowrap px-5 py-2">{String(v.cfrPartSection ?? "n/a")}</td>
                    <td className="max-w-[180px] truncate px-5 py-2">{String(v.hazardCategory ?? "")}</td>
                    <td className="px-5 py-2">
                      <span className="flex flex-wrap gap-1">
                        <Flag on={v.isUnwarrantableFailure} label="104(d)" />
                        <Flag on={v.isImminentDanger} label="107(a)" />
                        <Flag on={v.isHighNegligence} label="High neg." />
                        <Flag on={v.isSignificantSubstantial} label="S&S" />
                      </span>
                    </td>
                    <td className="num px-5 py-2 text-right">{v.proposedPenaltyUsd === null ? <span className="text-muted-foreground">Not yet assessed</span> : fmt.usd(v.proposedPenaltyUsd, false)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Panel>
    </div>
  )
}

/* ---------- Accidents ---------- */

function Accidents({ id }: { id: string }) {
  const [offset, setOffset] = useState(0)
  const [open, setOpen] = useState<string | null>(null)
  const res = useApi<{ rows: R[]; total: number; pageSize: number }>(`/api/mine/accidents?id=${id}&offset=${offset}`, { placeholderData: (p) => p })
  const d = res.data
  return (
    <Panel
      eyebrow="Accidents and injuries"
      title={d ? `${fmt.int(d.total)} accident records since 2010` : "Accidents"}
      right={<Provenance source="ANALYTICS.ACCIDENT_DETAIL" note="One row per person per accident. Narratives are truncated at 384 characters in the portal." />}
    >
      {res.error ? (
        <ErrorState message={res.error.message} />
      ) : !d ? (
        <Skeleton className="h-72" />
      ) : d.rows.length === 0 ? (
        <EmptyState title="No accidents on record" body="No accident reports for this mine since 2010." />
      ) : (
        <>
          <ul className="-mx-2 divide-y divide-hair">
            {d.rows.map((a, i) => {
              const key = `${a.accidentDocumentNumber}-${i + offset}`
              const isOpen = open === key
              const severe = a.isFatal || a.isLostTimeInjury
              return (
                <li key={key}>
                  <button onClick={() => setOpen(isOpen ? null : key)} className="flex w-full items-start gap-3 rounded-lg px-2 py-2.5 text-left hover:bg-[#fafbfc]">
                    <span className="num w-[92px] shrink-0 text-[12.5px] text-muted-foreground">{fmt.date(a.accidentDate)}</span>
                    <span className="min-w-0 flex-1">
                      <span className="flex flex-wrap items-center gap-2 text-[13px]">
                        <span className={cn("font-medium", a.isFatal ? "text-alert" : severe ? "text-amber" : "")}>{String(a.degreeOfInjury ?? "n/a")}</span>
                        {Boolean(a.isContractorEmployee) && <span className="rounded-full bg-muted px-1.5 text-[10.5px] text-muted-foreground">Contractor</span>}
                        {Boolean(a.isIgnitionExplosionFire) && <span className="rounded-full bg-amber-50 px-1.5 text-[10.5px] text-[#9a5b06]">Ignition/explosion</span>}
                      </span>
                      <span className="block truncate text-[12px] text-muted-foreground">{String(a.accidentClassification ?? "")}</span>
                    </span>
                    <ChevronDown className={cn("mt-1 size-4 shrink-0 text-muted-foreground transition-transform", isOpen && "rotate-180")} />
                  </button>
                  {isOpen && (
                    <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: "auto" }} className="overflow-hidden px-2 pb-3">
                      <p className="rounded-lg bg-[#fbfbfa] p-3 text-[13px] leading-relaxed">{String(a.narrative ?? "No narrative recorded.")}</p>
                      <div className="mt-1.5 flex flex-wrap gap-x-4 text-[11.5px] text-muted-foreground">
                        <span>Occupation: {String(a.occupation ?? "n/a")}</span>
                        <span>Equipment: {String(a.miningEquipment ?? "n/a")}</span>
                        <span>Days lost: {a.daysLost === null ? "n/a" : fmt.int(a.daysLost)}</span>
                        <span>Narratives are truncated at 384 characters in the portal.</span>
                      </div>
                    </motion.div>
                  )}
                </li>
              )
            })}
          </ul>
          {d.total > d.pageSize && (
            <div className="mt-3 flex items-center justify-between text-[12.5px] text-muted-foreground">
              <span className="num">
                {offset + 1}-{Math.min(offset + d.pageSize, d.total)} of {fmt.int(d.total)}
              </span>
              <span className="flex gap-2">
                <button disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - d.pageSize))} className="h-7 rounded-full border border-hair bg-white px-3 disabled:opacity-40">
                  Newer
                </button>
                <button disabled={offset + d.pageSize >= d.total} onClick={() => setOffset(offset + d.pageSize)} className="h-7 rounded-full border border-hair bg-white px-3 disabled:opacity-40">
                  Older
                </button>
              </span>
            </div>
          )}
        </>
      )}
    </Panel>
  )
}

/* ---------- Peers ---------- */

function Peers({ m, peers }: { m: R; peers: R | null }) {
  const hours = Number(m.last4qOperatorHours ?? 0)
  const per200k = (x: unknown) => (hours > 0 ? (Number(x ?? 0) * 200000) / hours : null)
  const rows: { label: string; mine: number | null; peer: number | null; pct: unknown; f: (n: number) => string }[] = peers
    ? [
        { label: "Injury rate per 200K hrs", mine: hours >= 20000 ? num(m.last4qInjuryRatePer200kHours) : null, peer: num(peers.pooledInjuryRate), pct: m.injuryRatePeerPercentile, f: (n) => n.toFixed(2) },
        { label: "Vent/methane per 200K hrs", mine: per200k(m.last4qVentilationMethaneViolations), peer: num(peers.pooledVentMethanePer200k), pct: m.ventilationMethanePeerPercentile, f: (n) => n.toFixed(2) },
        { label: "104(d)/107(a) per 200K hrs", mine: per200k(m.last4qUnwarrantableFailureImminentDangerActions), peer: num(peers.pooled104d107aPer200k), pct: m.unwarrantableImminentPeerPercentile, f: (n) => n.toFixed(2) },
        { label: "High negligence per 200K hrs", mine: per200k(m.last4qHighNegligenceViolations), peer: num(peers.pooledHighNegligencePer200k), pct: m.highNegligencePeerPercentile, f: (n) => n.toFixed(2) },
        { label: "Proposed penalties", mine: num(m.last4qProposedPenaltiesUsd), peer: num(peers.avgProposedPenaltiesUsd), pct: m.penaltiesPeerPercentile, f: (n) => fmt.usd(n) },
        { label: "Open/delinquent balance", mine: num(m.openDelinquentPenaltyBalanceUsd), peer: num(peers.avgOpenBalanceUsd), pct: m.openBalancePeerPercentile, f: (n) => fmt.usd(n) },
      ]
    : []
  return (
    <Panel
      eyebrow="Peer comparison, last 4 quarters"
      title={String(m.peerGroup ?? "Peer group")}
      right={<Provenance source="ANALYTICS.PEER_GROUP_BENCHMARK" note="Rates pooled across peer mines; dollars are per-mine averages. Percentile from MINE_PROFILE (higher = worse)." />}
    >
      {!peers ? (
        <EmptyState title="No peer group" body="This mine has no recent hours, so it has no peer benchmark." />
      ) : (
        <>
          <div className="mb-3 text-[12.5px] text-muted-foreground">
            Compared with <b className="num font-medium text-foreground">{fmt.int(peers.peerMines)}</b> peer mines that reported hours.
          </div>
          <table className="w-full text-[12.5px]">
            <thead>
              <tr className="border-b border-hair text-left">
                <th className="eyebrow py-2 font-medium">Metric</th>
                <th className="eyebrow py-2 text-right font-medium">This mine</th>
                <th className="eyebrow py-2 text-right font-medium">Peers</th>
                <th className="eyebrow py-2 text-right font-medium">Percentile</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => {
                const worse = r.mine !== null && r.peer !== null && r.mine > r.peer * 1.1
                return (
                  <tr key={r.label} className="border-b border-hair last:border-0">
                    <td className="py-2">{r.label}</td>
                    <td className={cn("num py-2 text-right", worse && "font-medium text-amber")}>{r.mine === null ? "n/a" : r.f(r.mine)}</td>
                    <td className="num py-2 text-right text-muted-foreground">{r.peer === null ? "n/a" : r.f(r.peer)}</td>
                    <td className="num py-2 text-right">{fmt.pctile(r.pct)}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </>
      )}
    </Panel>
  )
}
