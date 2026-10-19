import { useMemo, useRef, useState, type DragEvent } from 'react'
import { Link } from 'react-router-dom'
import Brain3D from '../components/Brain3D'
import { BarChart, LineChart, SignalChart, Wave } from '../components/Charts'
import ClusterPanel from '../components/ClusterPanel'
import { Button, Card, CardTitle, Chip, Empty, ErrorBox, Field, Input, KV, Kpi, PageHeader, Segmented, Spinner, Table, useToast } from '../components/ui'
import { api, type AlgoVersion, type Readiness, type GraphEdge, type GraphNode } from '../lib/api'
import { useAuth } from '../lib/auth'
import { fmtDate, fmtDateTime, fmtNum, ROUGH_COLORS, TYPE_NAMES } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'
import { Mark, ScanBar } from '../components/Loaders'
import type { Taxonomy } from '../lib/api'

type Tab = 'graph' | 'timeline'
const TABS: { value: Tab; label: string }[] = [{ value: 'graph', label: '3D-граф' }, { value: 'timeline', label: 'Версии и метрики' }]

interface Summary { current: Record<string, number | string>; history: unknown[] }

export default function Brain() {
  const [tab, setTab] = useState<Tab>('graph')
  const s = useGet<Summary>('/admin/brain/summary')
  const c = s.data?.current
  return (
    <div>
      <PageHeader title="Мозг" sub="Как система учится различать ямы, люки и рельсы: данные, разметка, версии, параметры" right={c ? <Chip tone="amber">активно: {String(c.active_algo)}</Chip> : undefined} />
      {s.error && <ErrorBox error={s.error} onRetry={() => s.refetch()} />}
      {c && (
        <div className="mb-5 flex flex-wrap gap-4">
          <Kpi label="Событий" value={fmtNum(Number(c.events))} sub={`${fmtNum(Number(c.trips))} поездок`} />
          <Kpi label="Ям (кластеров)" value={fmtNum(Number(c.clusters))} sub={`подтверждено: ${fmtNum(Number(c.confirmed))}`} tone="crater" />
          <Kpi label="Разметки" value={fmtNum(Number(c.labels))} sub={`вопросов открыто: ${fmtNum(Number(c.questions_open))}`} tone="info" />
          <Kpi label="Дорожная сеть" value={fmtNum(Number(c.segments))} sub={`оценено сегментов: ${fmtNum(Number(c.segments_scored))}`} tone="smooth" />
        </div>
      )}
      <ReadinessCard />
      <div className="mb-4"><Segmented label="Раздел" value={tab} onChange={setTab} options={TABS} /></div>
      {tab === 'graph' && <GraphTab />}
      {tab === 'timeline' && <TimelineTab />}
    </div>
  )
}

// ───────────────────────── 3D-граф ─────────────────────────
const KIND_NAMES: Record<string, string> = { cluster: 'яма', road: 'дорога', version: 'версия', feature: 'признак', device: 'устройство-подтвердитель' }

