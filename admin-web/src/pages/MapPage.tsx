import { useState } from 'react'
import ClusterPanel from '../components/ClusterPanel'
import MapView, { type ClusterKind, type MapLayers } from '../components/MapView'
import { Button, Card, Chip, Field, Input, Modal, PageHeader, Select, cx, useToast } from '../components/ui'
import { api } from '../lib/api'
import { ROUGH_COLORS, STATUS_NAMES } from '../lib/format'
import { useGet } from '../lib/hooks'
import { useAuth } from '../lib/auth'

const ELEMENT_KINDS: { key: string; label: string; type: string; level: string }[] = [
  { key: 'deep', label: 'Глубокая яма', type: 'pothole', level: 'deep' },
  { key: 'danger', label: 'Опасная яма', type: 'pothole', level: 'danger' },
  { key: 'bump', label: 'Лежачий полицейский', type: 'bump', level: 'mid' },
  { key: 'manhole_raised', label: 'Люк выступает над дорогой', type: 'manhole', level: 'mid' },
  { key: 'manhole_sunk', label: 'Люк просел под дорогой', type: 'manhole', level: 'mid' },
  { key: 'rail_tram', label: 'Трамвайные рельсы', type: 'rail_tram', level: 'mid' },
  { key: 'rail_train', label: 'Ж/д переезд', type: 'rail_train', level: 'mid' },
]
const SIDES = [['left', 'Слева'], ['center', 'По центру'], ['right', 'Справа'], ['all', 'На всю ширину']] as const

interface Hit { type: string; code: string; name: string; lat: number; lon: number }
const STATUSES = ['candidate', 'confirmed', 'complaint', 'fixed']

