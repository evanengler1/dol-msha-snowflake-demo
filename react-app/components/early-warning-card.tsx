"use client"

import { motion, useReducedMotion } from "framer-motion"
import { Info } from "lucide-react"
import {
  DISCLAIMER,
  GROUP_LABEL,
  isValidated,
  SIGNAL_LABEL,
  SIGNAL_UNIT,
  SIGNALS,
  TIER_STYLE,
  type Category,
  type Group,
  type Signal,
  type Tier,
} from "@/lib/early-warning"
import { fmt } from "@/lib/client"
import { GroupChip, Provenance, TierChip, Tip } from "@/components/kit"
import { cn } from "@/lib/utils"

export type EarlyWarningRow = Record<string, unknown> & {
  tier: string
  mineCategory: string
  tierReasons: string[] | null
}

const KEY: Record<Signal, string> = {
  PRIOR_INJURY_RATE: "priorInjuryRate",
  VENTILATION_METHANE: "ventilationMethane",
  UNWARRANTABLE_IMMINENT: "unwarrantableImminent",
  HIGH_NEGLIGENCE: "highNegligence",
}

export function signalOf(row: Record<string, unknown>, s: Signal) {
  const k = KEY[s]
  return {
    group: (row[`${k}Group`] ?? null) as Group | null,
    value: (row[`${k}Value`] ?? null) as number | null,
    evidence: (row[`${k}EvidenceRate`] ?? null) as number | null,
    evidencePct: (row[`${k}EvidencePct`] ?? null) as number | null,
    baseline: (row[`${k}BaselineRate`] ?? null) as number | null,
  }
}

/** Evidence bar: next-quarter rate for the mine's group vs mines with none (Phase 3 Leading Indicators). */
function EvidenceBar({ evidence, baseline, max, hot }: { evidence: number; baseline: number; max: number; hot: boolean }) {
  const reduce = useReducedMotion()
  const w = (v: number) => `${Math.max(2, (v / max) * 100)}%`
  return (
    <div className="space-y-1">
      <div className="flex items-center gap-2">
        <div className="relative h-2 flex-1 overflow-hidden rounded-full bg-[#f1f2f4]">
          <motion.div
            className="absolute inset-y-0 left-0 rounded-full"
            style={{ background: hot ? "#d97706" : "#0b2545" }}
            initial={{ width: reduce ? w(evidence) : 0 }}
            animate={{ width: w(evidence) }}
            transition={{ duration: 0.9, ease: [0.25, 1, 0.5, 1] }}
          />
        </div>
        <span className={cn("num w-10 text-right text-[12.5px] font-medium", hot && "text-amber")}>{evidence.toFixed(1)}</span>
      </div>
      <div className="flex items-center gap-2">
        <div className="relative h-2 flex-1 overflow-hidden rounded-full bg-[#f1f2f4]">
          <div className="absolute inset-y-0 left-0 rounded-full bg-teal/70" style={{ width: w(baseline) }} />
        </div>
        <span className="num w-10 text-right text-[12.5px] text-muted-foreground">{baseline.toFixed(1)}</span>
      </div>
    </div>
  )
}