function GraphTab() {
  const [limit, setLimit] = useState('220')
  const g = useGet<{ nodes: GraphNode[]; edges: GraphEdge[]; counts: { clusters: number; nodes: number; edges: number } }>('/admin/brain/graph', { limit })
  const [sel, setSel] = useState<GraphNode | null>(null)
  const nodes = useMemo(() => g.data?.nodes ?? [], [g.data])
  const edges = useMemo(() => g.data?.edges ?? [], [g.data])
  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_380px]">
      <Card pad={false} className="relative h-[560px] overflow-hidden">
        {g.isLoading && <div className="flex h-full flex-col items-center justify-center gap-4"><Mark size={110} /><ScanBar width={180} /></div>}
        {g.error && <div className="p-4"><ErrorBox error={g.error} onRetry={() => g.refetch()} /></div>}
        {g.data && nodes.length === 0 && <div className="p-6"><Empty>Данных для графа пока нет: ямы появятся после первых поездок.</Empty></div>}
        {nodes.length > 0 && <Brain3D nodes={nodes} edges={edges} onSelect={setSel} selectedId={sel?.id ?? null} />}
        <div className="pointer-events-none absolute left-3 top-3 flex flex-wrap gap-2">
          {g.data && <Chip tone="muted">{g.data.counts.nodes} узлов · {g.data.counts.edges} связей</Chip>}
          {[['crater', 'яма'], ['muted', 'дорога'], ['amber', 'версия'], ['info', 'признак'], ['smooth', 'устройство']].map(([t, l]) => <Chip key={l} tone={t as 'crater'}>{l}</Chip>)}
        </div>
        <div className="absolute bottom-3 left-3 flex items-center gap-2 rounded-xl bg-surface/90 px-3 py-2 text-xs text-muted">
          Вращение — мышь, масштаб — колесо, клик — карточка узла. Яркость узла = уверенность.
          <select aria-label="Число ям" className="rounded-lg border border-line bg-raised px-2 py-1" value={limit} onChange={(e) => setLimit(e.target.value)}>{['100', '220', '400'].map((v) => <option key={v} value={v}>{v} ям</option>)}</select>
        </div>
      </Card>
      <Card className="max-h-[560px] overflow-auto">
        {!sel && <p className="text-sm text-muted">Нажмите на узел графа: яма откроется с историей и волнами ударов, дорога — со ссылкой на реестр, версия — с метриками.</p>}
        {sel?.kind === 'cluster' && sel.ref && <ClusterPanel id={sel.ref} />}
        {sel && sel.kind !== 'cluster' && (
          <div className="flex flex-col gap-3">
            <h3 className="text-lg font-bold">{sel.label}</h3>
            <Chip tone="info">{KIND_NAMES[sel.kind] ?? sel.kind}</Chip>
            <KV rows={[['Уверенность', sel.confidence.toFixed(2)], ...(sel.events !== undefined ? [['Событий версии', fmtNum(sel.events)] as [string, string]] : []), ...(sel.road_class ? [['Класс', sel.road_class] as [string, string]] : [])]} />
            {sel.kind === 'road' && <Link className="text-info hover:underline" to="/roads">Открыть реестр дорог →</Link>}
            {sel.kind === 'device' && sel.ref && <Link className="text-info hover:underline" to={`/devices/${sel.ref}`}>Открыть устройство →</Link>}
          </div>
        )}
      </Card>
    </div>
  )
}

// ───────────────────────── версии и метрики ─────────────────────────
interface Timeline { runs: { id: number; at: string; n_labels: number; metrics: Record<string, any>; log: string; version: string | null }[]; snapshots: { day: string; events: number; clusters: number; labels: number; km: number; devices: number }[]; versions: AlgoVersion[]; base: { version: string; f1: number | null } }