export default function MapPage() {
  const [layers, setLayers] = useState<MapLayers>({ roads: false, roughness: true, clusters: true, stretches: true })
  const [kind, setKind] = useState<ClusterKind>('element')
  const [statuses, setStatuses] = useState<string[]>(['candidate', 'confirmed', 'complaint'])
  const [sel, setSel] = useState<number | null>(null)
  const [fly, setFly] = useState<{ lon: number; lat: number; zoom?: number; n: number } | null>(null)
  const [q, setQ] = useState('')
  const [hits, setHits] = useState<Hit[]>([])
  const [msg, setMsg] = useState('')
  const stats = useGet<{ items: { id: number }[]; total: number }>('/admin/clusters', { size: 1 })
  const { can } = useAuth()
  const toast = useToast()
  const [adding, setAdding] = useState(false)
  const [picked, setPicked] = useState<{ lon: number; lat: number } | null>(null)
  const [form, setForm] = useState({ kind: 'deep', side: 'all', heading: '' })
  const [saving, setSaving] = useState(false)
  const [reload, setReload] = useState(0)

  async function addElement() {
    if (!picked) return
    const k = ELEMENT_KINDS.find((x) => x.key === form.kind)!
    setSaving(true)
    try {
      const hd = form.heading.trim() === '' ? undefined : Number(form.heading)
      const c = await api.post<{ id: number }>('/admin/clusters/create', { lat: picked.lat, lon: picked.lon, type: k.type, level: k.level, side: form.side === 'all' ? undefined : form.side, heading: hd })
      toast('Элемент добавлен: ' + k.label, 'ok')
      setPicked(null); setAdding(false); setSel(c.id); setReload((n) => n + 1)
    } catch (e) { toast(e instanceof Error ? e.message : 'Не удалось добавить', 'err') } finally { setSaving(false) }
  }

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
      <PageHeader title="Карта" sub={stats.data ? `${stats.data.total} мест в базе · элементы — точки на дороге, качество — участки` : undefined} />
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
          {can('labeler') && (
            <div className="flex flex-col gap-2 rounded-2xl border border-line bg-raised p-3">
              <Button kind={adding ? 'primary' : 'secondary'} onClick={() => { setAdding((a) => !a); setPicked(null) }}>{adding ? 'Отмена' : '＋ Добавить элемент'}</Button>
              {adding && <p className="text-xs text-muted">Нажмите на карте место элемента: откроется форма — что это и на какой стороне дороги.</p>}
            </div>
          )}
          <fieldset className="flex flex-col gap-2">
            <legend className="mb-1 text-sm font-semibold">Слои</legend>
            {([['clusters', 'Элементы и ямы'], ['stretches', 'Плохие участки (D/E)'], ['roughness', 'Ровность A–E по сегментам'], ['roads', 'Все дороги серым']] as [keyof MapLayers, string][]).map(([k, l]) => (
              <label key={k} className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!layers[k]} onChange={() => toggle(k)} className="h-4 w-4 accent-[var(--amber)]" />{l}</label>
            ))}
          </fieldset>
          <fieldset className="flex flex-col gap-2">
            <legend className="mb-1 text-sm font-semibold">Что показывать точками</legend>
            <div className="flex flex-wrap gap-2">
              {([['element', 'Элементы'], ['quality', 'Мелкие и средние ямы'], ['all', 'Всё']] as [ClusterKind, string][]).map(([k, l]) => (
                <button key={k} type="button" aria-pressed={kind === k} onClick={() => setKind(k)}
                  className={cx('rounded-full border px-3 py-1 text-xs font-medium', kind === k ? 'border-amber bg-amber-dim text-amber-text' : 'border-line text-muted')}>{l}</button>
              ))}
            </div>
            <p className="text-xs text-muted">Элемент — глубокая или опасная яма, лежачий, люк с перепадом, рельсы. Мелкие и средние ямы входят в качество дороги.</p>
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
          <MapView key={reload} layers={layers} statuses={statuses} kind={kind} onSelect={(c) => setSel(c.id)} selectedId={sel} flyTo={fly} onPick={adding ? setPicked : undefined} picked={picked} />
        </Card>
        <Card className="overflow-auto">
          {sel ? <ClusterPanel id={sel} onChanged={() => undefined} /> : <p className="text-sm text-muted">Выберите яму на карте — здесь появятся детали и действия модерации.</p>}
        </Card>
      </div>
      <Modal open={!!picked} title="Новый элемент на карте" onClose={() => setPicked(null)}>
        {picked && (
          <div className="flex flex-col gap-4">
            <p className="text-sm text-muted">Место: {picked.lat.toFixed(5)}, {picked.lon.toFixed(5)}. Элемент сразу появится как подтверждённый.</p>
            <Field label="Что это"><Select value={form.kind} onChange={(e) => setForm({ ...form, kind: e.target.value })}>{ELEMENT_KINDS.map((k) => <option key={k.key} value={k.key}>{k.label}</option>)}</Select></Field>
            <Field label="Где на дороге (по ходу движения)" hint="Лежачий и рельсы — на всю ширину: объехать нельзя, водитель только сбрасывает скорость.">
              <div className="flex flex-wrap gap-2">{SIDES.map(([v, l]) => <button key={v} type="button" aria-pressed={form.side === v} onClick={() => setForm({ ...form, side: v })} className={cx('rounded-full border px-3.5 py-1.5 text-sm font-medium', form.side === v ? 'border-amber bg-amber-dim text-amber-text' : 'border-line text-muted')}>{l}</button>)}</div>
            </Field>
            <Field label="Направление движения, ° (необязательно)" hint="0 — север, 90 — восток. Если пусто, элемент виден водителям с обеих сторон."><Input inputMode="numeric" value={form.heading} onChange={(e) => setForm({ ...form, heading: e.target.value.replace(/[^0-9]/g, '') })} placeholder="например 90" /></Field>
            <div className="flex justify-end gap-2"><Button onClick={() => setPicked(null)}>Отмена</Button><Button kind="primary" loading={saving} onClick={() => void addElement()}>Добавить</Button></div>
          </div>
        )}
      </Modal>
    </div>
  )
}
