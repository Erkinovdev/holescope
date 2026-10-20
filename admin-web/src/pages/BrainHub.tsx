import { lazy, Suspense, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { LineChart } from '../components/Charts'
import { Button, Card, CardTitle, Chip, ErrorBox, Kpi, PageHeader, Spinner, type Tone, cx } from '../components/ui'
import { fmtNum } from '../lib/format'
import { useGet } from '../lib/hooks'
import Learning from './Learning'
import { GraphTab, ParamsTab, QueueTab, ReadinessCard, TimelineTab, UploadsTab } from './Brain'

const DigitalBrain = lazy(() => import('../components/DigitalBrain'))

interface ModelInfo { key: string; name: string; sub: string; color: string; tab: Tab; version: string; about: string; stats: { label: string; value: string | number }[] }
interface Overview {
  models: ModelInfo[]
  iq: { score: number; parts: Record<string, number>; formula: string } | null
  activity: { events_24h: number; trips_24h: number; labels_7d: number; questions_open: number; events_total: number; labels_total: number; trips_total: number; clusters_total: number; elements: number; quality: number }
}
interface Experiments {
  labeled: number; kinds: Record<string, number>
  floor_sweep: { floor: number; events_kept: number | null; noise_removed: number | null; elements_kept: number | null; quality_kept: number | null }[]
  learning_curve: { labels: number; top1: number; top3: number; logloss: number }[]
  lane: Record<string, number>
}

type Tab = 'brain' | 'learning' | 'experiments' | 'questions' | 'memory' | 'algo' | 'graph' | 'timeline'
const TABS: { value: Tab; label: string }[] = [
  { value: 'brain', label: 'Нейросеть' }, { value: 'learning', label: 'Обучение' }, { value: 'experiments', label: 'Эксперименты' }, { value: 'questions', label: 'Вопросы' },
  { value: 'memory', label: 'Память · CSV' }, { value: 'algo', label: 'Алгоритм' }, { value: 'graph', label: 'Граф памяти' }, { value: 'timeline', label: 'Версии' },
]
const TONE: Record<string, Tone> = { '#ffb020': 'amber', '#4da3ff': 'info', '#3ecf8e': 'smooth', '#ff5d5d': 'crater' }
const pct = (v: number | null) => (v == null ? '—' : `${Math.round(v * 100)}%`)

export default function BrainHub() {
  const [sp, setSp] = useSearchParams()
  const tab = (TABS.find((t) => t.value === sp.get('tab'))?.value ?? 'brain') as Tab
  const go = (t: Tab) => setSp(t === 'brain' ? {} : { tab: t })
  return (
    <div>
      <PageHeader title="Мозг Holescope" sub="Единая система: шесть моделей, обучение, вопросы, память и алгоритм" />
      <div role="tablist" aria-label="Разделы мозга" className="mb-5 flex flex-wrap gap-1.5 rounded-2xl border border-line bg-surface p-1.5">
        {TABS.map((t) => (
          <button key={t.value} role="tab" aria-selected={tab === t.value} onClick={() => go(t.value)}
            className={cx('rounded-xl px-4 py-2 text-sm font-semibold transition', tab === t.value ? 'bg-amber text-inverse' : 'text-ink/80 hover:bg-raised')}>{t.label}</button>
        ))}
      </div>
      {tab === 'brain' && <BrainTab go={go} />}
      {tab === 'learning' && <Learning embedded />}
      {tab === 'experiments' && <ExperimentsTab />}
      {tab === 'questions' && <QueueTab />}
      {tab === 'memory' && <UploadsTab />}
      {tab === 'algo' && <ParamsTab />}
      {tab === 'graph' && <GraphTab />}
      {tab === 'timeline' && <><ReadinessCard /><TimelineTab /></>}
    </div>
  )
}

// ───────────────────────── Нейросеть ─────────────────────────
function BrainTab({ go }: { go: (t: Tab) => void }) {
  const q = useGet<Overview>('/admin/brain/models', undefined, { refetchMs: 30_000 })
  const [sel, setSel] = useState<string>('nazar')
  const m = q.data?.models.find((x) => x.key === sel)
  const a = q.data?.activity
  // активность 0..1 по событиям за сутки: чем больше обрабатывается, тем быстрее бежит волна по мозгу
  const activity = a ? Math.min(1, 0.25 + a.events_24h / 120) : 0.3
  return (
    <div className="flex flex-col gap-5">
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      <div className="grid gap-4 xl:grid-cols-[1fr_400px]">
        <Card pad={false} className="relative h-[640px] overflow-hidden" >
          <div className="pointer-events-none absolute inset-0" style={{ background: 'radial-gradient(ellipse 60% 55% at 50% 48%, color-mix(in srgb, var(--amber) 14%, transparent), transparent 70%)' }} />
          <Suspense fallback={<div className="grid h-full place-items-center"><Spinner label="Собираем мозг…" /></div>}>
            <DigitalBrain activity={activity} selected={sel} onSelect={setSel} />
          </Suspense>
          <div className="pointer-events-none absolute left-4 top-4 flex flex-wrap gap-2">
            {q.data?.iq && <Chip tone="amber">Индекс ума {q.data.iq.score} / 100</Chip>}
            <Chip tone="smooth">онлайн</Chip>
            {a && <Chip tone="muted">{fmtNum(a.events_24h)} событий за сутки</Chip>}
          </div>
          <div className="absolute bottom-3 left-4 right-4 flex items-center justify-between gap-3 rounded-xl bg-surface/85 px-3 py-2 text-xs text-muted backdrop-blur">
            <span>Вращайте мышью, колесом — масштаб. Нажмите на светящийся узел — откроется модель.</span>
            <span className="hidden whitespace-nowrap md:inline">Волна света = данные, которые мозг обрабатывает сейчас</span>
          </div>
        </Card>
        <div className="flex flex-col gap-4">
          {m ? <ModelCard m={m} go={go} /> : <Card><Spinner label="Загружаем модели…" /></Card>}
          <Card>
            <CardTitle>Все модели</CardTitle>
            <div className="grid grid-cols-2 gap-2">
              {q.data?.models.map((x) => (
                <button key={x.key} onClick={() => setSel(x.key)} aria-pressed={sel === x.key}
                  className={cx('flex items-center gap-2.5 rounded-xl border px-3 py-2.5 text-left transition', sel === x.key ? 'border-amber bg-amber-dim' : 'border-line hover:bg-raised')}>
                  <span className="h-3 w-3 shrink-0 rounded-full" style={{ background: x.color, boxShadow: `0 0 10px ${x.color}` }} />
                  <span className="min-w-0"><span className="block truncate text-sm font-bold">{x.name}</span><span className="block truncate text-[11px] text-muted">{x.sub}</span></span>
                </button>
              ))}
            </div>
          </Card>
        </div>
      </div>
      {a && (
        <div className="flex flex-wrap gap-4">
          <Kpi label="Событий обработано" value={fmtNum(a.events_total)} sub={`${fmtNum(a.trips_total)} поездок`} tone="amber" />
          <Kpi label="Элементов на карте" value={fmtNum(a.elements)} sub="глубокие ямы, лежачие, люки, рельсы" tone="crater" />
          <Kpi label="Ушло в качество дороги" value={fmtNum(a.quality)} sub="мелкие и средние ямы" tone="info" />
          <Kpi label="Разметка" value={fmtNum(a.labels_total)} sub={`${fmtNum(a.labels_7d)} за неделю · вопросов ${fmtNum(a.questions_open)}`} tone="smooth" />
        </div>
      )}
      <Pipeline />
      <ElementVsQuality />
    </div>
  )
}

function ModelCard({ m, go }: { m: ModelInfo; go: (t: Tab) => void }) {
  return (
    <Card className="relative overflow-hidden">
      <div className="pointer-events-none absolute -right-10 -top-10 h-40 w-40 rounded-full opacity-25 blur-2xl" style={{ background: m.color }} />
      <div className="relative">
        <div className="flex items-center gap-3">
          <span className="grid h-11 w-11 place-items-center rounded-2xl text-lg font-black text-inverse" style={{ background: m.color }}>{m.name[0]}</span>
          <div className="min-w-0 flex-1"><div className="text-xl font-extrabold leading-tight">{m.name}</div><div className="text-sm text-muted">{m.sub}</div></div>
          <Chip tone={TONE[m.color] ?? 'muted'}>{m.version}</Chip>
        </div>
        <p className="mt-4 text-sm leading-relaxed text-ink/90">{m.about}</p>
        <dl className="mt-4 grid grid-cols-2 gap-2.5">
          {m.stats.map((s) => (
            <div key={s.label} className="rounded-xl bg-raised px-3 py-2.5"><dt className="text-[11px] text-muted">{s.label}</dt><dd className="mt-0.5 text-base font-bold">{typeof s.value === 'number' ? fmtNum(s.value) : s.value}</dd></div>
          ))}
        </dl>
        <Button className="mt-4 w-full" onClick={() => go(m.tab)}>Открыть раздел →</Button>
      </div>
    </Card>
  )
}

function Pipeline() {
  const steps = [
    { n: 'Телефон', s: 'датчики и GPS', c: 'var(--muted)' }, { n: 'Сезги', s: 'ловит удары', c: '#ffb020' }, { n: 'Назар', s: 'что это было', c: '#4da3ff' },
    { n: 'Хотира', s: 'запоминает место, сторону', c: '#ff5d5d' }, { n: 'Мезон', s: 'качество участка', c: '#3ecf8e' }, { n: 'Карта и голос', s: 'предупреждение водителю', c: 'var(--amber)' },
  ]
  return (
    <Card>
      <CardTitle>Как мозг думает</CardTitle>
      <ol className="flex flex-wrap items-stretch gap-2">
        {steps.map((s, i) => (
          <li key={s.n} className="flex items-center gap-2">
            <div className="rounded-xl border border-line bg-raised px-4 py-3"><div className="text-sm font-bold" style={{ color: s.c }}>{s.n}</div><div className="text-[11px] text-muted">{s.s}</div></div>
            {i < steps.length - 1 && <span className="text-muted" aria-hidden>→</span>}
          </li>
        ))}
      </ol>
      <p className="mt-3 text-sm text-muted">Рядом работают <b className="text-ink">Устоз</b> — спрашивает водителей там, где Назар сомневается, и <b className="text-ink">Холи</b> — принимает голосовые отметки. Ответы становятся разметкой, и все модели переобучаются.</p>
    </Card>
  )
}

function ElementVsQuality() {
  const rows: { t: string; tone: Tone; items: string; warn: string }[] = [
    { t: 'Элемент', tone: 'crater', items: 'Глубокая и опасная яма · лежачий · люк, выступающий или просевший · рельсы и переезд', warn: 'Конкретная точка. Предупреждение «через 150 м», сторона и полоса: яму можно объехать, лежачий — только сбросить скорость.' },
    { t: 'Качество дороги', tone: 'info', items: 'Мелкие и средние ямы · россыпь · колея · волнистость · старый асфальт · полотно, расшатанное грузовиками', warn: 'Участок в сотни метров и километры. Класс A–E, предупреждение о скорости на всём участке; внутри могут быть элементы.' },
  ]
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      {rows.map((r) => (
        <Card key={r.t}>
          <div className="mb-2 flex items-center gap-2"><Chip tone={r.tone}>{r.t}</Chip></div>
          <p className="text-sm font-semibold">{r.items}</p>
          <p className="mt-2 text-sm text-muted">{r.warn}</p>
        </Card>
      ))}
    </div>
  )
}