export function TimelineTab() {
  const { can } = useAuth()
  const t = useGet<Timeline>('/admin/brain/timeline')
  const toast = useToast()
  const act = useSave((b: { version_id: number; force?: boolean; off?: boolean }) => api.post(b.off ? '/admin/brain/deactivate' : '/admin/brain/activate', b), { ok: 'Готово', invalidate: ['/admin/brain', '/api'] })
  const train = useSave(() => api.post<{ log: string; version: string | null; active: boolean }>('/admin/brain/train'), { invalidate: ['/admin/brain'], onDone: (r) => toast(r.log, 'ok') })
  const tryActivate = (v: AlgoVersion) => {
    if (v.kind === 'gbm' && !v.metrics.activated) {
      if (!window.confirm('Версия не прошла проверку: она не лучше правил на отложенных поездках. Включить вручную?')) return
      act.mutate({ version_id: v.id, force: true })
    } else act.mutate({ version_id: v.id })
  }
  if (t.isLoading) return <Spinner />
  if (t.error) return <ErrorBox error={t.error} onRetry={() => t.refetch()} />
  const d = t.data!
  const f1 = (v: AlgoVersion) => v.metrics?.model?.f1
  const gbm = d.versions.filter((v) => v.kind === 'gbm').slice().reverse()
  return (
    <div className="flex flex-col gap-4">
      <div className="grid gap-4 xl:grid-cols-2">
        <Card>
          <CardTitle>F1 по версиям (проверка «поездка против поездки»)</CardTitle>
          {gbm.length === 0 ? <Empty>Обученных версий пока нет. Нужна разметка: ≥60 меток и ≥2 поездки по ≥20 меток.</Empty> : (
            <LineChart labels={gbm.map((v) => v.version)} series={[{ name: 'модель', color: 'var(--amber)', points: gbm.map((v) => f1(v) ?? null) }, { name: 'правила', color: 'var(--info)', points: gbm.map((v) => v.metrics?.rules?.f1 ?? null) }]} />
          )}
          <div className="mt-2 flex gap-4 text-xs text-muted"><span><b className="text-amber-text">●</b> модель</span><span><b className="text-info">●</b> правила (база {d.base.f1 == null ? '—' : d.base.f1.toFixed(2)})</span></div>
        </Card>
        <Card>
          <CardTitle>Рост данных</CardTitle>
          {d.snapshots.length === 0 ? <Empty>Снимков пока нет (создаются ночной задачей).</Empty> : <BarChart data={d.snapshots.map((s) => ({ label: fmtDate(s.day), value: s.events, sub: `ям ${s.clusters} · меток ${s.labels} · ${s.km} км` }))} />}
        </Card>
      </div>
      <Card>
        <CardTitle right={can('admin') && <Button small kind="primary" disabled={train.isPending} onClick={() => train.mutate(undefined)}>Обучить сейчас</Button>}>Версии «мозга»</CardTitle>
        <Table rowKey={(r) => r.id} rows={d.versions} empty="Версий нет — работают встроенные правила" cols={[
          { key: 'v', title: 'Версия', render: (r) => <b>{r.version}</b> }, { key: 'k', title: 'Вид', render: (r) => (r.kind === 'rules' ? 'правила' : 'модель gbm') },
          { key: 'c', title: 'Создана', render: (r) => fmtDateTime(r.created) },
          { key: 'f', title: 'F1 модель / правила', render: (r) => (r.kind === 'gbm' ? `${f1(r)?.toFixed(2) ?? '—'} / ${r.metrics?.rules?.f1?.toFixed(2) ?? '—'}` : '—') },
          { key: 'cv', title: 'Проверка', render: (r) => (r.kind === 'gbm' ? (r.metrics?.cv === 'leave-trip-out' ? 'поездка против поездки' : 'блоки одной поездки (слабая)') : '—') },
          { key: 's', title: 'Статус', render: (r) => <Chip tone={r.active ? 'smooth' : 'muted'}>{r.active ? 'активна' : 'не включена'}</Chip> },
          { key: 'n', title: 'Заметка', render: (r) => <span className="line-clamp-2 max-w-xs text-xs text-muted">{r.notes || '—'}</span> },
          { key: 'a', title: '', align: 'right', render: (r) => can('admin') && (r.active ? <Button small onClick={() => act.mutate({ version_id: r.id, off: true })}>Выключить</Button> : <Button small onClick={() => tryActivate(r)}>Включить</Button>) },
        ]} />
        <p className="mt-3 text-xs text-muted">Новая версия включается автоматически только если на отложенных поездках лучше правил по F1 (прирост ≥ 0.02) при ≥2 поездках по ≥20 меток. Ручное включение — на вашу ответственность.</p>
      </Card>
      <Card>
        <CardTitle>Запуски обучения</CardTitle>
        <Table rowKey={(r) => r.id} rows={d.runs} empty="Запусков не было" cols={[
          { key: 'a', title: 'Когда', render: (r) => fmtDateTime(r.at) }, { key: 'n', title: 'Меток', align: 'right', render: (r) => r.n_labels },
          { key: 'v', title: 'Версия', render: (r) => r.version ?? '—' }, { key: 'l', title: 'Итог', render: (r) => <span className="text-xs">{r.log}</span> },
        ]} />
      </Card>
    </div>
  )
}

