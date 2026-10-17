import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { cleanup, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { layout3d } from '../components/Brain3D'
import { BarChart, LineChart } from '../components/Charts'
import { ToastProvider } from '../components/ui'
import App from '../App'
import { ApiError, api, tokenStore } from '../lib/api'
import { AuthProvider } from '../lib/auth'
import { ago, fmtDateTime, fmtNum } from '../lib/format'
import Events from '../pages/Events'
import Overview from '../pages/Overview'
import { mockApi, status } from './mockApi'

// WebGL/карта в jsdom недоступны — подменяем тяжёлые компоненты
vi.mock('../components/MapView', () => ({ default: () => <div data-testid="map" /> }))
vi.mock('../components/Brain3D', async (orig) => ({ ...(await orig<typeof import('../components/Brain3D')>()), default: () => <div data-testid="brain3d" /> }))

const cluster = (o: Record<string, unknown> = {}) => ({
  id: 7, lat: 41.327, lon: 69.2284, heading: 90, type: 'pothole', level: 'deep', status: 'confirmed', passes: 7, devices: 3, quiet_passes: 0, confidence: 0.9, score_median: 6.2,
  safe_speed: 30, first_seen: '2026-10-14T10:00:00Z', last_hit: '2026-10-16T10:00:00Z', fixed_at: null, street: 'ул. Навои', road: 'A001', segment: 'A001-0012', district: 'Юнусабадский район', ...o,
})
const detail = { ...cluster(), events: [{ id: 1, at: '2026-10-16T10:00:00Z', device: 'Тихий Сокол', device_id: 4, speed_kmh: 41, peak: 6.1, score: 6.2, type: 'pothole', level: 'deep', confidence: 0.6, user_label: '', trip: 2, wave: [0, 1, -2, 3, 0], algo_version: '2.0.0', features: {} }], type_votes: {}, complaints: 0, quiet: [] }
const overview = {
  days: 30, kpi: { trips: 12, km: 345.6, events: 400, clusters_total: 80, confirmed: 30, fixed: 4, candidates: 40, devices_active: 5, devices_total: 9, labels: 77 },
  queues: { candidates_single: 21, questions_open: 6, complaints_to_file: 2 },
  series: Array.from({ length: 30 }, (_, i) => ({ day: `2026-09-${String(i + 1).padStart(2, '0')}`, trips: i % 3, km: i, events: i * 2, clusters: i % 4 })), recent: [cluster()],
}

function wrap(ui: React.ReactElement, path = '/') {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}><ToastProvider><AuthProvider><MemoryRouter initialEntries={[path]}>{ui}</MemoryRouter></AuthProvider></ToastProvider></QueryClientProvider>,
  )
}

beforeEach(() => { localStorage.clear(); document.documentElement.dataset.theme = 'dark' })
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('форматирование', () => {
  it('числа и даты по-русски', () => {
    expect(fmtNum(1234.5, 1)).toBe('1 234,5')
    expect(fmtNum(null)).toBe('—')
    expect(fmtDateTime(null)).toBe('—')
    expect(fmtDateTime('мусор')).toBe('—')
    expect(ago('2026-10-17T10:00:00Z', new Date('2026-10-17T10:00:30Z').getTime())).toBe('только что')
    expect(ago('2026-10-17T10:00:00Z', new Date('2026-10-17T13:00:00Z').getTime())).toBe('3 ч назад')
  })
})

describe('API-клиент', () => {
  it('отправляет токен и разбирает ошибку сервера', async () => {
    tokenStore.set('abc')
    const calls = mockApi({ 'GET /admin/me': status(403, { error: 'forbidden' }) })
    await expect(api.get('/admin/me')).rejects.toMatchObject({ message: 'forbidden', status: 403 })
    expect(calls[0].headers.Authorization).toBe('Bearer abc')
  })
  it('401 очищает токен и вызывает выход', async () => {
    tokenStore.set('abc')
    mockApi({ 'GET /admin/overview': status(401, { error: 'unauthorized' }) })
    await expect(api.get('/admin/overview')).rejects.toBeInstanceOf(ApiError)
    expect(tokenStore.get()).toBeNull()
  })
  it('нет сети — понятная ошибка', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => { throw new TypeError('x') }))
    await expect(api.get('/admin/me')).rejects.toMatchObject({ message: 'Нет связи с сервером', status: 0 })
  })
})

