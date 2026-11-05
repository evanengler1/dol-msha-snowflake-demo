"use client"

import { useEffect, useMemo, useState } from "react"
import { geoAlbersUsa, geoPath } from "d3-geo"
import { feature } from "topojson-client"
import type { Topology, GeometryCollection } from "topojson-specification"
import type { FeatureCollection } from "geojson"
import { motion, useReducedMotion } from "framer-motion"

const W = 480
const H = 300

/** US map with one pin. TopoJSON is bundled in /public (SPCS has no outbound network). */
export function MineMap({ lat, lon, label, color = "#0b2545" }: { lat: number; lon: number; label: string; color?: string }) {
  const [states, setStates] = useState<FeatureCollection | null>(null)
  const reduce = useReducedMotion()
  useEffect(() => {
    let live = true
    fetch("/states-10m.json")
      .then((r) => r.json())
      .then((topo: Topology) => {
        if (live) setStates(feature(topo, topo.objects.states as GeometryCollection) as unknown as FeatureCollection)
      })
      .catch(() => {})
    return () => {
      live = false
    }
  }, [])
  const { path, pin } = useMemo(() => {
    const projection = geoAlbersUsa().scale(600).translate([W / 2, H / 2])
    return { path: geoPath(projection), pin: projection([lon, lat]) }
  }, [lat, lon])

  if (!pin) {
    return <div className="flex h-[220px] items-center justify-center text-[13px] text-muted-foreground">Location is outside the mapped area.</div>
  }
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label={`Map pin for ${label}`}>
      {states?.features.map((f, i) => (
        <path key={i} d={path(f) ?? undefined} fill="#f4f5f7" stroke="#dfe3e8" strokeWidth={0.6} tabIndex={-1} />
      ))}
      <g transform={`translate(${pin[0]},${pin[1]})`}>
        {!reduce && (
          <motion.circle
            r={6}
            fill={color}
            initial={{ opacity: 0.35, scale: 1 }}
            animate={{ opacity: 0, scale: 3.2 }}
            transition={{ duration: 1.8, repeat: Infinity, ease: "easeOut" }}
          />
        )}
        <circle r={5.5} fill={color} stroke="#fff" strokeWidth={2} />
      </g>
    </svg>
  )
}
