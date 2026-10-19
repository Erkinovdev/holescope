import { useState } from 'react'
import { ErrorBox, Kpi, PageHeader, Segmented, Spinner } from '../components/ui'
import { fmtNum } from '../lib/format'
import { useGet } from '../lib/hooks'

interface Resp { days: number; found: number; fixed: number; complaints: number; drivers: number; km: number }

export default function Reports() {
  const [days, setDays] = useState<'7' | '30' | '90'>('7')
  const q = useGet<Resp>('/reports/weekly', { days })
  const d = q.data
  return (
    <div>
      <PageHeader title="Отчёты" sub="Итоги периода — то, что публикуется в приложении и для города"
        right={<Segmented label="Период" value={days} onChange={setDays} options={[{ value: '7', label: '7 дн' }, { value: '30', label: '30 дн' }, { value: '90', label: '90 дн' }]} />} />
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      {d && (
        <div className="flex flex-wrap gap-4">
          <Kpi label="Найдено ям" value={fmtNum(d.found)} icon="pulse" tone="crater" />
          <Kpi label="Заделано" value={fmtNum(d.fixed)} icon="check" tone="smooth" />
          <Kpi label="Жалоб отправлено" value={fmtNum(d.complaints)} icon="flag" tone="warn" />
          <Kpi label="Водителей" value={fmtNum(d.drivers)} icon="phone" tone="info" />
          <Kpi label="Километров" value={fmtNum(d.km, 1)} icon="road" />
        </div>
      )}
    </div>
  )
}
