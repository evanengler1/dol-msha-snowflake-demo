"use client"

import Link from "next/link"
import Image from "next/image"
import { usePathname, useRouter } from "next/navigation"
import { motion, AnimatePresence } from "framer-motion"
import { Command } from "cmdk"
import { ExternalLink, Gauge, GitCompareArrows, ListOrdered, Mountain, Search, Workflow } from "lucide-react"
import { Suspense, useEffect, useState } from "react"
import * as Tooltip from "@radix-ui/react-tooltip"
import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { APP_SHORT, DASHBOARD_URL, LOGO_SRC, SOURCE_LINE } from "@/lib/constants"
import { displayName, fmt, useApi, useDebounced, type SearchHit } from "@/lib/client"
import { Tip, TierChip } from "@/components/kit"
import { MineSearch } from "@/components/mine-search"
import { cn } from "@/lib/utils"

export const NAV = [
  { href: "/", label: "Overview", Icon: Gauge, hint: "Search and early-warning at a glance" },
  { href: "/watchlist", label: "Watch list", Icon: ListOrdered, hint: "Ranked mines by district and field office" },
  { href: "/compare", label: "Compare", Icon: GitCompareArrows, hint: "2-3 mines side by side" },
  { href: "/architecture", label: "Architecture", Icon: Workflow, hint: "How the platform is built on Snowflake" },
] as const

interface Stats {
  latestAccidentDate?: string
  latestHoursQuarter?: string
  queriedAt?: string
}

function Rail() {
  const path = usePathname()
  return (
    <nav className="sticky top-14 hidden h-[calc(100vh-56px)] w-[220px] shrink-0 flex-col gap-1 border-r border-hair bg-[#fafafa]/80 px-3 py-5 lg:flex">
      <div className="eyebrow px-3 pb-2">Workspace</div>
      {NAV.map(({ href, label, Icon }) => {
        const active = href === "/" ? path === "/" : path.startsWith(href)
        return (
          <Link
            key={href}
            href={href}
            prefetch
            className={cn(
              "relative flex h-9 items-center gap-2.5 rounded-md px-3 text-[13.5px] font-medium transition-colors duration-150",
              active ? "text-foreground" : "text-muted-foreground hover:text-foreground",
            )}
          >
            {active && (
              <motion.span
                layoutId="rail-active"
                className="absolute inset-0 rounded-md border border-hair bg-white"
                style={{ boxShadow: "0 1px 2px rgb(0 0 0 / 0.04)" }}
                transition={{ type: "spring", stiffness: 500, damping: 38 }}
              />
            )}
            <Icon className={cn("relative size-4", active && "text-navy")} />
            <span className="relative">{label}</span>
          </Link>
        )
      })}
      {path.startsWith("/mine") && (
        <div className="relative flex h-9 items-center gap-2.5 rounded-md border border-dashed border-hair px-3 text-[13.5px] font-medium text-foreground">
          <Mountain className="size-4 text-navy" /> Mine profile
        </div>
      )}
      <a
        href={DASHBOARD_URL}
        target="_blank"
        rel="noreferrer"
        className="mt-3 flex h-9 items-center gap-2.5 rounded-md px-3 text-[13px] text-muted-foreground hover:text-foreground"
      >
        <ExternalLink className="size-4" /> Industry trends dashboard
      </a>
      <div className="mt-auto rounded-lg border border-hair bg-white p-3 text-[11.5px] leading-relaxed text-muted-foreground">
        <div className="mb-1 font-medium text-foreground">Data notice</div>
        Public MSHA data only. Ventilation/methane figures are <b className="font-medium text-foreground">compliance proxies</b>, not
        sensor readings. Tiers are illustrative, not MSHA ratings.
      </div>
    </nav>
  )
}

function AsOf() {
  const { data } = useApi<Stats>("/api/stats", { staleTime: 300_000 })
  return (
    <Tip
      content={
        <div className="space-y-1">
          <div>Latest accident in the portal: {fmt.date(data?.latestAccidentDate)}</div>
          <div>Latest quarter with hours: {data?.latestHoursQuarter ?? "n/a"} (partial year)</div>
          <div className="text-muted-foreground">The DOL portal refreshes weekly.</div>
        </div>
      }
    >
      <span className="hidden items-center gap-1.5 text-[11.5px] text-muted-foreground xl:flex">
        <span className="relative flex size-1.5">
          <span className="absolute inline-flex size-full animate-ping rounded-full bg-teal opacity-60" />
          <span className="relative inline-flex size-1.5 rounded-full bg-teal" />
        </span>
        Data as of{" "}
        <span className="num text-foreground">
          {data ? `${fmt.date(data.latestAccidentDate)} · hours ${data.latestHoursQuarter}` : "loading"}
        </span>
      </span>
    </Tip>
  )
}

function Header({ onPalette }: { onPalette: () => void }) {
  const [scrolled, setScrolled] = useState(false)
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 4)
    window.addEventListener("scroll", on, { passive: true })
    return () => window.removeEventListener("scroll", on)
  }, [])
  return (
    <header
      className={cn(
        "sticky top-0 z-40 h-14 w-full border-b bg-[#fafafa]/85 backdrop-blur-md transition-colors duration-300",
        scrolled ? "border-hair" : "border-transparent",
      )}
    >
      <div className="flex h-full items-center gap-4 px-5">
        <Link href="/" className="flex shrink-0 items-center gap-2.5">
          <Image src={LOGO_SRC} alt="" width={26} height={26} priority />
          <span className="leading-tight">
            <span className="block text-[13.5px] font-semibold tracking-[-0.01em]">MSHA {APP_SHORT}</span>
            <span className="block text-[11px] text-muted-foreground">Mine safety command center</span>
          </span>
        </Link>
        <div className="ml-4 hidden max-w-md flex-1 items-center gap-2 md:flex">
          <MineSearch />
          <button type="button" onClick={onPalette} className="flex shrink-0 items-center gap-0.5" aria-label="Open command palette">
            <span className="kbd">⌘</span>
            <span className="kbd">K</span>
          </button>
        </div>
        <div className="ml-auto flex items-center gap-3">
          <AsOf />
        </div>
      </div>
    </header>
  )
}

