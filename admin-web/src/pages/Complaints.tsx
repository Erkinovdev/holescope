import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Button, Chip, ErrorBox, Field, Input, Modal, PageHeader, Pagination, Select, Spinner, Table, Textarea } from '../components/ui'
import { api, type Complaint, type Page } from '../lib/api'
import { useAuth } from '../lib/auth'
import { fmtDateTime } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'

const STATUS: Record<string, string> = { draft: 'черновик', filed: 'подана', review: 'рассмотрение', answered: 'дан ответ', fixed: 'исправлено', rejected: 'отклонена' }
const TONE: Record<string, 'smooth' | 'warn' | 'crater' | 'info' | 'muted' | 'amber'> = { draft: 'muted', filed: 'amber', review: 'info', answered: 'smooth', fixed: 'smooth', rejected: 'crater' }

export default function Complaints() {
  const [page, setPage] = useState(1)
  const [status, setStatus] = useState('')
  const [open, setOpen] = useState<Complaint | null>(null)
  useEffect(() => setPage(1), [status])
  const q = useGet<Page<Complaint>>('/admin/complaints', { page, size: 30, status })
  return (
    <div>
      <PageHeader title="Жалобы" sub="Текст и координаты готовятся автоматически. Подача в Xalq Nazorati и другие системы пока ручная: введите номер обращения после подачи (интеграция — TODO)." />
      <div className="mb-4 max-w-xs"><Field label="Статус"><Select value={status} onChange={(e) => setStatus(e.target.value)}><option value="">все</option>{Object.entries(STATUS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field></div>
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      {q.data && (
        <>
          <Table rowKey={(r) => r.id} rows={q.data.items} empty="Жалоб нет" onRow={setOpen} cols={[
            { key: 'id', title: '№', width: '60px', render: (r) => r.id },
            { key: 's', title: 'Улица', render: (r) => <span className="font-medium">{r.street ?? `яма #${r.cluster_id}`}</span> },
            { key: 'c', title: 'Канал', render: (r) => r.channel },
            { key: 'st', title: 'Статус', render: (r) => <Chip tone={TONE[r.status]}>{STATUS[r.status] ?? r.status}</Chip> },
            { key: 'n', title: 'Номер обращения', render: (r) => r.external_number || <span className="text-muted">нет</span> },
            { key: 'f', title: 'Подана', render: (r) => fmtDateTime(r.filed_at) },
            { key: 'd', title: 'Срок ответа', render: (r) => fmtDateTime(r.due_at) },
          ]} />
          <Pagination page={q.data.page} size={q.data.size} total={q.data.total} onPage={setPage} />
        </>
      )}
      <ComplaintModal item={open} onClose={() => setOpen(null)} />
    </div>
  )
}

function ComplaintModal({ item, onClose }: { item: Complaint | null; onClose: () => void }) {
  const { can } = useAuth()
  const [f, setF] = useState<Record<string, string>>({})
  useEffect(() => setF({}), [item?.id])
  const save = useSave((b: Record<string, unknown>) => api.patch<Complaint>(`/admin/complaints/${item?.id}/patch`, b), { ok: 'Жалоба обновлена', invalidate: ['/admin/complaints', '/admin/overview'], onDone: onClose })
  if (!item) return <Modal open={false} onClose={onClose} title="" children={null} />
  const v = (k: keyof Complaint) => f[k] ?? String(item[k] ?? '')
  const due = f.due_at ?? (item.due_at ? item.due_at.slice(0, 10) : '')
  return (
    <Modal open onClose={onClose} title={`Жалоба №${item.id}`} width="max-w-2xl">
      <div className="flex flex-col gap-3">
        <p className="text-sm text-muted">Яма <Link className="text-info hover:underline" to={`/events?focus=${item.cluster_id}`}>#{item.cluster_id}</Link> · статус ямы: {item.cluster_status}</p>
        <Field label="Текст обращения"><Textarea disabled={!can('labeler')} value={v('text')} onChange={(e) => setF({ ...f, text: e.target.value })} rows={6} /></Field>
        <div className="grid grid-cols-3 gap-3">
          <Field label="Статус"><Select disabled={!can('labeler')} value={v('status')} onChange={(e) => setF({ ...f, status: e.target.value })}>{Object.entries(STATUS).map(([k, s]) => <option key={k} value={k}>{s}</option>)}</Select></Field>
          <Field label="Номер обращения"><Input disabled={!can('labeler')} value={v('external_number')} onChange={(e) => setF({ ...f, external_number: e.target.value })} /></Field>
          <Field label="Срок ответа"><Input disabled={!can('labeler')} type="date" value={due} onChange={(e) => setF({ ...f, due_at: e.target.value })} /></Field>
        </div>
        <div className="flex justify-end gap-2">
          <Button kind="ghost" onClick={onClose}>Закрыть</Button>
          {can('labeler') && <Button kind="primary" disabled={!Object.keys(f).length || save.isPending} onClick={() => save.mutate({ ...f, due_at: f.due_at === undefined ? undefined : (f.due_at ? `${f.due_at}T12:00:00+05:00` : null) })}>Сохранить</Button>}
        </div>
      </div>
    </Modal>
  )
}
