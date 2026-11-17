"use client"

import { useRouter, useSearchParams } from "next/navigation"
import { Download } from "lucide-react"
import { useCallback, useMemo } from "react"
import { displayName, downloadCsv, fmt, useApi } from "@/lib/client"
import { SIGNAL_LABEL, isValidated, type Category } from "@/lib/early-warning"
import { EmptyState, ErrorState, GroupChip, PageHeader, Provenance, Skeleton, TierChip, Tip, useRowKeys } from "@/components/kit"
import { cn } from "@/lib/utils"

type R = Record<string, unknown>
interface Lists {
  districts: { district: string; mines: number }[]
  offices: { district: string; officeName: string; mines: number }[]
}

const SIG_COLS = [
  ["priorInjuryRateGroup", "PRIOR_INJURY_RATE", "Prior inj."],
  ["ventilationMethaneGroup", "VENTILATION_METHANE", "Vent/meth."],
  ["unwarrantableImminentGroup", "UNWARRANTABLE_IMMINENT", "104(d)/107(a)"],
  ["highNegligenceGroup", "HIGH_NEGLIGENCE", "High neg."],
] as const

const GROUP_TXT = ["None", "Low", "Med-low", "Med-high", "Highest"]

function Select({ label, value, onChange, children }: { label: string; value: string; onChange: (v: string) => void; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="eyebrow">{label}</span>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="h-9 min-w-[180px] rounded-lg border border-hair bg-white px-2.5 text-[13px] outline-none focus:border-[#c7ced8]"
      >
        {children}
      </select>
    </label>
  )
}