describe('вход и роли', () => {
  it('форма входа → обзор; неверный пароль показывает ошибку', async () => {
    const user = userEvent.setup()
    mockApi({
      'POST /admin/login': ({ body }: { body: unknown }) => ((body as { password: string }).password === 'good-password-1' ? { token: 't1', user: { username: 'boss', role: 'admin', role_name: 'админ' } } : status(401, { error: 'неверный логин или пароль' })),
      'GET /admin/overview': overview,
    })
    render(<App />)
    await user.type(await screen.findByLabelText('Логин'), 'boss')
    await user.type(screen.getByLabelText('Пароль'), 'bad')
    await user.click(screen.getByRole('button', { name: 'Войти' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('неверный логин или пароль')
    await user.clear(screen.getByLabelText('Пароль'))
    await user.type(screen.getByLabelText('Пароль'), 'good-password-1')
    await user.click(screen.getByRole('button', { name: 'Войти' }))
    expect(await screen.findByRole('heading', { name: 'Обзор' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Доступы' })).toBeInTheDocument()    // админу видно
    expect(tokenStore.get()).toBe('t1')
  })

  it('разметчик не видит «Доступы»; выход возвращает форму входа', async () => {
    const user = userEvent.setup()
    tokenStore.set('t2')
    mockApi({ 'GET /admin/me': { username: 'lab', role: 'labeler', role_name: 'разметчик' }, 'GET /admin/overview': overview })
    render(<App />)
    expect(await screen.findByRole('heading', { name: 'Обзор' })).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Доступы' })).not.toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Мозг' })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Выйти' }))
    expect(await screen.findByLabelText('Логин')).toBeInTheDocument()
    expect(tokenStore.get()).toBeNull()
  })

  it('просроченный токен → форма входа', async () => {
    tokenStore.set('old')
    mockApi({ 'GET /admin/me': status(401, { error: 'unauthorized' }) })
    render(<App />)
    expect(await screen.findByLabelText('Логин')).toBeInTheDocument()
  })
})

describe('обзор', () => {
  it('показывает KPI, очередь и последние ямы', async () => {
    tokenStore.set('t')
    mockApi({ 'GET /admin/me': { username: 'a', role: 'analyst', role_name: 'аналитик' }, 'GET /admin/overview': overview })
    wrap(<Overview />)
    expect(await screen.findByText('345,6')).toBeInTheDocument()
    expect(screen.getByText('Кандидаты с одним проездом')).toBeInTheDocument()
    expect(screen.getByText('21')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'ул. Навои' })).toHaveAttribute('href', '/events?focus=7')
  })
  it('ошибка сервера → сообщение и кнопка «Повторить»', async () => {
    mockApi({ 'GET /admin/overview': status(500, { error: 'сервер лёг' }) })
    wrap(<Overview />)
    expect(await screen.findByRole('alert')).toHaveTextContent('сервер лёг')
    expect(screen.getByRole('button', { name: 'Повторить' })).toBeInTheDocument()
  })
})

describe('модерация ям', () => {
  it('аналитик видит данные, но не кнопки правки; разметчик может подтвердить', async () => {
    const user = userEvent.setup()
    tokenStore.set('t')
    const calls = mockApi({
      'GET /admin/me': { username: 'lab', role: 'labeler', role_name: 'разметчик' },
      'GET /admin/clusters': { items: [cluster(), cluster({ id: 8, status: 'candidate', street: 'ул. Бабура', level: 'light', passes: 1, devices: 1 })], total: 2, page: 1, size: 25 },
      'GET /admin/clusters/8': { ...detail, id: 8, status: 'candidate', street: 'ул. Бабура' },
      'PATCH /admin/clusters/8/patch': cluster({ id: 8, status: 'confirmed' }),
    })
    wrap(<Events />)
    // роль подтягивается из /admin/me
    expect(await screen.findByText('ул. Бабура')).toBeInTheDocument()
    await user.click(screen.getByText('ул. Бабура'))
    const confirm = await screen.findByRole('button', { name: 'Подтвердить' })
    await user.click(confirm)
    await waitFor(() => expect(calls.some((c) => c.method === 'PATCH' && c.path === '/admin/clusters/8/patch' && (c.body as { status: string }).status === 'confirmed')).toBe(true))
  })

  it('объединение требует выбрать ≥2 ямы', async () => {
    const user = userEvent.setup()
    tokenStore.set('t')
    const calls = mockApi({
      'GET /admin/me': { username: 'lab', role: 'labeler', role_name: 'разметчик' },
      'GET /admin/clusters': { items: [cluster(), cluster({ id: 8, street: 'ул. Бабура' })], total: 2, page: 1, size: 25 },
      'POST /admin/clusters/merge': cluster({ id: 7, passes: 8 }),
      'GET /admin/clusters/7': detail,
    })
    wrap(<Events />)
    const merge = await screen.findByRole('button', { name: /Объединить/ })
    expect(merge).toBeDisabled()
    await user.click(await screen.findByLabelText('Выбрать яму 7'))
    await user.click(screen.getByLabelText('Выбрать яму 8'))
    expect(merge).toBeEnabled()
    await user.click(merge)
    await waitFor(() => expect(calls.find((c) => c.path === '/admin/clusters/merge')?.body).toEqual({ ids: [7, 8] }))
  })

  it('аналитику кнопки модерации недоступны', async () => {
    const user = userEvent.setup()
    tokenStore.set('t')
    mockApi({
      'GET /admin/me': { username: 'ana', role: 'analyst', role_name: 'аналитик' },
      'GET /admin/clusters': { items: [cluster()], total: 1, page: 1, size: 25 }, 'GET /admin/clusters/7': detail,
    })
    wrap(<Events />)
    await user.click(await screen.findByText('ул. Навои'))
    expect(await screen.findByText('События (1)')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Подтвердить' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Добавить яму' })).not.toBeInTheDocument()
  })
})

