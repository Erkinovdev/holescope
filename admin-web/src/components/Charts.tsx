import { useMemo, useState } from 'react'

export interface BarDatum { label: string; value: number; sub?: string }

/** Столбчатый график на SVG (значения в подсказке; доступно с клавиатуры через title). */
export function BarChart({ data, height = 190, color = 'var(--amber)' }: { data: BarDatum[]; height?: number; color?: string }) {
  const [hover, setHover] = useState<number | null>(null)
  const max = useMemo(() => Math.max(1, ...data.map((d) => d.value)), [data])
  const W = 1000, pad = 22
  const bw = data.length ? (W - pad * 2) / data.length : 0
  return (
    <div className="relative w-full" style={{ height }}>
      <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" className="h-full w-full" role="img" aria-label="График активности">
        <line x1={pad} x2={W - pad} y1={height - 22} y2={height - 22} stroke="var(--line)" />
        {data.map((d, i) => {
          const h = (d.value / max) * (height - 50)
          return (
            <g key={d.label} onMouseEnter={() => setHover(i)} onMouseLeave={() => setHover(null)}>
              <rect x={pad + i * bw + bw * 0.12} width={bw * 0.76} y={height - 22 - h} height={Math.max(h, d.value > 0 ? 2 : 0)} rx={4} fill={color} opacity={hover === null || hover === i ? 1 : 0.5}>
                <title>{`${d.label}: ${d.value.toLocaleString('ru-RU')}${d.sub ? ` · ${d.sub}` : ''}`}</title>
              </rect>
            </g>
          )
        })}
      </svg>
      <div className="pointer-events-none absolute bottom-0 left-0 right-0 flex text-[11px] text-muted" style={{ paddingInline: `${(22 / 1000) * 100}%` }}>
        {data.map((d, i) => <span key={d.label + i} className="min-w-0 flex-1 text-center">{(data.length <= 16 || i % Math.ceil(data.length / 8) === 0) ? d.label : ''}</span>)}
      </div>
      {hover !== null && <div className="pointer-events-none absolute right-2 top-0 rounded-lg bg-raised px-3 py-1.5 text-xs">{data[hover].label}: <b>{data[hover].value.toLocaleString('ru-RU')}</b>{data[hover].sub ? ` · ${data[hover].sub}` : ''}</div>}
    </div>
  )
}

export interface LineSeries { name: string; color: string; points: (number | null)[] }
/** Линии метрик по версиям/дням. */
export function LineChart({ labels, series, height = 200, yMin = 0, yMax = 1 }: { labels: string[]; series: LineSeries[]; height?: number; yMin?: number; yMax?: number }) {
  const W = 1000, pad = 36
  const x = (i: number) => pad + (labels.length <= 1 ? (W - pad * 2) / 2 : (i * (W - pad * 2)) / (labels.length - 1))
  const y = (v: number) => height - 26 - ((v - yMin) / (yMax - yMin || 1)) * (height - 46)
  return (
    <div>
    <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" className="w-full" style={{ height }} role="img" aria-label="График метрик">
      {[0, 0.25, 0.5, 0.75, 1].map((g) => <line key={g} x1={pad} x2={W - pad} y1={y(yMin + g * (yMax - yMin))} y2={y(yMin + g * (yMax - yMin))} stroke="var(--line)" strokeDasharray="4 6" />)}
      {series.map((s) => {
        const pts = s.points.map((v, i) => (v === null ? null : [x(i), y(v)] as const))
        const d = pts.reduce<string>((acc, p, i) => (p === null ? acc : `${acc}${acc && pts[i - 1] ? 'L' : 'M'}${p[0]},${p[1]}`), '')
        return (
          <g key={s.name}>
            <path d={d} fill="none" stroke={s.color} strokeWidth={3} strokeLinejoin="round" />
            {pts.map((p, i) => p && <circle key={i} cx={p[0]} cy={p[1]} r={5} fill={s.color}><title>{`${s.name} · ${labels[i]}: ${s.points[i]}`}</title></circle>)}
          </g>
        )
      })}
    </svg>
    <div className="flex justify-between px-2 text-[11px] text-muted">{labels.filter((_, i) => labels.length <= 8 || i % Math.ceil(labels.length / 8) === 0).map((l, i) => <span key={l + i}>{l}</span>)}</div>
    </div>
  )
}

