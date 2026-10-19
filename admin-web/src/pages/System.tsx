import { Card, CardTitle, ErrorBox, KV, PageHeader, Spinner, Table } from '../components/ui'
import { fmtDateTime, fmtNum } from '../lib/format'
import { useGet } from '../lib/hooks'

interface Resp {
  now: string; algo: string; active_version: string | null; uptime_note: string
  services: { name: string; state: 'ok' | 'slow' | 'down' | 'off'; detail: string }[]
  counts: Record<string, number>
  log: { id: number; at: string; user: string | null; action: string; target: string }[]
}
const STATE: Record<string, [string, string]> = { ok: ['работает', 'bg-smooth'], slow: ['внимание', 'bg-warn'], down: ['не отвечает', 'bg-crater'], off: ['выключено', 'bg-muted'] }
const COUNTS: Record<string, string> = { trips: 'Поездок', events: 'Событий', clusters: 'Ям (кластеров)', segments: 'Сегментов сети', devices: 'Устройств', marks: 'Ответов водителей', complaints: 'Жалоб', uploads: 'Записей CSV' }

export default function System() {
  const q = useGet<Resp>('/admin/system', undefined, { refetchMs: 30_000 })
  const d = q.data
  return (
    <div>
      <PageHeader title="Система" sub="Состояние сервисов, объёмы данных и журнал действий сотрудников" />
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      {d && (
        <div className="flex flex-col gap-4">
          <div className="grid gap-4 xl:grid-cols-2">
            <Card>
              <CardTitle>Сервисы</CardTitle>
              <ul className="divide-y divide-line">
                {d.services.map((s) => (
                  <li key={s.name} className="flex items-center gap-3 py-3 text-sm">
                    <span className={`h-2.5 w-2.5 rounded-full ${STATE[s.state][1]}`} aria-hidden /><span className="font-medium">{s.name}</span>
                    <span className="ml-auto text-right text-muted">{STATE[s.state][0]} · {s.detail.replace(/\d{4}-\d\d-\d\dT[\d:.+]+/, (m) => fmtDateTime(m))}</span>
                  </li>
                ))}
              </ul>
              <p className="mt-3 text-xs text-muted">{d.uptime_note}</p>
            </Card>
            <Card>
              <CardTitle>Данные в системе</CardTitle>
              <KV rows={Object.entries(d.counts).map(([k, v]) => [COUNTS[k] ?? k, fmtNum(v)] as [string, string])} />
            </Card>
          </div>
          <div>
            <h2 className="mb-3 text-base font-semibold">Журнал действий</h2>
            <Table rowKey={(r) => r.id} rows={d.log} empty="Действий ещё не было" cols={[
              { key: 't', title: 'Когда', render: (r) => fmtDateTime(r.at) },
              { key: 'u', title: 'Кто', render: (r) => r.user ?? '—' },
              { key: 'a', title: 'Действие', render: (r) => <code className="text-xs">{r.action}</code> },
              { key: 'o', title: 'Объект', render: (r) => r.target || '—' },
            ]} />
          </div>
        </div>
      )}
    </div>
  )
}
