import { AnimatePresence, motion } from 'framer-motion'
import { createContext, useCallback, useContext, useEffect, useId, useMemo, useState, type ButtonHTMLAttributes, type InputHTMLAttributes, type ReactNode, type SelectHTMLAttributes, type TextareaHTMLAttributes } from 'react'

export type Tone = 'smooth' | 'warn' | 'crater' | 'info' | 'muted' | 'amber'
const dot: Record<Tone, string> = { smooth: 'bg-smooth', warn: 'bg-warn', crater: 'bg-crater', info: 'bg-info', muted: 'bg-muted', amber: 'bg-amber' }
const cx = (...a: (string | false | undefined | null)[]) => a.filter(Boolean).join(' ')

export function Card({ children, className, pad = true }: { children: ReactNode; className?: string; pad?: boolean }) {
  return <section className={cx('rounded-[20px] border border-line bg-surface', pad && 'p-5', className)}>{children}</section>
}

export function CardTitle({ children, right }: { children: ReactNode; right?: ReactNode }) {
  return (
    <div className="mb-3 flex items-center gap-3">
      <h2 className="text-base font-semibold">{children}</h2>
      <div className="ml-auto flex items-center gap-2">{right}</div>
    </div>
  )
}

export function Chip({ tone = 'muted', children }: { tone?: Tone; children: ReactNode }) {
  return (
    <span className="inline-flex items-center gap-2 rounded-full bg-raised px-3 py-1 text-xs font-medium">
      <span className={cx('h-2 w-2 rounded-full', dot[tone])} aria-hidden />
      {children}
    </span>
  )
}

type BtnKind = 'primary' | 'secondary' | 'danger' | 'ghost'
const btnCls: Record<BtnKind, string> = {
  primary: 'bg-amber text-inverse hover:brightness-105',
  secondary: 'bg-raised text-ink border border-line hover:border-muted',
  danger: 'bg-crater text-white hover:brightness-110',
  ghost: 'text-muted hover:text-ink hover:bg-raised',
}
export function Button({ kind = 'secondary', small, className, ...p }: ButtonHTMLAttributes<HTMLButtonElement> & { kind?: BtnKind; small?: boolean }) {
  return (
    <button
      type="button"
      {...p}
      className={cx('inline-flex items-center justify-center gap-2 rounded-xl font-semibold transition disabled:cursor-not-allowed disabled:opacity-50', small ? 'px-3 py-1.5 text-xs' : 'px-4 py-2.5 text-sm', btnCls[kind], className)}
    />
  )
}

export function Field({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="text-xs font-medium text-muted">{label}</span>
      {children}
      {hint && <span className="text-xs text-muted">{hint}</span>}
    </label>
  )
}
const inputCls = 'w-full rounded-xl border border-line bg-raised px-3.5 py-2.5 text-sm placeholder:text-muted disabled:opacity-60'
export const Input = (p: InputHTMLAttributes<HTMLInputElement>) => <input {...p} className={cx(inputCls, p.className)} />
export const Textarea = (p: TextareaHTMLAttributes<HTMLTextAreaElement>) => <textarea {...p} className={cx(inputCls, 'min-h-24', p.className)} />
export const Select = (p: SelectHTMLAttributes<HTMLSelectElement>) => <select {...p} className={cx(inputCls, p.className)} />

export function Segmented<T extends string>({ value, options, onChange, label }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void; label?: string }) {
  return (
    <div role="tablist" aria-label={label} className="inline-flex gap-1 rounded-2xl bg-surface p-1 border border-line">
      {options.map((o) => (
        <button key={o.value} type="button" role="tab" aria-selected={o.value === value} onClick={() => onChange(o.value)}
          className={cx('rounded-xl px-4 py-2 text-sm font-semibold transition', o.value === value ? 'bg-raised text-ink' : 'text-muted hover:text-ink')}>
          {o.label}
        </button>
      ))}
    </div>
  )
}

export function Spinner({ label = 'Загрузка…' }: { label?: string }) {
  return <div className="flex items-center gap-3 p-6 text-muted" role="status"><span className="h-4 w-4 animate-spin rounded-full border-2 border-line border-t-amber" />{label}</div>
}

