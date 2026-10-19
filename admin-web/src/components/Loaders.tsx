import type { CSSProperties } from 'react'

/** Знак-загрузчик: кольцо рисуется, риски собираются, появляется яма. */
export function Mark({ size = 104, className }: { size?: number; className?: string }) {
  return (
    <svg className={`hs-mark ${className ?? ''}`} width={size} height={size} viewBox="0 0 64 64" aria-hidden>
      <defs><linearGradient id="hs-ag" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#ffcf5a" /><stop offset="1" stopColor="#ff9f0a" /></linearGradient></defs>
      <circle className="ring" cx="32" cy="32" r="22" />
      <line className="tick t1" x1="32" y1="4" x2="32" y2="15" /><line className="tick t2" x1="32" y1="60" x2="32" y2="49" />
      <line className="tick t3" x1="4" y1="32" x2="15" y2="32" /><line className="tick t4" x1="60" y1="32" x2="49" y2="32" />
      <ellipse className="hole" cx="32" cy="33" rx="10" ry="6" />
    </svg>
  )
}

/** Мини-спиннер (цвет — currentColor; по умолчанию янтарный). */
export function MiniSpin({ size = 22, className = 'amber' }: { size?: number; className?: string }) {
  return <svg className={`hs-spin ${className}`} style={{ width: size, height: size }} viewBox="0 0 64 64" aria-hidden><circle cx="32" cy="32" r="22" /></svg>
}

/** Полоса со «сканером». */
export function ScanBar({ width = 220, className }: { width?: number | string; className?: string }) {
  return <div className={`hs-scan ${className ?? ''}`} style={{ width }} aria-hidden />
}

/** Три точки-ямы. */
export function Dots() {
  return <span className="hs-dots" aria-hidden><i /><i /><i /></span>
}

/** Заготовка-«скелетон»: блок с бегущим бликом. */
export function Sk({ h = 12, w = '100%', r, style }: { h?: number; w?: number | string; r?: number; style?: CSSProperties }) {
  return <div className="hs-sk" style={{ height: h, width: w, borderRadius: r, ...style }} aria-hidden />
}

/** Скелетон карточки: иконка и строки. */
export function CardSkeleton({ rows = 3 }: { rows?: number }) {
  return (
    <div className="flex flex-col gap-3 p-1" role="status" aria-label="Загрузка">
      <div className="flex items-center gap-3"><Sk h={46} w={46} r={14} /><div className="flex flex-1 flex-col gap-2"><Sk w="70%" /><Sk h={10} w="45%" /></div></div>
      {Array.from({ length: rows }, (_, i) => <Sk key={i} w={`${100 - i * 9}%`} />)}
    </div>
  )
}

/** Скелетон таблицы. */
export function TableSkeleton({ rows = 8 }: { rows?: number }) {
  return (
    <div className="flex flex-col gap-2" role="status" aria-label="Загрузка">
      {Array.from({ length: rows }, (_, i) => <Sk key={i} h={40} r={12} style={{ opacity: 1 - i * 0.08 }} />)}
    </div>
  )
}

/** «Холи слушает»: круги и эквалайзер. */
export function HoliWave() {
  return <div className="hs-holi" aria-hidden><span className="halo" /><span className="halo" /><span className="halo" /><div className="core"><i /><i /><i /><i /><i /></div></div>
}

/** Загрузка страницы целиком: знак, подпись и сканер. */
export function PageLoader({ label = 'Загружаем…' }: { label?: string }) {
  return (
    <div className="hs-page" role="status" aria-live="polite">
      <Mark size={96} />
      <div className="text-sm font-medium text-muted">{label}</div>
      <ScanBar width={200} />
    </div>
  )
}
