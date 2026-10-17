import { useEffect, useState } from 'react'
import { Button, Card, Chip, ErrorBox, Field, Input, Modal, PageHeader, Pagination, Select, Spinner, Table } from '../components/ui'
import { api, type Page, type Road, type RoadSegmentRow } from '../lib/api'
import { useAuth } from '../lib/auth'
import { fmtNum, ROAD_CLASS_NAMES, ROUGH_COLORS, SURFACE_NAMES } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'

interface RoadDetail extends Omit<Road, 'segments'> { classes: Record<string, number>; segments_total: number; segments: RoadSegmentRow[]; osm_way_ids: number[]; clusters: number }

export default function Roads() {
  const [page, setPage] = useState(1)
  const [cls, setCls] = useState('')
  const [q, setQ] = useState('')
  const [named, setNamed] = useState('')
  const [reviewed, setReviewed] = useState('')
  const [open, setOpen] = useState<number | null>(null)
  useEffect(() => setPage(1), [cls, q, named, reviewed])
  const list = useGet<Page<Road>>('/admin/roads', { page, size: 30, class: cls, q: q.trim(), named, reviewed })
  return (
    <div>
      <PageHeader title="Дороги" sub="Реестр дорог из OSM: классы R/A/B/C/D/S, покрытие, ровность. Класс проверяет человек." />
      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <Field label="Класс"><Select value={cls} onChange={(e) => setCls(e.target.value)}><option value="">все</option>{Object.entries(ROAD_CLASS_NAMES).map(([k, v]) => <option key={k} value={k}>{k} — {v}</option>)}</Select></Field>
        <Field label="Название или код"><Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Бабура или A039" /></Field>
        <Field label="Названия"><Select value={named} onChange={(e) => setNamed(e.target.value)}><option value="">все</option><option value="1">с названием</option><option value="0">без названия</option></Select></Field>
        <Field label="Проверка класса"><Select value={reviewed} onChange={(e) => setReviewed(e.target.value)}><option value="">все</option><option value="1">проверен</option><option value="0">не проверен</option></Select></Field>
      </div>
      {list.isLoading && <Spinner />}
      {list.error && <ErrorBox error={list.error} onRetry={() => list.refetch()} />}
      {list.data && (
        <>
          <Table rowKey={(r) => r.id} rows={list.data.items} empty="Дорог по фильтрам нет" onRow={(r) => setOpen(r.id)} cols={[
            { key: 'code', title: 'Код', width: '90px', render: (r) => <b>{r.code}</b> },
            { key: 'name', title: 'Название', render: (r) => <span className={r.named ? 'font-medium' : 'text-muted'}>{r.name_ru}</span> },
            { key: 'c', title: 'Класс', render: (r) => <Chip tone={r.class_reviewed ? 'smooth' : 'muted'}>{r.road_class}{r.class_reviewed ? ' ✓' : ''}</Chip> },
            { key: 'sf', title: 'Покрытие', render: (r) => SURFACE_NAMES[r.surface] ?? r.surface },
            { key: 'd', title: 'Район', render: (r) => r.district ?? '—' },
            { key: 'len', title: 'Длина, км', align: 'right', render: (r) => fmtNum(r.length_km, 1) },
            { key: 'sg', title: 'Оценено сегм.', align: 'right', render: (r) => `${r.scored ?? 0} / ${r.segments ?? 0}` },
            { key: 'ri', title: 'RI', align: 'right', render: (r) => (r.ri_avg == null ? '—' : r.ri_avg.toFixed(3)) },
          ]} />
          <Pagination page={list.data.page} size={list.data.size} total={list.data.total} onPage={setPage} />
        </>
      )}
      <RoadModal id={open} onClose={() => setOpen(null)} />
    </div>
  )
}