export function ErrorBox({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const msg = error instanceof Error ? error.message : 'Ошибка'
  return (
    <div role="alert" className="flex items-center gap-4 rounded-2xl border border-line bg-surface p-5">
      <span className="text-crater">{msg}</span>
      {onRetry && <Button small onClick={onRetry}>Повторить</Button>}
    </div>
  )
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="rounded-2xl border border-dashed border-line p-8 text-center text-muted">{children}</div>
}

export interface Col<T> { key: string; title: string; width?: string; render: (r: T) => ReactNode; align?: 'right' }
export function Table<T>({ cols, rows, onRow, rowKey, empty = 'Нет данных', selected }: { cols: Col<T>[]; rows: T[]; onRow?: (r: T) => void; rowKey: (r: T) => string | number; empty?: string; selected?: (r: T) => boolean }) {
  if (!rows.length) return <Empty>{empty}</Empty>
  return (
    <div className="overflow-x-auto rounded-[20px] border border-line bg-surface">
      <table className="w-full min-w-[640px] border-collapse text-left text-sm">
        <thead>
          <tr className="bg-raised text-xs text-muted">
            {cols.map((c) => <th key={c.key} style={{ width: c.width }} className={cx('px-4 py-3 font-semibold', c.align === 'right' && 'text-right')}>{c.title}</th>)}
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={rowKey(r)} onClick={onRow ? () => onRow(r) : undefined} tabIndex={onRow ? 0 : undefined}
              onKeyDown={onRow ? (e) => { if (e.key === 'Enter') onRow(r) } : undefined}
              className={cx('border-t border-line', onRow && 'cursor-pointer hover:bg-raised/60', selected?.(r) && 'bg-amber-dim/40')}>
              {cols.map((c) => <td key={c.key} className={cx('px-4 py-3 align-middle', c.align === 'right' && 'text-right')}>{c.render(r)}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function Pagination({ page, size, total, onPage }: { page: number; size: number; total: number; onPage: (p: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / size))
  return (
    <div className="mt-3 flex items-center gap-3 text-sm text-muted">
      <span>{total.toLocaleString('ru-RU')} записей</span>
      <div className="ml-auto flex items-center gap-2">
        <Button small disabled={page <= 1} onClick={() => onPage(page - 1)}>← Назад</Button>
        <span>{page} / {pages}</span>
        <Button small disabled={page >= pages} onClick={() => onPage(page + 1)}>Вперёд →</Button>
      </div>
    </div>
  )
}

export function Modal({ open, title, onClose, children, width = 'max-w-lg' }: { open: boolean; title: string; onClose: () => void; children: ReactNode; width?: string }) {
  const id = useId()
  useEffect(() => {
    if (!open) return
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [open, onClose])
  return (
    <AnimatePresence>
      {open && (
        <motion.div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onMouseDown={onClose}>
          <motion.div role="dialog" aria-modal="true" aria-labelledby={id} onMouseDown={(e) => e.stopPropagation()} initial={{ y: 12, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: 12, opacity: 0 }}
            className={cx('max-h-[90vh] w-full overflow-auto rounded-[24px] border border-line bg-surface p-6', width)}>
            <h2 id={id} className="mb-4 text-lg font-bold">{title}</h2>
            {children}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}

// ── уведомления ──
interface Toast { id: number; text: string; tone: 'ok' | 'err' }
const ToastCtx = createContext<(text: string, tone?: 'ok' | 'err') => void>(() => {})
export const useToast = () => useContext(ToastCtx)
export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<Toast[]>([])
  const push = useCallback((text: string, tone: 'ok' | 'err' = 'ok') => {
    const id = Date.now() + Math.random()
    setItems((s) => [...s, { id, text, tone }])
    setTimeout(() => setItems((s) => s.filter((x) => x.id !== id)), 4500)
  }, [])
  const value = useMemo(() => push, [push])
  return (
    <ToastCtx.Provider value={value}>
      {children}
      <div className="fixed bottom-5 right-5 z-[60] flex flex-col gap-2" aria-live="polite">
        {items.map((t) => (
          <motion.div key={t.id} initial={{ x: 20, opacity: 0 }} animate={{ x: 0, opacity: 1 }}
            className={cx('rounded-xl border px-4 py-3 text-sm shadow-lg', t.tone === 'ok' ? 'border-smooth bg-surface' : 'border-crater bg-surface')}>
            {t.text}
          </motion.div>
        ))}
      </div>
    </ToastCtx.Provider>
  )
}

export function Kpi({ label, value, sub, tone = 'amber' }: { label: string; value: ReactNode; sub?: string; tone?: Tone }) {
  const col: Record<Tone, string> = { amber: 'text-amber-text', smooth: 'text-smooth', warn: 'text-warn', crater: 'text-crater', info: 'text-info', muted: 'text-ink' }
  return (
    <Card className="flex-1 min-w-[200px]">
      <div className="text-[13px] font-medium text-muted">{label}</div>
      <div className={cx('mt-1 text-4xl font-bold tracking-tight', col[tone])}>{value}</div>
      {sub && <div className="mt-1 text-xs text-muted">{sub}</div>}
    </Card>
  )
}

export function PageHeader({ title, sub, right }: { title: string; sub?: string; right?: ReactNode }) {
  return (
    <div className="mb-5 flex flex-wrap items-center gap-3">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">{title}</h1>
        {sub && <p className="mt-1 text-sm text-muted">{sub}</p>}
      </div>
      <div className="ml-auto flex items-center gap-2">{right}</div>
    </div>
  )
}

export function KV({ rows }: { rows: [string, ReactNode][] }) {
  return (
    <dl className="divide-y divide-line">
      {rows.map(([k, v]) => (
        <div key={k} className="flex items-center gap-4 py-2.5 text-sm">
          <dt className="text-muted">{k}</dt>
          <dd className="ml-auto text-right font-semibold">{v}</dd>
        </div>
      ))}
    </dl>
  )
}

export { cx }
