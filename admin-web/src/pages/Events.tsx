import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import ClusterPanel from '../components/ClusterPanel'
import { Button, Card, Chip, ErrorBox, Field, Input, Modal, PageHeader, Pagination, Select, Table, useToast } from '../components/ui'
import { api, type Cluster, type Page } from '../lib/api'
import { useAuth } from '../lib/auth'
import { ago, LEVEL_NAMES, LEVEL_TONE, STATUS_NAMES, STATUS_TONE, TYPE_NAMES } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'
import { TableSkeleton } from '../components/Loaders'

export default function Events() {
  const { can } = useAuth()
  const toast = useToast()
  const [sp, setSp] = useSearchParams()
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState(sp.get('status') ?? '')
  const [type, setType] = useState('')
  const [level, setLevel] = useState('')
  const [q, setQ] = useState('')
  const [sort, setSort] = useState('-last_hit')
  const [open, setOpen] = useState<number | null>(sp.get('focus') ? Number(sp.get('focus')) : null)
  const [picked, setPicked] = useState<number[]>([])
  const [addOpen, setAddOpen] = useState(false)
  useEffect(() => setPage(1), [status, type, level, q, sort])
  const list = useGet<Page<Cluster>>('/admin/clusters', { page, size: 25, status, type, level, q: q.trim(), sort })
  const merge = useSave((ids: number[]) => api.post<Cluster>('/admin/clusters/merge', { ids }), {
    ok: 'Ямы объединены', invalidate: ['/admin/clusters', '/admin/overview'], onDone: (c) => { setPicked([]); setOpen(c.id) },
  })
  const toggle = (id: number) => setPicked((p) => (p.includes(id) ? p.filter((x) => x !== id) : [...p, id]))

  return (
    <div>
      <PageHeader title="События" sub="Модерация ям: подтвердить, отклонить, объединить дубли, сменить тип и уровень"
        right={<>
          {can('labeler') && <Button kind="primary" onClick={() => setAddOpen(true)}>Добавить яму</Button>}
          {can('labeler') && <Button disabled={picked.length < 2 || merge.isPending} onClick={() => merge.mutate(picked)}>Объединить ({picked.length})</Button>}
        </>} />
      <div className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-5">
        <Field label="Статус"><Select value={status} onChange={(e) => { setStatus(e.target.value); setSp({}) }}><option value="">все</option>{Object.entries(STATUS_NAMES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
        <Field label="Тип"><Select value={type} onChange={(e) => setType(e.target.value)}><option value="">все</option>{Object.entries(TYPE_NAMES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
        <Field label="Уровень"><Select value={level} onChange={(e) => setLevel(e.target.value)}><option value="">все</option>{['light', 'mid', 'deep', 'danger'].map((k) => <option key={k} value={k}>{LEVEL_NAMES[k]}</option>)}</Select></Field>
        <Field label="Улица"><Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="название" /></Field>
        <Field label="Сортировка"><Select value={sort} onChange={(e) => setSort(e.target.value)}>
          <option value="-last_hit">по последнему удару</option><option value="-passes">по проездам</option><option value="-devices">по устройствам</option><option value="-score_median">по силе</option><option value="-first_seen">новые первыми</option>
        </Select></Field>
      </div>
      <div className="grid gap-4 xl:grid-cols-[1fr_420px]">
        <div>
          {list.isLoading && <TableSkeleton />}
          {list.error && <ErrorBox error={list.error} onRetry={() => list.refetch()} />}
          {list.data && (
            <>
              <Table rowKey={(r) => r.id} rows={list.data.items} empty="По фильтрам ям нет" selected={(r) => r.id === open} onRow={(r) => setOpen(r.id)} cols={[
                ...(can('labeler') ? [{ key: 'pick', title: '', width: '36px', render: (r: Cluster) => <input type="checkbox" aria-label={`Выбрать яму ${r.id}`} checked={picked.includes(r.id)} onClick={(e) => e.stopPropagation()} onChange={() => toggle(r.id)} className="h-4 w-4 accent-[var(--amber)]" /> }] : []),
                { key: 'id', title: '№', width: '60px', render: (r: Cluster) => r.id },
                { key: 'street', title: 'Улица', render: (r: Cluster) => <span className="font-medium">{r.street ?? `${r.lat.toFixed(4)}, ${r.lon.toFixed(4)}`}</span> },
                { key: 'type', title: 'Тип', render: (r: Cluster) => TYPE_NAMES[r.type] ?? r.type },
                { key: 'lvl', title: 'Уровень', render: (r: Cluster) => <Chip tone={LEVEL_TONE[r.level]}>{LEVEL_NAMES[r.level]}</Chip> },
                { key: 'st', title: 'Статус', render: (r: Cluster) => <Chip tone={STATUS_TONE[r.status]}>{STATUS_NAMES[r.status]}</Chip> },
                { key: 'p', title: 'Устр./проездов', render: (r: Cluster) => `${r.devices} / ${r.passes}` },
                { key: 't', title: 'Удар', render: (r: Cluster) => ago(r.last_hit) },
              ]} />
              <Pagination page={list.data.page} size={list.data.size} total={list.data.total} onPage={setPage} />
            </>
          )}
        </div>
        <Card className="max-h-[calc(100vh-220px)] overflow-auto xl:sticky xl:top-0">
          {open ? <ClusterPanel id={open} onChanged={() => undefined} /> : <p className="text-sm text-muted">Выберите строку, чтобы увидеть события, волны ударов и действия модерации.</p>}
        </Card>
      </div>
      <AddModal open={addOpen} onClose={() => setAddOpen(false)} onCreated={(c) => { setOpen(c.id); toast('Яма добавлена') }} />
    </div>
  )
}

function AddModal({ open, onClose, onCreated }: { open: boolean; onClose: () => void; onCreated: (c: Cluster) => void }) {
  const [lat, setLat] = useState('')
  const [lon, setLon] = useState('')
  const [type, setType] = useState('pothole')
  const [level, setLevel] = useState('mid')
  const [heading, setHeading] = useState('')
  const save = useSave((b: Record<string, unknown>) => api.post<Cluster>('/admin/clusters/create', b), {
    invalidate: ['/admin/clusters', '/admin/overview'], onDone: (c) => { onCreated(c); onClose() },
  })
  const bad = !lat || !lon || Number.isNaN(Number(lat)) || Number.isNaN(Number(lon))
  return (
    <Modal open={open} onClose={onClose} title="Добавить яму вручную">
      <div className="flex flex-col gap-3">
        <div className="grid grid-cols-2 gap-3">
          <Field label="Широта"><Input value={lat} onChange={(e) => setLat(e.target.value)} placeholder="41.3270" inputMode="decimal" /></Field>
          <Field label="Долгота"><Input value={lon} onChange={(e) => setLon(e.target.value)} placeholder="69.2284" inputMode="decimal" /></Field>
          <Field label="Тип"><Select value={type} onChange={(e) => setType(e.target.value)}>{Object.entries(TYPE_NAMES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
          <Field label="Уровень"><Select value={level} onChange={(e) => setLevel(e.target.value)}>{['light', 'mid', 'deep', 'danger'].map((k) => <option key={k} value={k}>{LEVEL_NAMES[k]}</option>)}</Select></Field>
          <Field label="Курс, ° (необязательно)" hint="0 — север, 90 — восток"><Input value={heading} onChange={(e) => setHeading(e.target.value)} inputMode="decimal" /></Field>
        </div>
        <p className="text-xs text-muted">Яма появится как подтверждённая человеком; к дорожной сети привяжется автоматически.</p>
        <div className="flex justify-end gap-2">
          <Button kind="ghost" onClick={onClose}>Отмена</Button>
          <Button kind="primary" disabled={bad || save.isPending} onClick={() => save.mutate({ lat: Number(lat), lon: Number(lon), type, level, heading: heading === '' ? undefined : Number(heading) })}>Добавить</Button>
        </div>
      </div>
    </Modal>
  )
}