function RoadModal({ id, onClose }: { id: number | null; onClose: () => void }) {
  const { can } = useAuth()
  const q = useGet<RoadDetail>(`/admin/roads/${id}`, undefined, { enabled: id !== null })
  const [f, setF] = useState<Record<string, string>>({})
  useEffect(() => setF({}), [id])
  const save = useSave((b: Record<string, unknown>) => api.patch<Road>(`/admin/roads/${id}/patch`, b), { ok: 'Дорога сохранена', invalidate: ['/admin/roads'], onDone: () => setF({}) })
  const r = q.data
  const val = (k: keyof Road) => f[k] ?? String(r?.[k] ?? '')
  const dirty = Object.keys(f).length > 0
  return (
    <Modal open={id !== null} onClose={onClose} title={r ? `${r.code} · ${r.name_ru}` : 'Дорога'} width="max-w-3xl">
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} />}
      {r && (
        <div className="flex flex-col gap-4">
          <div className="flex flex-wrap gap-2">
            <Chip tone="info">{r.road_class} · {ROAD_CLASS_NAMES[r.road_class]}</Chip><Chip>{r.segments_total} сегментов · {fmtNum(r.length_km, 1)} км</Chip>
            {r.has_tram && <Chip tone="amber">трамвай</Chip>}{r.has_level_crossing && <Chip tone="amber">ж/д переезд</Chip>}<Chip tone="crater">ям: {r.clusters}</Chip>
          </div>
          <div>
            <div className="mb-2 text-sm font-semibold">Классы ровности сегментов</div>
            <div className="flex h-5 overflow-hidden rounded-full bg-raised" role="img" aria-label="Распределение классов ровности">
              {['A', 'B', 'C', 'D', 'E'].map((k) => { const n = r.classes[k] ?? 0; const tot = Object.values(r.classes).reduce((a, b) => a + b, 0) || 1; return n ? <div key={k} style={{ width: `${(n / tot) * 100}%`, background: ROUGH_COLORS[k] }} title={`${k}: ${n}`} /> : null })}
            </div>
            <p className="mt-1 text-xs text-muted">{Object.keys(r.classes).length ? Object.entries(r.classes).map(([k, v]) => `${k}: ${v}`).join(' · ') : 'Оценок ровности пока нет'}</p>
          </div>
          {can('admin') ? (
            <div className="grid grid-cols-2 gap-3 rounded-2xl bg-raised p-4">
              <Field label="Класс"><Select value={val('road_class')} onChange={(e) => setF({ ...f, road_class: e.target.value })}>{Object.entries(ROAD_CLASS_NAMES).map(([k, v]) => <option key={k} value={k}>{k} — {v}</option>)}</Select></Field>
              <Field label="Покрытие"><Select value={val('surface')} onChange={(e) => setF({ ...f, surface: e.target.value })}>{Object.entries(SURFACE_NAMES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
              <Field label="Название (рус.)"><Input value={val('name_ru')} onChange={(e) => setF({ ...f, name_ru: e.target.value })} /></Field>
              <Field label="Название (узб.)"><Input value={val('name_uz')} onChange={(e) => setF({ ...f, name_uz: e.target.value })} /></Field>
              <Field label="Ограничение скорости, км/ч"><Input type="number" value={val('speed_limit_kmh')} onChange={(e) => setF({ ...f, speed_limit_kmh: e.target.value })} /></Field>
              <div className="flex items-end justify-end"><Button kind="primary" disabled={!dirty || save.isPending} onClick={() => save.mutate({ ...f, speed_limit_kmh: f.speed_limit_kmh === undefined ? undefined : (f.speed_limit_kmh === '' ? null : Number(f.speed_limit_kmh)) })}>Сохранить</Button></div>
            </div>
          ) : <Card className="text-sm text-muted">Править дороги может только администратор.</Card>}
          <details>
            <summary className="cursor-pointer text-sm font-semibold">Сегменты (первые {r.segments.length})</summary>
            <div className="mt-2 max-h-60 overflow-auto text-xs">
              <table className="w-full"><thead><tr className="text-muted"><th className="p-1 text-left">№</th><th className="p-1 text-left">напр.</th><th className="p-1 text-left">класс</th><th className="p-1 text-right">RI</th><th className="p-1 text-right">проездов</th></tr></thead>
                <tbody>{r.segments.map((s) => <tr key={s.id} className="border-t border-line"><td className="p-1">{r.code}-{String(s.index).padStart(4, '0')}{s.direction === -1 ? 'r' : ''}</td><td className="p-1">{s.direction === 1 ? '→' : '←'}</td><td className="p-1" style={{ color: ROUGH_COLORS[s.cls] }}>{s.cls || '—'}</td><td className="p-1 text-right">{s.ri_median?.toFixed(3) ?? '—'}</td><td className="p-1 text-right">{s.ri_n}</td></tr>)}</tbody></table>
            </div>
          </details>
        </div>
      )}
    </Modal>
  )
}
