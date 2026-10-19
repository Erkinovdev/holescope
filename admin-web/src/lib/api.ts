/** Клиент API админки. Токен — в localStorage, истёкший/неверный токен → выход на страницу входа. */
export type Role = 'analyst' | 'labeler' | 'admin'
export const ROLE_LEVEL: Record<Role, number> = { analyst: 1, labeler: 2, admin: 3 }
export const ROLE_NAMES: Record<Role, string> = { analyst: 'аналитик', labeler: 'разметчик', admin: 'админ' }

const KEY = 'holescope_admin_token'
let onUnauthorized: (() => void) | null = null

export const tokenStore = {
  get: (): string | null => {
    try { return localStorage.getItem(KEY) } catch { return null }
  },
  set: (t: string) => { try { localStorage.setItem(KEY, t) } catch { /* приватный режим */ } },
  clear: () => { try { localStorage.removeItem(KEY) } catch { /* приватный режим */ } },
}
export function setUnauthorizedHandler(fn: (() => void) | null) { onUnauthorized = fn }

export class ApiError extends Error {
  status: number
  constructor(message: string, status: number) { super(message); this.status = status }
}

type Query = Record<string, string | number | boolean | undefined | null>
const qs = (q?: Query) => {
  if (!q) return ''
  const p = new URLSearchParams()
  for (const [k, v] of Object.entries(q)) if (v !== undefined && v !== null && v !== '') p.set(k, String(v))
  const s = p.toString()
  return s ? `?${s}` : ''
}

export async function request<T>(method: string, path: string, opts: { query?: Query; body?: unknown; form?: FormData } = {}): Promise<T> {
  const headers: Record<string, string> = {}
  const t = tokenStore.get()
  if (t) headers.Authorization = `Bearer ${t}`
  let body: BodyInit | undefined
  if (opts.form) body = opts.form
  else if (opts.body !== undefined) { headers['Content-Type'] = 'application/json'; body = JSON.stringify(opts.body) }
  let res: Response
  try {
    res = await fetch(`/api/v1${path}${qs(opts.query)}`, { method, headers, body })
  } catch {
    throw new ApiError('Нет связи с сервером', 0)
  }
  let data: unknown = null
  try { data = await res.json() } catch { /* пустой ответ */ }
  if (res.status === 401 && path !== '/admin/login') { tokenStore.clear(); onUnauthorized?.() }
  if (!res.ok) {
    const msg = (data as { error?: string } | null)?.error ?? `Ошибка ${res.status}`
    throw new ApiError(msg, res.status)
  }
  return data as T
}

