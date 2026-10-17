import { useState } from 'react'
import { Link } from 'react-router-dom'
import { BarChart } from '../components/Charts'
import { Card, CardTitle, Chip, ErrorBox, Kpi, PageHeader, Segmented, Spinner, Table } from '../components/ui'
import type { Overview as Ov } from '../lib/api'
import { ago, fmtDate, fmtNum, LEVEL_NAMES, LEVEL_TONE, STATUS_NAMES, STATUS_TONE, TYPE_NAMES } from '../lib/format'
import { useGet } from '../lib/hooks'

export default function Overview() {
  const [days, setDays] = useState<'7' | '30' | '90'>('30')
  const q = useGet<Ov>('/admin/overview', { days })
  const d = q.data
  return (
    <div>
      <PageHeader
        title="Обзор"
        sub="Состояние данных и очереди работы"
        right={<Segmented label="Период" value={days} onChange={setDays} options={[{ value: '7', label: '7 дн' }, { value: '30', label: '30 дн' }, { value: '90', label: '90 дн' }]} />}
      />
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      {d && (
        <div className="flex flex-col gap-4">
          <div className="flex flex-wrap gap-4">
            <Kpi label={`Поездок за ${d.days} дн`} value={fmtNum(d.kpi.trips)} sub={`${fmtNum(d.kpi.events)} событий`} />
            <Kpi label="Километров" value={fmtNum(d.kpi.km, 1)} sub="по всем устройствам" tone="info" />
            <Kpi label="Подтверждённых ям" value={fmtNum(d.kpi.confirmed)} sub={`заделано: ${fmtNum(d.kpi.fixed)} · кандидатов: ${fmtNum(d.kpi.candidates)}`} tone="crater" />
            <Kpi label="Активных устройств" value={fmtNum(d.kpi.devices_active)} sub={`всего ${fmtNum(d.kpi.devices_total)}`} tone="smooth" />
          </div>
          <div className="grid gap-4 lg:grid-cols-[1fr_360px]">
            <Card>
              <CardTitle right={<Chip tone="amber">события по дням</Chip>}>Активность</CardTitle>
              <BarChart data={d.series.map((s) => ({ label: fmtDate(s.day), value: s.events, sub: `${s.trips} поездок · ${s.km} км · новых ям ${s.clusters}` }))} />
            </Card>
            <Card>
              <CardTitle>Очередь работы</CardTitle>
              <ul className="divide-y divide-line text-sm">
                <li className="flex items-center gap-3 py-3"><span>Кандидаты с одним проездом</span><Link className="ml-auto font-bold text-amber-text" to="/events?status=candidate">{d.queues.candidates_single}</Link></li>
                <li className="flex items-center gap-3 py-3"><span>Вопросы водителям без ответа</span><Link className="ml-auto font-bold text-amber-text" to="/brain">{d.queues.questions_open}</Link></li>
                <li className="flex items-center gap-3 py-3"><span>Жалобы без номера обращения</span><Link className="ml-auto font-bold text-amber-text" to="/complaints">{d.queues.complaints_to_file}</Link></li>
                <li className="flex items-center gap-3 py-3"><span>Размечено событий</span><b className="ml-auto">{d.kpi.labels}</b></li>
              </ul>
            </Card>
          </div>
          <h2 className="mt-2 text-base font-semibold">Последние ямы</h2>
          <Table
            rowKey={(r) => r.id}
            rows={d.recent}
            empty="Ям пока нет"
            cols={[
              { key: 't', title: 'Обновлена', render: (r) => ago(r.last_hit) },
              { key: 's', title: 'Улица', render: (r) => <Link to={`/events?focus=${r.id}`} className="font-medium hover:underline">{r.street ?? `${r.lat.toFixed(4)}, ${r.lon.toFixed(4)}`}</Link> },
              { key: 'ty', title: 'Тип', render: (r) => TYPE_NAMES[r.type] ?? r.type },
              { key: 'l', title: 'Уровень', render: (r) => <Chip tone={LEVEL_TONE[r.level]}>{LEVEL_NAMES[r.level]}</Chip> },
              { key: 'st', title: 'Статус', render: (r) => <Chip tone={STATUS_TONE[r.status]}>{STATUS_NAMES[r.status]}</Chip> },
              { key: 'p', title: 'Устройств', align: 'right', render: (r) => r.devices },
            ]}
          />
        </div>
      )}
    </div>
  )
}
