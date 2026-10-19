import { Button, Card, CardTitle, Chip, Empty, ErrorBox, KV, Kpi, PageHeader, Spinner, Table, useToast } from '../components/ui'
import { BarChart, LineChart } from '../components/Charts'
import { api } from '../lib/api'
import { useAuth } from '../lib/auth'
import { fmtDate, fmtDateTime, fmtNum } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'
import CalibrationTab from './Calibration'

interface Split { n: number; accuracy: number }
interface Evo {
  labeled: number; events: number; coverage: number
  eval: { n: number; guess?: { top1: number; top3: number; logloss: number }; majority?: { label: string; acc: number }; road_vs_not?: number; level?: { n: number; exact: number | null; within_one: number | null }; calibration?: { mean_confidence: number; accuracy: number }; by_speed?: Record<string, { n: number; top1: number }>; by_score?: Record<string, { n: number; top1: number }>; by_label?: Record<string, { n: number; top1: number; mean_p: number }> }
  classes: { key: string; name: string; n: number }[]
  device_guess: { n: number; top1: number; top3: number; voice_share: number; mean_confidence: number } | null
  intelligence: { score: number; parts: Record<string, number>; weights: Record<string, number>; formula: string }
  series: { day: string; labeled: number; accuracy: number; cumulative: number }[]
  by_road_class: Record<string, Split>; by_vehicle: Record<string, Split>; by_source: Record<string, Split>
  confusion: { truth: string; truth_name: string; predicted: Record<string, number> }[]
  snapshots: { day: string; events: number; labels: number; km: number; devices: number }[]
  versions: { id: number; version: string; kind: string; active: boolean; created: string; f1: number | null; rules_f1: number | null; logloss: number | null }[]
  runs: { id: number; at: string; kind: string; n: number; log: string }[]
  marks_per_day: { day: string; n: number }[]
}
const PART_NAMES: Record<string, string> = { data: 'Объём разметки', lift: 'Выигрыш у «самого частого»', calibration: 'Честность уверенности', coverage: 'Охват типов' }
const pct = (v: number | null | undefined) => (v == null ? '—' : `${Math.round(v * 100)}%`)

function SplitCard({ title, data }: { title: string; data: Record<string, Split> }) {
  const rows = Object.entries(data)
  return (
    <Card>
      <CardTitle>{title}</CardTitle>
      {!rows.length ? <p className="text-sm text-muted">Нет данных</p> : (
        <ul className="flex flex-col gap-2.5 text-sm">
          {rows.slice(0, 8).map(([k, v]) => (
            <li key={k}>
              <div className="flex gap-2"><span className="truncate">{k}</span><span className="ml-auto text-muted">{v.n} · {pct(v.accuracy)}</span></div>
              <div className="mt-1 h-1.5 rounded-full bg-raised"><div className="h-full rounded-full bg-amber" style={{ width: `${Math.round(v.accuracy * 100)}%` }} /></div>
            </li>
          ))}
        </ul>
      )}
    </Card>
  )
}

