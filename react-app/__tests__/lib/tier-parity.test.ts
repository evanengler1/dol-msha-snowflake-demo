/**
 * Parity: the SQL Dynamic Table ANALYTICS.MINE_EARLY_WARNING and lib/early-warning.ts
 * must agree on group, tier and reason text for sampled mines (5 per tier, both categories).
 * Runs against Snowflake when SNOWFLAKE_CONNECTION_NAME is set (local dev); skipped otherwise.
 */
import { afterAll, describe, expect, it } from "vitest"
import { closePool, querySnowflake } from "../../lib/sar-sdk"
import {
  computeTier,
  groupFor,
  reasonText,
  SIGNALS,
  NOT_ENOUGH_HOURS_REASON,
  type Category,
  type Group,
  type Signal,
} from "../../lib/early-warning"

const live = !!process.env.SNOWFLAKE_CONNECTION_NAME
const WH = "DOL_MSHA_WH"
const COL: Record<Signal, string> = {
  PRIOR_INJURY_RATE: "PRIOR_INJURY_RATE",
  VENTILATION_METHANE: "VENTILATION_METHANE",
  UNWARRANTABLE_IMMINENT: "UNWARRANTABLE_IMMINENT",
  HIGH_NEGLIGENCE: "HIGH_NEGLIGENCE",
}

describe.skipIf(!live)("SQL vs TS tier parity", () => {
  afterAll(() => closePool())

  it("agrees for ~20 sampled mines", async () => {
    const ref = await querySnowflake(
      `SELECT MINE_CATEGORY, SIGNAL, SIGNAL_GROUP, GROUP_MAX_VALUE, NEXT_QUARTER_INJURY_RATE
       FROM DOL_MSHA_DEMO.ANALYTICS.EARLY_WARNING_REFERENCE`,
      { warehouse: WH },
    )
    const sample = await querySnowflake(
      `SELECT e.*, p.LAST_4Q_INJURIES AS INJ, p.LAST_4Q_VENTILATION_METHANE_VIOLATIONS AS VENT,
              p.LAST_4Q_UNWARRANTABLE_FAILURE_IMMINENT_DANGER_ACTIONS AS UFID, p.LAST_4Q_HIGH_NEGLIGENCE_VIOLATIONS AS HN
       FROM DOL_MSHA_DEMO.ANALYTICS.MINE_EARLY_WARNING e
       JOIN DOL_MSHA_DEMO.ANALYTICS.MINE_DIRECTORY p ON p.MINE_ID = e.MINE_ID
       QUALIFY ROW_NUMBER() OVER (PARTITION BY e.TIER ORDER BY HASH(e.MINE_ID)) <= 5`,
      { warehouse: WH },
    )
    expect(sample.length).toBeGreaterThanOrEqual(18)

    const bound = (cat: string, sig: Signal, grp: number) => {
      const r = ref.find((x) => x.MINE_CATEGORY === cat && x.SIGNAL === sig && Number(x.SIGNAL_GROUP) === grp)
      return r ? Number(r.GROUP_MAX_VALUE) : null
    }
    const rate = (cat: string, sig: Signal, grp: number) => {
      const r = ref.find((x) => x.MINE_CATEGORY === cat && x.SIGNAL === sig && Number(x.SIGNAL_GROUP) === grp)
      return r ? Number(r.NEXT_QUARTER_INJURY_RATE) : null
    }

    for (const m of sample) {
      const cat = m.MINE_CATEGORY as Category
      const hours = Number(m.LAST_4Q_OPERATOR_HOURS)
      // Recompute each signal's value (per 200K hours) and group from raw counts
      const counts: Record<Signal, number> = {
        PRIOR_INJURY_RATE: Number(m.INJ),
        VENTILATION_METHANE: Number(m.VENT),
        UNWARRANTABLE_IMMINENT: Number(m.UFID),
        HIGH_NEGLIGENCE: Number(m.HN),
      }
      const groups = {} as Record<Signal, Group | null>
      for (const s of SIGNALS) {
        const v = hours > 0 ? (counts[s] * 200000) / hours : null
        groups[s] = groupFor(v, [bound(cat, s, 1), bound(cat, s, 2), bound(cat, s, 3)])
        if (hours >= 20000) expect(groups[s], `${m.MINE_ID} ${s} group`).toBe(m[`${COL[s]}_GROUP`] === null ? null : Number(m[`${COL[s]}_GROUP`]))
      }
      const tier = computeTier({ category: cat, hours, groups })
      expect(tier, `${m.MINE_ID} tier`).toBe(m.TIER)

      const sqlReasons = typeof m.TIER_REASONS === "string" ? JSON.parse(m.TIER_REASONS) : m.TIER_REASONS
      const tsReasons =
        tier === "Not enough recent hours"
          ? [NOT_ENOUGH_HOURS_REASON]
          : SIGNALS.map((s) => reasonText(cat, s, groups[s], groups[s] === null ? null : rate(cat, s, groups[s]!), rate(cat, s, 0))).filter(Boolean)
      expect(tsReasons, `${m.MINE_ID} reasons`).toEqual(sqlReasons)
    }
  }, 120_000)
})
