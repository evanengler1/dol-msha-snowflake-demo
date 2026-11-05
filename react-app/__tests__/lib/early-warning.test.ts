import { describe, expect, it } from "vitest"
import {
  computeTier,
  fmt1,
  groupFor,
  isValidated,
  reasonText,
  validatedHighestCount,
  type Group,
  type Signal,
} from "../../lib/early-warning"

const g = (inj: Group, vent: Group, ufid: Group, hn: Group): Record<Signal, Group> => ({
  PRIOR_INJURY_RATE: inj,
  VENTILATION_METHANE: vent,
  UNWARRANTABLE_IMMINENT: ufid,
  HIGH_NEGLIGENCE: hn,
})

describe("groupFor (Phase 3 quartile cut points)", () => {
  const ub: [number, number, number] = [2.3007, 4.1861, 6.9239] // coal prior injury rate
  it("zero is the None group", () => expect(groupFor(0, ub)).toBe(0))
  it("upper bounds are inclusive", () => {
    expect(groupFor(2.3007, ub)).toBe(1)
    expect(groupFor(4.1861, ub)).toBe(2)
    expect(groupFor(6.9239, ub)).toBe(3)
  })
  it("just above a bound moves up a group", () => {
    expect(groupFor(2.3008, ub)).toBe(2)
    expect(groupFor(6.924, ub)).toBe(4)
  })
  it("a signal with no non-zero history is always None", () => expect(groupFor(12, [null, null, null])).toBe(0))
  it("missing value has no group", () => expect(groupFor(null, ub)).toBeNull())
})

describe("computeTier", () => {
  it("needs 20,000 operator hours", () => {
    expect(computeTier({ category: "Coal", hours: 19_999, groups: g(4, 4, 4, 4) })).toBe("Not enough recent hours")
    expect(computeTier({ category: "Coal", hours: 20_000, groups: g(0, 0, 0, 0) })).toBe("Typical")
  })
  it("coal: two validated signals in the Highest group is Elevated", () => {
    expect(computeTier({ category: "Coal", hours: 50_000, groups: g(0, 4, 0, 4) })).toBe("Elevated")
  })
  it("coal: prior injury Highest plus another signal at Med-high is Elevated", () => {
    expect(computeTier({ category: "Coal", hours: 50_000, groups: g(4, 0, 3, 0) })).toBe("Elevated")
  })
  it("coal: prior injury Highest alone is Watch", () => {
    expect(computeTier({ category: "Coal", hours: 50_000, groups: g(4, 2, 2, 2) })).toBe("Watch")
  })
  it("coal: one Highest non-injury signal plus Med-high signals is Watch", () => {
    expect(computeTier({ category: "Coal", hours: 50_000, groups: g(3, 4, 3, 3) })).toBe("Watch")
  })
  it("coal: everything at Med-low or below is Typical", () => {
    expect(computeTier({ category: "Coal", hours: 50_000, groups: g(2, 2, 2, 2) })).toBe("Typical")
  })
  it("M/NM: only prior injury rate sets Watch", () => {
    expect(computeTier({ category: "Metal/Nonmetal", hours: 50_000, groups: g(0, 0, 4, 4) })).toBe("Typical")
    expect(computeTier({ category: "Metal/Nonmetal", hours: 50_000, groups: g(3, 0, 0, 0) })).toBe("Watch")
  })
  it("M/NM: prior injury Highest plus a corroborating signal is Elevated", () => {
    expect(computeTier({ category: "Metal/Nonmetal", hours: 50_000, groups: g(4, 0, 3, 0) })).toBe("Elevated")
    expect(computeTier({ category: "Metal/Nonmetal", hours: 50_000, groups: g(4, 0, 2, 2) })).toBe("Watch")
  })
  it("validated-highest count respects category", () => {
    expect(validatedHighestCount("Coal", g(4, 4, 4, 4))).toBe(4)
    expect(validatedHighestCount("Metal/Nonmetal", g(4, 4, 4, 4))).toBe(1)
    expect(isValidated("Metal/Nonmetal", "HIGH_NEGLIGENCE")).toBe(false)
  })
})

describe("reasonText", () => {
  it("matches the SQL wording for a Highest group", () => {
    expect(reasonText("Coal", "PRIOR_INJURY_RATE", 4, 7.17, 1.43)).toBe(
      "Prior injury rate: Highest group (7.2 vs 1.4 for mines with none)",
    )
  })
  it("Med-high group and one-decimal rounding", () => {
    expect(reasonText("Coal", "VENTILATION_METHANE", 3, 4.99, 1.47)).toBe(
      "Ventilation/methane citations: Med-high group (5.0 vs 1.5 for mines with none)",
    )
  })
  it("no reason below group 3", () => {
    expect(reasonText("Coal", "HIGH_NEGLIGENCE", 2, 4.46, 2.12)).toBeNull()
    expect(reasonText("Coal", "HIGH_NEGLIGENCE", null, 4.46, 2.12)).toBeNull()
  })
  it("marks corroborating signals for metal/nonmetal", () => {
    expect(reasonText("Metal/Nonmetal", "UNWARRANTABLE_IMMINENT", 4, 3.64, 1.91)).toBe(
      "104(d)/107(a) actions: Highest group (3.6 vs 1.9 for mines with none) - corroborating only for metal/nonmetal",
    )
  })
  it("fmt1 rounds half away from zero like TO_VARCHAR FM990.0", () => {
    expect(fmt1(1.45)).toBe("1.5")
    expect(fmt1(2.25)).toBe("2.3")
    expect(fmt1(0.04)).toBe("0.0")
    expect(fmt1(10)).toBe("10.0")
  })
})