export default function Learning() {
  const { can } = useAuth()
  const toast = useToast()
  const q = useGet<Evo>('/admin/brain/evolution')
  const train = useSave(() => api.post<{ log: string }>('/admin/brain/train'), { invalidate: ['/admin/brain'], onDone: (r) => toast(r.log, 'ok') })
  const d = q.data
  const g = d?.eval.guess
  return (
    <div>
      <PageHeader title="Обучение и эволюция" sub="Насколько модель умнеет: оценка на отложенных поездках, честная — не по тем данным, на которых она училась"
        right={can('admin') ? <Button kind="primary" loading={train.isPending} onClick={() => train.mutate(undefined)}>Запустить обучение</Button> : undefined} />
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      {d && (
        <div className="flex flex-col gap-4">
          <div className="flex flex-wrap gap-4">
            <Kpi label="Индекс ума" value={`${d.intelligence.score}/100`} sub="из четырёх частей, формула ниже" icon="brain" trend={d.series.map((s) => s.cumulative)} />
            <Kpi label="Точность догадки (топ-1)" value={pct(g?.top1)} sub={d.eval.majority ? `«всегда самое частое»: ${pct(d.eval.majority.acc)}` : 'мало разметки'} tone="smooth" icon="check" />
            <Kpi label="Верный ответ в тройке" value={pct(g?.top3)} sub={d.eval.level?.within_one != null ? `уровень ±1: ${pct(d.eval.level.within_one)}` : undefined} tone="info" icon="pulse" />
            <Kpi label="Размечено событий" value={fmtNum(d.labeled)} sub={`из ${fmtNum(d.events)} · охват ${pct(d.coverage)}`} tone="warn" icon="db" />
          </div>
          {d.eval.n < 20 && <Empty>Размеченных событий пока мало ({d.eval.n}) — оценка ненадёжна. Модель растёт от ответов водителей на вопрос «что это было?» и от разметки в «Вопросах».</Empty>}
          <div className="grid gap-4 xl:grid-cols-[1fr_1fr]">
            <Card>
              <CardTitle>Из чего сложен индекс ума</CardTitle>
              <ul className="flex flex-col gap-3 text-sm">
                {Object.entries(d.intelligence.parts).map(([k, v]) => (
                  <li key={k}>
                    <div className="flex"><span>{PART_NAMES[k] ?? k}</span><span className="ml-auto text-muted">вес {Math.round((d.intelligence.weights[k] ?? 0) * 100)}% · {pct(v)}</span></div>
                    <div className="mt-1 h-2 rounded-full bg-raised"><div className="h-full rounded-full bg-amber" style={{ width: `${Math.round(v * 100)}%` }} /></div>
                  </li>
                ))}
              </ul>
              <p className="mt-3 text-xs text-muted">{d.intelligence.formula}</p>
            </Card>
            <Card>
              <CardTitle>Точность по дням разметки</CardTitle>
              {d.series.length ? <LineChart labels={d.series.map((s) => fmtDate(s.day))} series={[{ name: 'за день', color: 'var(--info)', points: d.series.map((s) => s.accuracy) }, { name: 'накопленная', color: 'var(--amber)', points: d.series.map((s) => s.cumulative) }]} /> : <p className="text-sm text-muted">Догадки на момент приёма пока не сравнивались с метками.</p>}
              <div className="mt-2 flex gap-2"><Chip tone="info">за день</Chip><Chip tone="amber">накопленная</Chip></div>
            </Card>
          </div>
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            <SplitCard title="По классам дороги" data={d.by_road_class} />
            <SplitCard title="По машинам" data={d.by_vehicle} />
            <SplitCard title="По источнику метки" data={d.by_source} />
            <Card>
              <CardTitle>По скорости, км/ч</CardTitle>
              {d.eval.by_speed && Object.keys(d.eval.by_speed).length ? <BarChart height={150} data={Object.entries(d.eval.by_speed).map(([k, v]) => ({ label: k, value: Math.round(v.top1 * 100), sub: `${v.n} событий` }))} /> : <p className="text-sm text-muted">Нет данных</p>}
            </Card>
          </div>
          <div className="grid gap-4 xl:grid-cols-[1.3fr_1fr]">
            <Card>
              <CardTitle>Матрица ошибок: что было → что сказала модель</CardTitle>
              {d.confusion.length ? (
                <table className="w-full text-sm"><tbody>
                  {d.confusion.map((r) => (
                    <tr key={r.truth} className="border-t border-line"><td className="py-2 pr-3 font-medium">{r.truth_name}</td>
                      <td className="py-2"><div className="flex flex-wrap gap-1.5">{Object.entries(r.predicted).map(([p, n]) => <span key={p} className={`rounded-lg px-2 py-0.5 text-xs font-semibold ${p === r.truth ? 'bg-smooth/20 text-smooth' : 'bg-crater/15 text-crater'}`}>{p} × {n}</span>)}</div></td></tr>
                  ))}
                </tbody></table>
              ) : <p className="text-sm text-muted">Нет разметки с сохранённой догадкой</p>}
            </Card>
            <Card>
              <CardTitle>Размечено по типам</CardTitle>
              <ul className="flex flex-col gap-1.5 text-sm">{d.classes.slice(0, 10).map((c) => <li key={c.key} className="flex"><span>{c.name}</span><b className="ml-auto">{c.n}</b></li>)}</ul>
            </Card>
          </div>
          {d.device_guess && (
            <Card>
              <CardTitle>Догадки на телефонах (по ответам водителей)</CardTitle>
              <KV rows={[['Ответов', d.device_guess.n], ['Верно (топ-1)', pct(d.device_guess.top1)], ['В тройке', pct(d.device_guess.top3)], ['Голосом', pct(d.device_guess.voice_share)], ['Средняя уверенность', pct(d.device_guess.mean_confidence)]]} />
            </Card>
          )}
          <div className="grid gap-4 xl:grid-cols-2">
            <div>
              <h2 className="mb-3 text-base font-semibold">Версии модели</h2>
              <Table rowKey={(r) => r.id} rows={d.versions} empty="Версий нет" cols={[
                { key: 'v', title: 'Версия', render: (r) => <b>{r.version}</b> },
                { key: 'k', title: 'Вид', render: (r) => r.kind },
                { key: 'f', title: 'F1', render: (r) => (r.f1 == null ? '—' : r.f1.toFixed(2)) },
                { key: 'a', title: '', render: (r) => (r.active ? <Chip tone="smooth">активна</Chip> : '') },
                { key: 'c', title: 'Создана', render: (r) => fmtDate(r.created) },
              ]} />
            </div>
            <div>
              <h2 className="mb-3 text-base font-semibold">Запуски обучения</h2>
              <Table rowKey={(r) => r.id} rows={d.runs} empty="Запусков ещё не было" cols={[
                { key: 't', title: 'Когда', render: (r) => fmtDateTime(r.at) },
                { key: 'k', title: 'Вид', render: (r) => r.kind },
                { key: 'n', title: 'Меток', align: 'right', render: (r) => r.n },
                { key: 'l', title: 'Итог', render: (r) => <span className="text-xs text-muted">{r.log.slice(0, 90)}</span> },
              ]} />
            </div>
          </div>
          <h2 className="mt-2 text-base font-semibold">Калибровка порогов</h2>
          <CalibrationTab />
        </div>
      )}
    </div>
  )
}