function Palette({ open, setOpen }: { open: boolean; setOpen: (o: boolean) => void }) {
  const router = useRouter()
  const [value, setValue] = useState("")
  const term = useDebounced(value.trim(), 300)
  const hits = useApi<SearchHit[]>(open && term.length >= 2 ? `/api/search?q=${encodeURIComponent(term)}` : null, { staleTime: 60_000 })
  const go = (href: string) => {
    setOpen(false)
    setValue("")
    router.push(href)
  }
  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-[90] flex items-start justify-center bg-black/20 pt-[14vh] backdrop-blur-[2px]"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={() => setOpen(false)}
        >
          <motion.div
            initial={{ opacity: 0, scale: 0.97, y: -6 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.98 }}
            transition={{ duration: 0.16, ease: [0.25, 0.46, 0.45, 0.94] }}
            onClick={(e) => e.stopPropagation()}
            className="w-[620px] max-w-[92vw] overflow-hidden rounded-xl border border-hair bg-white"
            style={{ boxShadow: "var(--shadow-pop)" }}
          >
            <Command label="Command palette" loop shouldFilter={false}>
              <div className="flex items-center gap-2 border-b border-hair px-4">
                <Search className="size-4 text-muted-foreground" />
                <Command.Input
                  autoFocus
                  value={value}
                  onValueChange={setValue}
                  maxLength={100}
                  placeholder="Jump to a page, or find a mine by name, ID or operator"
                  className="h-12 flex-1 bg-transparent text-[14px] outline-none placeholder:text-muted-foreground"
                />
                <span className="kbd">esc</span>
              </div>
              <Command.List className="max-h-[420px] overflow-y-auto p-2 [&_[cmdk-group-heading]]:eyebrow [&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:py-1.5">
                <Command.Group heading="Pages">
                  {NAV.filter((n) => !value || n.label.toLowerCase().includes(value.toLowerCase())).map((n) => (
                    <Item key={n.href} value={n.href} onSelect={() => go(n.href)} hint={n.hint}>
                      <n.Icon className="size-4 text-muted-foreground" />
                      {n.label}
                    </Item>
                  ))}
                </Command.Group>
                {term.length >= 2 && Array.isArray(hits.data) && hits.data.length > 0 && (
                  <Command.Group heading="Mines">
                    {hits.data.map((h) => (
                      <Item key={h.mineId} value={`mine-${h.mineId}`} onSelect={() => go(`/mine?id=${h.mineId}`)}>
                        <Mountain className="size-4 text-muted-foreground" />
                        <span className="truncate">{displayName(h.mineName)}</span>
                        <span className="mono text-[11.5px] text-muted-foreground">{h.mineId}</span>
                        <span className="ml-auto">
                          <TierChip tier={h.tier} />
                        </span>
                      </Item>
                    ))}
                  </Command.Group>
                )}
                {term.length >= 2 && hits.isFetching && <div className="px-3 py-3 text-[12.5px] text-muted-foreground">Searching mines...</div>}
              </Command.List>
            </Command>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}

function Item({ children, onSelect, hint, value }: { children: React.ReactNode; onSelect: () => void; hint?: string; value: string }) {
  return (
    <Command.Item
      value={value}
      onSelect={onSelect}
      className="flex h-10 cursor-pointer items-center gap-2.5 rounded-lg px-2.5 text-[13.5px] data-[selected=true]:bg-muted"
    >
      {children}
      {hint && <span className="ml-auto text-[11.5px] text-muted-foreground">{hint}</span>}
    </Command.Item>
  )
}

function Footer() {
  return (
    <footer className="mt-16 flex flex-wrap items-center justify-between gap-3 border-t border-hair pt-5 text-[12px] text-muted-foreground">
      <span>{SOURCE_LINE}</span>
      <span className="flex items-center gap-1.5">
        Powered by <span className="font-medium text-navy">Snowflake</span>
      </span>
    </footer>
  )
}

function Inner({ children }: { children: React.ReactNode }) {
  const [palette, setPalette] = useState(false)
  useEffect(() => {
    const on = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault()
        setPalette((p) => !p)
      }
    }
    window.addEventListener("keydown", on)
    return () => window.removeEventListener("keydown", on)
  }, [])
  const path = usePathname()
  return (
    <>
      <Header onPalette={() => setPalette(true)} />
      <div className="flex">
        <Rail />
        <main className="min-w-0 flex-1 px-6 pb-10 pt-8 xl:px-10">
          <motion.div
            key={path}
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.25, ease: [0.25, 1, 0.5, 1] }}
            className="mx-auto max-w-[1360px]"
          >
            <Suspense>{children}</Suspense>
            <Footer />
          </motion.div>
        </main>
      </div>
      <Palette open={palette} setOpen={setPalette} />
    </>
  )
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const [client] = useState(() => new QueryClient({ defaultOptions: { queries: { refetchOnWindowFocus: false, staleTime: 60_000 } } }))
  return (
    <QueryClientProvider client={client}>
      <Tooltip.Provider>
        <Inner>{children}</Inner>
      </Tooltip.Provider>
    </QueryClientProvider>
  )
}