export default function WatchList() {
  const router = useRouter()
  const sp = useSearchParams()
  const lists = useApi<Lists>("/api/lists", { staleTime: 3_600_000 })
  const district = sp.get("district") ?? (lists.data?.districts.find((d) => d.district === "C04")?.district ?? lists.data?.districts[0]?.district ?? "")
  const office = sp.get("office") ?? ""
  const category = sp.get("category") ?? "All"
  const set = (patch: Record<string, string>) => {
    const p = new URLSearchParams({ district, office, category, ...patch })
    if (!p.get("office")) p.delete("office")
    if (p.get("category") === "All") p.delete("category")
    router.replace(`/watchlist?${p.toString()}`)
  }
  const qs = new URLSearchParams({ district, ...(office ? { office } : {}), ...(category !== "All" ? { category } : {}) })
  const res = useApi<{ rows: R[] }>(district ? `/api/watchlist?${qs.toString()}` : null, { placeholderData: (p) => p })
  const rows = res.data?.rows ?? []
  const rated = rows.filter((r) => r.tier !== "Not enough recent hours")
  const unrated = rows.length - rated.length
  const open = useCallback((i: number) => rated[i] && router.push(`/mine?id=${rated[i].mineId}`), [rated, router])
  const active = useRowKeys(rated.length, open)
  const offices = useMemo(() => (lists.data?.offices ?? []).filter((o) => o.district === district), [lists.data, district])
  const counts = useMemo(() => ({ E: rated.filter((r) => r.tier === "Elevated").length, W: rated.filter((r) => r.tier === "Watch").length }), [rated])

  const exportCsv = () =>
    downloadCsv(
      `msha-watchlist-${district}${office ? "-" + office.replace(/\W+/g, "_") : ""}.csv`,
      [
        { key: "tier", label: "Tier" },
        { key: "mineId", label: "Mine ID" },
        { key: "mineName", label: "Mine" },
        { key: "mineCategory", label: "Category" },
        { key: "operatorName", label: "Operator" },
        { key: "officeName", label: "Field office" },
        { key: "lastInspection", label: "Last inspection" },
        ...SIG_COLS.map(([k, , l]) => ({ key: `${k}Txt`, label: `${l} group` })),
        { key: "last4qInjuries", label: "Injuries (last 4Q)" },
        { key: "openDelinquentPenaltyBalanceUsd", label: "Open/delinquent balance USD" },
      ],
      rated.map((r) => ({
        ...r,
        lastInspection: r.lastInspectionDate ? String(r.lastInspectionDate).slice(0, 10) : "",
        ...Object.fromEntries(SIG_COLS.map(([k]) => [`${k}Txt`, r[k] === null || r[k] === undefined ? "" : GROUP_TXT[Number(r[k])]])),
      })),
    )

  return (
    <div>
      <PageHeader
        eyebrow="District watch list"
        title="Which mines should we visit first?"
        sub="Mines with at least 20,000 operator hours in the last 4 quarters, ranked by early-warning tier, then the number of screened signals in the Highest group, then prior injury rate."
      />
      <div className="card mb-4 flex flex-wrap items-end gap-4 p-4">
        {lists.error ? (
          <span className="text-[13px] text-muted-foreground">Filters are unavailable right now.</span>
        ) : !lists.data ? (
          <Skeleton className="h-14 w-full" />
        ) : (
          <>
            <Select label="MSHA district" value={district} onChange={(v) => set({ district: v, office: "" })}>
              {lists.data.districts.map((d) => (
                <option key={d.district} value={d.district}>
                  {d.district} ({d.district.startsWith("C") ? "coal" : "metal/nonmetal"}) · {fmt.int(d.mines)} mines
                </option>
              ))}
            </Select>
            <Select label="Field office" value={office} onChange={(v) => set({ office: v })}>
              <option value="">All field offices</option>
              {offices.map((o) => (
                <option key={o.officeName} value={o.officeName}>
                  {o.officeName} · {fmt.int(o.mines)}
                </option>
              ))}
            </Select>
            <Select label="Category" value={category} onChange={(v) => set({ category: v })}>
              {["All", "Coal", "Metal/Nonmetal"].map((c) => (
                <option key={c}>{c}</option>
              ))}
            </Select>
            <div className="ml-auto flex items-center gap-3">
              <span className="text-[12.5px] text-muted-foreground">
                <b className="num font-medium text-amber">{counts.E}</b> Elevated · <b className="num font-medium text-navy">{counts.W}</b> Watch ·{" "}
                <span className="num">{rated.length}</span> rated
              </span>
              <button
                onClick={exportCsv}
                disabled={rated.length === 0}
                className="flex h-9 items-center gap-2 rounded-full border border-hair bg-white px-4 text-[13px] font-medium hover:bg-muted disabled:opacity-40"
              >
                <Download className="size-4" /> Export CSV
              </button>
            </div>
          </>
        )}
      </div>

      <section className="card overflow-hidden">
        <div className="flex items-center justify-between border-b border-hair px-5 py-3">
          <span className="text-[12.5px] text-muted-foreground">
            Press <span className="kbd">j</span> <span className="kbd">k</span> to move, <span className="kbd">enter</span> to open.
            {unrated > 0 && <> {fmt.int(unrated)} more mines in this view have too few recent hours to rate.</>}
          </span>
          <Provenance source="ANALYTICS.MINE_EARLY_WARNING" />
        </div>
        {res.error ? (
          <div className="p-5">
            <ErrorState message={res.error.message} onRetry={() => res.refetch()} />
          </div>
        ) : !res.data ? (
          <div className="space-y-2 p-5">
            {Array.from({ length: 8 }).map((_, i) => (
              <Skeleton key={i} className="h-9" />
            ))}
          </div>
        ) : rated.length === 0 ? (
          <EmptyState title="No rated mines here" body="No mine in this district, office and category has 20,000+ operator hours in the last 4 quarters." />
        ) : (
          <div className={cn("overflow-x-auto transition-opacity", res.isFetching && "opacity-60")}>
            <table className="w-full min-w-[1180px] text-[12.5px]">
              <thead className="sticky top-0 bg-white">
                <tr className="border-b border-hair text-left">
                  <th className="eyebrow px-5 py-2 font-medium">#</th>
                  <th className="eyebrow py-2 font-medium">Tier</th>
                  <th className="eyebrow py-2 font-medium">Mine</th>
                  <th className="eyebrow py-2 font-medium">Operator</th>
                  <th className="eyebrow py-2 font-medium">Last inspection</th>
                  {SIG_COLS.map(([, s, l]) => (
                    <th key={s} className="eyebrow whitespace-nowrap py-2 pr-2 font-medium">
                      <Tip content={<span>{SIGNAL_LABEL[s]}, last 4 quarters, grouped as in the leading-indicator analysis.</span>}>
                        <span>{l}</span>
                      </Tip>
                    </th>
                  ))}
                  <th className="eyebrow py-2 text-right font-medium">Injuries 4Q</th>
                  <th className="eyebrow px-5 py-2 text-right font-medium">Open balance</th>
                </tr>
              </thead>
              <tbody>
                {rated.map((r, i) => (
                  <tr
                    key={String(r.mineId)}
                    data-row={i}
                    onClick={() => router.push(`/mine?id=${r.mineId}`)}
                    className={cn("cursor-pointer border-b border-hair last:border-0 hover:bg-[#f7f9fc]", active === i && "bg-[#eef3fa]")}
                  >
                    <td className="num px-5 py-2 text-muted-foreground">{i + 1}</td>
                    <td className="py-2">
                      <TierChip tier={String(r.tier)} />
                    </td>
                    <td className="max-w-[240px] py-2 pr-3">
                      <div className="truncate font-medium">{displayName(r.mineName)}</div>
                      <div className="flex gap-2 text-[11.5px] text-muted-foreground">
                        <span className="mono">{String(r.mineId)}</span>
                        <span>{String(r.mineType)}</span>
                        <span>{String(r.state)}</span>
                      </div>
                    </td>
                    <td className="max-w-[200px] truncate py-2 pr-3">{displayName(r.operatorName)}</td>
                    <td className="num whitespace-nowrap py-2 pr-3">{fmt.date(r.lastInspectionDate)}</td>
                    {SIG_COLS.map(([k, s]) => (
                      <td key={k} className="py-2 pr-2">
                        <GroupChip group={r[k] as number | null} label={SIGNAL_LABEL[s]} validated={isValidated(r.mineCategory as Category, s)} />
                      </td>
                    ))}
                    <td className="num py-2 text-right">{fmt.int(r.last4qInjuries)}</td>
                    <td className={cn("num px-5 py-2 text-right", Number(r.openDelinquentPenaltyBalanceUsd ?? 0) > 0 && "text-amber")}>
                      {fmt.usd(r.openDelinquentPenaltyBalanceUsd)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
      <p className="mt-3 text-[12px] text-muted-foreground">
        Tiers are an illustrative early-warning indicator from public MSHA data, not an official MSHA rating or a prediction for any mine.
        Dashed chips are corroborating-only signals for metal/nonmetal mines.
      </p>
    </div>
  )
}
