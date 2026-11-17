"use client"

import { animate, motion, useMotionValue, useReducedMotion, useTransform } from "framer-motion"
import * as Tooltip from "@radix-ui/react-tooltip"
import { Database, TriangleAlert } from "lucide-react"
import { memo, useEffect, useState } from "react"
import { cn } from "@/lib/utils"
import { GROUP_LABEL, TIER_STYLE, type Group, type Tier } from "@/lib/early-warning"
import { CATEGORY_COLOR } from "@/lib/client"

/* ---------- Tooltip: white, bordered, 14px, plain English ---------- */

export function Tip({ content, children, side }: { content: React.ReactNode; children: React.ReactNode; side?: "top" | "bottom" | "left" | "right" }) {
  return (
    <Tooltip.Root delayDuration={150}>
      <Tooltip.Trigger asChild>{children}</Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content
          side={side}
          sideOffset={6}
          className="z-[100] max-w-sm rounded-lg border border-hair bg-white px-3.5 py-2.5 text-[14px] leading-snug text-foreground"
          style={{ boxShadow: "var(--shadow-pop)" }}
        >
          {content}
        </Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  )
}

/* ---------- Provenance: which view a number comes from ---------- */

export function Provenance({ source, note, compact = false }: { source: string; note?: string; compact?: boolean }) {
  return (
    <Tip
      content={
        <div className="space-y-1">
          <div className="eyebrow">Source view</div>
          <div className="mono text-[12.5px]">{source}</div>
          {note && <div className="text-[13px] text-muted-foreground">{note}</div>}
        </div>
      }
    >
      <button
        type="button"
        className="inline-flex h-5 items-center gap-1 rounded-full border border-[#d9e3f2] bg-[#eef3fa] px-2 text-[10.5px] font-medium text-[#13315c]"
      >
        <Database className="size-3" />
        {!compact && <span className="mono">{source.split(".").pop()}</span>}
      </button>
    </Tip>
  )
}

/* ---------- Card ---------- */

export function Panel({
  title,
  eyebrow,
  right,
  children,
  className,
}: {
  title?: React.ReactNode
  eyebrow?: React.ReactNode
  right?: React.ReactNode
  children: React.ReactNode
  className?: string
}) {
  return (
    <section className={cn("card card-hover min-w-0 p-5", className)}>
      {(title || right || eyebrow) && (
        <header className="mb-4 flex items-start justify-between gap-3">
          <div className="min-w-0">
            {eyebrow && <div className="eyebrow mb-1">{eyebrow}</div>}
            {title && <h2 className="text-[15px] font-medium tracking-[-0.01em]">{title}</h2>}
          </div>
          {right}
        </header>
      )}
      {children}
    </section>
  )
}

/* ---------- Count up ---------- */

export const CountUp = memo(function CountUp({ value, format }: { value: number; format: (n: number) => string }) {
  const reduce = useReducedMotion()
  const mv = useMotionValue(reduce ? value : 0)
  const integral = Number.isInteger(value)
  const text = useTransform(mv, (v) => format(integral ? Math.round(v) : v))
  useEffect(() => {
    if (reduce) {
      mv.set(value)
      return
    }
    const c = animate(mv, value, { duration: 1.1, ease: [0.25, 1, 0.5, 1] })
    return () => c.stop()
  }, [value, reduce, mv])
  return <motion.span className="num">{text}</motion.span>
})

export function Kpi({
  label,
  value,
  format,
  source,
  note,
  tone = "default",
  sub,
  compact = false,
}: {
  label: string
  value: number | null
  format: (n: number) => string
  source: string
  note?: string
  tone?: "default" | "alert" | "good"
  sub?: React.ReactNode
  /** Icon-only provenance badge for dense grids. */
  compact?: boolean
}) {
  return (
    <motion.div
      variants={{ hidden: { opacity: 0, y: 8 }, show: { opacity: 1, y: 0 } }}
      transition={{ type: "spring", stiffness: 380, damping: 32 }}
      className="card card-hover flex min-w-0 flex-col justify-between gap-3 p-4"
    >
      <div className="flex items-start justify-between gap-2">
        <span className="text-[12.5px] font-medium text-muted-foreground">{label}</span>
        <Provenance source={source} note={note} compact={compact} />
      </div>
      <div className={cn("text-[28px] font-medium leading-none", tone === "alert" && "text-amber", tone === "good" && "text-teal")}>
        {value === null ? <span className="text-muted-foreground">n/a</span> : <CountUp value={value} format={format} />}
      </div>
      {sub && <div className="text-[12px] text-muted-foreground">{sub}</div>}
    </motion.div>
  )
}

export const stagger = { hidden: {}, show: { transition: { staggerChildren: 0.05 } } }

/* ---------- Domain chips ---------- */

export function TierChip({ tier, size = "sm", tip = true }: { tier: string; size?: "sm" | "lg"; tip?: boolean }) {
  const t = (TIER_STYLE[tier as Tier] ? tier : "Not enough recent hours") as Tier
  const s = TIER_STYLE[t]
  const chip = (
      <span
        className={cn(
          "inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border font-medium",
          size === "lg" ? "h-8 px-3.5 text-[14px]" : "h-5 px-2 text-[10.5px]",
          s.chip,
        )}
      >
        <span className={cn("rounded-full", size === "lg" ? "size-2" : "size-1.5", s.dot)} />
        {t === "Not enough recent hours" && size === "sm" ? "Too few hours" : t}
      </span>
  )
  if (!tip) return chip
  return <Tip content={<span><b>{t}</b>. {s.blurb} Illustrative, not an official MSHA rating.</span>}>{chip}</Tip>
}

