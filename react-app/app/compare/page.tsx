"use client"

import Link from "next/link"
import { useRouter, useSearchParams } from "next/navigation"
import { motion } from "framer-motion"
import { Plus, Sparkles, X } from "lucide-react"
import { displayName, fmt, useApi } from "@/lib/client"
import { COMPARE_EXAMPLE } from "@/lib/constants"
import { isValidated, SIGNAL_LABEL, SIGNALS, type Category, type Signal } from "@/lib/early-warning"
import { CategoryDot, EmptyState, ErrorState, GroupChip, PageHeader, Provenance, ProxyNote, Skeleton, TierChip } from "@/components/kit"
import { MineSearch } from "@/components/mine-search"
import { cn } from "@/lib/utils"

type R = Record<string, unknown>

const GROUP_KEY: Record<Signal, string> = {
  PRIOR_INJURY_RATE: "priorInjuryRateGroup",
  VENTILATION_METHANE: "ventilationMethaneGroup",
  UNWARRANTABLE_IMMINENT: "unwarrantableImminentGroup",
  HIGH_NEGLIGENCE: "highNegligenceGroup",
}

/** Rows: [label, value getter, formatter, higher-is-worse]. The worst value per row is amber. */
const METRICS: [string, (r: R) => number | null, (n: number) => string][] = [
  ["Operator hours", (r) => n(r.last4qOperatorHours), fmt.int],
  ["Operator injuries", (r) => n(r.last4qInjuries), fmt.int],
  ["Injury rate per 200K hrs", (r) => (Number(r.last4qOperatorHours ?? 0) >= 20000 ? n(r.last4qInjuryRatePer200kHours) : null), (x) => x.toFixed(2)],
  ["Citations", (r) => n(r.last4qViolations), fmt.int],
  ["S&S citations", (r) => n(r.last4qSignificantSubstantialViolations), fmt.int],
  ["Vent/methane citations (proxy)", (r) => n(r.last4qVentilationMethaneViolations), fmt.int],
  ["104(d)/107(a) actions", (r) => n(r.last4qUnwarrantableFailureImminentDangerActions), fmt.int],
  ["High-negligence citations", (r) => n(r.last4qHighNegligenceViolations), fmt.int],
  ["Proposed penalties", (r) => n(r.last4qProposedPenaltiesUsd), (x) => fmt.usd(x)],
  ["Open/delinquent balance", (r) => n(r.openDelinquentPenaltyBalanceUsd), (x) => fmt.usd(x)],
]
const PCTILES: [string, string][] = [
  ["Injury rate", "injuryRatePeerPercentile"],
  ["Vent/methane", "ventilationMethanePeerPercentile"],
  ["104(d)/107(a)", "unwarrantableImminentPeerPercentile"],
  ["High negligence", "highNegligencePeerPercentile"],
  ["Penalties", "penaltiesPeerPercentile"],
]

function n(v: unknown): number | null {
  return v === null || v === undefined ? null : Number(v)
}

function worstIndex(vals: (number | null)[]): number {
  const present = vals.filter((v): v is number => v !== null)
  if (present.length < 2) return -1
  const max = Math.max(...present)
  if (present.every((v) => v === max)) return -1
  return vals.indexOf(max)
}

