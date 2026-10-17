import { useState } from 'react'
import { Button, Card, Chip, ErrorBox, Field, Input, Modal, PageHeader, Pagination, Select, Spinner, Table } from '../components/ui'
import { api, ROLE_NAMES, type AuditRow, type Page, type StaffUser } from '../lib/api'
import { useAuth } from '../lib/auth'
import { fmtDateTime } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'

const ROLE_HELP: Record<string, string> = { admin: 'всё, включая доступы, дороги, машины, параметры алгоритма', labeler: 'модерация ям, разметка, жалобы, загрузка CSV', analyst: 'только просмотр' }

export default function Access() {
  const { me } = useAuth()
  const users = useGet<{ items: StaffUser[] }>('/admin/users')
  const [page, setPage] = useState(1)
  const audit = useGet<Page<AuditRow>>('/admin/audit', { page, size: 20 })
  const [create, setCreate] = useState(false)
  const [pw, setPw] = useState<StaffUser | null>(null)
  const patch = useSave((v: { id: number; body: Record<string, unknown> }) => api.patch<StaffUser>(`/admin/users/${v.id}/patch`, v.body), { ok: 'Сохранено', invalidate: ['/admin/users', '/admin/audit'] })
  return (
    <div>
      <PageHeader title="Доступы" sub="Сотрудники и роли. Роль определяет, что можно менять." right={<Button kind="primary" onClick={() => setCreate(true)}>Новый сотрудник</Button>} />
      <div className="mb-4 grid gap-3 md:grid-cols-3">
        {Object.entries(ROLE_HELP).map(([k, v]) => <Card key={k}><Chip tone="info">{ROLE_NAMES[k as keyof typeof ROLE_NAMES]}</Chip><p className="mt-2 text-sm text-muted">{v}</p></Card>)}
      </div>
      {users.isLoading && <Spinner />}
      {users.error && <ErrorBox error={users.error} onRetry={() => users.refetch()} />}
      {users.data && (
        <Table rowKey={(r) => r.id} rows={users.data.items} cols={[
          { key: 'u', title: 'Логин', render: (r) => <b>{r.username}{r.username === me?.username ? ' (вы)' : ''}</b> },
          { key: 'r', title: 'Роль', render: (r) => (
            <Select value={r.role ?? ''} disabled={r.username === me?.username} onChange={(e) => patch.mutate({ id: r.id, body: { role: e.target.value } })} aria-label={`Роль ${r.username}`}>
              {Object.entries(ROLE_NAMES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </Select>) },
          { key: 'a', title: 'Статус', render: (r) => <Chip tone={r.is_active ? 'smooth' : 'crater'}>{r.is_active ? 'активен' : 'отключён'}</Chip> },
          { key: 'l', title: 'Последний вход', render: (r) => fmtDateTime(r.last_login) },
          { key: 'x', title: '', align: 'right', render: (r) => (
            <div className="flex justify-end gap-2">
              <Button small onClick={() => setPw(r)}>Сменить пароль</Button>
              <Button small kind={r.is_active ? 'danger' : 'secondary'} disabled={r.username === me?.username} onClick={() => patch.mutate({ id: r.id, body: { is_active: !r.is_active } })}>{r.is_active ? 'Отключить' : 'Включить'}</Button>
            </div>) },
        ]} />
      )}
      <h2 className="mb-3 mt-8 text-base font-semibold">Журнал действий</h2>
      {audit.data && (
        <>
          <Table rowKey={(r) => r.id} rows={audit.data.items} empty="Записей нет" cols={[
            { key: 't', title: 'Когда', render: (r) => fmtDateTime(r.at) }, { key: 'u', title: 'Кто', render: (r) => r.user ?? '—' },
            { key: 'a', title: 'Действие', render: (r) => <code className="text-xs">{r.action}</code> }, { key: 'g', title: 'Объект', render: (r) => r.target },
            { key: 'p', title: 'Детали', render: (r) => <span className="line-clamp-1 max-w-md text-xs text-muted">{JSON.stringify(r.payload)}</span> },
          ]} />
          <Pagination page={audit.data.page} size={audit.data.size} total={audit.data.total} onPage={setPage} />
        </>
      )}
      <CreateModal open={create} onClose={() => setCreate(false)} />
      <PasswordModal user={pw} onClose={() => setPw(null)} />
    </div>
  )
}

function CreateModal({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [u, setU] = useState('')
  const [p, setP] = useState('')
  const [role, setRole] = useState('labeler')
  const save = useSave(() => api.post('/admin/users/create', { username: u, password: p, role }), { ok: 'Сотрудник создан', invalidate: ['/admin/users', '/admin/audit'], onDone: () => { setU(''); setP(''); onClose() } })
  return (
    <Modal open={open} onClose={onClose} title="Новый сотрудник">
      <div className="flex flex-col gap-3">
        <Field label="Логин"><Input value={u} onChange={(e) => setU(e.target.value)} autoComplete="off" /></Field>
        <Field label="Пароль" hint="Не короче 10 символов, не из распространённых и не только из цифр"><Input type="password" value={p} onChange={(e) => setP(e.target.value)} autoComplete="new-password" /></Field>
        <Field label="Роль"><Select value={role} onChange={(e) => setRole(e.target.value)}>{Object.entries(ROLE_NAMES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
        <div className="flex justify-end gap-2"><Button kind="ghost" onClick={onClose}>Отмена</Button><Button kind="primary" disabled={!u || !p || save.isPending} onClick={() => save.mutate(undefined)}>Создать</Button></div>
      </div>
    </Modal>
  )
}

function PasswordModal({ user, onClose }: { user: StaffUser | null; onClose: () => void }) {
  const [p, setP] = useState('')
  const save = useSave(() => api.post(`/admin/users/${user?.id}/password`, { password: p }), { ok: 'Пароль изменён', invalidate: ['/admin/audit'], onDone: () => { setP(''); onClose() } })
  return (
    <Modal open={user !== null} onClose={onClose} title={`Пароль: ${user?.username ?? ''}`}>
      <div className="flex flex-col gap-3">
        <Field label="Новый пароль"><Input type="password" value={p} onChange={(e) => setP(e.target.value)} autoComplete="new-password" /></Field>
        <div className="flex justify-end gap-2"><Button kind="ghost" onClick={onClose}>Отмена</Button><Button kind="primary" disabled={!p || save.isPending} onClick={() => save.mutate(undefined)}>Сменить</Button></div>
      </div>
    </Modal>
  )
}
