import { Map as MLMap, NavigationControl, setWorkerUrl, type ExpressionSpecification, type GeoJSONSource } from 'maplibre-gl'
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?url'
import 'maplibre-gl/dist/maplibre-gl.css'
import { useEffect, useRef, useState } from 'react'
import { api, type Cluster, type Page } from '../lib/api'

/** Центр Ташкента (приблизительно) — старт карты. */
export const TASHKENT: [number, number] = [69.279, 41.311]

// воркер карты отдаём явным адресом: иначе сборщик не кладёт maplibre-gl-worker.mjs рядом с чанком (404)
setWorkerUrl(workerUrl)

const css = (name: string) => getComputedStyle(document.documentElement).getPropertyValue(name).trim() || '#888'
const theme = () => (document.documentElement.dataset.theme === 'light' ? 'light' : 'dark')
/** Свои векторные тайлы Ташкента (planetiler) и стиль в цветах бренда: /map/style-dark.json, /map/style-light.json */
const styleUrl = () => `${location.origin}/map/style-${theme()}.json`

// ячейка карты 0.01°: целые смещения от угла ячейки в миллионных долях градуса (см. /map/cell на сервере)
interface CellResp { o: [number, number]; u: number; s: [number, number, number, number, number, string, string, number][] }
interface StretchResp { stretches: { id: string; cls: string; length_m: number; speed_kmh: number; road: string; geometry: [number, number][] }[] }
const CELL = 0.01
type Feat = { type: 'Feature'; properties: { cls: string; rc: string; dir: number }; geometry: { type: 'LineString'; coordinates: number[][] } }

export interface MapLayers { roads: boolean; roughness: boolean; clusters: boolean; stretches?: boolean }
/** element — только элементы (глубокие ямы, лежачие, люки, рельсы); quality — то, что уходит в качество дороги; all — всё */
export type ClusterKind = 'element' | 'quality' | 'all'

