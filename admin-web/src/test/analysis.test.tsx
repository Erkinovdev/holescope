import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { cleanup, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AnalysisBlock } from '../components/Analysis'
import { ToastProvider } from '../components/ui'
import { tokenStore, type Analysis, type Calibration } from '../lib/api'
import { AuthProvider } from '../lib/auth'
import CalibrationTab from '../pages/Calibration'
import { mockApi } from './mockApi'

const analysis: Analysis = {
  guess: { top: 'manhole', ranked: [{ type: 'manhole', name: 'люк', p: 0.62 }, { type: 'pothole', name: 'яма', p: 0.25 }], reasons: ['удар на 100% проездов — постоянный объект, а не яма на одной полосе'], matches_current: false },
  context: { c_hit_rate: 1, c_score_cv: 0.12, c_speed_slope: 0.1, c_passes: 8, c_devices: 3, c_low_speed: 0.4 },
  votes: [{ label: 'manhole_sunk', name: 'Люк просел', n: 2 }],
  level: { current: 'mid', score: 7.2, bounds: [5, 8, 14], calibrated: false, text: 'Сила удара 7.2 → уровень «средняя»; до «глубокая» ещё 0.8' },
  roughness: { cls: 'D', name: 'плохая', ri: 0.11, passes: 14, devices: 4, road: 'ул. Навои', road_class: 'A', surface: 'asphalt', flags: ['трамвай'] },
}

const calib = (o: Partial<Calibration['levels']> = {}): Calibration => ({
  levels: { n: 41, counts: { light: 19, mid: 17, deep: 5, danger: 0 }, current: [5, 8, 14], suggested: [3.1, 6.04, 8.49], acc_current: 0.56, acc_suggested: 0.61, cv_current: 0.5, cv_suggested: 0.52, significant: false, active: false, default: [5, 8, 14], ...o },
  ri: { stats: Object.fromEntries('ABCDE'.split('').map((c) => [c, { n: 0, median: null, p25: null, p75: null }])), current: [0.03, 0.05, 0.08, 0.13], suggested: null, enough: false, names: { A: 'Ровная', B: 'Хорошая', C: 'Удовлетворительная', D: 'Плохая', E: 'Разбитая' } },
})

function wrap(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return render(<QueryClientProvider client={qc}><ToastProvider><AuthProvider><MemoryRouter>{ui}</MemoryRouter></AuthProvider></ToastProvider></QueryClientProvider>)
}

beforeEach(() => { localStorage.clear(); document.documentElement.dataset.theme = 'dark' })
afterEach(() => { cleanup(); vi.unstubAllGlobals() })

describe('разбор объекта', () => {
  it('показывает вероятности, причины, голоса, уровень и дорогу; предупреждает о расхождении с картой', () => {
    render(<AnalysisBlock a={analysis} currentType="pothole" />)
    expect(screen.getByText('62%')).toBeInTheDocument()
    expect(screen.getByText(/постоянный объект/)).toBeInTheDocument()
    expect(screen.getByText('Люк просел × 2')).toBeInTheDocument()
    expect(screen.getByText(/до «глубокая» ещё 0.8/)).toBeInTheDocument()
    expect(screen.getByText('ул. Навои')).toBeInTheDocument()
    expect(screen.getByText(/склоняются к «люк»/)).toBeInTheDocument()
  })
})

describe('калибровка', () => {
  it('предложение без подтверждения на отложенных данных нельзя применить', async () => {
    tokenStore.set('t')
    mockApi({ 'GET /admin/me': { username: 'boss', role: 'admin', role_name: 'админ' }, 'GET /admin/brain/calibration': calib() })
    wrap(<CalibrationTab />)
    expect(await screen.findByText('Уровни ям по силе удара')).toBeInTheDocument()
    const buttons = await screen.findAllByRole('button', { name: 'Применить предложение' })
    expect(buttons[0]).toBeDisabled()
    expect(screen.getByText(/не лучше текущих границ на отложенных данных/)).toBeInTheDocument()
  })

  it('значимое предложение применяется с выбранными границами', async () => {
    const user = userEvent.setup()
    tokenStore.set('t')
    const calls = mockApi({
      'GET /admin/me': { username: 'boss', role: 'admin', role_name: 'админ' },
      'GET /admin/brain/calibration': calib({ significant: true, cv_suggested: 0.7 }),
      'POST /admin/brain/calibration/apply': { version: 'levels-1', events: 3, clusters: 1, bounds: [3.1, 6.04, 8.49] },
    })
    wrap(<CalibrationTab />)
    const btn = (await screen.findAllByRole('button', { name: 'Применить предложение' }))[0]
    await waitFor(() => expect(btn).toBeEnabled())
    await user.click(btn)
    await waitFor(() => expect(calls.some((c) => c.method === 'POST' && (c.body as { kind: string }).kind === 'levels' && JSON.stringify((c.body as { bounds: number[] }).bounds) === '[3.1,6.04,8.49]')).toBe(true))
  })
})