// ───────────────────────── очередь разметки ─────────────────────────
interface QueueResp { stats: { open: number; answered: number; skipped: number; answered_7d: number; labels: number; by_source: Record<string, number> }; queue: { id: number; priority: number; at: string; speed_kmh: number; peak: number; score: number; type: string; level: string; confidence: number; wave: number[]; cluster: number | null }[]; labels: string[]; taxonomy: Taxonomy }
export function QueueTab() {
  const { can } = useAuth()
  const q = useGet<QueueResp>('/admin/brain/questions', { limit: 24 })
  const label = useSave((b: { event_id: number; label: string }) => api.post('/admin/brain/label', b), { ok: 'Метка сохранена', invalidate: ['/admin/brain'] })
  if (q.isLoading) return <Spinner />
  if (q.error) return <ErrorBox error={q.error} onRetry={() => q.refetch()} />
  const d = q.data!
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap gap-4">
        <Kpi label="Вопросов открыто" value={d.stats.open} tone="warn" /><Kpi label="Ответов за 7 дней" value={d.stats.answered_7d} tone="smooth" /><Kpi label="Всего меток" value={d.stats.labels} sub={Object.entries(d.stats.by_source).map(([k, v]) => `${k}: ${v}`).join(' · ')} tone="info" />
      </div>
      <p className="text-sm text-muted">Очередь отсортирована по приоритету: неопределённость × новизна × сила удара. Разметка идёт в обучение.</p>
      {d.queue.length === 0 ? <Empty>Неразмеченных событий нет.</Empty> : (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {d.queue.map((e) => (
            <Card key={e.id} className="flex flex-col gap-2">
              <div className="flex flex-wrap items-center gap-2 text-xs text-muted"><Chip tone="amber">приоритет {e.priority}</Chip><span>{Math.round(e.speed_kmh)} км/ч · score {e.score}</span>{e.cluster && <Link className="ml-auto hover:underline" to={`/events?focus=${e.cluster}`}>яма #{e.cluster}</Link>}</div>
              <Wave wave={e.wave} />
              <div className="text-xs text-muted">догадка: {TYPE_NAMES[e.type] ?? e.type}, уверенность {e.confidence.toFixed(2)}</div>
              {can('labeler') && (
                <div className="flex flex-col gap-2">
                  {Object.entries(d.taxonomy.groups).map(([g, info]) => (
                    <div key={g}>
                      <div className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-muted">{info.ru}</div>
                      <div className="flex flex-wrap gap-1.5">{d.taxonomy.items.filter((i) => i.group === g).map((i) => <Button key={i.key} small title={i.hint} disabled={label.isPending} onClick={() => label.mutate({ event_id: e.id, label: i.key })}>{i.ru}</Button>)}</div>
                    </div>
                  ))}
                </div>
              )}
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}

// ───────────────────────── записи CSV ─────────────────────────
interface UploadRow { id: number; filename: string; created: string; processed: boolean; algo_version: string; report: { events?: number; by_type?: Record<string, number>; segments?: number; distance_km?: number; duration_s?: number; wheelbase_m?: number; error?: string } }
interface ReviewResp { duration_s: number; samples: number; signal: { t: number[]; vz: number[] }; events: { t: number; type: string; level: string | null; score: number; peak: number; speed_kmh: number; lat: number; lon: number }[]; hands: number[][]; path: number[][]; fwd_ok: boolean }

export function UploadsTab() {
  const { can } = useAuth()
  const list = useGet<{ items: UploadRow[]; total: number }>('/admin/brain/uploads', { size: 30 })
  const [sel, setSel] = useState<number | null>(null)
  const [wb, setWb] = useState('2.485')
  const [drag, setDrag] = useState(false)
  const input = useRef<HTMLInputElement>(null)
  const up = useSave((f: File) => { const fd = new FormData(); fd.append('file', f); fd.append('wheelbase_m', wb); return api.upload<{ raw_id: number; report: UploadRow['report'] }>('/admin/brain/upload-csv', fd) },
    { ok: 'Файл разобран', invalidate: ['/admin/brain'], onDone: (r) => setSel(r.raw_id) })
  const onDrop = (e: DragEvent) => { e.preventDefault(); setDrag(false); const f = e.dataTransfer.files?.[0]; if (f && can('labeler')) up.mutate(f) }
  return (
    <div className="flex flex-col gap-4">
      {can('labeler') && (
        <Card>
          <div role="button" tabIndex={0} aria-label="Загрузить CSV" onClick={() => input.current?.click()} onKeyDown={(e) => { if (e.key === 'Enter') input.current?.click() }}
            onDragOver={(e) => { e.preventDefault(); setDrag(true) }} onDragLeave={() => setDrag(false)} onDrop={onDrop}
            className={`flex cursor-pointer flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed p-8 text-center transition ${drag ? 'border-amber bg-amber-dim' : 'border-line bg-raised'}`}>
            <span className="font-semibold text-amber-text">{up.isPending ? 'Разбираем запись…' : 'Перетащите CSV поездки сюда или нажмите'}</span>
            <span className="text-xs text-muted">Формат веб-логгера (pothole-logger). Прогоняется алгоритм активной версии; результат в карту не попадает.</span>
            <input ref={input} type="file" accept=".csv,text/csv" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) up.mutate(f); e.target.value = '' }} />
          </div>
          <div className="mt-3 max-w-xs"><Field label="Колёсная база машины, м" hint="Влияет на интервал второго удара"><Input value={wb} onChange={(e) => setWb(e.target.value)} inputMode="decimal" /></Field></div>
        </Card>
      )}
      <Table rowKey={(r) => r.id} rows={list.data?.items ?? []} empty="Записей ещё нет" selected={(r) => r.id === sel} onRow={(r) => setSel(r.id)} cols={[
        { key: 'f', title: 'Файл', render: (r) => <b>{r.filename}</b> }, { key: 'c', title: 'Загружен', render: (r) => fmtDateTime(r.created) },
        { key: 'e', title: 'Событий', align: 'right', render: (r) => r.report.events ?? '—' },
        { key: 't', title: 'Типы', render: (r) => (r.report.by_type ? Object.entries(r.report.by_type).map(([k, v]) => `${TYPE_NAMES[k] ?? k}: ${v}`).join(', ') : '—') },
        { key: 'km', title: 'Км', align: 'right', render: (r) => r.report.distance_km ?? '—' }, { key: 'a', title: 'Алгоритм', render: (r) => r.algo_version || '—' },
      ]} />
      {sel && <ReviewPanel id={sel} />}
    </div>
  )
}

function ReviewPanel({ id }: { id: number }) {
  const q = useGet<ReviewResp>(`/admin/brain/uploads/${id}/review`)
  const [ev, setEv] = useState<number | null>(null)
  if (q.isLoading) return <Spinner label="Считаем сигнал записи…" />
  if (q.error) return <ErrorBox error={q.error} onRetry={() => q.refetch()} />
  const d = q.data!
  const e = ev !== null ? d.events[ev] : null
  return (
    <Card>
      <CardTitle right={<Chip tone={d.fwd_ok ? 'smooth' : 'warn'}>ось «вперёд» {d.fwd_ok ? 'определена' : 'не определена'}</Chip>}>Просмотр записи · {Math.round(d.duration_s)} с · {fmtNum(d.samples)} отсчётов</CardTitle>
      <SignalChart t={d.signal.t} vz={d.signal.vz} events={d.events} hands={d.hands} selected={ev} onSelect={setEv} />
      <p className="mt-1 text-xs text-muted">Серые линии — вертикаль; красные — ямы, серые — шум/касания; синие полосы — участки «телефон в руке» (вырезаются). Нажмите на линию события.</p>
      {e && (
        <div className="mt-3 rounded-2xl bg-raised p-4 text-sm"><b>{e.t.toFixed(1)} с</b> · {TYPE_NAMES[e.type] ?? e.type}{e.level ? ` · ${e.level}` : ''} · пик {e.peak} · score {e.score} · {Math.round(e.speed_kmh)} км/ч · {e.lat.toFixed(5)}, {e.lon.toFixed(5)}</div>
      )}
      <h4 className="mb-2 mt-4 text-sm font-semibold">События ({d.events.length})</h4>
      <div className="max-h-64 overflow-auto">
        <table className="w-full text-xs"><thead><tr className="text-left text-muted"><th className="p-1">с</th><th className="p-1">тип</th><th className="p-1">уровень</th><th className="p-1 text-right">пик</th><th className="p-1 text-right">score</th><th className="p-1 text-right">км/ч</th></tr></thead>
          <tbody>{d.events.map((x, i) => <tr key={i} onClick={() => setEv(i)} className={`cursor-pointer border-t border-line hover:bg-raised ${ev === i ? 'bg-amber-dim/40' : ''}`}><td className="p-1">{x.t.toFixed(1)}</td><td className="p-1">{TYPE_NAMES[x.type] ?? x.type}</td><td className="p-1">{x.level ?? '—'}</td><td className="p-1 text-right">{x.peak}</td><td className="p-1 text-right">{x.score}</td><td className="p-1 text-right">{Math.round(x.speed_kmh)}</td></tr>)}</tbody></table>
      </div>
      <div className="mt-3 flex gap-2 text-xs text-muted">{['A', 'B', 'C', 'D', 'E'].map((k) => <span key={k} className="flex items-center gap-1"><span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: ROUGH_COLORS[k] }} />{k}</span>)} · маршрут: {d.path.length} точек</div>
    </Card>
  )
}

// ───────────────────────── параметры ─────────────────────────
interface ParamsResp { version: string; params: Record<string, number | number[]>; ranges: Record<string, [number, number]>; defaults: Record<string, number | number[]> }
interface PreviewResp { current: { total: number; by_type: Record<string, number>; by_level: Record<string, number> }; preview: { total: number; by_type: Record<string, number>; by_level: Record<string, number> }; added: number; removed: number }
const PARAM_NAMES: Record<string, string> = { floor: 'Минимальный порог, м/с²', k_noise: 'Множитель фонового шума', speed_alpha: 'Показатель скорости α', merge_gap_s: 'Склейка событий, с', wheelbase_m: 'Колёсная база, м (по умолчанию)', min_speed_ms: 'Мин. скорость поиска, м/с', low_conf_speed_ms: 'Порог «слабая достоверность», м/с', v0_ms: 'Опорная скорость v0, м/с', seg_len_m: 'Длина сегмента ровности, м', ri_beta: 'Показатель β индекса ровности', min_speed_ri_ms: 'Мин. скорость для ровности, м/с', grav_alpha: 'Сглаживание гравитации', smooth_samples: 'Сглаживание вертикали, отсчётов' }

export function ParamsTab() {
  const { can } = useAuth()
  const p = useGet<ParamsResp>('/admin/brain/params')
  const uploads = useGet<{ items: UploadRow[] }>('/admin/brain/uploads', { size: 30 })
  const [edit, setEdit] = useState<Record<string, string>>({})
  const [bounds, setBounds] = useState<string[] | null>(null)
  const [raw, setRaw] = useState('')
  const [activate, setActivate] = useState(false)
  const [notes, setNotes] = useState('')
  const [prev, setPrev] = useState<PreviewResp | null>(null)
  const toNum = (k: string) => (edit[k] === undefined ? undefined : Number(edit[k]))
  const changed = useMemo(() => {
    const out: Record<string, unknown> = {}
    for (const k of Object.keys(edit)) if (edit[k] !== '' && !Number.isNaN(Number(edit[k]))) out[k] = Number(edit[k])
    if (bounds) out.ri_bounds = bounds.map(Number)
    return out
  }, [edit, bounds])
  const preview = useSave(() => api.post<PreviewResp>('/admin/brain/preview', { raw_id: Number(raw), params: { ...(p.data?.params ?? {}), ...changed } }), { onDone: setPrev })
  const save = useSave(() => api.put('/admin/brain/params/save', { params: { ...(p.data?.params ?? {}), ...changed }, activate, notes }), { ok: 'Версия параметров сохранена', invalidate: ['/admin/brain', '/api'], onDone: () => { setEdit({}); setBounds(null); setPrev(null) } })
  if (p.isLoading) return <Spinner />
  if (p.error) return <ErrorBox error={p.error} onRetry={() => p.refetch()} />
  const d = p.data!
  const scalar = Object.keys(d.params).filter((k) => k !== 'ri_bounds')
  void toNum
  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_420px]">
      <Card>
        <CardTitle right={<Chip tone="amber">{d.version}</Chip>}>Параметры алгоритма</CardTitle>
        <p className="mb-3 text-sm text-muted">Приложение подтягивает активные параметры и применяет их на устройстве (порог, шум, скоростная поправка); границы классов ровности использует сервер.</p>
        <div className="grid gap-3 md:grid-cols-2">
          {scalar.map((k) => (
            <Field key={k} label={PARAM_NAMES[k] ?? k} hint={d.ranges[k] ? `допустимо ${d.ranges[k][0]} … ${d.ranges[k][1]} (по умолчанию ${d.defaults[k]})` : undefined}>
              <Input type="number" step="any" disabled={!can('admin')} value={edit[k] ?? String(d.params[k])} onChange={(e) => setEdit({ ...edit, [k]: e.target.value })} />
            </Field>
          ))}
        </div>
        <div className="mt-4">
          <div className="mb-2 text-sm font-semibold">Границы классов ровности A|B|C|D|E (RI)</div>
          <div className="grid grid-cols-4 gap-3">{(bounds ?? (d.params.ri_bounds as number[]).map(String)).map((b, i) => <Input key={i} type="number" step="0.005" disabled={!can('admin')} value={b} onChange={(e) => { const nb = [...(bounds ?? (d.params.ri_bounds as number[]).map(String))]; nb[i] = e.target.value; setBounds(nb) }} aria-label={`Граница ${i + 1}`} />)}</div>
          <p className="mt-1 text-xs text-muted">Стартовые значения — не итог: калибруются по городу, когда поездок станет много.</p>
        </div>
        {can('admin') && (
          <div className="mt-5 flex flex-col gap-3 rounded-2xl bg-raised p-4">
            <Field label="Заметка к версии"><Input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="что и зачем меняем" /></Field>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" className="h-4 w-4 accent-[var(--amber)]" checked={activate} onChange={(e) => setActivate(e.target.checked)} />Сразу сделать активной</label>
            <div className="flex gap-2"><Button kind="primary" disabled={!Object.keys(changed).length || save.isPending} onClick={() => save.mutate(undefined)}>Сохранить как новую версию</Button><Button kind="ghost" onClick={() => { setEdit({}); setBounds(null); setPrev(null) }}>Сбросить</Button></div>
          </div>
        )}
      </Card>
      <Card>
        <CardTitle>Предпросмотр на записи</CardTitle>
        <p className="mb-3 text-sm text-muted">Прогон алгоритма с вашими параметрами на загруженной записи — без сохранения. Покажет, сколько событий добавится или пропадёт.</p>
        <Field label="Запись"><select value={raw} onChange={(e) => setRaw(e.target.value)} className="w-full rounded-xl border border-line bg-raised px-3.5 py-2.5 text-sm"><option value="">— выберите —</option>{uploads.data?.items.map((u) => <option key={u.id} value={u.id}>{u.filename} · {u.report.events ?? '?'} соб.</option>)}</select></Field>
        <div className="mt-3"><Button kind="primary" disabled={!raw || preview.isPending} onClick={() => preview.mutate(undefined)}>{preview.isPending ? 'Считаем…' : 'Посмотреть'}</Button></div>
        {prev && (
          <div className="mt-4 flex flex-col gap-2 text-sm">
            <KV rows={[['Событий сейчас', prev.current.total], ['Событий с новыми параметрами', prev.preview.total], ['Добавится', prev.added], ['Пропадёт', prev.removed]]} />
            <div className="text-xs text-muted">Типы: {Object.entries(prev.preview.by_type).map(([k, v]) => `${TYPE_NAMES[k] ?? k}: ${v}`).join(', ') || '—'}</div>
            <div className="text-xs text-muted">Уровни: {Object.entries(prev.preview.by_level).map(([k, v]) => `${k}: ${v}`).join(', ') || '—'}</div>
          </div>
        )}
      </Card>
    </div>
  )
}