export default function MapView({ layers, statuses, kind = 'element', onSelect, selectedId, flyTo, height = '100%', minimal = false, center, zoom = 12, onMove }: {
  layers: MapLayers; statuses?: string[]; kind?: ClusterKind; onSelect?: (c: Cluster) => void; selectedId?: number | null; flyTo?: { lon: number; lat: number; zoom?: number; n: number } | null
  height?: string | number; minimal?: boolean; center?: [number, number]; zoom?: number; onMove?: (c: { lon: number; lat: number; zoom: number }) => void
}) {
  const el = useRef<HTMLDivElement>(null)
  const map = useRef<MLMap | null>(null)
  const clustersRef = useRef<Cluster[]>([])
  const cellCache = useRef(new Map<string, { at: number; feats: Feat[] }>())
  const loadGen = useRef(0)
  const [status, setStatus] = useState<string>('')
  const propsRef = useRef({ layers, statuses, kind, onSelect, onMove })
  propsRef.current = { layers, statuses, kind, onSelect, onMove }

  // создание карты
  useEffect(() => {
    if (!el.current) return
    const m = new MLMap({
      container: el.current,
      center: center ?? TASHKENT,
      zoom,
      minZoom: 9,
      maxZoom: 19,
      style: styleUrl(),
      attributionControl: { compact: true, customAttribution: 'Данные карты: © OpenStreetMap contributors (ODbL)' },
    })
    map.current = m
    if (!minimal) m.addControl(new NavigationControl({ showCompass: false }), 'top-right')
    const addOverlay = () => {
      if (m.getSource('segs')) return
      m.addSource('segs', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
      m.addSource('str', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
      m.addSource('cl', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
      // протяжённые участки плохого качества: широкая полупрозрачная подложка под цветной ровностью
      m.addLayer({ id: 'stretch-glow', type: 'line', source: 'str', layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': ['match', ['get', 'cls'], 'E', css('--crater'), css('--warn')], 'line-opacity': 0.22, 'line-width': ['interpolate', ['linear'], ['zoom'], 10, 8, 16, 26], 'line-blur': 2 } })
      m.addLayer({ id: 'roads', type: 'line', source: 'segs', filter: ['==', ['get', 'cls'], ''], layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': css('--muted'), 'line-opacity': 0.4, 'line-width': ['interpolate', ['linear'], ['zoom'], 10, 1, 16, 4] } })
      m.addLayer({ id: 'rough-casing', type: 'line', source: 'segs', filter: ['!=', ['get', 'cls'], ''], layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': css('--bg-base'), 'line-opacity': 0.55, 'line-width': ['interpolate', ['exponential', 1.4], ['zoom'], 10, 2.4, 14, 6.5, 18, 17], 'line-offset': ['*', ['get', 'dir'], 1.2] } })
      m.addLayer({ id: 'rough', type: 'line', source: 'segs', filter: ['!=', ['get', 'cls'], ''], layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-width': ['interpolate', ['exponential', 1.4], ['zoom'], 10, 1.4, 14, 4, 18, 11], 'line-offset': ['*', ['get', 'dir'], 1.2], 'line-color': roughExpr() } })
      m.addLayer({ id: 'halo', type: 'circle', source: 'cl', filter: ['==', ['get', 'sel'], 1], paint: { 'circle-radius': 22, 'circle-color': css('--amber'), 'circle-opacity': 0.3, 'circle-blur': 0.6 } })
      m.addLayer({ id: 'glow', type: 'circle', source: 'cl', paint: { 'circle-radius': ['interpolate', ['linear'], ['zoom'], 10, 9, 16, 20], 'circle-color': clusterExpr(), 'circle-opacity': 0.28, 'circle-blur': 0.7 } })
      m.addLayer({ id: 'clusters', type: 'circle', source: 'cl',
        paint: { 'circle-radius': ['interpolate', ['linear'], ['get', 'passes'], 0, 6, 10, 11], 'circle-color': clusterExpr(), 'circle-stroke-color': css('--bg-base'), 'circle-stroke-width': 1.8 } })
      m.addLayer({ id: 'core', type: 'circle', source: 'cl', paint: { 'circle-radius': ['interpolate', ['linear'], ['get', 'passes'], 0, 2.2, 10, 4], 'circle-color': css('--bg-base') } })
      m.on('click', 'clusters', (e) => {
        const id = e.features?.[0]?.properties?.id as number | undefined
        const c = clustersRef.current.find((x) => x.id === id)
        if (c) propsRef.current.onSelect?.(c)
      })
      m.on('mouseenter', 'clusters', () => { m.getCanvas().style.cursor = 'pointer' })
      m.on('mouseleave', 'clusters', () => { m.getCanvas().style.cursor = '' })
      load()
    }
    m.on('load', addOverlay)
    m.on('styledata', () => { if (m.isStyleLoaded()) addOverlay() }) // после смены темы (setStyle) слои добавляются заново
    let t: ReturnType<typeof setTimeout> | undefined
    m.on('moveend', () => {
      const c = m.getCenter()
      propsRef.current.onMove?.({ lon: c.lng, lat: c.lat, zoom: m.getZoom() })
      clearTimeout(t)
      t = setTimeout(load, 350)
    })
    // смена темы → другой стиль подложки (слои вернёт addOverlay)
    let cur = theme()
    const mo = new MutationObserver(() => { if (theme() !== cur) { cur = theme(); m.setStyle(styleUrl()) } })
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] })
    const ro = new ResizeObserver(() => m.resize())
    ro.observe(el.current)
    return () => { clearTimeout(t); mo.disconnect(); ro.disconnect(); m.remove(); map.current = null }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function load() {
    const m = map.current
    if (!m || !m.getSource('segs')) return
    const b = m.getBounds()
    const z = m.getZoom()
    const gen = ++loadGen.current
    const bbox = `${b.getSouth()},${b.getWest()},${b.getNorth()},${b.getEast()}`
    const L = propsRef.current.layers
    setStatus('загрузка…')
    try {
      if (z >= 11.3 && (L.roads || L.roughness)) {
        // карта грузится ячейками: уже загруженные берутся из кэша, запрашиваются только недостающие; подложку рисуют тайлы, поэтому только оценённые сегменты
        const set = z >= 14 ? 'all' : z >= 12.5 ? 'main' : 'major'
        const scored = L.roads ? 0 : 1
        const i0 = Math.floor(b.getSouth() / CELL), i1 = Math.floor(b.getNorth() / CELL)
        const j0 = Math.floor(b.getWest() / CELL), j1 = Math.floor(b.getEast() / CELL)
        const keys: { i: number; j: number; key: string }[] = []
        for (let i = i0; i <= i1; i++) for (let j = j0; j <= j1; j++) keys.push({ i, j, key: `${i}:${j}:${set}:${scored}` })
        const ctr = m.getCenter()
        keys.sort((p, q) => Math.hypot((p.i + 0.5) * CELL - ctr.lat, (p.j + 0.5) * CELL - ctr.lng) - Math.hypot((q.i + 0.5) * CELL - ctr.lat, (q.j + 0.5) * CELL - ctr.lng))
        const now = Date.now()
        const need = keys.slice(0, 40).filter((k) => { const c = cellCache.current.get(k.key); return !c || now - c.at > 600_000 })
        const draw = () => {
          const feats: Feat[] = []
          for (const k of keys) {
            const c = cellCache.current.get(k.key)
            if (c) for (const f of c.feats) if (f.properties.cls === '' ? L.roads : L.roughness) feats.push(f)
          }
          ;(m.getSource('segs') as GeoJSONSource).setData({ type: 'FeatureCollection', features: feats })
        }
        for (let n = 0; n < need.length; n += 6) {
          if (gen !== loadGen.current) return // пользователь уже сдвинул карту — этот проход устарел
          await Promise.all(need.slice(n, n + 6).map(async (k) => {
            const r = await api.get<CellResp>('/map/cell', { i: k.i, j: k.j, set, scored: scored || undefined })
            cellCache.current.set(k.key, { at: Date.now(), feats: r.s.map((x) => ({ type: 'Feature' as const, properties: { cls: x[5], rc: x[6], dir: x[7] }, geometry: { type: 'LineString' as const, coordinates: [[r.o[1] + x[2] * r.u, r.o[0] + x[1] * r.u], [r.o[1] + x[4] * r.u, r.o[0] + x[3] * r.u]] } })) })
          }))
          draw()
        }
        draw()
        if (cellCache.current.size > 160) { const old = [...cellCache.current.entries()].sort((p, q) => p[1].at - q[1].at).slice(0, 60); for (const [k] of old) cellCache.current.delete(k) }
        m.setLayoutProperty('roads', 'visibility', L.roads ? 'visible' : 'none')
        m.setLayoutProperty('rough', 'visibility', L.roughness ? 'visible' : 'none')
        m.setLayoutProperty('rough-casing', 'visibility', L.roughness ? 'visible' : 'none')
      } else {
        ;(m.getSource('segs') as GeoJSONSource).setData({ type: 'FeatureCollection', features: [] })
      }
      // протяжённые участки плохого качества (D/E от 100 м)
      if (L.stretches && z >= 11) {
        const r = await api.get<StretchResp>('/map/stretches', { bbox })
        ;(m.getSource('str') as GeoJSONSource).setData({ type: 'FeatureCollection', features: r.stretches.map((s) => ({ type: 'Feature' as const, properties: { cls: s.cls, len: s.length_m }, geometry: { type: 'LineString' as const, coordinates: s.geometry.map(([la, lo]) => [lo, la]) } })) })
      } else {
        ;(m.getSource('str') as GeoJSONSource).setData({ type: 'FeatureCollection', features: [] })
      }
      if (L.clusters) {
        const st = propsRef.current.statuses
        const kd = propsRef.current.kind
        const r = await api.get<Page<Cluster>>('/admin/clusters', { bbox, size: 200, status: st?.length ? st.join(',') : undefined, kind: kd === 'all' ? undefined : kd, sort: '-passes' })
        clustersRef.current = r.items
        pushClusters()
        setStatus(r.total > r.items.length ? `показано ${r.items.length} из ${r.total}` : `${r.total} ${kd === 'quality' ? 'мелких ям' : 'элементов'}`)
      } else {
        clustersRef.current = []
        pushClusters()
        setStatus('')
      }
    } catch (e) {
      setStatus(e instanceof Error ? e.message : 'ошибка загрузки')
    }
  }

  function pushClusters() {
    const m = map.current
    const src = m?.getSource('cl') as GeoJSONSource | undefined
    if (!src) return
    src.setData({
      type: 'FeatureCollection',
      features: clustersRef.current.map((c) => ({ type: 'Feature' as const, properties: { id: c.id, passes: c.passes, level: c.level, status: c.status, el: c.element ? 1 : 0, sel: c.id === selectedRef.current ? 1 : 0 }, geometry: { type: 'Point' as const, coordinates: [c.lon, c.lat] } })),
    })
  }
  const selectedRef = useRef<number | null | undefined>(selectedId)
  useEffect(() => { selectedRef.current = selectedId; pushClusters() }, [selectedId])
  useEffect(() => { load() /* смена слоёв/фильтров */ }, [layers.roads, layers.roughness, layers.clusters, layers.stretches, kind, (statuses ?? []).join(',')])
  useEffect(() => { if (flyTo && map.current) map.current.flyTo({ center: [flyTo.lon, flyTo.lat], zoom: flyTo.zoom ?? 15, duration: 700 }) }, [flyTo?.n])

  return (
    <div className="relative" style={{ height }}>
      <div ref={el} className="h-full w-full" role="application" aria-label="Карта" />
      {status && <div className="pointer-events-none absolute bottom-8 left-3 rounded-lg bg-surface/90 px-3 py-1.5 text-xs text-muted">{status}</div>}
    </div>
  )
}

function roughExpr(): ExpressionSpecification {
  return ['match', ['get', 'cls'], 'A', css('--smooth'), 'B', mix(css('--smooth'), css('--amber')), 'C', css('--amber'), 'D', css('--warn'), 'E', css('--crater'), css('--line')]
}
function clusterExpr(): ExpressionSpecification {
  return ['case', ['==', ['get', 'status'], 'fixed'], css('--smooth'), ['==', ['get', 'el'], 0], css('--muted'), ['in', ['get', 'level'], ['literal', ['deep', 'danger']]], css('--crater'), css('--warn')]
}
function mix(a: string, b: string): string {
  const p = (c: string) => { const m = c.replace('#', ''); const n = m.length === 3 ? m.split('').map((x) => x + x).join('') : m; return [0, 2, 4].map((i) => parseInt(n.slice(i, i + 2), 16)) }
  try { const x = p(a), y = p(b); return `rgb(${x.map((v, i) => Math.round(v * 0.55 + y[i] * 0.45)).join(',')})` } catch { return a }
}
