import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { Button, Card, CardTitle, Chip, ErrorBox, Field, Input, KV, PageHeader, Pagination, Select, Spinner, Table } from '../components/ui'
import { api, type CarModel, type Device, type Page, type Vehicle } from '../lib/api'
import { useAuth } from '../lib/auth'
import { ago, fmtDateTime, fmtNum, MODE_NAMES } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'
import { TableSkeleton } from '../components/Loaders'

const ROLES: Record<string, string> = { driver: 'водитель', passenger: 'пассажир / такси', research: 'исследовательский логгер' }
const MOUNTS: Record<string, string> = { '': 'не указано', seat: 'на сиденье', cupholder: 'в подстаканнике', holder: 'в держателе' }

export default function Devices() {
  const nav = useNavigate()
  const [page, setPage] = useState(1)
  const [q, setQ] = useState('')
  const [role, setRole] = useState('')
  const [blocked, setBlocked] = useState('')
  useEffect(() => setPage(1), [q, role, blocked])
  const list = useGet<Page<Device & { trips: number }>>('/admin/devices', { page, size: 30, q: q.trim(), role, blocked })
  return (
    <div>
      <PageHeader title="Устройства" sub="Телефоны и логгеры: платформа, роль, машина, доверие, калибровка" />
      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Field label="Поиск"><Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="ник или модель телефона" /></Field>
        <Field label="Роль"><Select value={role} onChange={(e) => setRole(e.target.value)}><option value="">все</option>{Object.entries(ROLES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
        <Field label="Блокировка"><Select value={blocked} onChange={(e) => setBlocked(e.target.value)}><option value="">все</option><option value="1">заблокированные</option><option value="0">активные</option></Select></Field>
      </div>
      {list.isLoading && <TableSkeleton />}
      {list.error && <ErrorBox error={list.error} onRetry={() => list.refetch()} />}
      {list.data && (
        <>
          <Table rowKey={(r) => r.id} rows={list.data.items} empty="Устройств нет" onRow={(r) => nav(`/devices/${r.id}`)} cols={[
            { key: 'n', title: 'Ник', render: (r) => <span className="font-medium">{r.nickname || `device ${r.id}`}</span> },
            { key: 'p', title: 'Платформа', render: (r) => [r.platform, r.phone_model].filter(Boolean).join(' · ') || '—' },
            { key: 'r', title: 'Роль', render: (r) => ROLES[r.role] ?? r.role },
            { key: 'v', title: 'Машина', render: (r) => r.vehicle?.car_model ?? r.vehicle?.name ?? '—' },
            { key: 't', title: 'Доверие', render: (r) => <Chip tone={r.blocked ? 'crater' : r.trust >= 0.5 ? 'smooth' : 'warn'}>{r.blocked ? 'заблокирован' : r.trust.toFixed(2)}</Chip> },
            { key: 'tr', title: 'Поездок', align: 'right', render: (r) => r.trips as number },
            { key: 'l', title: 'Активность', render: (r) => ago(r.last_seen) },
          ]} />
          <Pagination page={list.data.page} size={list.data.size} total={list.data.total} onPage={setPage} />
        </>
      )}
    </div>
  )
}

export function DeviceCard() {
  const { id } = useParams()
  const { can } = useAuth()
  const q = useGet<Device>(`/admin/devices/${id}`)
  const models = useGet<{ items: CarModel[] }>('/admin/car-models')
  const [f, setF] = useState<Record<string, string | boolean>>({})
  const [vf, setVf] = useState<Record<string, string>>({})
  useEffect(() => { setF({}); setVf({}) }, [id])
  const saveDev = useSave((b: Record<string, unknown>) => api.patch<Device>(`/admin/devices/${id}/patch`, b), { ok: 'Устройство сохранено', invalidate: ['/admin/devices'], onDone: () => setF({}) })
  const d = q.data
  const veh = d?.vehicle
  const saveVeh = useSave((b: Record<string, unknown>) => api.patch<Vehicle>(`/admin/vehicles/${veh?.id}/patch`, b), { ok: 'Машина сохранена', invalidate: ['/admin/devices'], onDone: () => setVf({}) })
  if (q.isLoading) return <Spinner />
  if (q.error) return <ErrorBox error={q.error} onRetry={() => q.refetch()} />
  if (!d) return null
  const admin = can('admin')
  const dv = (k: keyof Device) => String(f[k] ?? d[k] ?? '')
  const vv = (k: keyof Vehicle) => vf[k] ?? String(veh?.[k] ?? '')
  const trips = Array.isArray(d.trips) ? d.trips : []
  const numOrNull = (s: string) => (s === '' ? null : Number(s))
  return (
    <div>
      <PageHeader title={d.nickname || `Устройство ${d.id}`} sub={[d.platform, d.phone_model, `v${d.app_version || '?'}`].filter(Boolean).join(' · ')}
        right={<Link to="/devices"><Button kind="ghost">← К списку</Button></Link>} />
      <div className="grid gap-4 xl:grid-cols-[420px_1fr]">
        <div className="flex flex-col gap-4">
          <Card>
            <CardTitle right={d.blocked ? <Chip tone="crater">заблокировано</Chip> : <Chip tone="smooth">активно</Chip>}>Устройство</CardTitle>
            <KV rows={[['Роль', ROLES[d.role] ?? d.role], ['Положение телефона', MOUNTS[d.mount] ?? d.mount], ['Язык', d.lang], ['Калибровка (gain)', `${d.calib_gain.toFixed(2)} · n=${d.calib_n}`], ['Доверие', d.trust.toFixed(2)],
              ['Событий', fmtNum(d.events_total)], ['Размечено', fmtNum(d.labels)], ['Создано', fmtDateTime(d.created)], ['Последняя активность', `${fmtDateTime(d.last_seen)} (${ago(d.last_seen)})`]]} />
            {admin && (
              <div className="mt-4 grid grid-cols-2 gap-3 rounded-2xl bg-raised p-4">
                <Field label="Роль"><Select value={dv('role')} onChange={(e) => setF({ ...f, role: e.target.value })}>{Object.entries(ROLES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
                <Field label="Положение"><Select value={dv('mount')} onChange={(e) => setF({ ...f, mount: e.target.value })}>{Object.entries(MOUNTS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
                <Field label="Доверие 0–1"><Input type="number" step="0.05" min={0} max={1} value={dv('trust')} onChange={(e) => setF({ ...f, trust: e.target.value })} /></Field>
                <Field label="Ник"><Input value={dv('nickname')} onChange={(e) => setF({ ...f, nickname: e.target.value })} /></Field>
                <div className="col-span-2 flex flex-wrap gap-2">
                  <Button kind="primary" disabled={!Object.keys(f).length || saveDev.isPending} onClick={() => saveDev.mutate({ ...f, trust: f.trust === undefined ? undefined : Number(f.trust) })}>Сохранить</Button>
                  <Button kind={d.blocked ? 'secondary' : 'danger'} onClick={() => saveDev.mutate({ blocked: !d.blocked })}>{d.blocked ? 'Разблокировать' : 'Заблокировать'}</Button>
                  <Button onClick={() => saveDev.mutate({ reset_calibration: true })}>Сбросить калибровку</Button>
                </div>
              </div>
            )}
          </Card>
          <Card>
            <CardTitle>Поездки</CardTitle>
            {trips.length === 0 ? <p className="text-sm text-muted">Поездок нет</p> : (
              <ul className="flex flex-col gap-2">
                {trips.map((t) => <li key={t.id}><Link to={`/trips/${t.id}`} className="flex items-center gap-3 rounded-xl bg-raised px-3 py-2.5 text-sm hover:brightness-110"><span>{fmtDateTime(t.started_at)}</span><span className="text-muted">{fmtNum(t.distance_km, 1)} км · {t.events} ям · {MODE_NAMES[t.mode] ?? t.mode}</span></Link></li>)}
              </ul>
            )}
          </Card>
        </div>
        <Card>
          <CardTitle right={veh?.suspension_cls ? <Chip tone="info">подвеска {veh.suspension_cls}</Chip> : undefined}>Машина и подвеска</CardTitle>
          {!veh ? <p className="text-sm text-muted">Профиль машины не создан: водитель ещё не указал машину в приложении.</p> : (
            <div className="flex flex-col gap-4">
              <div className="grid gap-3 md:grid-cols-2">
                <Field label="Модель">
                  <Select disabled={!admin} value={vf.car_model_id ?? String(veh.car_model_id ?? '')} onChange={(e) => setVf({ ...vf, car_model_id: e.target.value })}>
                    <option value="">не выбрана</option>{models.data?.items.map((m) => <option key={m.id} value={m.id}>{m.brand} {m.model}{m.specs_verified ? ' ✓' : ''}</option>)}
                  </Select>
                </Field>
                <Field label="Название (у владельца)"><Input disabled={!admin} value={vv('name')} onChange={(e) => setVf({ ...vf, name: e.target.value })} /></Field>
                <Field label="Год"><Input disabled={!admin} type="number" value={vv('year')} onChange={(e) => setVf({ ...vf, year: e.target.value })} /></Field>
                <Field label="Колёсная база, мм" hint={`в расчётах: ${veh.wheelbase_effective_m} м`}><Input disabled={!admin} type="number" value={vv('wheelbase_mm')} onChange={(e) => setVf({ ...vf, wheelbase_mm: e.target.value })} /></Field>
                <Field label="Диск, дюймы"><Input disabled={!admin} type="number" value={vv('rim_inch')} onChange={(e) => setVf({ ...vf, rim_inch: e.target.value })} /></Field>
                <Field label="Давление в шинах, бар"><Input disabled={!admin} type="number" step="0.1" value={vv('tire_pressure_bar')} onChange={(e) => setVf({ ...vf, tire_pressure_bar: e.target.value })} /></Field>
                <Field label="Слова владельца о подвеске"><Input disabled={!admin} value={vv('suspension_note')} onChange={(e) => setVf({ ...vf, suspension_note: e.target.value })} /></Field>
                <Field label="Класс подвески (вручную)"><Select disabled={!admin} value={vv('suspension_cls')} onChange={(e) => setVf({ ...vf, suspension_cls: e.target.value })}><option value="">не задан</option>{['S1', 'S2', 'S3', 'S4', 'S5'].map((s) => <option key={s}>{s}</option>)}</Select></Field>
              </div>
              {admin && <div><Button kind="primary" disabled={!Object.keys(vf).length || saveVeh.isPending} onClick={() => saveVeh.mutate({
                ...vf, car_model_id: vf.car_model_id === undefined ? undefined : numOrNull(vf.car_model_id), year: vf.year === undefined ? undefined : numOrNull(vf.year), wheelbase_mm: vf.wheelbase_mm === undefined ? undefined : numOrNull(vf.wheelbase_mm),
                rim_inch: vf.rim_inch === undefined ? undefined : numOrNull(vf.rim_inch), tire_pressure_bar: vf.tire_pressure_bar === undefined ? undefined : numOrNull(vf.tire_pressure_bar) })}>Сохранить машину</Button></div>}
              <KV rows={[['Индекс мягкости (0–100)', veh.softness_score == null ? 'нет данных' : `${veh.softness_score} · доверие ${veh.softness_conf}`], ['Пробег по приложению', `${fmtNum(veh.km_total, 1)} км`],
                ['f кузова / ζ (резервный показатель)', veh.f_body_median == null ? '—' : `${veh.f_body_median.toFixed(2)} Гц / ${veh.zeta_median?.toFixed(3)}`], ['Догадка о модели', veh.model_guess ? `${veh.model_guess} (${veh.model_guess_conf.toFixed(2)})` : 'нет (мало машин с известной моделью)']]} />
              <p className="text-xs text-muted">Абсолютные f кузова и ζ с одного телефона ненадёжны (резонанс телефона); основной индекс — относительный, считается по сегментам с ≥3 машинами.</p>
            </div>
          )}
        </Card>
      </div>
    </div>
  )
}
