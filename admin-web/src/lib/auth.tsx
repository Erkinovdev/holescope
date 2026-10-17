import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { api, ROLE_LEVEL, setUnauthorizedHandler, tokenStore, type Role } from './api'

export interface Me { username: string; role: Role; role_name: string }
interface AuthCtx {
  me: Me | null
  loading: boolean
  login: (username: string, password: string) => Promise<void>
  logout: () => void
  can: (min: Role) => boolean
}
const Ctx = createContext<AuthCtx | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null)
  const [loading, setLoading] = useState(() => !!tokenStore.get())

  const logout = useCallback(() => { tokenStore.clear(); setMe(null) }, [])

  useEffect(() => {
    setUnauthorizedHandler(logout)
    return () => setUnauthorizedHandler(null)
  }, [logout])

  useEffect(() => {
    if (!tokenStore.get()) return
    api.get<Me>('/admin/me').then(setMe).catch(() => tokenStore.clear()).finally(() => setLoading(false))
  }, [])

  const login = useCallback(async (username: string, password: string) => {
    const r = await api.post<{ token: string; user: Me }>('/admin/login', { username, password })
    tokenStore.set(r.token)
    setMe(r.user)
  }, [])

  const value = useMemo<AuthCtx>(() => ({ me, loading, login, logout, can: (min) => !!me && ROLE_LEVEL[me.role] >= ROLE_LEVEL[min] }), [me, loading, login, logout])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useAuth(): AuthCtx {
  const c = useContext(Ctx)
  if (!c) throw new Error('AuthProvider отсутствует')
  return c
}
