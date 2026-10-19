import { useState } from 'react'
import { api, type Analysis, type Taxonomy } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useGet, useSave } from '../lib/hooks'
import { Button, Chip, KV, Select } from './ui'

const pct = (p: number) => `${Math.round(p * 100)}%`

/** Что система думает про объект: тип с вероятностями и причинами, голоса людей, уровень, ровность дороги. */
export function AnalysisBlock({ a, currentType }: { a: Analysis; currentType: string }) {
  const top = a.guess.ranked[0]
  return (
    <div className="flex flex-col gap-4 rounded-2xl border border-line p-4">
      <div>
        <h4 className="mb-2 text-sm font-semibold">Что это, по мнению системы</h4>
        <div className="flex flex-col gap-1.5">
          {a.guess.ranked.map((r) => (
            <div key={r.type} className="flex items-center gap-3 text-sm">
              <span className="w-40 shrink-0 truncate">{r.name}{r.type === currentType ? ' · сейчас' : ''}</span>
              <div className="h-2 flex-1 overflow-hidden rounded-full bg-raised" role="presentation"><div className="h-full rounded-full bg-[var(--amber)]" style={{ width: pct(r.p) }} /></div>
              <span className="w-10 text-right tabular-nums text-muted">{pct(r.p)}</span>
            </div>
          ))}
        </div>
        {top && !a.guess.matches_current && <p className="mt-2 text-xs text-warn">Правила склоняются к «{top.name}», а на карте стоит другой тип. Проверьте и при необходимости поправьте.</p>}
        {a.guess.reasons.length > 0 && (
          <ul className="mt-2 list-disc pl-5 text-xs text-muted">{a.guess.reasons.map((r, i) => <li key={i}>{r}</li>)}</ul>
        )}
        <p className="mt-2 text-xs text-muted">Пока это правила по форме удара и повторяемости. Когда накопится разметка, их заменит обученная модель.</p>
      </div>
      {a.votes.length > 0 && (
        <div>
          <h4 className="mb-2 text-sm font-semibold">Голоса водителей и разметка</h4>
          <div className="flex flex-wrap gap-2">{a.votes.map((v) => <Chip key={v.label} tone="info">{v.name} × {v.n}</Chip>)}</div>
        </div>
      )}
      <div>
        <h4 className="mb-1 text-sm font-semibold">Уровень</h4>
        <p className="text-sm">{a.level.text}</p>
        <p className="text-xs text-muted">Границы по силе удара: {a.level.bounds.join(' / ')} {a.level.calibrated ? '(подобраны по разметке)' : '(стартовые)'}</p>
      </div>
      {a.roughness && (
        <div>
          <h4 className="mb-1 text-sm font-semibold">Дорога на этом месте</h4>
          <KV rows={[
            ['Улица', a.roughness.road],
            ['Ровность', a.roughness.cls ? `${a.roughness.cls} · ${a.roughness.name}${a.roughness.ri !== null ? ` (индекс ${a.roughness.ri})` : ''}` : 'нет данных'],
            ['Проездов / устройств', `${a.roughness.passes} / ${a.roughness.devices}`],
            ['Покрытие', a.roughness.surface],
            ...(a.roughness.flags.length ? [['Рядом', a.roughness.flags.join(', ')] as [string, string]] : []),
          ]} />
        </div>
      )}
      <details className="text-xs text-muted">
        <summary className="cursor-pointer">Признаки повторяемости</summary>
        <KV rows={[
          ['Доля проездов с ударом', pct(a.context.c_hit_rate)], ['Разброс силы удара', a.context.c_score_cv.toFixed(2)], ['Проездов', a.context.c_passes], ['Устройств', a.context.c_devices],
          ['Доля проездов на малой скорости', pct(a.context.c_low_speed)],
        ]} />
      </details>
    </div>
  )
}

/** Выбор метки из справочника, сгруппированный (ямы, лежачие, люки, рельсы, покрытие, не дорога). */
export function LabelSelect({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const t = useGet<Taxonomy>('/taxonomy')
  const groups = Object.entries(t.data?.groups ?? {})
  return (
    <Select value={value} onChange={(e) => onChange(e.target.value)} aria-label="Метка">
      <option value="">— выберите, что это —</option>
      {groups.map(([g, info]) => (
        <optgroup key={g} label={info.ru}>{t.data!.items.filter((i) => i.group === g).map((i) => <option key={i.key} value={i.key}>{i.ru}</option>)}</optgroup>
      ))}
    </Select>
  )
}

/** Разметка объекта целиком: метка попадает в обучение и в голоса, меняет тип и уровень объекта. */
export function ClusterLabeler({ eventId, onDone }: { eventId: number | null; onDone?: () => void }) {
  const { can } = useAuth()
  const [v, setV] = useState('')
  const save = useSave((b: { event_id: number; label: string }) => api.post('/admin/brain/label', b), { ok: 'Метка сохранена', invalidate: ['/admin/clusters', '/admin/brain'], onDone: () => { setV(''); onDone?.() } })
  if (!can('labeler') || eventId === null) return null
  return (
    <div className="flex flex-col gap-2 rounded-2xl bg-raised p-4">
      <h4 className="text-sm font-semibold">Разметить объект</h4>
      <div className="flex gap-2">
        <div className="flex-1"><LabelSelect value={v} onChange={setV} /></div>
        <Button kind="primary" disabled={!v} loading={save.isPending} onClick={() => save.mutate({ event_id: eventId, label: v })}>Сохранить</Button>
      </div>
      <p className="text-xs text-muted">Метка идёт в обучение модели и учитывается как голос: после трёх согласных голосов объект меняет тип и уровень.</p>
    </div>
  )
}
