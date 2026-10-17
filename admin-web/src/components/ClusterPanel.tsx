import { useState } from 'react'
import { Link } from 'react-router-dom'
import { api, type Cluster, type ClusterDetail } from '../lib/api'
import { useAuth } from '../lib/auth'
import { ago, fmtDateTime, LEVEL_NAMES, LEVEL_TONE, STATUS_NAMES, STATUS_TONE, TYPE_NAMES } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'
import { Wave } from './Charts'
import { Button, Chip, ErrorBox, Field, Input, KV, Select, Spinner } from './ui'

const STATUSES = Object.keys(STATUS_NAMES)
const TYPES = Object.keys(TYPE_NAMES)
const LEVELS = ['light', 'mid', 'deep', 'danger']

/** Карточка ямы с модерацией: статус, тип, уровень, безопасная скорость; события с волнами. */
export default function ClusterPanel({ id, onChanged, onMerge }: { id: number; onChanged?: (c: Cluster) => void; onMerge?: () => void }) {
  const { can } = useAuth()
  const q = useGet<ClusterDetail>(`/admin/clusters/${id}`)
  const [safe, setSafe] = useState<string | null>(null)
  const save = useSave((b: Record<string, unknown>) => api.patch<Cluster>(`/admin/clusters/${id}/patch`, b), { ok: 'Сохранено', invalidate: ['/admin/clusters', '/admin/overview', '/admin/brain'], onDone: (c) => onChanged?.(c) })
  if (q.isLoading) return <Spinner />
  if (q.error) return <ErrorBox error={q.error} onRetry={() => q.refetch()} />
  const c = q.data!
  const edit = can('labeler')
  return (
    <div className="flex flex-col gap-4">
      <div>
        <h3 className="text-lg font-bold">{c.street ?? `${c.lat.toFixed(5)}, ${c.lon.toFixed(5)}`}</h3>
        <p className="text-sm text-muted">{[c.district, c.segment].filter(Boolean).join(' · ') || 'вне дорожной сети'}</p>
        <div className="mt-2 flex flex-wrap gap-2">
          <Chip tone={STATUS_TONE[c.status]}>{STATUS_NAMES[c.status]}</Chip>
          <Chip tone={LEVEL_TONE[c.level]}>{TYPE_NAMES[c.type] ?? c.type} · {LEVEL_NAMES[c.level]}</Chip>
          <Chip tone="info">{c.devices} устр. · {c.passes} проездов</Chip>
        </div>
      </div>
      <KV rows={[
        ['Уверенность', c.confidence.toFixed(2)],
        ['Сила удара (медиана)', c.score_median],
        ['Безопасная скорость', c.safe_speed ? `${c.safe_speed} км/ч` : '—'],
        ['Первое обнаружение', fmtDateTime(c.first_seen)],
        ['Последний удар', `${fmtDateTime(c.last_hit)} (${ago(c.last_hit)})`],
        ['Тихих проездов', c.quiet_passes],
        ['Жалоб', c.complaints],
        ['Голоса водителей', Object.keys(c.type_votes ?? {}).length ? Object.entries(c.type_votes).map(([k, v]) => `${k}: ${v}`).join(', ') : '—'],
      ]} />
      {edit && (
        <div className="flex flex-col gap-3 rounded-2xl bg-raised p-4">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Статус"><Select value={c.status} onChange={(e) => save.mutate({ status: e.target.value })}>{STATUSES.map((s) => <option key={s} value={s}>{STATUS_NAMES[s]}</option>)}</Select></Field>
            <Field label="Тип"><Select value={c.type} onChange={(e) => save.mutate({ type: e.target.value })}>{TYPES.map((s) => <option key={s} value={s}>{TYPE_NAMES[s]}</option>)}</Select></Field>
            <Field label="Уровень"><Select value={c.level} onChange={(e) => save.mutate({ level: e.target.value })}><option value="">—</option>{LEVELS.map((s) => <option key={s} value={s}>{LEVEL_NAMES[s]}</option>)}</Select></Field>
            <Field label="Безопасная скорость, км/ч">
              <div className="flex gap-2">
                <Input type="number" min={5} max={120} value={safe ?? c.safe_speed ?? ''} onChange={(e) => setSafe(e.target.value)} />
                <Button small onClick={() => save.mutate({ safe_speed: safe === null || safe === '' ? null : Number(safe) })}>OK</Button>
              </div>
            </Field>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button small kind="primary" disabled={c.status === 'confirmed'} onClick={() => save.mutate({ status: 'confirmed' })}>Подтвердить</Button>
            <Button small disabled={c.status === 'false'} onClick={() => save.mutate({ status: 'false' })}>Отклонить (ложная)</Button>
            <Button small disabled={c.status === 'fixed'} onClick={() => save.mutate({ status: 'fixed' })}>Заделана</Button>
            {onMerge && <Button small kind="ghost" onClick={onMerge}>Объединить с…</Button>}
          </div>
          <p className="text-xs text-muted">Правка типа и уровня сохраняется и как разметка для обучения.</p>
        </div>
      )}
      <div>
        <h4 className="mb-2 text-sm font-semibold">События ({c.events.length})</h4>
        <div className="flex flex-col gap-3">
          {c.events.slice(0, 12).map((e) => (
            <div key={e.id} className="rounded-2xl border border-line p-3">
              <div className="mb-1 flex flex-wrap items-center gap-2 text-xs text-muted">
                <span>{fmtDateTime(e.at)}</span><span>·</span><Link to={`/devices/${e.device_id}`} className="hover:underline">{e.device}</Link><span>·</span><span>{Math.round(e.speed_kmh)} км/ч</span>
                <span>·</span><span>пик {e.peak} · score {e.score}</span>{e.user_label && <Chip tone="info">ответ: {e.user_label}</Chip>}
                <Link to={`/trips/${e.trip}`} className="ml-auto hover:underline">поездка #{e.trip}</Link>
              </div>
              <Wave wave={e.wave} />
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