// ───────────────────────── Эксперименты ─────────────────────────
function ExperimentsTab() {
  const q = useGet<Experiments>('/admin/brain/experiments')
  const d = q.data
  return (
    <div className="flex flex-col gap-5">
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      {q.isLoading && <Spinner label="Проводим опыты на разметке…" />}
      {d && (
        <>
          <Card>
            <CardTitle right={<Chip tone="muted">{d.labeled} размеченных событий</Chip>}>Опыт 1 · Чувствительность Сезги</CardTitle>
            <p className="mb-3 text-sm text-muted">Что будет, если поднять порог удара. Хорошая строка — где почти весь шум убран, а элементы сохранены. Слишком высокий порог начнёт терять настоящие глубокие ямы.</p>
            <div className="overflow-x-auto">
              <table className="w-full min-w-[560px] text-sm">
                <thead><tr className="text-left text-xs text-muted"><th className="py-2">Порог, м/с²</th><th>События остаются</th><th>Шум убран</th><th>Элементы сохранены</th><th>Качество сохранено</th></tr></thead>
                <tbody>
                  {d.floor_sweep.map((r) => (
                    <tr key={r.floor} className="border-t border-line">
                      <td className="py-2.5 font-bold">{r.floor.toFixed(1)}</td><td>{pct(r.events_kept)}</td><td className="text-smooth">{pct(r.noise_removed)}</td>
                      <td className={r.elements_kept != null && r.elements_kept < 0.9 ? 'text-crater' : 'text-smooth'}>{pct(r.elements_kept)}</td><td>{pct(r.quality_kept)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>
          <div className="grid gap-5 lg:grid-cols-2">
            <Card>
              <CardTitle>Опыт 2 · Кривая обучения Назара</CardTitle>
              {d.learning_curve.length < 2 ? <p className="text-sm text-muted">Нужно больше разметки: кривая появится, когда меток будет ≥ 20.</p> : (
                <>
                  <LineChart labels={d.learning_curve.map((p) => String(p.labels))} series={[{ name: 'top-1', color: 'var(--amber)', points: d.learning_curve.map((p) => p.top1) }, { name: 'top-3', color: 'var(--smooth)', points: d.learning_curve.map((p) => p.top3) }]} />
                  <p className="mt-2 text-xs text-muted">Горизонталь — число меток, вертикаль — доля верных догадок на отложенных поездках. Растёт кривая — модель учится.</p>
                </>
              )}
            </Card>
            <Card>
              <CardTitle>Опыт 3 · Сторона и полоса</CardTitle>
              <ul className="flex flex-col gap-2 text-sm">
                {Object.entries(d.lane).length === 0 && <li className="text-muted">Элементов пока нет.</li>}
                {Object.entries(d.lane).map(([k, v]) => {
                  const [span, adv] = k.split(':')
                  const name = span === 'full' ? 'На всю ширину — перестроиться бесполезно' : span === 'stretch' ? 'Протяжённый участок' : adv === 'avoid' ? 'Сторона известна — можно объехать' : 'Сторона пока неизвестна — только сбросить скорость'
                  return <li key={k} className="flex items-center gap-3"><span className="flex-1">{name}</span><b>{v}</b></li>
                })}
              </ul>
              <p className="mt-3 text-xs text-muted">Сторону даёт медиана поперечных смещений проездов. Чем больше проездов, тем точнее: за 3–4 проезда ошибка ≈ 1–1,5 м.</p>
            </Card>
          </div>
        </>
      )}
    </div>
  )
}
