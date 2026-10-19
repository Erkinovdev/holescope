import { useState } from 'react'
import { Button, Card, CardTitle, ErrorBox, Field, Input, Kpi, PageHeader, Select, Spinner, useToast } from '../components/ui'
import { Icon } from '../components/icons'
import { api } from '../lib/api'
import { useAuth } from '../lib/auth'
import { fmtNum } from '../lib/format'
import { useGet, useSave } from '../lib/hooks'

interface Ch { id: number; title: string; kind: string; kind_name: string; target: number; done: number; percent: number; district: string | null; starts: string; ends: string | null; days_left: number | null; reward: string; archived: boolean; participants: number }
interface Resp { items: Ch[]; summary: { active: number; participants: number; completed: number; avg_percent: number }; districts: { code: string; name: string }[] }
const KINDS: [string, string][] = [['confirmed', 'Подтверждённые ямы'], ['km', 'Километры'], ['trips', 'Поездки'], ['marks', 'Ответы водителей']]
const COLORS = ['var(--amber)', 'var(--smooth)', 'var(--info)', 'var(--warn)']
const today = () => new Date().toISOString().slice(0, 10)

export default function Challenges() {
  const { can } = useAuth()
  const toast = useToast()
  const q = useGet<Resp>('/admin/challenges')
  const [f, setF] = useState({ title: '', kind: 'confirmed', target: '100', district: '', starts: today(), ends: '', reward: '' })
  const create = useSave(() => api.post('/admin/challenges/create', { ...f, target: Number(f.target), district: f.district || undefined, ends: f.ends || undefined }), {
    invalidate: ['/admin/challenges'], onDone: () => { toast('Челлендж создан', 'ok'); setF({ ...f, title: '', reward: '' }) } })
  const archive = useSave((b: { id: number; archived: boolean }) => api.post(`/admin/challenges/${b.id}/patch`, { archived: b.archived }), { invalidate: ['/admin/challenges'] })
  const d = q.data
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <div>
      <PageHeader title="Челленджи" sub="Общие цели для водителей: прогресс считается по реальным поездкам, ямам и ответам" />
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} onRetry={() => q.refetch()} />}
      {d && (
        <div className="flex flex-col gap-4">
          <div className="flex flex-wrap gap-4">
            <Kpi label="Активных челленджей" value={d.summary.active} icon="trophy" />
            <Kpi label="Водителей в периодах" value={fmtNum(d.summary.participants)} tone="info" icon="phone" />
            <Kpi label="Выполнено целей" value={d.summary.completed} tone="smooth" icon="check" />
            <Kpi label="Средний прогресс" value={`${d.summary.avg_percent}%`} tone="warn" icon="pulse" />
          </div>
          <div className="grid gap-4 xl:grid-cols-[1fr_380px]">
            <Card>
              <CardTitle>Челленджи</CardTitle>
              {!d.items.length && <p className="text-sm text-muted">Пока нет ни одного. Создайте первый справа.</p>}
              <ul className="flex flex-col gap-3">
                {d.items.map((c, i) => (
                  <li key={c.id} className={`flex items-center gap-4 rounded-2xl bg-raised p-4 ${c.archived ? 'opacity-50' : ''}`}>
                    <span className="grid h-12 w-12 shrink-0 place-items-center rounded-xl bg-surface" style={{ color: COLORS[i % 4] }}><Icon name="trophy" size={24} /></span>
                    <div className="min-w-0 flex-1">
                      <div className="truncate font-semibold">{c.title}</div>
                      <div className="mt-2 h-2 rounded-full bg-surface"><div className="h-full rounded-full" style={{ width: `${c.percent}%`, background: COLORS[i % 4] }} /></div>
                      <div className="mt-1.5 text-xs text-muted">{fmtNum(c.done, c.kind === 'km' ? 1 : 0)} / {c.target} · {c.kind_name}{c.district ? ` · ${c.district}` : ''} · {c.participants} водит.{c.days_left != null ? ` · ${c.days_left >= 0 ? `${c.days_left} дн.` : 'срок вышел'}` : ' · без срока'}{c.reward ? ` · награда: ${c.reward}` : ''}</div>
                    </div>
                    <span className="rounded-full bg-surface px-3 py-1 text-xs font-bold">{c.percent}%</span>
                    {can('admin') && <Button small kind="ghost" onClick={() => archive.mutate({ id: c.id, archived: !c.archived })}>{c.archived ? 'Вернуть' : 'В архив'}</Button>}
                  </li>
                ))}
              </ul>
            </Card>
            {can('admin') && (
              <Card>
                <CardTitle>Новый челлендж</CardTitle>
                <div className="flex flex-col gap-3">
                  <Field label="Название"><Input value={f.title} onChange={set('title')} placeholder="Подтвердить 150 ям · Юнусабад" /></Field>
                  <Field label="Что считаем"><Select value={f.kind} onChange={set('kind')}>{KINDS.map(([k, n]) => <option key={k} value={k}>{n}</option>)}</Select></Field>
                  <Field label="Цель"><Input type="number" min={1} value={f.target} onChange={set('target')} /></Field>
                  {f.kind === 'confirmed' && <Field label="Район (необязательно)"><Select value={f.district} onChange={set('district')}><option value="">весь город</option>{d.districts.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</Select></Field>}
                  <div className="grid grid-cols-2 gap-3"><Field label="С"><Input type="date" value={f.starts} onChange={set('starts')} /></Field><Field label="По (необязательно)"><Input type="date" value={f.ends} onChange={set('ends')} /></Field></div>
                  <Field label="Награда (текст)"><Input value={f.reward} onChange={set('reward')} placeholder="значок «Охотник за ямами»" /></Field>
                  <Button kind="primary" loading={create.isPending} disabled={!f.title.trim() || !Number(f.target)} onClick={() => create.mutate(undefined)}>Создать</Button>
                  <p className="text-xs text-muted">Значки и уведомления водителям пока не подключены — это цели с прогрессом.</p>
                </div>
              </Card>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