const GROUP_CLS: Record<number, string> = {
  0: "bg-white text-muted-foreground border-hair",
  1: "bg-[#f5f7fa] text-[#475467] border-[#e4e7ec]",
  2: "bg-[#eef3fa] text-[#13315c] border-[#d9e3f2]",
  3: "bg-[#fff7ea] text-[#9a5b06] border-[#f6e2bf]",
  4: "bg-amber text-white border-amber",
}

export function GroupChip({ group, label, validated = true }: { group: number | null | undefined; label?: string; validated?: boolean }) {
  if (group === null || group === undefined) return <span className="text-[11.5px] text-muted-foreground">n/a</span>
  const g = group as Group
  return (
    <Tip
      content={
        <span>
          {label && <b>{label}: </b>}
          {GROUP_LABEL[g]} group{g === 0 ? " (signal was zero)" : ` (quartile ${g} of mines with any)`}.
          {!validated && " Not screened in for metal/nonmetal; corroborating only."}
        </span>
      }
    >
      <span
        className={cn(
          "inline-flex h-5 min-w-[64px] items-center justify-center rounded-[5px] border px-1.5 text-[10.5px] font-medium",
          GROUP_CLS[g],
          !validated && "border-dashed opacity-70",
        )}
      >
        {GROUP_LABEL[g]}
      </span>
    </Tip>
  )
}

export function CategoryDot({ category }: { category: string }) {
  return (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap text-[12px]">
      <span className="size-2 rounded-full" style={{ background: CATEGORY_COLOR[category] ?? "#9ca3af" }} />
      {category}
    </span>
  )
}

export function StatusPill({ status }: { status: string }) {
  const active = status === "Active"
  return (
    <span
      className={cn(
        "inline-flex h-5 items-center rounded-full border px-2 text-[10.5px] font-medium",
        active ? "border-[#cfe9e7] bg-teal-50 text-teal" : "border-hair bg-muted text-muted-foreground",
      )}
    >
      {status}
    </span>
  )
}

/* ---------- States ---------- */

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("shimmer rounded-lg", className)} />
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="card flex flex-col items-center gap-3 p-10 text-center">
      <span className="flex size-10 items-center justify-center rounded-full bg-[#fef3f2]">
        <TriangleAlert className="size-5 text-alert" />
      </span>
      <h3 className="text-[18px] font-medium tracking-[-0.02em]">That did not load</h3>
      <p className="max-w-md text-[13px] text-muted-foreground">{message}</p>
      {onRetry && (
        <button onClick={onRetry} className="h-8 rounded-full border border-hair bg-white px-4 text-[13px] font-medium hover:bg-muted">
          Try again
        </button>
      )}
    </div>
  )
}

export function EmptyState({ title, body, action }: { title: string; body: string; action?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-12 text-center">
      <h3 className="text-[17px] font-medium tracking-[-0.02em]">{title}</h3>
      <p className="max-w-sm text-[13px] text-muted-foreground">{body}</p>
      {action}
    </div>
  )
}

export function PageHeader({ eyebrow, title, sub, right }: { eyebrow: string; title: React.ReactNode; sub?: React.ReactNode; right?: React.ReactNode }) {
  return (
    <div className="relative mb-8">
      <div className="hero-gradient pointer-events-none absolute -inset-x-10 -top-10 h-56" />
      <div className="dot-grid pointer-events-none absolute -inset-x-10 -top-10 h-56" />
      <div className="relative flex flex-wrap items-end justify-between gap-4 pt-2">
        <div className="min-w-0">
          <div className="eyebrow mb-3">{eyebrow}</div>
          <h1 className="headline max-w-3xl">{title}</h1>
          {sub && <p className="mt-3 max-w-2xl text-[15px] text-muted-foreground">{sub}</p>}
        </div>
        {right}
      </div>
    </div>
  )
}

export function ProxyNote({ className }: { className?: string }) {
  return (
    <p className={cn("text-[12px] text-muted-foreground", className)}>
      Ventilation/methane figures are <b className="font-medium text-foreground">compliance proxies</b> (citations under 30 CFR 75 Subpart D),
      not sensor readings. The DOL portal has no methane or temperature data.
    </p>
  )
}

/** Keyboard j/k row navigation for hairline tables; Enter opens the row. */
export function useRowKeys(count: number, onOpen: (i: number) => void) {
  const [active, setActive] = useState(-1)
  useEffect(() => {
    const on = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement
      if (t && (t.tagName === "INPUT" || t.tagName === "SELECT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return
      if (e.metaKey || e.ctrlKey || e.altKey) return
      if (e.key === "j") setActive((a) => Math.min(count - 1, a + 1))
      else if (e.key === "k") setActive((a) => Math.max(0, a - 1))
      else if (e.key === "Enter" && active >= 0) onOpen(active)
    }
    window.addEventListener("keydown", on)
    return () => window.removeEventListener("keydown", on)
  }, [count, active, onOpen])
  useEffect(() => {
    if (active >= 0) document.querySelector(`[data-row="${active}"]`)?.scrollIntoView({ block: "nearest" })
  }, [active])
  return active
}
