import { useState } from 'react'
import { Link } from 'react-router-dom'
import { BarChart, Donut } from '../components/Charts'
import { Icon } from '../components/icons'
import { Card, CardTitle, Chip, ErrorBox, Kpi, PageHeader, Segmented, Spinner, Table } from '../components/ui'
import type { Overview as Ov } from '../lib/api'
import { ago, fmtDate, fmtNum, LEVEL_NAMES, LEVEL_TONE, ROUGH_COLORS, STATUS_NAMES, STATUS_TONE, TYPE_NAMES } from '../lib/format'
import { useGet } from '../lib/hooks'

/** Изменение за последнюю неделю периода относительно предыдущей, в процентах (null — не с чем сравнить). */
function weekDelta(v: number[]): number | null {
  if (v.length < 14) return null
  const last = v.slice(-7).reduce((a, b) => a + b, 0), prev = v.slice(-14, -7).reduce((a, b) => a + b, 0)
  return prev > 0 ? Math.round(((last - prev) / prev) * 100) : null
}

export default function Overview() {
  const [days, setDays] = useState<'7' | '30' | '90'>('30')
  const q = useGet<Ov>('/admin/overview', { days })
  const d = q.data
  const col = (k: 'trips' | 'km' | 'events' | 'clusters') => d?.series.map((s) => s[k]) ?? []
  const scored = d ? Object.values(d.classes ?? {}).reduce((a, b) => a + b, 0) : 0
  return (
    <div>
      <PageHeader
        title="Обзор"
        sub={`Сводка по городу за последние ${days} дн.`}
        right={<Segmented label="Период" value={days} onChange={setDays} options={[{ value: '7', label: '7 дн' }, { value: '30', label: '30 дн' }, { value: '90', label: '90 дн' }]} />}
      />
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      {d && (
        <div className="flex flex-col gap-4">
          <div className="flex flex-wrap gap-4">
            <Kpi label={`Поездок · ${d.days} дн`} value={fmtNum(d.kpi.trips)} sub={`${fmtNum(d.kpi.events)} событий`} icon="wheel" trend={col('trips')} delta={weekDelta(col('trips'))} />
            <Kpi label="Километров" value={fmtNum(d.kpi.km, 1)} sub="по всем устройствам" tone="info" icon="road" trend={col('km')} delta={weekDelta(col('km'))} />
            <Kpi label="Подтверждённых ям" value={fmtNum(d.kpi.confirmed)} sub={`заделано ${fmtNum(d.kpi.fixed)} · кандидатов ${fmtNum(d.kpi.candidates)}`} tone="crater" icon="pulse" trend={col('clusters')} delta={weekDelta(col('clusters'))} />
            <Kpi label="Активных устройств" value={fmtNum(d.kpi.devices_active)} sub={`всего ${fmtNum(d.kpi.devices_total)}`} tone="smooth" icon="phone" />
            <Kpi label="Охват дорог" value={d.segments_total ? `${Math.round((scored / d.segments_total) * 100)}%` : '—'} sub={`${fmtNum(scored)} из ${fmtNum(d.segments_total)} сегментов оценены`} tone="warn" icon="layers" />
          </div>
          <div className="grid gap-4 xl:grid-cols-[1fr_380px]">
            <Card>
              <CardTitle right={<Chip tone="amber">события по дням</Chip>}>Активность по дням</CardTitle>
              <BarChart data={d.series.map((s) => ({ label: fmtDate(s.day), value: s.events, sub: `${s.trips} поездок · ${s.km} км · новых ям ${s.clusters}` }))} height={220} />
            </Card>
            <Card>
              <CardTitle>Классы ровности</CardTitle>
              {scored ? <Donut slices={Object.entries(d.classes ?? {}).map(([k, v]) => ({ label: `Класс ${k}`, value: v, color: ROUGH_COLORS[k] }))} /> : <div className="py-8 text-sm text-muted">Оценённых участков пока нет</div>}
              <p className="mt-3 text-xs text-muted">Оценено {fmtNum(scored)} из {fmtNum(d.segments_total)} сегментов дорожной сети.</p>
            </Card>
          </div>
          <div className="grid gap-4 lg:grid-cols-[320px_minmax(0,1fr)] 2xl:grid-cols-[320px_minmax(0,1fr)_280px]">
            <Card>
              <CardTitle>Очередь работы</CardTitle>
              <ul className="flex flex-col gap-2 text-sm">
                {[
                  ['Кандидаты без подтверждения', d.queues.candidates_single, '/events?status=candidate', 'text-amber-text'],
                  ['Вопросы водителям', d.queues.questions_open, '/questions', 'text-info'],
                  ['Жалобы к отправке', d.queues.complaints_to_file, '/complaints', 'text-crater'],
                ].map(([t, n, to, c]) => (
                  <li key={String(t)}><Link to={String(to)} className="flex items-center gap-3 rounded-xl bg-raised px-3.5 py-3 hover:brightness-110"><span>{t}</span><b className={`ml-auto rounded-full bg-surface px-2.5 py-0.5 ${c}`}>{n}</b></Link></li>
                ))}
                <li className="flex items-center gap-3 px-3.5 py-2 text-muted"><span>Размечено событий</span><b className="ml-auto text-ink">{d.kpi.labels}</b></li>
              </ul>
            </Card>
            <div>
              <h2 className="mb-3 text-base font-semibold">Последние ямы</h2>
              <Table
                rowKey={(r) => r.id}
                rows={d.recent}
                empty="Ям пока нет"
                cols={[
                  { key: 't', title: 'Время', render: (r) => ago(r.last_hit) },
                  { key: 's', title: 'Улица', render: (r) => <Link to={`/events?focus=${r.id}`} className="font-medium hover:underline">{r.street ?? `${r.lat.toFixed(4)}, ${r.lon.toFixed(4)}`}</Link> },
                  { key: 'ty', title: 'Тип', render: (r) => TYPE_NAMES[r.type] ?? r.type },
                  { key: 'l', title: 'Уровень', render: (r) => <Chip tone={LEVEL_TONE[r.level]}>{LEVEL_NAMES[r.level]}</Chip> },
                  { key: 'st', title: 'Статус', render: (r) => <Chip tone={STATUS_TONE[r.status]}>{STATUS_NAMES[r.status]}</Chip> },
                  { key: 'p', title: 'Устр.', align: 'right', render: (r) => r.devices },
                ]}
              />
            </div>
            <Card className="lg:col-span-2 2xl:col-span-1">
              <CardTitle>Мозг сегодня</CardTitle>
              <div className="grid place-items-center rounded-2xl bg-raised py-5 text-amber"><Icon name="brain" size={64} /></div>
              <div className="mt-3 text-xs text-muted">Версия {d.brain?.version ?? '—'} · метка F1 {d.brain?.f1 != null ? d.brain.f1.toFixed(2) : '—'}</div>
              <div className="mt-1 text-sm">Размечено событий: <b>{d.brain?.labels ?? d.kpi.labels}</b></div>
              <Link to="/learning" className="mt-3 inline-block text-sm font-semibold text-amber-text hover:underline">Эволюция модели →</Link>
            </Card>
          </div>
        </div>
      )}
    </div>
  )
}
