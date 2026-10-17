import { Map as MLMap, NavigationControl, setWorkerUrl, type ExpressionSpecification, type GeoJSONSource } from 'maplibre-gl'
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?url'
import 'maplibre-gl/dist/maplibre-gl.css'
import { useEffect, useRef, useState } from 'react'
import { api, type Cluster, type Page } from '../lib/api'

/** Центр Ташкента (приблизительно) — старт карты. */
export const TASHKENT: [number, number] = [69.279, 41.311]
const TILE_URL = import.meta.env.VITE_TILE_URL as string | undefined   // необязательная растровая подложка (например OSM — учитывайте политику тайлов)

// воркер карты отдаём явным адресом: иначе сборщик не кладёт maplibre-gl-worker.mjs рядом с чанком (404)
setWorkerUrl(workerUrl)

const css = (name: string) => getComputedStyle(document.documentElement).getPropertyValue(name).trim() || '#888'

interface SegResp { segments: [number, number, number, number, number, string, string, number][] }

export interface MapLayers { roads: boolean; roughness: boolean; clusters: boolean }

export default function MapView({ layers, statuses, onSelect, selectedId, flyTo, height = '100%', minimal = false, center, zoom = 12, onMove }: {
  layers: MapLayers; statuses?: string[]; onSelect?: (c: Cluster) => void; selectedId?: number | null; flyTo?: { lon: number; lat: number; zoom?: number; n: number } | null
  height?: string | number; minimal?: boolean; center?: [number, number]; zoom?: number; onMove?: (c: { lon: number; lat: number; zoom: number }) => void
}) {
  const el = useRef<HTMLDivElement>(null)
  const map = useRef<MLMap | null>(null)
  const clustersRef = useRef<Cluster[]>([])
  const [status, setStatus] = useState<string>('')
  const propsRef = useRef({ layers, statuses, onSelect, onMove })
  propsRef.current = { layers, statuses, onSelect, onMove }

  // создание карты
  useEffect(() => {
    if (!el.current) return
    const m = new MLMap({
      container: el.current,
      center: center ?? TASHKENT,
      zoom,
      style: { version: 8, sources: TILE_URL ? { base: { type: 'raster', tiles: [TILE_URL], tileSize: 256, attribution: '© OpenStreetMap contributors' } } : {}, layers: [{ id: 'bg', type: 'background', paint: { 'background-color': css('--bg-surface') } }, ...(TILE_URL ? [{ id: 'base', type: 'raster' as const, source: 'base', paint: { 'raster-opacity': 0.35 } }] : [])] },
      attributionControl: { compact: true, customAttribution: 'Дороги: © OpenStreetMap contributors (ODbL)' },
    })
    map.current = m
    if (!minimal) m.addControl(new NavigationControl({ showCompass: false }), 'top-right')
    m.on('load', () => {
      m.addSource('segs', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
      m.addSource('cl', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } })
      m.addLayer({ id: 'roads', type: 'line', source: 'segs', filter: ['==', ['get', 'cls'], ''], layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': css('--muted'), 'line-opacity': 0.4, 'line-width': ['interpolate', ['linear'], ['zoom'], 10, ['match', ['get', 'rc'], 'R', 2, 'A', 1.8, 1], 16, ['match', ['get', 'rc'], 'R', 8, 'A', 7, 'B', 5, 3]] } })
      m.addLayer({ id: 'rough', type: 'line', source: 'segs', filter: ['!=', ['get', 'cls'], ''], layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-width': ['interpolate', ['linear'], ['zoom'], 10, 2, 16, 6], 'line-offset': ['interpolate', ['linear'], ['zoom'], 14, 0, 17, ['*', ['get', 'dir'], 2.5]], 'line-color': roughExpr() } })
      m.addLayer({ id: 'halo', type: 'circle', source: 'cl', filter: ['==', ['get', 'sel'], 1], paint: { 'circle-radius': 20, 'circle-color': css('--amber'), 'circle-opacity': 0.25 } })
      m.addLayer({ id: 'clusters', type: 'circle', source: 'cl',
        paint: { 'circle-radius': ['interpolate', ['linear'], ['get', 'passes'], 0, 6, 10, 11], 'circle-color': clusterExpr(), 'circle-stroke-color': css('--bg-base'), 'circle-stroke-width': 2 } })
      m.on('click', 'clusters', (e) => {
        const id = e.features?.[0]?.properties?.id as number | undefined
        const c = clustersRef.current.find((x) => x.id === id)
        if (c) propsRef.current.onSelect?.(c)
      })
      m.on('mouseenter', 'clusters', () => { m.getCanvas().style.cursor = 'pointer' })
      m.on('mouseleave', 'clusters', () => { m.getCanvas().style.cursor = '' })
      load()
    })
    let t: ReturnType<typeof setTimeout> | undefined
    m.on('moveend', () => {
      const c = m.getCenter()
      propsRef.current.onMove?.({ lon: c.lng, lat: c.lat, zoom: m.getZoom() })
      clearTimeout(t)
      t = setTimeout(load, 350)
    })
    // смена темы → перекрасить слои и фон
    const mo = new MutationObserver(() => recolor())
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] })
    const ro = new ResizeObserver(() => m.resize())
    ro.observe(el.current)
    return () => { clearTimeout(t); mo.disconnect(); ro.disconnect(); m.remove(); map.current = null }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  function recolor() {
    const m = map.current
    if (!m || !m.isStyleLoaded()) return
    m.setPaintProperty('bg', 'background-color', css('--bg-surface'))
    m.setPaintProperty('roads', 'line-color', css('--muted'))
    m.setPaintProperty('rough', 'line-color', roughExpr())
    m.setPaintProperty('clusters', 'circle-color', clusterExpr())
    m.setPaintProperty('clusters', 'circle-stroke-color', css('--bg-base'))
    m.setPaintProperty('halo', 'circle-color', css('--amber'))
  }

  async function load() {
    const m = map.current
    if (!m || !m.getSource('segs')) return
    const b = m.getBounds()
    const z = m.getZoom()
    const ctr = m.getCenter()
    // сервер принимает bbox ≤ 0.1° — ограничиваем окно вокруг центра (на больших экранах край карты догружается при сдвиге)
    const bb = { s: Math.max(b.getSouth(), ctr.lat - 0.045), n: Math.min(b.getNorth(), ctr.lat + 0.045), w: Math.max(b.getWest(), ctr.lng - 0.045), e: Math.min(b.getEast(), ctr.lng + 0.045) }
    const bbox = `${bb.s},${bb.w},${bb.n},${bb.e}`
    const L = propsRef.current.layers
    setStatus('загрузка…')
    try {
      if (z >= 11.3 && (L.roads || L.roughness)) {
        const r = await api.get<SegResp>('/map/segments', { bbox, limit: 8000, scored: L.roads ? undefined : 1 })
        const feats = r.segments.filter((s) => (s[5] === '' ? L.roads : L.roughness)).map((s) => ({
          type: 'Feature' as const, properties: { cls: s[5], rc: s[6], dir: s[7] }, geometry: { type: 'LineString' as const, coordinates: [[s[2], s[1]], [s[4], s[3]]] },
        }))
        ;(m.getSource('segs') as GeoJSONSource).setData({ type: 'FeatureCollection', features: feats })
        m.setLayoutProperty('roads', 'visibility', L.roads ? 'visible' : 'none')
        m.setLayoutProperty('rough', 'visibility', L.roughness ? 'visible' : 'none')
      } else {
        ;(m.getSource('segs') as GeoJSONSource).setData({ type: 'FeatureCollection', features: [] })
      }
      if (L.clusters) {
        const st = propsRef.current.statuses
        const r = await api.get<Page<Cluster>>('/admin/clusters', { bbox, size: 200, status: st?.length ? st.join(',') : undefined, sort: '-passes' })
        clustersRef.current = r.items
        pushClusters()
        setStatus(r.total > r.items.length ? `показано ${r.items.length} из ${r.total} ям` : `${r.total} ям`)
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
      features: clustersRef.current.map((c) => ({ type: 'Feature' as const, properties: { id: c.id, passes: c.passes, level: c.level, status: c.status, sel: c.id === selectedRef.current ? 1 : 0 }, geometry: { type: 'Point' as const, coordinates: [c.lon, c.lat] } })),
    })
  }
  const selectedRef = useRef<number | null | undefined>(selectedId)
  useEffect(() => { selectedRef.current = selectedId; pushClusters() }, [selectedId])
  useEffect(() => { load() /* смена слоёв/фильтров */ }, [layers.roads, layers.roughness, layers.clusters, (statuses ?? []).join(',')])
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
  return ['case', ['==', ['get', 'status'], 'fixed'], css('--smooth'), ['==', ['get', 'status'], 'candidate'], css('--muted'), ['in', ['get', 'level'], ['literal', ['deep', 'danger']]], css('--crater'), css('--warn')]
}
function mix(a: string, b: string): string {
  const p = (c: string) => { const m = c.replace('#', ''); const n = m.length === 3 ? m.split('').map((x) => x + x).join('') : m; return [0, 2, 4].map((i) => parseInt(n.slice(i, i + 2), 16)) }
  try { const x = p(a), y = p(b); return `rgb(${x.map((v, i) => Math.round(v * 0.55 + y[i] * 0.45)).join(',')})` } catch { return a }
}
