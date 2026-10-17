import { vi } from 'vitest'

type Handler = (req: { method: string; url: URL; body: unknown }) => unknown | { __status: number; body: unknown }

/** Подменяет fetch: маршруты — по «METHOD /путь» (без /api/v1). Возвращает журнал вызовов. */
export function mockApi(routes: Record<string, Handler | unknown>) {
  const calls: { method: string; path: string; body: unknown; headers: Record<string, string> }[] = []
  vi.stubGlobal('fetch', vi.fn(async (input: string, init?: RequestInit) => {
    const url = new URL(input, 'http://localhost')
    const path = url.pathname.replace('/api/v1', '')
    const method = init?.method ?? 'GET'
    const body = init?.body && typeof init.body === 'string' ? JSON.parse(init.body) : undefined
    calls.push({ method, path, body, headers: (init?.headers ?? {}) as Record<string, string> })
    const key = Object.keys(routes).find((k) => k === `${method} ${path}`) ?? Object.keys(routes).find((k) => k === `* ${path}`)
    if (!key) return new Response(JSON.stringify({ error: `нет маршрута ${method} ${path}` }), { status: 404 })
    const r = routes[key]
    const out = typeof r === 'function' ? (r as Handler)({ method, url, body }) : r
    if (out && typeof out === 'object' && '__status' in (out as object)) {
      const o = out as { __status: number; body: unknown }
      return new Response(JSON.stringify(o.body), { status: o.__status })
    }
    return new Response(JSON.stringify(out), { status: 200 })
  }))
  return calls
}
export const status = (code: number, body: unknown) => ({ __status: code, body })