export function EarlyWarningCard({ ew, hours }: { ew: EarlyWarningRow | null; hours: number | null }) {
  const tier = (ew?.tier ?? "Not enough recent hours") as Tier
  const category = (ew?.mineCategory ?? "Coal") as Category
  const rated = tier !== "Not enough recent hours"
  const rows = SIGNALS.map((s) => ({ s, ...(ew ? signalOf(ew, s) : { group: null, value: null, evidence: null, evidencePct: null, baseline: null }) }))
  const max = Math.max(1, ...rows.map((r) => Math.max(r.evidence ?? 0, r.baseline ?? 0))) * 1.08

  return (
    <section
      className={cn("card relative overflow-hidden p-5", tier === "Elevated" && "border-[#f6e2bf]")}
      style={tier === "Elevated" ? { background: "linear-gradient(180deg,#fffaf2 0%,#ffffff 38%)" } : undefined}
    >
      <header className="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="eyebrow mb-2">Early-warning indicator</div>
          <div className="flex flex-wrap items-center gap-3">
            <TierChip tier={tier} size="lg" />
            <span className="text-[13.5px] text-muted-foreground">{TIER_STYLE[tier].blurb}</span>
          </div>
        </div>
        <Provenance source="ANALYTICS.MINE_EARLY_WARNING" note="Dynamic Table built from LEADING_INDICATORS cut points (sql/11_app_views.sql)." />
      </header>

      {!rated ? (
        <div className="rounded-lg border border-hair bg-[#fbfbfa] p-4 text-[13.5px] leading-relaxed">
          <b className="font-medium">Not enough recent hours.</b> This mine reported {hours ? fmt.int(hours) : "no"} operator hours in the
          last 4 quarters. Rates are unstable below 20,000 hours (about 10 full-time miners), so no tier is shown. The briefing below
          still lists its citations and accidents.
        </div>
      ) : (
        <>
          {ew?.tierReasons && ew.tierReasons.length > 0 && (
            <ul className="mb-4 space-y-1.5">
              {ew.tierReasons.map((r) => (
                <li key={r} className="flex gap-2 text-[13.5px]">
                  <span className="mt-[7px] size-1.5 shrink-0 rounded-full bg-amber" />
                  {r}
                </li>
              ))}
            </ul>
          )}
          <div className="mb-2 hidden grid-cols-[1.3fr_88px_1.4fr] gap-4 text-[11px] text-muted-foreground md:grid">
            <span className="eyebrow">Signal (last 4 quarters)</span>
            <span className="eyebrow">Group</span>
            <span className="eyebrow">
              Next-quarter injuries per 200K hrs: <span className="text-amber">this group</span> vs <span className="text-teal">none</span>
            </span>
          </div>
          <div className="divide-y divide-hair">
            {rows.map((r) => {
              const validated = isValidated(category, r.s)
              const ventNa = r.s === "VENTILATION_METHANE" && category !== "Coal"
              return (
                <div key={r.s} className="grid gap-x-4 gap-y-2 py-3 md:grid-cols-[1.3fr_88px_1.4fr] md:items-center">
                  <div className="min-w-0">
                    <div className="flex items-center gap-1.5 text-[13.5px] font-medium">
                      {SIGNAL_LABEL[r.s]}
                      {ventNa ? (
                        <Tip content={<span>Ventilation/methane citations are essentially zero across metal/nonmetal mines, so this signal is not used for them.</span>}>
                          <span className="inline-flex h-4 items-center rounded-full border border-dashed border-hair px-1.5 text-[10px] font-normal text-muted-foreground">
                            not used
                          </span>
                        </Tip>
                      ) : !validated && (
                        <Tip content={<span>The leading-indicator analysis found this signal does not separate risk for metal/nonmetal mines. It can corroborate a high prior injury rate but never sets the tier on its own.</span>}>
                          <span className="inline-flex h-4 items-center rounded-full border border-dashed border-hair px-1.5 text-[10px] font-normal text-muted-foreground">
                            corroborating
                          </span>
                        </Tip>
                      )}
                    </div>
                    <div className="text-[12px] text-muted-foreground">
                      <span className="num text-foreground">{r.value === null ? "n/a" : r.value.toFixed(2)}</span> {SIGNAL_UNIT[r.s]}
                    </div>
                  </div>
                  <div>
                    <GroupChip group={r.group} label={SIGNAL_LABEL[r.s]} validated={validated} />
                  </div>
                  <div className="min-w-0">
                    {ventNa ? (
                      <span className="text-[12px] text-muted-foreground">Too sparse for metal/nonmetal mines to measure.</span>
                    ) : r.evidence !== null && r.baseline !== null ? (
                      <Tip
                        content={
                          <span>
                            Mines in the <b>{GROUP_LABEL[(r.group ?? 0) as Group]}</b> group had <b>{r.evidence.toFixed(1)}</b> injuries per 200K hours the
                            next quarter vs <b>{r.baseline.toFixed(1)}</b> for mines with none
                            {r.evidencePct !== null && <>; {r.evidencePct.toFixed(0)}% of those mine-quarters had any injury</>}. Pooled over{" "}
                            {category.toLowerCase()} mine-quarters since 2010.
                          </span>
                        }
                      >
                        <div>
                          <EvidenceBar evidence={r.evidence} baseline={r.baseline} max={max} hot={(r.group ?? 0) >= 3 && validated} />
                        </div>
                      </Tip>
                    ) : (
                      <span className="text-[12px] text-muted-foreground">n/a</span>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        </>
      )}
      <p className="mt-4 flex gap-2 rounded-lg bg-[#fbfbfa] p-3 text-[12px] leading-relaxed text-muted-foreground">
        <Info className="mt-0.5 size-3.5 shrink-0" />
        {DISCLAIMER}
      </p>
    </section>
  )
}