describe('графики и 3D', () => {
  it('столбчатый график подписывает значения', () => {
    const { container } = render(<BarChart data={[{ label: '01.10', value: 5 }, { label: '02.10', value: 0 }]} />)
    expect(container.querySelectorAll('rect')).toHaveLength(2)
    expect(container.querySelector('title')?.textContent).toContain('01.10: 5')
  })
  it('линейный график пропускает пустые точки', () => {
    const { container } = render(<LineChart labels={['a', 'b', 'c']} series={[{ name: 'F1', color: 'red', points: [0.5, null, 0.8] }]} />)
    expect(container.querySelectorAll('circle')).toHaveLength(2)
  })
  it('раскладка графа: детерминирована, конечна, связанные узлы ближе несвязанных', () => {
    const nodes = Array.from({ length: 6 }, (_, i) => ({ id: `n${i}`, kind: 'cluster', label: `n${i}`, size: 1, confidence: 1 }))
    const edges = [{ a: 'n0', b: 'n1', kind: 'x', w: 1 }, { a: 'n1', b: 'n2', kind: 'x', w: 1 }, { a: 'n0', b: 'n2', kind: 'x', w: 1 }]
    const p1 = layout3d(nodes, edges), p2 = layout3d(nodes, edges)
    expect(Array.from(p1)).toEqual(Array.from(p2))
    expect(Array.from(p1).every(Number.isFinite)).toBe(true)
    const d = (a: number, b: number) => Math.hypot(p1[a * 3] - p1[b * 3], p1[a * 3 + 1] - p1[b * 3 + 1], p1[a * 3 + 2] - p1[b * 3 + 2])
    expect(d(0, 1)).toBeLessThan(d(0, 5))
    expect(layout3d([], [])).toHaveLength(0)
  })
})

describe('«Мозг»', () => {
  const summary = { current: { events: 37, clusters: 27, confirmed: 5, labels: 77, questions_open: 2, devices: 3, vehicles: 1, active_algo: 'rules 2.0.0', segments: 311765, segments_scored: 200, trips: 3, uploads: 1 }, history: [] }
  const timeline = {
    runs: [{ id: 1, at: '2026-10-17T10:00:00Z', n_labels: 72, metrics: {}, log: 'ok: версия gbm-1 сохранена неактивной', version: 'gbm-1' }], snapshots: [],
    versions: [{ id: 5, version: 'gbm-1', kind: 'gbm', active: false, metrics: { activated: false, cv: 'blocks-of-one-trip', model: { f1: 0.81 }, rules: { f1: 0.84 } }, notes: 'не включена', created: '2026-10-17T10:00:00Z', params: {} }], base: { version: 'rules 2.0.0', f1: 0.84 },
  }
  it('вкладка версий: метрики и подтверждение ручного включения', async () => {
    const user = userEvent.setup()
    tokenStore.set('t')
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true)
    const calls = mockApi({
      'GET /admin/me': { username: 'boss', role: 'admin', role_name: 'админ' }, 'GET /admin/brain/summary': summary, 'GET /admin/brain/timeline': timeline,
      'GET /admin/brain/graph': { nodes: [], edges: [], counts: { clusters: 0, nodes: 0, edges: 0 } }, 'POST /admin/brain/activate': {},
    })
    const { default: Brain } = await import('../pages/Brain')
    wrap(<Brain />)
    expect(await screen.findByText(/311\s765/)).toBeInTheDocument()
    await user.click(screen.getByRole('tab', { name: 'Версии и метрики' }))
    const row = (await screen.findByText('gbm-1', { selector: 'b' })).closest('tr')!
    expect(within(row).getByText('0.81 / 0.84')).toBeInTheDocument()
    expect(within(row).getByText('блоки одной поездки (слабая)')).toBeInTheDocument()
    await user.click(within(row).getByRole('button', { name: 'Включить' }))
    expect(confirmSpy).toHaveBeenCalled()
    await waitFor(() => expect(calls.find((c) => c.path === '/admin/brain/activate')?.body).toEqual({ version_id: 5, force: true }))
  })
  it('вкладка графа без данных объясняет, чего ждать', async () => {
    tokenStore.set('t')
    mockApi({ 'GET /admin/me': { username: 'a', role: 'analyst', role_name: 'аналитик' }, 'GET /admin/brain/summary': summary, 'GET /admin/brain/graph': { nodes: [], edges: [], counts: { clusters: 0, nodes: 0, edges: 0 } } })
    const { default: Brain } = await import('../pages/Brain')
    wrap(<Brain />)
    expect(await screen.findByText(/Данных для графа пока нет/)).toBeInTheDocument()
  })
})