export const api = {
  get: <T>(path: string, query?: Query) => request<T>('GET', path, { query }),
  post: <T>(path: string, body?: unknown, query?: Query) => request<T>('POST', path, { body, query }),
  patch: <T>(path: string, body: unknown) => request<T>('PATCH', path, { body }),
  put: <T>(path: string, body: unknown) => request<T>('PUT', path, { body }),
  upload: <T>(path: string, form: FormData) => request<T>('POST', path, { form }),
}
// ── типы ответов (только используемые поля) ──
export interface Page<T> { items: T[]; total: number; page: number; size: number }
export interface Cluster {
  id: number; lat: number; lon: number; heading: number | null; type: string; level: string; status: string; passes: number; devices: number; quiet_passes: number
  confidence: number; score_median: number; safe_speed: number | null; first_seen: string | null; last_hit: string | null; fixed_at: string | null
  street: string | null; road: string | null; segment: string | null; district: string | null
}
export interface ClusterEvent {
  id: number; at: string; device: string; device_id: number; speed_kmh: number; peak: number; score: number; type: string; level: string; confidence: number
  user_label: string; trip: number; wave: number[]; algo_version: string; features: Record<string, number | null>
  explain: { verdict: string; reasons: { ok: boolean; text: string }[] }
}
export interface Readiness {
  types: { counts: Record<string, number>; active: string | null; per_class: number }
  state: 'rules' | 'ready' | 'learned'; title: string; progress: number; steps: string[]; last_training: string | null
  facts: { labels: number; road: number; not_road: number; trips_ready: number; trips_needed: number; labels_needed: number; open_questions: number }
}
export interface Taxonomy {
  items: { key: string; group: string; ru: string; uz: string; road: boolean; type: string; level: string; driver: boolean; hint: string }[]
  groups: Record<string, { ru: string; uz: string }>
  road_ratings: Record<string, { cls: string; ru: string; uz: string }>
  driver_options: string[]
}
export interface Analysis {
  guess: { top: string; ranked: { type: string; name: string; p: number }[]; reasons: string[]; matches_current: boolean }
  context: { c_hit_rate: number; c_score_cv: number; c_speed_slope: number; c_passes: number; c_devices: number; c_low_speed: number }
  votes: { label: string; name: string; n: number }[]
  level: { current: string; score: number; bounds: number[]; calibrated: boolean; text: string }
  roughness: { cls: string; name: string; ri: number | null; passes: number; devices: number; road: string; road_class: string; surface: string; flags: string[] } | null
}
export interface Calibration {
  levels: { n: number; counts: Record<string, number>; current: number[]; suggested: number[] | null; acc_current: number | null; acc_suggested: number | null; cv_current: number | null; cv_suggested: number | null; significant: boolean; active: boolean; default: number[] }
  ri: { stats: Record<string, { n: number; median: number | null; p25: number | null; p75: number | null }>; current: number[]; suggested: number[] | null; enough: boolean; warning?: string; names: Record<string, string> }
}
export interface ClusterDetail extends Cluster { analysis?: Analysis; why: string; events: ClusterEvent[]; type_votes: Record<string, number>; complaints: number; quiet: { at: string; speed_kmh: number; device_id: number }[] }
export interface Overview {
  days: number
  kpi: { trips: number; km: number; events: number; clusters_total: number; confirmed: number; fixed: number; candidates: number; devices_active: number; devices_total: number; labels: number }
  queues: { candidates_single: number; questions_open: number; complaints_to_file: number }
  series: { day: string; trips: number; km: number; events: number; clusters: number }[]
  recent: Cluster[]
  classes: Record<string, number>
  segments_total: number
  brain: { version: string | null; f1: number | null; labels: number }
}
export interface Vehicle {
  id: number; name: string; car_model_id: number | null; car_model: string | null; year: number | null; rim_inch: number | null; tire_pressure_bar: number | null
  wheelbase_mm: number | null; wheelbase_effective_m: number; suspension_note: string; suspension_cls: string; softness_score: number | null; softness_conf: number
  km_total: number; zeta_median: number | null; f_body_median: number | null; model_guess: string | null; model_guess_conf: number
}
export interface Device {
  id: number; nickname: string; platform: string; phone_model: string; app_version: string; role: string; mount: string; lang: string; calib_gain: number; calib_n: number
  trust: number; blocked: boolean; last_seen: string | null; created: string; vehicle: Vehicle | null; trips: number | { id: number; started_at: string; distance_km: number; mode: string; events: number; algo_version: string }[] | null
  events_total?: number; labels?: number
}
export interface Road {
  id: number; code: string; name_ru: string; name_uz: string; road_class: string; surface: string; named: boolean; length_km: number; district: string | null; district_code: string | null
  has_tram: boolean; has_level_crossing: boolean; speed_limit_kmh: number | null; class_reviewed: boolean; segments?: number; scored?: number; ri_avg?: number | null
}
export interface RoadSegmentRow { id: number; index: number; direction: number; lat_a: number; lon_a: number; lat_b: number; lon_b: number; cls: string; ri_median: number | null; ri_n: number }
export interface CarModel { id: number; brand: string; model: string; generation: string; body: string; is_ev: boolean; wheelbase_mm: number | null; length_mm: number | null; tire_size: string; rim_inch: number | null; popularity_rank: number | null; specs_verified: boolean; source_url: string; softness_median: number | null; softness_n_vehicles: number }
export interface TripRow { id: number; device: string; device_id: number; started_at: string; ended_at: string | null; distance_km: number; mode: string; events: number; algo_version: string; end_reason: string }
export interface Complaint { id: number; cluster_id: number; street: string | null; channel: string; status: string; external_number: string; text: string; anonymous: boolean; created: string; filed_at: string | null; due_at: string | null; answered_at: string | null; cluster_status: string }
export interface StaffUser { id: number; username: string; role: Role | null; role_name: string; is_active: boolean; last_login: string | null }
export interface AuditRow { id: number; user: string | null; action: string; target: string; payload: Record<string, unknown>; at: string }
export interface AlgoVersion { id: number; version: string; kind: string; active: boolean; metrics: Record<string, any>; notes: string; created: string; params: Record<string, unknown> }
export interface GraphNode { id: string; kind: string; label: string; size: number; confidence: number; status?: string; level?: string; ref?: number; active?: boolean; road_class?: string; events?: number }
export interface GraphEdge { a: string; b: string; kind: string; w: number }
export interface Dictionaries { [k: string]: Record<string, string> }
