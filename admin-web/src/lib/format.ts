const pad = (n: number) => String(n).padStart(2, '0')

export function fmtDateTime(iso: string | null | undefined): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return `${pad(d.getDate())}.${pad(d.getMonth() + 1)}.${d.getFullYear()} ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function fmtDate(iso: string | null | undefined): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return Number.isNaN(d.getTime()) ? '—' : `${pad(d.getDate())}.${pad(d.getMonth() + 1)}`
}

export function fmtNum(v: number | null | undefined, digits = 0): string {
  if (v === null || v === undefined || Number.isNaN(v)) return '—'
  return v.toLocaleString('ru-RU', { minimumFractionDigits: digits, maximumFractionDigits: digits })
}

export function ago(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return '—'
  const s = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000))
  if (s < 90) return 'только что'
  if (s < 3600) return `${Math.round(s / 60)} мин назад`
  if (s < 86400) return `${Math.round(s / 3600)} ч назад`
  return `${Math.round(s / 86400)} дн назад`
}

export const TYPE_NAMES: Record<string, string> = { pothole: 'яма', bump: 'лежачий', manhole: 'люк', joint: 'стык / шов', rail_tram: 'рельсы трамвая', rail_train: 'ж/д переезд', rough_patch: 'волнистость', rutting: 'колея', broken: 'разбитый участок', patch: 'заплатка', crack: 'трещина', cobble: 'брусчатка' }
export const LEVEL_NAMES: Record<string, string> = { light: 'лёгкая', mid: 'средняя', deep: 'глубокая', danger: 'опасная', '': '—' }
export const STATUS_NAMES: Record<string, string> = { candidate: 'кандидат', confirmed: 'подтверждена', complaint: 'жалоба подана', fixed: 'заделана', false: 'ложная' }
export const STATUS_TONE: Record<string, 'smooth' | 'warn' | 'crater' | 'info' | 'muted' | 'amber'> = { candidate: 'muted', confirmed: 'crater', complaint: 'info', fixed: 'smooth', false: 'muted' }
export const LEVEL_TONE: Record<string, 'smooth' | 'warn' | 'crater' | 'info' | 'muted' | 'amber'> = { light: 'warn', mid: 'warn', deep: 'crater', danger: 'crater', '': 'muted' }
export const ROAD_CLASS_NAMES: Record<string, string> = { R: 'кольцевые и скоростные', A: 'городские магистрали', B: 'районные', C: 'местные', D: 'дворы и проезды', S: 'служебные, грунт' }
export const SURFACE_NAMES: Record<string, string> = { asphalt: 'асфальт', concrete: 'бетонные плиты', paving: 'брусчатка', gravel: 'гравий', dirt: 'грунт', unknown: 'не известно' }
export const MODE_NAMES: Record<string, string> = { car: 'авто', bus_or_tram: 'автобус / трамвай', walk_or_bike: 'пешком / велосипед', train_or_highway: 'поезд / трасса', unknown: 'не определено' }
export const ROUGH_COLORS: Record<string, string> = { A: 'var(--smooth)', B: 'color-mix(in srgb, var(--smooth) 55%, var(--amber))', C: 'var(--amber)', D: 'var(--warn)', E: 'var(--crater)' }