/** Волна события (вертикальное ускорение). */
export function Wave({ wave, height = 80, color = 'var(--amber)' }: { wave: number[]; height?: number; color?: string }) {
  if (!wave || wave.length < 2) return <div className="text-xs text-muted">нет волны</div>
  const W = 400
  const peak = Math.max(1, ...wave.map((v) => Math.abs(v)))
  const pts = wave.map((v, i) => `${(i / (wave.length - 1)) * W},${height / 2 - (v / peak) * (height / 2 - 4)}`).join(' ')
  return (
    <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" className="w-full" style={{ height }} role="img" aria-label="Волна удара">
      <line x1={0} x2={W} y1={height / 2} y2={height / 2} stroke="var(--line)" />
      <polyline points={pts} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
    </svg>
  )
}

/** Полный сигнал записи с отметками событий (перенос review.html). Нажатие по графику — выбор события. */
export function SignalChart({ t, vz, events, hands, selected, onSelect, height = 220 }: {
  t: number[]; vz: number[]; events: { t: number; type: string; score: number }[]; hands: number[][]; selected?: number | null; onSelect?: (i: number) => void; height?: number
}) {
  const W = 1200
  const T = t.length ? t[t.length - 1] : 1
  const peak = Math.max(1, ...vz.map((v) => Math.abs(v)))
  const X = (s: number) => (s / T) * W
  const Y = (v: number) => height / 2 - (v / peak) * (height / 2 - 6)
  const d = t.map((s, i) => `${i ? 'L' : 'M'}${X(s).toFixed(1)},${Y(vz[i]).toFixed(1)}`).join('')
  return (
    <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" className="w-full" style={{ height }} role="img" aria-label="Сигнал вертикали">
      {hands.map((h, i) => <rect key={i} x={X(h[0])} width={Math.max(2, X(h[1]) - X(h[0]))} y={0} height={height} fill="var(--info)" opacity={0.18}><title>«в руке»</title></rect>)}
      <line x1={0} x2={W} y1={height / 2} y2={height / 2} stroke="var(--line)" />
      <path d={d} fill="none" stroke="var(--muted)" strokeWidth={1} vectorEffect="non-scaling-stroke" />
      {events.map((e, i) => (
        <g key={i} onClick={() => onSelect?.(i)} style={{ cursor: onSelect ? 'pointer' : undefined }}>
          <line x1={X(e.t)} x2={X(e.t)} y1={0} y2={height} stroke={e.type === 'pothole' ? 'var(--crater)' : 'var(--muted)'} strokeWidth={selected === i ? 3 : 1.2} opacity={selected === i ? 1 : 0.7} vectorEffect="non-scaling-stroke">
            <title>{`${e.t.toFixed(1)} с · ${e.type} · score ${e.score}`}</title>
          </line>
        </g>
      ))}
    </svg>
  )
}

/** Мини-график тренда для карточек показателей. */
export function Sparkline({ data, color = 'var(--amber)', height = 36 }: { data: number[]; color?: string; height?: number }) {
  if (data.length < 2) return <div style={{ height }} />
  const W = 200, lo = Math.min(...data), hi = Math.max(...data), span = hi - lo || 1
  const pts = data.map((v, i) => [(i * W) / (data.length - 1), height - 4 - ((v - lo) / span) * (height - 8)] as const)
  const d = pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join('')
  return (
    <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" className="w-full" style={{ height }} aria-hidden>
      <path d={d} fill="none" stroke={color} strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round" vectorEffect="non-scaling-stroke" />
    </svg>
  )
}

export interface Slice { label: string; value: number; color: string }
/** Кольцевая диаграмма с легендой (доли в процентах). */
export function Donut({ slices, size = 150 }: { slices: Slice[]; size?: number }) {
  const total = slices.reduce((a, s) => a + s.value, 0)
  const r = 54, C = 2 * Math.PI * r
  let off = 0
  return (
    <div className="flex items-center gap-5">
      <svg width={size} height={size} viewBox="0 0 140 140" role="img" aria-label="Распределение по классам" className="shrink-0 -rotate-90">
        <circle cx="70" cy="70" r={r} fill="none" stroke="var(--bg-raised)" strokeWidth="14" />
        {total > 0 && slices.map((s) => {
          const len = (s.value / total) * C
          const el = <circle key={s.label} cx="70" cy="70" r={r} fill="none" stroke={s.color} strokeWidth="14" strokeDasharray={`${Math.max(0, len - 2)} ${C}`} strokeDashoffset={-off}><title>{`${s.label}: ${s.value}`}</title></circle>
          off += len
          return el
        })}
      </svg>
      <ul className="flex flex-col gap-1.5 text-sm">
        {slices.map((s) => <li key={s.label} className="flex items-center gap-2"><span className="h-2.5 w-2.5 rounded-[3px]" style={{ background: s.color }} /><span className="w-16">{s.label}</span><b className="text-muted">{total ? Math.round((s.value / total) * 100) : 0}%</b></li>)}
      </ul>
    </div>
  )
}
