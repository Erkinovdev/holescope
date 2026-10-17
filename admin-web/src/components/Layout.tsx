import { motion } from 'framer-motion'
import { useEffect, useState } from 'react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
import { ROLE_NAMES, type Role } from '../lib/api'
import { useAuth } from '../lib/auth'
import { Button, Chip, cx } from './ui'

interface NavItem { to: string; label: string; min: Role }
export const NAV: NavItem[] = [
  { to: '/', label: 'Обзор', min: 'analyst' },
  { to: '/map', label: 'Карта', min: 'analyst' },
  { to: '/events', label: 'События', min: 'analyst' },
  { to: '/roads', label: 'Дороги', min: 'analyst' },
  { to: '/devices', label: 'Устройства', min: 'analyst' },
  { to: '/trips', label: 'Поездки', min: 'analyst' },
  { to: '/dictionaries', label: 'Справочники', min: 'analyst' },
  { to: '/complaints', label: 'Жалобы', min: 'analyst' },
  { to: '/brain', label: 'Мозг', min: 'analyst' },
  { to: '/access', label: 'Доступы', min: 'admin' },
]

type Theme = 'dark' | 'light'
function useTheme(): [Theme, () => void] {
  const [t, setT] = useState<Theme>(() => {
    // по умолчанию — тёмная тема бренда; выбор сотрудника запоминается
    try { return (localStorage.getItem('hs_theme') as Theme) === 'light' ? 'light' : 'dark' } catch { return 'dark' }
  })
  useEffect(() => {
    document.documentElement.dataset.theme = t
    try { localStorage.setItem('hs_theme', t) } catch { /* приватный режим */ }
  }, [t])
  return [t, () => setT((x) => (x === 'dark' ? 'light' : 'dark'))]
}

export function Logo({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 96 96" fill="none" aria-hidden>
      <circle cx="48" cy="48" r="38.88" stroke="var(--amber)" strokeWidth="6.72" />
      <rect x="44.64" width="6.72" height="21.12" rx="3.36" fill="var(--amber)" /><rect x="44.64" y="74.88" width="6.72" height="21.12" rx="3.36" fill="var(--amber)" />
      <rect y="44.64" width="21.12" height="6.72" rx="3.36" fill="var(--amber)" /><rect x="74.88" y="44.64" width="21.12" height="6.72" rx="3.36" fill="var(--amber)" />
      <ellipse cx="48" cy="48" rx="22.08" ry="12.96" fill="var(--amber)" /><ellipse cx="48" cy="50.4" rx="14.4" ry="7.2" fill="var(--bg-base)" />
    </svg>
  )
}

export default function Layout() {
  const { me, can, logout } = useAuth()
  const [theme, toggle] = useTheme()
  const loc = useLocation()
  return (
    <div className="flex h-full">
      <aside className="flex w-60 shrink-0 flex-col gap-1 border-r border-line bg-surface px-4 py-6" aria-label="Разделы">
        <div className="mb-1 flex items-center gap-2.5 py-1"><Logo /><span className="text-lg font-bold">Holescope</span></div>
        <div className="mb-3 text-[11px] font-semibold tracking-widest text-muted">АДМИНКА</div>
        <nav className="flex flex-col gap-1">
          {NAV.filter((n) => can(n.min)).map((n) => (
            <NavLink key={n.to} to={n.to} end={n.to === '/'} className={({ isActive }) => cx('rounded-xl px-3 py-2.5 text-sm font-medium transition', isActive ? 'bg-amber-dim font-semibold text-amber-text' : 'text-muted hover:bg-raised hover:text-ink')}>
              {n.label}
            </NavLink>
          ))}
        </nav>
        <div className="mt-auto flex flex-col gap-2 pt-4">
          <div className="text-xs text-muted">Вы вошли как</div>
          <div className="flex items-center gap-2"><span className="font-semibold">{me?.username}</span><Chip tone="info">{me ? ROLE_NAMES[me.role] : ''}</Chip></div>
          <div className="flex gap-2">
            <Button small onClick={toggle} aria-label="Переключить тему">{theme === 'dark' ? 'Светлая' : 'Тёмная'}</Button>
            <Button small kind="ghost" onClick={logout}>Выйти</Button>
          </div>
        </div>
      </aside>
      <main className="min-w-0 flex-1 overflow-auto p-7">
        <motion.div key={loc.pathname} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.18 }} className="h-full">
          <Outlet />
        </motion.div>
      </main>
    </div>
  )
}
