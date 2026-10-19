import { Kpi, PageHeader, Spinner, ErrorBox, Table } from '../components/ui'
import { useGet } from '../lib/hooks'

interface Resp { days: number; city_score: number | null; districts: { code: string; name: string; score: number; segments: number }[]; note: string }

export default function Districts() {
  const q = useGet<Resp>('/rankings/districts', { days: 90 })
  const d = q.data
  return (
    <div>
      <PageHeader title="Районы" sub="Качество дорог по районам за 90 дней, 0–100" />
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      {d && (
        <div className="flex flex-col gap-4">
          <div className="flex flex-wrap gap-4">
            <Kpi label="Оценка города" value={d.city_score ?? '—'} sub="среднее по покрытым сегментам" icon="layers" tone="smooth" />
            <Kpi label="Районов с оценкой" value={d.districts.length} sub="достаточно покрытых сегментов" icon="map" tone="info" />
          </div>
          <Table rowKey={(r) => r.code} rows={d.districts} empty="Пока ни в одном районе не хватает покрытых сегментов" cols={[
            { key: 'n', title: 'Район', render: (r) => <b>{r.name}</b> },
            { key: 's', title: 'Оценка', render: (r) => (
              <div className="flex items-center gap-3"><div className="h-2 w-40 rounded-full bg-raised"><div className="h-full rounded-full" style={{ width: `${r.score}%`, background: r.score >= 70 ? 'var(--smooth)' : r.score >= 45 ? 'var(--amber)' : 'var(--crater)' }} /></div><b>{r.score}</b></div>
            ) },
            { key: 'g', title: 'Сегментов', align: 'right', render: (r) => r.segments },
          ]} />
          <p className="text-xs text-muted">{d.note}</p>
        </div>
      )}
    </div>
  )
}
