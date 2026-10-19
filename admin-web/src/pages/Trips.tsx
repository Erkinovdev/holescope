import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { Wave } from '../components/Charts'
import { Button, Card, CardTitle, Chip, ErrorBox, Field, Input, KV, PageHeader, Pagination, Select, Spinner, Table } from '../components/ui'
import type { Page, TripRow } from '../lib/api'
import { fmtDateTime, fmtNum, LEVEL_NAMES, LEVEL_TONE, MODE_NAMES, ROUGH_COLORS, TYPE_NAMES } from '../lib/format'
import { useGet } from '../lib/hooks'
import { TableSkeleton } from '../components/Loaders'

export default function Trips() {
  const nav = useNavigate()
  const [page, setPage] = useState(1)
  const [mode, setMode] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  useEffect(() => setPage(1), [mode, from, to])
  const list = useGet<Page<TripRow>>('/admin/trips', { page, size: 30, mode, from: from || undefined, to: to ? `${to}T23:59:59+05:00` : undefined })
  return (
    <div>
      <PageHeader title="Поездки" sub="Список и разбор: события с волнами и маршрут. Загрузка CSV и просмотр сигнала — в разделе «Мозг»." />
      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Field label="Режим"><Select value={mode} onChange={(e) => setMode(e.target.value)}><option value="">все</option>{Object.entries(MODE_NAMES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
        <Field label="С даты"><Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
        <Field label="По дату"><Input type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
      </div>
      {list.isLoading && <TableSkeleton />}
      {list.error && <ErrorBox error={list.error} onRetry={() => list.refetch()} />}
      {list.data && (
        <>
          <Table rowKey={(r) => r.id} rows={list.data.items} empty="Поездок нет" onRow={(r) => nav(`/trips/${r.id}`)} cols={[
            { key: 'id', title: '№', width: '60px', render: (r) => r.id },
            { key: 's', title: 'Начало', render: (r) => fmtDateTime(r.started_at) },
            { key: 'd', title: 'Устройство', render: (r) => r.device },
            { key: 'km', title: 'Км', align: 'right', render: (r) => fmtNum(r.distance_km, 1) },
            { key: 'e', title: 'Ям', align: 'right', render: (r) => r.events },
            { key: 'm', title: 'Режим', render: (r) => <Chip tone={r.mode === 'car' ? 'smooth' : 'warn'}>{MODE_NAMES[r.mode] ?? r.mode}</Chip> },
            { key: 'a', title: 'Алгоритм', render: (r) => r.algo_version || '—' },
            { key: 'r', title: 'Окончание', render: (r) => r.end_reason || '—' },
          ]} />
          <Pagination page={list.data.page} size={list.data.size} total={list.data.total} onPage={setPage} />
        </>
      )}
    </div>
  )
}

interface TripDetail {
  id: number; device: string; device_id: number; started_at: string; ended_at: string | null; distance_km: number; mode: string; mode_conf: number; algo_version: string; end_reason: string
  summary: Record<string, unknown>; quiet_passes: number
  events: { id: number; t: number; lat: number; lon: number; speed_kmh: number; peak: number; score: number; type: string; level: string; confidence: number; cluster: number | null; user_label: string; wave: number[] }[]
  segments: { lat_a: number; lon_a: number; lat_b: number; lon_b: number; ri: number; cls: string; speed_kmh: number }[]
}

/** Схема маршрута: сегменты поездки, окрашенные по классу ровности, и ямы (проекция в метры вокруг центра). */
function RoutePlot({ t }: { t: TripDetail }) {
  const pts = useMemo(() => {
    const all = [...t.segments.flatMap((s) => [[s.lat_a, s.lon_a], [s.lat_b, s.lon_b]]), ...t.events.map((e) => [e.lat, e.lon])]
    if (!all.length) return null
    const lat0 = all.reduce((a, p) => a + p[0], 0) / all.length
    const k = Math.cos((lat0 * Math.PI) / 180)
    const xy = (la: number, lo: number): [number, number] => [lo * k * 111320, -la * 111320]
    const xs = all.map((p) => xy(p[0], p[1])[0]), ys = all.map((p) => xy(p[0], p[1])[1])
    const minX = Math.min(...xs), maxX = Math.max(...xs), minY = Math.min(...ys), maxY = Math.max(...ys)
    const W = 800, H = 420, pad = 20
    const sc = Math.min((W - pad * 2) / Math.max(maxX - minX, 1), (H - pad * 2) / Math.max(maxY - minY, 1))
    const P = (la: number, lo: number) => { const [x, y] = xy(la, lo); return [pad + (x - minX) * sc, pad + (y - minY) * sc] as const }
    return { P, W, H }
  }, [t])
  if (!pts) return <p className="text-sm text-muted">Нет координат</p>
  const { P, W, H } = pts
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full rounded-2xl bg-raised" role="img" aria-label="Маршрут поездки">
      {t.segments.map((s, i) => { const a = P(s.lat_a, s.lon_a), b = P(s.lat_b, s.lon_b); return <line key={i} x1={a[0]} y1={a[1]} x2={b[0]} y2={b[1]} stroke={ROUGH_COLORS[s.cls] ?? 'var(--line)'} strokeWidth={4} strokeLinecap="round"><title>{`${s.cls} · RI ${s.ri.toFixed(3)} · ${Math.round(s.speed_kmh)} км/ч`}</title></line> })}
      {t.events.map((e) => { const p = P(e.lat, e.lon); return <circle key={e.id} cx={p[0]} cy={p[1]} r={7} fill={e.level === 'deep' || e.level === 'danger' ? 'var(--crater)' : 'var(--warn)'} stroke="var(--bg-base)" strokeWidth={2}><title>{`${TYPE_NAMES[e.type] ?? e.type} · ${LEVEL_NAMES[e.level]} · score ${e.score}`}</title></circle> })}
    </svg>
  )
}

export function TripPage() {
  const { id } = useParams()
  const q = useGet<TripDetail>(`/admin/trips/${id}`)
  if (q.isLoading) return <Spinner />
  if (q.error) return <ErrorBox error={q.error} onRetry={() => q.refetch()} />
  const t = q.data!
  return (
    <div>
      <PageHeader title={`Поездка #${t.id}`} sub={`${fmtDateTime(t.started_at)} · ${t.device}`} right={<Link to="/trips"><Button kind="ghost">← К списку</Button></Link>} />
      <div className="grid gap-4 xl:grid-cols-[1fr_380px]">
        <div className="flex flex-col gap-4">
          <Card><CardTitle>Маршрут и ровность</CardTitle><RoutePlot t={t} />
            <div className="mt-2 flex gap-3 text-xs text-muted">{['A', 'B', 'C', 'D', 'E'].map((k) => <span key={k} className="flex items-center gap-1"><span className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: ROUGH_COLORS[k] }} />{k}</span>)}</div></Card>
          <Card>
            <CardTitle>События ({t.events.length})</CardTitle>
            {t.events.length === 0 ? <p className="text-sm text-muted">Событий нет (поездка не в режиме «авто» или после обрезки 200 м ничего не осталось).</p> : (
              <div className="grid gap-3 md:grid-cols-2">
                {t.events.map((e) => (
                  <div key={e.id} className="rounded-2xl border border-line p-3">
                    <div className="mb-1 flex flex-wrap items-center gap-2 text-xs"><Chip tone={LEVEL_TONE[e.level]}>{TYPE_NAMES[e.type] ?? e.type} · {LEVEL_NAMES[e.level]}</Chip><span className="text-muted">{Math.round(e.speed_kmh)} км/ч · score {e.score}</span>
                      {e.cluster && <Link to={`/events?focus=${e.cluster}`} className="ml-auto hover:underline">яма #{e.cluster}</Link>}</div>
                    <Wave wave={e.wave} />
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
        <Card>
          <CardTitle>Сводка</CardTitle>
          <KV rows={[['Устройство', <Link key="d" to={`/devices/${t.device_id}`} className="hover:underline">{t.device}</Link>], ['Дистанция', `${fmtNum(t.distance_km, 2)} км`], ['Режим', `${MODE_NAMES[t.mode] ?? t.mode} (${t.mode_conf})`], ['Алгоритм', t.algo_version || '—'],
            ['Окончание', t.end_reason || '—'], ['Сегментов ровности', t.segments.length], ['Тихих проездов', t.quiet_passes]]} />
          {Object.keys(t.summary ?? {}).length > 0 && <pre className="mt-3 max-h-48 overflow-auto rounded-xl bg-raised p-3 text-xs">{JSON.stringify(t.summary, null, 2)}</pre>}
        </Card>
      </div>
    </div>
  )
}
