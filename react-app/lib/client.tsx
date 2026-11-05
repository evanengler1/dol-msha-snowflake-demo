"use client"

import { useEffect, useState } from "react"
import { useQuery, type UseQueryOptions } from "@tanstack/react-query"

/* ---------- API ---------- */

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message)
  }
}

export async function api<T>(path: string): Promise<T> {
  const res = await fetch(path, { headers: { "content-type": "application/json" } })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new ApiError(body?.error ?? `Request failed (${res.status})`, res.status)
  return body as T
}

export function useApi<T>(path: string | null, opts: Omit<UseQueryOptions<T, ApiError>, "queryKey" | "queryFn"> = {}) {
  return useQuery<T, ApiError>({
    queryKey: [path],
    queryFn: () => api<T>(path!),
    enabled: !!path,
    retry: (n, err) => err.status >= 500 && n < 1,
    ...opts,
  })
}

export function useDebounced<T>(value: T, ms = 300): T {
  const [v, setV] = useState(value)
  useEffect(() => {
    const t = setTimeout(() => setV(value), ms)
    return () => clearTimeout(t)
  }, [value, ms])
  return v
}

/* ---------- Formatting ---------- */

const n0 = (v: unknown) => Number(v ?? 0)

export const fmt = {
  usd(v: unknown, compact = true) {
    const x = n0(v)
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD",
      notation: compact && Math.abs(x) >= 10_000 ? "compact" : "standard",
      maximumFractionDigits: compact && Math.abs(x) >= 10_000 ? 1 : 0,
    }).format(x)
  },
  int(v: unknown) {
    return new Intl.NumberFormat("en-US").format(Math.round(n0(v)))
  },
  compact(v: unknown) {
    return new Intl.NumberFormat("en-US", { notation: "compact", maximumFractionDigits: 1 }).format(n0(v))
  },
  rate(v: unknown) {
    return v === null || v === undefined ? "n/a" : n0(v).toFixed(2)
  },
  one(v: unknown) {
    return v === null || v === undefined ? "n/a" : n0(v).toFixed(1)
  },
  pctile(v: unknown) {
    if (v === null || v === undefined) return "n/a"
    return `${Math.round(n0(v) * 100)}th`
  },
  date(v: unknown) {
    if (!v) return "n/a"
    const d = new Date(String(v))
    return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric", timeZone: "UTC" })
  },
  dateTime(v: unknown) {
    if (!v) return "n/a"
    return new Date(String(v)).toLocaleString("en-US", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
  },
}

/* ---------- Domain ---------- */

export const CATEGORY_COLOR: Record<string, string> = { Coal: "#0b2545", "Metal/Nonmetal": "#0e7c7b" }

export interface SearchHit {
  mineId: string
  mineName: string
  state: string
  mineCategory: string
  mineType: string
  operatorName: string | null
  controllerName: string | null
  currentStatus: string
  tier: string
  hasRecentHours: boolean
}

/** Title-case ALL-CAPS portal names for display ("BRUSH VALLEY" -> "Brush Valley"); mixed case is left alone. */
export function displayName(s: unknown): string {
  const v = String(s ?? "")
  if (v !== v.toUpperCase() || !/[A-Z]/.test(v)) return v
  return v.toLowerCase().replace(/(^|[\s\-/(&.#])([a-z])/g, (_, pre: string, c: string) => pre + c.toUpperCase()).replace(/\b(Llc|Inc|Lp)\b/g, (m) => m.toUpperCase())
}

export function downloadCsv(filename: string, columns: { key: string; label: string }[], rows: Record<string, unknown>[]) {
  const esc = (v: unknown) => {
    const s = v === null || v === undefined ? "" : String(v)
    // Neutralize spreadsheet formula injection and quote every cell
    const safe = /^[=+\-@\t\r]/.test(s) ? `'${s}` : s
    return `"${safe.replace(/"/g, '""')}"`
  }
  const lines = [columns.map((c) => esc(c.label)).join(","), ...rows.map((r) => columns.map((c) => esc(r[c.key])).join(","))]
  const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8" })
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