export default function Compare() {
  const router = useRouter()
  const raw = useSearchParams().get("ids") ?? ""
  const ids = raw.split(",").map((s) => s.trim()).filter((s) => /^\d{7}$/.test(s)).slice(0, 3)
  const res = useApi<{ rows: R[]; missing: string[] }>(ids.length ? `/api/compare?ids=${ids.join(",")}` : null, { placeholderData: (p) => p })
  const rows = res.data?.rows ?? []
  const setIds = (next: string[]) => router.replace(next.length ? `/compare?ids=${next.join(",")}` : "/compare")
  const samePeer = rows.length > 1 && rows.every((r) => r.peerGroup === rows[0].peerGroup)

  return (
    <div>
      <PageHeader
        eyebrow="Compare"
        title="Put mines side by side."
        sub="Compare 2-3 mines on the early-warning signals, last-4-quarter metrics and peer percentiles. The higher-risk value in each row is amber. The URL is shareable."
        right={
          <button
            onClick={() => setIds(COMPARE_EXAMPLE)}
            className="flex h-9 items-center gap-2 rounded-full bg-navy px-4 text-[13px] font-medium text-white hover:bg-[#13315c]"
          >
            <Sparkles className="size-4" /> Try an example
          </button>
        }
      />
      {ids.length < 3 && (
        <div className="card mb-4 flex flex-wrap items-center gap-3 p-4">
          <Plus className="size-4 text-muted-foreground" />
          <span className="text-[13px] font-medium">Add a mine</span>
          <div className="min-w-[280px] flex-1">
            <AddMine onAdd={(id) => !ids.includes(id) && setIds([...ids, id])} />
          </div>
        </div>
      )}
      {ids.length === 0 ? (
        <div className="card">
          <EmptyState title="Nothing to compare yet" body="Add mines above, or try the example: three coal underground mines (100-499 employees) with different tiers." />
        </div>
      ) : res.error ? (
        <ErrorState message={res.error.message} onRetry={() => res.refetch()} />
      ) : !res.data ? (
        <Skeleton className="h-[520px]" />
      ) : (
        <motion.section initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} className="card overflow-x-auto">
          {samePeer && (
            <div className="border-b border-hair px-5 py-2.5 text-[12.5px] text-muted-foreground">
              Same peer group: <b className="font-medium text-foreground">{String(rows[0].peerGroup)}</b>, a fair comparison.
            </div>
          )}
          <table className="w-full min-w-[760px] text-[13px]">
            <thead>
              <tr className="border-b border-hair align-top">
                <th className="w-[230px] px-5 py-4 text-left">
                  <Provenance source="ANALYTICS.MINE_DIRECTORY" note="MINE_PROFILE plus MINE_EARLY_WARNING." />
                </th>
                {rows.map((r) => (
                  <th key={String(r.mineId)} className="px-4 py-4 text-left font-normal">
                    <div className="flex items-start justify-between gap-2">
                      <Link href={`/mine?id=${r.mineId}`} className="min-w-0 hover:underline">
                        <div className="truncate text-[15px] font-medium">{displayName(r.mineName)}</div>
                        <div className="mono text-[11.5px] text-muted-foreground">{String(r.mineId)}</div>
                      </Link>
                      <button onClick={() => setIds(ids.filter((x) => x !== r.mineId))} className="rounded-md p-1 hover:bg-muted" aria-label="Remove">
                        <X className="size-3.5" />
                      </button>
                    </div>
                    <div className="mt-2 flex flex-wrap items-center gap-2 text-[12px] text-muted-foreground">
                      <CategoryDot category={String(r.mineCategory)} />
                      <span>{String(r.mineType)}</span>
                      <span>{String(r.state)}</span>
                    </div>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              <Section label="Early-warning" />
              <tr className="border-b border-hair">
                <td className="px-5 py-2.5 text-muted-foreground">Tier</td>
                {rows.map((r) => (
                  <td key={String(r.mineId)} className="px-4 py-2.5">
                    <TierChip tier={String(r.tier)} />
                  </td>
                ))}
              </tr>
              {SIGNALS.map((s) => {
                const vals = rows.map((r) => n(r[GROUP_KEY[s]]))
                const w = worstIndex(vals)
                return (
                  <tr key={s} className="border-b border-hair">
                    <td className="px-5 py-2.5 text-muted-foreground">{SIGNAL_LABEL[s]}</td>
                    {rows.map((r, i) => (
                      <td key={String(r.mineId)} className={cn("px-4 py-2.5", i === w && "bg-amber-50/60")}>
                        <GroupChip group={vals[i]} label={SIGNAL_LABEL[s]} validated={isValidated(r.mineCategory as Category, s)} />
                      </td>
                    ))}
                  </tr>
                )
              })}
              <Section label="Last 4 complete quarters" />
              {METRICS.map(([label, get, f]) => {
                const vals = rows.map(get)
                const w = label === "Operator hours" ? -1 : worstIndex(vals)
                return (
                  <tr key={label} className="border-b border-hair">
                    <td className="px-5 py-2.5 text-muted-foreground">{label}</td>
                    {vals.map((v, i) => (
                      <td key={i} className={cn("num px-4 py-2.5", i === w && "bg-amber-50/60 font-medium text-amber")}>
                        {v === null ? "n/a" : f(v)}
                      </td>
                    ))}
                  </tr>
                )
              })}
              <Section label="Peer percentile (higher = worse vs own peer group)" />
              {PCTILES.map(([label, k]) => {
                const vals = rows.map((r) => n(r[k]))
                const w = worstIndex(vals)
                return (
                  <tr key={k} className="border-b border-hair last:border-0">
                    <td className="px-5 py-2.5 text-muted-foreground">{label}</td>
                    {vals.map((v, i) => (
                      <td key={i} className={cn("px-4 py-2.5", i === w && "bg-amber-50/60")}>
                        {v === null ? (
                          <span className="text-muted-foreground">n/a</span>
                        ) : (
                          <span className="flex items-center gap-2">
                            <span className="h-1.5 w-20 overflow-hidden rounded-full bg-[#f1f2f4]">
                              <span className="block h-full rounded-full" style={{ width: `${v * 100}%`, background: i === w ? "#d97706" : "#0b2545" }} />
                            </span>
                            <span className={cn("num", i === w && "font-medium text-amber")}>{fmt.pctile(v)}</span>
                          </span>
                        )}
                      </td>
                    ))}
                  </tr>
                )
              })}
            </tbody>
          </table>
          {res.data.missing.length > 0 && (
            <div className="border-t border-hair px-5 py-2.5 text-[12.5px] text-muted-foreground">
              Not found in the portal Mines dataset: <span className="mono">{res.data.missing.join(", ")}</span>
            </div>
          )}
        </motion.section>
      )}
      <ProxyNote className="mt-3" />
    </div>
  )
}

function Section({ label }: { label: string }) {
  return (
    <tr className="bg-[#fbfbfa]">
      <td colSpan={4} className="eyebrow px-5 py-2">
        {label}
      </td>
    </tr>
  )
}

/** Search box that adds a mine to the comparison instead of navigating. */
function AddMine({ onAdd }: { onAdd: (id: string) => void }) {
  return <MineSearch onPickId={onAdd} />
}
