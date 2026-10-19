import { useState } from 'react'
import { Button, Card, CardTitle, Chip, ErrorBox, Field, Input, Modal, PageHeader, Spinner, Table } from '../components/ui'
import { api, type CarModel, type Dictionaries } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useGet, useSave } from '../lib/hooks'

const TITLES: Record<string, string> = {
  event_types: 'Типы событий', event_levels: 'Уровни ям', event_statuses: 'Статусы ям', road_classes: 'Классы дорог', surfaces: 'Покрытие', roughness_classes: 'Классы ровности A–E',
  suspension_classes: 'Классы подвески S1–S5', mounts: 'Положение телефона', roles: 'Роли устройств', trip_modes: 'Режимы поездки', complaint_statuses: 'Статусы жалоб', complaint_channels: 'Каналы жалоб',
  labels: 'Что это: варианты ответа и разметки', label_groups: 'Группы вариантов', road_ratings: 'Оценка дороги голосом',
}

export default function DictionariesPage() {
  const d = useGet<Dictionaries>('/dictionaries')
  return (
    <div>
      <PageHeader title="Справочники" sub="Все термины и коды системы. Значения закреплены в коде и едины для приложения, сервера и админки." />
      {d.isLoading && <Spinner />}
      {d.error && <ErrorBox error={d.error} onRetry={() => d.refetch()} />}
      {d.data && (
        <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {Object.entries(d.data).map(([k, v]) => (
            <Card key={k}>
              <CardTitle>{TITLES[k] ?? k}</CardTitle>
              <ul className="divide-y divide-line text-sm">{Object.entries(v).map(([code, name]) => <li key={code} className="flex gap-3 py-2"><code className="rounded bg-raised px-2 py-0.5 text-xs">{code}</code><span className="ml-auto">{name}</span></li>)}</ul>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}

export function CarModels() {
  const { can } = useAuth()
  const q = useGet<{ items: CarModel[] }>('/admin/car-models')
  const [edit, setEdit] = useState<Partial<CarModel> | null>(null)
  return (
    <Card>
      <CardTitle right={can('admin') ? <Button small kind="primary" onClick={() => setEdit({ brand: '', model: '', specs_verified: false })}>Добавить модель</Button> : undefined}>Модели автомобилей</CardTitle>
      <p className="mb-3 text-sm text-muted">Характеристики показываются в приложении и влияют на расчёты (колёсная база) только после проверки по источнику — «подтверждено» требует ссылку.</p>
      {q.isLoading && <Spinner />}
      {q.error && <ErrorBox error={q.error} />}
      {q.data && <Table rowKey={(r) => r.id} rows={q.data.items} onRow={can('admin') ? (r) => setEdit(r) : undefined} cols={[
        { key: 'r', title: '#', width: '50px', render: (r) => r.popularity_rank ?? '—' },
        { key: 'm', title: 'Модель', render: (r) => <b>{r.brand} {r.model}</b> },
        { key: 'wb', title: 'Колёсная база, мм', render: (r) => r.wheelbase_mm ?? <span className="text-muted">TODO</span> },
        { key: 'tire', title: 'Шины', render: (r) => r.tire_size || '—' },
        { key: 'ev', title: 'Тип', render: (r) => (r.is_ev ? 'электро' : 'ДВС / гибрид') },
        { key: 'v', title: 'Данные', render: (r) => (r.specs_verified ? <Chip tone="smooth">подтверждены</Chip> : <Chip tone="warn">не проверены</Chip>) },
        { key: 's', title: 'Источник', render: (r) => (r.source_url ? <a className="text-info hover:underline" href={r.source_url} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()}>ссылка</a> : '—') },
        { key: 'sm', title: 'Мягкость (мед.)', align: 'right', render: (r) => (r.softness_median == null ? '—' : `${r.softness_median.toFixed(0)} · ${r.softness_n_vehicles} маш.`) },
      ]} />}
      <CarModal item={edit} onClose={() => setEdit(null)} />
    </Card>
  )
}

function CarModal({ item, onClose }: { item: Partial<CarModel> | null; onClose: () => void }) {
  const [f, setF] = useState<Record<string, string | boolean>>({})
  const isNew = item !== null && item.id === undefined
  const save = useSave((b: Record<string, unknown>) => (isNew ? api.post<CarModel>('/admin/car-models/create', b) : api.patch<CarModel>(`/admin/car-models/${item?.id}/patch`, b)), {
    ok: 'Модель сохранена', invalidate: ['/admin/car-models'], onDone: () => { setF({}); onClose() },
  })
  const v = (k: keyof CarModel) => (f[k] ?? item?.[k] ?? '') as string
  const verified = (f.specs_verified ?? item?.specs_verified ?? false) as boolean
  return (
    <Modal open={item !== null} onClose={() => { setF({}); onClose() }} title={isNew ? 'Новая модель' : `${item?.brand} ${item?.model}`}>
      <div className="grid grid-cols-2 gap-3">
        <Field label="Марка"><Input value={v('brand')} onChange={(e) => setF({ ...f, brand: e.target.value })} /></Field>
        <Field label="Модель"><Input value={v('model')} onChange={(e) => setF({ ...f, model: e.target.value })} /></Field>
        <Field label="Колёсная база, мм"><Input type="number" value={v('wheelbase_mm')} onChange={(e) => setF({ ...f, wheelbase_mm: e.target.value })} /></Field>
        <Field label="Шины"><Input value={v('tire_size')} onChange={(e) => setF({ ...f, tire_size: e.target.value })} placeholder="205/60 R16" /></Field>
        <Field label="Диск, дюймы"><Input type="number" value={v('rim_inch')} onChange={(e) => setF({ ...f, rim_inch: e.target.value })} /></Field>
        <Field label="Место по продажам"><Input type="number" value={v('popularity_rank')} onChange={(e) => setF({ ...f, popularity_rank: e.target.value })} /></Field>
        <div className="col-span-2"><Field label="Ссылка на источник характеристик"><Input value={v('source_url')} onChange={(e) => setF({ ...f, source_url: e.target.value })} placeholder="https://…" /></Field></div>
        <label className="col-span-2 flex items-center gap-2 text-sm"><input type="checkbox" className="h-4 w-4 accent-[var(--amber)]" checked={verified} onChange={(e) => setF({ ...f, specs_verified: e.target.checked })} />Характеристики проверены по источнику</label>
        <label className="col-span-2 flex items-center gap-2 text-sm"><input type="checkbox" className="h-4 w-4 accent-[var(--amber)]" checked={(f.is_ev ?? item?.is_ev ?? false) as boolean} onChange={(e) => setF({ ...f, is_ev: e.target.checked })} />Электромобиль</label>
      </div>
      <div className="mt-4 flex justify-end gap-2">
        <Button kind="ghost" onClick={() => { setF({}); onClose() }}>Отмена</Button>
        <Button kind="primary" disabled={save.isPending || (!isNew && !Object.keys(f).length)} onClick={() => save.mutate(f)}>Сохранить</Button>
      </div>
    </Modal>
  )
}
