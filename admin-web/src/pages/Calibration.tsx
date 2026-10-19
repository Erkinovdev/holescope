import { Button, Card, CardTitle, Chip, ErrorBox, Kpi, Spinner } from '../components/ui'
import { api, type Calibration } from '../lib/api'
import { useAuth } from '../lib/auth'
import { LEVEL_NAMES, ROUGH_COLORS } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'

const fmt = (b: number[] | null | undefined) => (b && b.length ? b.join(' / ') : '—')

/** Калибровка: система сама подбирает границы уровней ям и классов ровности по разметке водителей и вашей разметке. */
export default function CalibrationTab() {
  const { can } = useAuth()
  const q = useGet<Calibration>('/admin/brain/calibration')
  const apply = useSave((b: { kind: 'levels' | 'ri'; bounds: number[] }) => api.post('/admin/brain/calibration/apply', b), { ok: 'Границы применены', invalidate: ['/admin/brain', '/admin/clusters', '/map'] })
  if (q.isLoading) return <Spinner />
  if (q.error) return <ErrorBox error={q.error} onRetry={() => q.refetch()} />
  const { levels, ri } = q.data!
  const levelRows = (['light', 'mid', 'deep', 'danger'] as const)
  return (
    <div className="flex flex-col gap-5">
      <p className="text-sm text-muted">
        Уровни ям и классы ровности сначала считаются по стартовым границам. Когда водители отвечают «что это» (мелкая, средняя, глубокая, опасная яма) и оценивают дорогу голосом («дорога ровная … разбитая»),
        система находит границы, которые лучше всего совпадают с их оценкой. Здесь видно, сколько данных уже есть, что система предлагает и насколько это точнее.
      </p>
      <div className="grid gap-4 xl:grid-cols-2">
        <Card>
          <CardTitle right={<Chip tone={levels.active ? 'smooth' : 'muted'}>{levels.active ? 'подобраны по разметке' : 'стартовые'}</Chip>}>Уровни ям по силе удара</CardTitle>
          <div className="mb-3 flex flex-wrap gap-4">
            <Kpi label="Размеченных ям" value={levels.n} sub={levelRows.map((l) => `${LEVEL_NAMES[l]}: ${levels.counts[l] ?? 0}`).join(' · ')} tone="info" />
          </div>
          <dl className="mb-3 grid grid-cols-[auto_1fr] gap-x-6 gap-y-1 text-sm">
            <dt className="text-muted">Сейчас</dt><dd>{fmt(levels.current)} <span className="text-muted">(лёгкая | средняя | глубокая | опасная)</span></dd>
            <dt className="text-muted">Точность сейчас</dt><dd>{levels.acc_current === null ? 'нужно ≥12 меток' : `${Math.round(levels.acc_current * 100)}%`}</dd>
            <dt className="text-muted">Предложение</dt><dd>{levels.suggested ? fmt(levels.suggested) : 'пока нет'}</dd>
            <dt className="text-muted">Точность с предложением</dt><dd>{levels.acc_suggested === null ? '—' : `${Math.round(levels.acc_suggested * 100)}%`}</dd>
            <dt className="text-muted">На новых данных (проверка)</dt><dd>{levels.cv_current === null ? '—' : `${Math.round(levels.cv_current * 100)}% → ${Math.round((levels.cv_suggested ?? 0) * 100)}%`}</dd>
          </dl>
          {can('admin') && (
            <Button kind="primary" disabled={!levels.suggested || !levels.significant} loading={apply.isPending} onClick={() => apply.mutate({ kind: 'levels', bounds: levels.suggested! })}>
              Применить предложение
            </Button>
          )}
          {levels.suggested && !levels.significant && <p className="mt-2 text-xs text-muted">Предложение пока не лучше текущих границ на отложенных данных (разметки мало или метки слабо связаны с силой удара): менять не нужно. Нужно больше размеченных ям, особенно глубоких и опасных.</p>}
          {levels.significant && <p className="mt-2 text-xs text-smooth">На отложенных данных предложение стабильно лучше текущих границ.</p>}
        </Card>
        <Card>
          <CardTitle right={<Chip tone={ri.enough ? 'smooth' : 'muted'}>{ri.enough ? 'данных достаточно' : 'мало оценок'}</Chip>}>Классы ровности A–E (индекс ровности)</CardTitle>
          <table className="mb-3 w-full text-sm">
            <thead className="text-left text-xs text-muted"><tr><th className="py-1">Оценка водителей</th><th>Оценок</th><th>Медиана</th><th>Разброс (25–75%)</th></tr></thead>
            <tbody>
              {(['A', 'B', 'C', 'D', 'E'] as const).map((c) => (
                <tr key={c} className="border-t border-line">
                  <td className="py-1.5"><span className="mr-2 inline-block h-2.5 w-2.5 rounded-full align-middle" style={{ background: ROUGH_COLORS[c] }} />{c} · {ri.names[c]}</td>
                  <td>{ri.stats[c].n}</td><td>{ri.stats[c].median ?? '—'}</td><td>{ri.stats[c].p25 !== null ? `${ri.stats[c].p25}–${ri.stats[c].p75}` : '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <dl className="mb-3 grid grid-cols-[auto_1fr] gap-x-6 gap-y-1 text-sm">
            <dt className="text-muted">Границы сейчас</dt><dd>{fmt(ri.current)} <span className="text-muted">(A|B, B|C, C|D, D|E)</span></dd>
            <dt className="text-muted">Предложение</dt><dd>{ri.suggested ? fmt(ri.suggested) : (ri.warning ?? 'нужно ≥8 оценок на каждый класс')}</dd>
          </dl>
          {can('admin') && <Button kind="primary" disabled={!ri.suggested} loading={apply.isPending} onClick={() => apply.mutate({ kind: 'ri', bounds: ri.suggested! })}>Применить предложение</Button>}
          {ri.warning && <p className="mt-2 text-xs text-warn">{ri.warning}</p>}
        </Card>
      </div>
      <Card>
        <CardTitle>Как набрать данные быстрее</CardTitle>
        <ul className="list-disc pl-5 text-sm text-muted">
          <li>Водители говорят Холи: «глубокая яма», «опасная яма», «просевший люк», «рельсы», «переезд» — отметка привязывается к удару и становится разметкой.</li>
          <li>После поездки приложение спрашивает «что это было?» — 20 вариантов, включая уровни ям, люки (просел, выступает), стыки, волнистость, колею.</li>
          <li>Оценка дороги голосом: «дорога ровная / хорошая / нормальная / плохая / разбитая» относится к участку, который только что проехали.</li>
          <li>Вы можете размечать удары в разделе «Очередь разметки» и в карточке ямы.</li>
        </ul>
      </Card>
    </div>
  )
}
