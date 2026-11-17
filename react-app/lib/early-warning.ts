/*
 * Early-warning tier: TypeScript mirror of ANALYTICS.MINE_EARLY_WARNING (sql/11_app_views.sql).
 * The SQL Dynamic Table is the source of truth (the watch list ranks thousands of
 * mines there); this file mirrors its labels, thresholds and rule so the UI can
 * explain a tier, and the parity test can prove the two agree.
 *
 * Illustrative only: not an official MSHA rating or a prediction for one mine.
 */

export type Category = "Coal" | "Metal/Nonmetal"
export type Tier = "Elevated" | "Watch" | "Typical" | "Not enough recent hours"
export type Signal = "PRIOR_INJURY_RATE" | "VENTILATION_METHANE" | "UNWARRANTABLE_IMMINENT" | "HIGH_NEGLIGENCE"
/** 0 = none, 1-4 = quartile of non-zero values within mine category (4 = highest). */
export type Group = 0 | 1 | 2 | 3 | 4

export const MIN_RECENT_HOURS = 20_000

export const SIGNALS: Signal[] = ["PRIOR_INJURY_RATE", "VENTILATION_METHANE", "UNWARRANTABLE_IMMINENT", "HIGH_NEGLIGENCE"]

export const SIGNAL_LABEL: Record<Signal, string> = {
  PRIOR_INJURY_RATE: "Prior injury rate",
  VENTILATION_METHANE: "Ventilation/methane citations",
  UNWARRANTABLE_IMMINENT: "104(d)/107(a) actions",
  HIGH_NEGLIGENCE: "High-negligence citations",
}

export const SIGNAL_UNIT: Record<Signal, string> = {
  PRIOR_INJURY_RATE: "operator injuries per 200K hrs",
  VENTILATION_METHANE: "citations per 200K hrs (compliance proxy)",
  UNWARRANTABLE_IMMINENT: "actions per 200K hrs",
  HIGH_NEGLIGENCE: "citations per 200K hrs",
}

export const GROUP_LABEL: Record<Group, string> = { 0: "None", 1: "Low", 2: "Med-low", 3: "Med-high", 4: "Highest" }

export const TIER_RANK: Record<Tier, number> = { Elevated: 3, Watch: 2, Typical: 1, "Not enough recent hours": 0 }

export const DISCLAIMER =
  "An illustrative early-warning indicator built from public MSHA data. It shows which mines look like the groups that had more injuries the next quarter. It is not an official MSHA rating or a prediction for this mine."

/** Phase 3 verdicts: coal holds up on all four signals; metal/nonmetal on prior injury rate only. */
export function isValidated(category: Category, signal: Signal): boolean {
  return signal === "PRIOR_INJURY_RATE" || category === "Coal"
}

/** Group for a value given the upper bounds of quartiles 1-3 (null bound = signal has no non-zero history). */
export function groupFor(value: number | null, ub: [number | null, number | null, number | null]): Group | null {
  if (value === null || Number.isNaN(value)) return null
  if (value === 0 || ub[0] === null) return 0
  if (value <= ub[0]) return 1
  if (ub[1] !== null && value <= ub[1]) return 2
  if (ub[2] !== null && value <= ub[2]) return 3
  return 4
}

export interface TierInput {
  category: Category
  hours: number
  groups: Record<Signal, Group | null>
}

export function computeTier({ category, hours, groups }: TierInput): Tier {
  if (!(hours >= MIN_RECENT_HOURS)) return "Not enough recent hours"
  const g = (s: Signal) => groups[s] ?? 0
  const validatedHighest = SIGNALS.filter((s) => isValidated(category, s) && g(s) === 4).length
  // Other signals (besides prior injury) at group >= 3. Vent/methane only counts for coal;
  // for metal/nonmetal 104(d)/107(a) and high negligence count as corroborating only.
  const otherGe3 = (["VENTILATION_METHANE", "UNWARRANTABLE_IMMINENT", "HIGH_NEGLIGENCE"] as Signal[]).filter(
    (s) => (s !== "VENTILATION_METHANE" || category === "Coal") && g(s) >= 3,
  ).length
  if (validatedHighest >= 2 || (g("PRIOR_INJURY_RATE") === 4 && otherGe3 >= 1)) return "Elevated"
  if (SIGNALS.some((s) => isValidated(category, s) && g(s) >= 3)) return "Watch"
  return "Typical"
}

export function validatedHighestCount(category: Category, groups: Record<Signal, Group | null>): number {
  return SIGNALS.filter((s) => isValidated(category, s) && groups[s] === 4).length
}

/**
 * One decimal, no padding, half away from zero (matches SQL TO_VARCHAR(n, 'FM990.0')).
 * Evidence values are NUMBER(10,2): round via integer hundredths so 1.45 -> "1.5",
 * not the float artifact "1.4".
 */
export function fmt1(n: number): string {
  const hundredths = Math.round(Math.abs(n) * 100)
  const tenths = Math.floor((hundredths + 5) / 10)
  return `${n < 0 ? "-" : ""}${Math.floor(tenths / 10)}.${tenths % 10}`
}

/**
 * Reason line for one signal, identical to the SQL tier_reasons entry, or null when the
 * signal is below group 3. evidence = pooled next-quarter rate for the mine's group;
 * baseline = rate for mines with none.
 */
export function reasonText(
  category: Category,
  signal: Signal,
  group: Group | null,
  evidence: number | null,
  baseline: number | null,
): string | null {
  if (group === null || group < 3 || evidence === null || baseline === null) return null
  const suffix =
    category !== "Coal" && (signal === "UNWARRANTABLE_IMMINENT" || signal === "HIGH_NEGLIGENCE")
      ? " - corroborating only for metal/nonmetal"
      : ""
  return `${SIGNAL_LABEL[signal]}: ${group === 4 ? "Highest" : "Med-high"} group (${fmt1(evidence)} vs ${fmt1(baseline)} for mines with none)${suffix}`
}

export const NOT_ENOUGH_HOURS_REASON = "Fewer than 20,000 operator hours in the last 4 quarters"

export const TIER_STYLE: Record<Tier, { chip: string; dot: string; blurb: string }> = {
  Elevated: {
    chip: "bg-amber-50 text-[#9a5b06] border-[#f6e2bf]",
    dot: "bg-amber",
    blurb: "Looks like the groups with the most injuries the next quarter.",
  },
  Watch: {
    chip: "bg-[#eef3fa] text-navy border-[#d9e3f2]",
    dot: "bg-navy",
    blurb: "At least one screened signal is in the upper half.",
  },
  Typical: {
    chip: "bg-teal-50 text-teal border-[#cfe9e7]",
    dot: "bg-teal",
    blurb: "No screened signal in the upper half.",
  },
  "Not enough recent hours": {
    chip: "bg-muted text-muted-foreground border-hair",
    dot: "bg-[#c4c4c8]",
    blurb: "Under 20,000 operator hours in the last 4 quarters, too few to rate.",
  },
}