// ───────────────────────── «Простыми словами» ─────────────────────────
export function ReadinessCard() {
  const r = useGet<Readiness>('/admin/brain/readiness')
  if (!r.data) return null
  const d = r.data
  const tone = d.state === 'learned' ? 'smooth' : d.state === 'ready' ? 'amber' : 'info'
  return (
    <Card className="mb-5">
      <CardTitle right={<Chip tone={tone}>{d.state === 'learned' ? 'модель работает' : d.state === 'ready' ? 'готово к обучению' : 'учится'}</Chip>}>Простыми словами</CardTitle>
      <p className="mb-3 text-base font-medium">{d.title}</p>
      <div className="mb-1 flex justify-between text-xs text-muted"><span>Готовность к обучению</span><span>{d.progress}%</span></div>
      <div className="mb-4 h-2 overflow-hidden rounded-full bg-raised" role="progressbar" aria-valuenow={d.progress} aria-valuemin={0} aria-valuemax={100}>
        <div className="h-full rounded-full bg-[var(--amber)] transition-all" style={{ width: `${d.progress}%` }} />
      </div>
      <p className="mb-1 text-sm font-semibold">Что делать дальше</p>
      <ol className="list-decimal pl-5 text-sm text-muted">{d.steps.map((x, i) => <li key={i}>{x}</li>)}</ol>
      <div className="mt-3 rounded-2xl bg-raised p-3 text-xs">
        <div className="mb-1 font-semibold">Модель «что это» (люк, лежачий, рельсы, яма…): {d.types.active ? `работает, версия ${d.types.active}` : 'пока решают правила по форме удара'}</div>
        <div className="flex flex-wrap gap-2">{Object.keys(d.types.counts).length === 0 ? <span className="text-muted">размеченных объектов по типам пока нет</span> : Object.entries(d.types.counts).map(([k, n]) => <Chip key={k} tone={n >= d.types.per_class ? 'smooth' : 'muted'}>{k}: {n}/{d.types.per_class}</Chip>)}</div>
      </div>
      <p className="mt-3 text-xs text-muted">Разметка: {d.facts.labels} (дорога {d.facts.road} · не дорога {d.facts.not_road}). {d.last_training ?? 'Обучений ещё не было.'}</p>
    </Card>
  )
}
