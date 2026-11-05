"use client"

import { useRouter } from "next/navigation"
import { AnimatePresence, motion } from "framer-motion"
import { Loader2, Search } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { displayName, useApi, useDebounced, type SearchHit } from "@/lib/client"
import { CategoryDot, StatusPill, TierChip } from "@/components/kit"
import { cn } from "@/lib/utils"

/** Typeahead over MINE_DIRECTORY: 2+ characters, 300ms debounce, arrow keys + Enter. */
export function MineSearch({
  size = "sm",
  autoFocus = false,
  onPicked,
  onPickId,
}: {
  size?: "sm" | "lg"
  autoFocus?: boolean
  onPicked?: () => void
  /** When set, picking a mine calls this instead of opening its profile. */
  onPickId?: (id: string) => void
}) {
  const router = useRouter()
  const [text, setText] = useState("")
  const [open, setOpen] = useState(false)
  const [hi, setHi] = useState(0)
  const box = useRef<HTMLDivElement>(null)
  const term = useDebounced(text.trim(), 300)
  const enabled = term.length >= 2 && term.length <= 100
  const res = useApi<SearchHit[]>(enabled ? `/api/search?q=${encodeURIComponent(term)}` : null, { staleTime: 60_000 })
  const hits = enabled && Array.isArray(res.data) ? res.data : []

  useEffect(() => setHi(0), [term])
  useEffect(() => {
    const on = (e: MouseEvent) => !box.current?.contains(e.target as Node) && setOpen(false)
    window.addEventListener("mousedown", on)
    return () => window.removeEventListener("mousedown", on)
  }, [])

  const pick = (h: SearchHit) => {
    setOpen(false)
    setText("")
    onPicked?.()
    if (onPickId) onPickId(h.mineId)
    else router.push(`/mine?id=${h.mineId}`)
  }
  const lg = size === "lg"

  return (
    <div ref={box} className="relative w-full">
      <label
        className={cn(
          "flex items-center gap-2 rounded-lg border border-hair bg-white focus-within:border-[#c7ced8]",
          lg ? "h-14 px-4 text-[16px]" : "h-8 px-2.5 text-[13px]",
        )}
        style={lg ? { boxShadow: "0 1px 2px rgb(0 0 0 / 0.04), 0 8px 24px -12px rgb(11 37 69 / 0.18)" } : undefined}
      >
        {res.isFetching ? (
          <Loader2 className={cn("animate-spin text-muted-foreground", lg ? "size-5" : "size-3.5")} />
        ) : (
          <Search className={cn("text-muted-foreground", lg ? "size-5" : "size-3.5")} />
        )}
        <input
          autoFocus={autoFocus}
          value={text}
          maxLength={100}
          onChange={(e) => {
            setText(e.target.value)
            setOpen(true)
          }}
          onFocus={() => setOpen(true)}
          onKeyDown={(e) => {
            if (e.key === "ArrowDown") {
              e.preventDefault()
              setHi((i) => Math.min(hits.length - 1, i + 1))
            } else if (e.key === "ArrowUp") {
              e.preventDefault()
              setHi((i) => Math.max(0, i - 1))
            } else if (e.key === "Enter" && hits[hi]) {
              e.preventDefault()
              pick(hits[hi])
            } else if (e.key === "Escape") setOpen(false)
          }}
          placeholder={lg ? "Search 92K mines by name, MSHA mine ID, operator or controller" : "Search mine, ID, operator"}
          className="min-w-0 flex-1 bg-transparent outline-none placeholder:text-muted-foreground"
          aria-label="Search mines"
        />
      </label>
      <AnimatePresence>
        {open && enabled && (
          <motion.div
            initial={{ opacity: 0, y: -4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            transition={{ duration: 0.14 }}
            className={cn(
              "absolute left-0 z-50 mt-2 overflow-hidden rounded-xl border border-hair bg-white",
              lg ? "w-full" : "w-[min(620px,92vw)]",
            )}
            style={{ boxShadow: "var(--shadow-pop)" }}
          >
            {res.error ? (
              <div className="px-4 py-5 text-[13px] text-muted-foreground">Search is unavailable right now. Try again in a moment.</div>
            ) : hits.length === 0 ? (
              <div className="px-4 py-5 text-[13px] text-muted-foreground">{res.isFetching ? "Searching..." : `No mines match "${term}".`}</div>
            ) : (
              <ul className="max-h-[420px] overflow-y-auto p-1.5">
                {hits.map((h, i) => (
                  <li key={h.mineId}>
                    <button
                      onMouseEnter={() => setHi(i)}
                      onClick={() => pick(h)}
                      className={cn("flex w-full items-start gap-3 rounded-lg px-3 py-2.5 text-left", i === hi && "bg-muted")}
                    >
                      <span className="min-w-0 flex-1">
                        <span className="flex items-center gap-2">
                          <span className="truncate text-[13.5px] font-medium">{displayName(h.mineName)}</span>
                          <span className="mono shrink-0 text-[11.5px] text-muted-foreground">{h.mineId}</span>
                        </span>
                        <span className="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[12px] text-muted-foreground">
                          <span>{h.state}</span>
                          <CategoryDot category={h.mineCategory} />
                          <span>{h.mineType}</span>
                          {h.operatorName && <span className="truncate">{displayName(h.operatorName)}</span>}
                        </span>
                      </span>
                      <span className="flex shrink-0 flex-col items-end gap-1">
                        <TierChip tier={h.tier} />
                        <StatusPill status={h.currentStatus} />
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
