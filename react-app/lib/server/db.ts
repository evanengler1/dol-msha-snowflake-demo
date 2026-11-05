import "server-only"
import { querySnowflake } from "@/lib/snowflake"

/*
 * Read-only query layer. Owner's rights everywhere: the app reads public MSHA
 * data through DOL_MSHA_DEMO_ROLE (locally) or the app service role (SPCS).
 * Every user value goes through binds; column and object names are constants.
 */

export const WAREHOUSE = "DOL_MSHA_WH"
export const DB = "DOL_MSHA_DEMO.ANALYTICS"

export type Row = Record<string, unknown>
type Bind = string | number | boolean | null

/** UPPER_SNAKE -> camelCase */
function camel(key: string): string {
  return key.toLowerCase().replace(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase())
}

/**
 * Numeric strings become numbers, except identifier-like columns (mineId,
 * operatorId, ...) and strings with a significant leading zero: mine_id is a
 * 7-digit text code and "0100851" must stay a string.
 */
export function normalizeValue(key: string, v: unknown): unknown {
  if (v === null || v === undefined) return null
  if (v instanceof Date) return v.toISOString()
  if (typeof v === "bigint") return Number(v)
  if (typeof v === "string" && !/(id|number)$/i.test(key) && /^-?(0|[1-9]\d*)(\.\d+)?(e[-+]?\d+)?$/i.test(v) && v.length < 17) {
    return Number(v)
  }
  // The SDK returns VARIANT/ARRAY already parsed; only parse strings that look like JSON arrays
  if (typeof v === "string" && /^\s*\[/.test(v)) {
    try {
      return JSON.parse(v)
    } catch {
      return v
    }
  }
  return v
}

export function normalizeRows(rows: Record<string, unknown>[]): Row[] {
  return rows.map((r) => {
    const out: Row = {}
    for (const [k, v] of Object.entries(r)) {
      const key = camel(k)
      out[key] = normalizeValue(key, v)
    }
    return out
  })
}

export async function q(sql: string, binds: Bind[] = []): Promise<Row[]> {
  const rows = await querySnowflake(sql, { binds: binds as never, warehouse: WAREHOUSE })
  return normalizeRows(rows)
}

/* ---------- In-memory TTL cache for aggregate routes ---------- */

const cache = new Map<string, { at: number; value: Promise<unknown> }>()

export function cached<T>(key: string, ttlMs: number, load: () => Promise<T>): Promise<T> {
  const hit = cache.get(key)
  if (hit && Date.now() - hit.at < ttlMs) return hit.value as Promise<T>
  const value = load()
  cache.set(key, { at: Date.now(), value })
  // A failed load must not be cached
  value.catch(() => cache.delete(key))
  return value
}

/* ---------- Errors and validation ---------- */

/** Client input error: surfaces as 400 with its message. */
export class BadRequestError extends Error {}

export async function handle(fn: () => Promise<unknown>) {
  try {
    return Response.json(await fn())
  } catch (err) {
    if (err instanceof BadRequestError) return Response.json({ error: err.message }, { status: 400 })
    const ref = Math.random().toString(36).slice(2, 10)
    console.error(`[error ${ref}]`, err)
    return Response.json({ error: `The query did not complete (ref ${ref}).` }, { status: 500 })
  }
}

const MINE_ID = /^\d{7}$/

export function mineId(v: string | null): string {
  if (!v || !MINE_ID.test(v)) throw new BadRequestError("Mine ID must be 7 digits, e.g. 0100851.")
  return v
}

export function mineIds(v: string | null): string[] {
  const ids = (v ?? "").split(",").map((s) => s.trim()).filter(Boolean)
  if (ids.length < 1 || ids.length > 3) throw new BadRequestError("Compare takes 1 to 3 mine IDs.")
  ids.forEach((id) => mineId(id))
  return [...new Set(ids)]
}

export function offset(v: string | null): number {
  const n = Number(v ?? 0)
  if (!Number.isInteger(n) || n < 0 || n > 100_000) throw new BadRequestError("Invalid offset.")
  return n
}
