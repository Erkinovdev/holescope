import { useState } from 'react'
import ClusterPanel from '../components/ClusterPanel'
import MapView, { type MapLayers } from '../components/MapView'
import { Button, Card, Chip, Field, Input, PageHeader, cx } from '../components/ui'
import { api } from '../lib/api'
import { ROUGH_COLORS, STATUS_NAMES } from '../lib/format'
import { useGet } from '../lib/hooks'

interface Hit { type: string; code: string; name: string; lat: number; lon: number }
const STATUSES = ['candidate', 'confirmed', 'complaint', 'fixed']

export default function MapPage() {
  const [layers, setLayers] = useState<MapLayers>({ roads: true, roughness: true, clusters: true })
  const [statuses, setStatuses] = useState<string[]>(['candidate', 'confirmed', 'complaint'])
  const [sel, setSel] = useState<number | null>(null)
  const [fly, setFly] = useState<{ lon: number; lat: number; zoom?: number; n: number } | null>(null)
  const [q, setQ] = useState('')
  const [hits, setHits] = useState<Hit[]>([])
  const [msg, setMsg] = useState('')
  const stats = useGet<{ items: { id: number }[]; total: number }>('/admin/clusters', { size: 1 })

  async function search() {
    setMsg('')
    if (q.trim().length < 2) return
    try {
      const r = await api.get<{ results: Hit[] }>('/search', { q: q.trim() })
      setHits(r.results)
      if (!r.results.length) setMsg('Ничего не найдено')
    } catch (e) { setMsg(e instanceof Error ? e.message : 'Ошибка поиска') }
  }
  const toggle = (k: keyof MapLayers) => setLayers((l) => ({ ...l, [k]: !l[k] }))
  const toggleStatus = (s: string) => setStatuses((a) => (a.includes(s) ? a.filter((x) => x !== s) : [...a, s]))

  return (
    <div className="flex h-full flex-col">
      <PageHeader title="Карта" sub={stats.data ? `${stats.data.total} ям в базе` : undefined} />
      <div className="grid min-h-0 flex-1 gap-4 lg:grid-cols-[250px_1fr_360px]">
        <Card className="flex flex-col gap-4 overflow-auto">
          <form onSubmit={(e) => { e.preventDefault(); void search() }} className="flex flex-col gap-2">
            <Field label="Поиск улицы или района"><Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Бабура" /></Field>
            <Button small type="submit">Найти</Button>
            {msg && <span className="text-xs text-muted">{msg}</span>}
            <ul className="flex flex-col gap-1">
              {hits.map((h) => <li key={h.type + h.code}><button type="button" className="w-full truncate rounded-lg px-2 py-1.5 text-left text-sm hover:bg-raised" onClick={() => setFly({ lon: h.lon, lat: h.lat, zoom: h.type === 'district' ? 12.5 : 15, n: Date.now() })}>{h.name} <span className="text-xs text-muted">{h.code}</span></button></li>)}
            </ul>
          </form>
          <fieldset className="flex flex-col gap-2">
            <legend className="mb-1 text-sm font-semibold">Слои</legend>
            {([['clusters', 'Ямы'], ['roughness', 'Ровность A–E'], ['roads', 'Дорожная сеть']] as [keyof MapLayers, string][]).map(([k, l]) => (
              <label key={k} className="flex items-center gap-2 text-sm"><input type="checkbox" checked={layers[k]} onChange={() => toggle(k)} className="h-4 w-4 accent-[var(--amber)]" />{l}</label>
            ))}
            <label className="flex items-center gap-2 text-sm text-muted"><input type="checkbox" disabled className="h-4 w-4" />Махалли (нет данных, TODO)</label>
          </fieldset>
          <fieldset className="flex flex-col gap-2">
            <legend className="mb-1 text-sm font-semibold">Статусы ям</legend>
            <div className="flex flex-wrap gap-2">
              {STATUSES.map((s) => (
                <button key={s} type="button" aria-pressed={statuses.includes(s)} onClick={() => toggleStatus(s)}
                  className={cx('rounded-full border px-3 py-1 text-xs font-medium', statuses.includes(s) ? 'border-amber bg-amber-dim text-amber-text' : 'border-line text-muted')}>{STATUS_NAMES[s]}</button>
              ))}
            </div>
          </fieldset>
          <div>
            <div className="mb-2 text-sm font-semibold">Ровность</div>
            <div className="flex gap-2">{['A', 'B', 'C', 'D', 'E'].map((k) => <Chip key={k} tone="muted"><span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: ROUGH_COLORS[k] }} />{k}</Chip>)}</div>
            <p className="mt-2 text-xs text-muted">Сегменты красятся с zoom ≥ 11.5. Границы классов — стартовые, не итог.</p>
          </div>
        </Card>
        <Card pad={false} className="min-h-[420px] overflow-hidden">
          <MapView layers={layers} statuses={statuses} onSelect={(c) => setSel(c.id)} selectedId={sel} flyTo={fly} />
        </Card>
        <Card className="overflow-auto">
          {sel ? <ClusterPanel id={sel} onChanged={() => undefined} /> : <p className="text-sm text-muted">Выберите яму на карте — здесь появятся детали и действия модерации.</p>}
        </Card>
      </div>
    </div>
  )
}
