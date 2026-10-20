import { motion } from 'framer-motion'
import { useEffect, useState } from 'react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
import { ROLE_NAMES, type Role } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useGet } from '../lib/hooks'
import { Icon, type IconName } from './icons'
import { Button, ChromeCtx, cx } from './ui'

interface NavItem { to: string; label: string; min: Role; icon: IconName; badge?: 'events' | 'complaints' | 'questions' }
interface NavGroup { title: string; items: NavItem[] }
export const GROUPS: NavGroup[] = [
  { title: 'ОПЕРАЦИИ', items: [
    { to: '/', label: 'Обзор', min: 'analyst', icon: 'home' },
    { to: '/map', label: 'Карта', min: 'analyst', icon: 'map' },
    { to: '/events', label: 'События', min: 'analyst', icon: 'pulse', badge: 'events' },
    { to: '/complaints', label: 'Жалобы', min: 'analyst', icon: 'flag', badge: 'complaints' },
  ] },
  { title: 'ДАННЫЕ', items: [
    { to: '/roads', label: 'Дороги', min: 'analyst', icon: 'road' },
    { to: '/districts', label: 'Районы', min: 'analyst', icon: 'layers' },
    { to: '/devices', label: 'Устройства', min: 'analyst', icon: 'phone' },
    { to: '/trips', label: 'Поездки', min: 'analyst', icon: 'wheel' },
    { to: '/cars', label: 'Автомобили', min: 'analyst', icon: 'car' },
    { to: '/dictionaries', label: 'Справочники', min: 'analyst', icon: 'doc' },
  ] },
  { title: 'МОЗГ', items: [
    { to: '/brain', label: 'Мозг', min: 'analyst', icon: 'brain', badge: 'questions' },
  ] },
  { title: 'ПУБЛИКАЦИИ', items: [
    { to: '/reports', label: 'Отчёты', min: 'analyst', icon: 'doc' },
    { to: '/challenges', label: 'Челленджи', min: 'analyst', icon: 'trophy' },
  ] },
  { title: 'СИСТЕМА', items: [
    { to: '/access', label: 'Доступы', min: 'admin', icon: 'key' },
    { to: '/system', label: 'Система', min: 'analyst', icon: 'wrench' },
  ] },
]
export const NAV = GROUPS.flatMap((g) => g.items)

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
  const badges = useGet<{ events: number; complaints: number; questions: number; algo: string }>('/admin/badges', undefined, { refetchMs: 60_000 })
  const initials = (me?.username ?? '?').slice(0, 2).toUpperCase()
  const chrome = (
    <>
      {badges.data?.algo && <span className="inline-flex items-center gap-2 rounded-full bg-amber-dim px-3 py-1.5 text-xs font-semibold text-amber-text"><span className="h-2 w-2 rounded-full bg-amber" aria-hidden />Правила {badges.data.algo}</span>}
      <span className="rounded-full bg-info/15 px-3 py-1.5 text-xs font-semibold text-info">Ташкент</span>
      <span title={me ? `${me.username} · ${ROLE_NAMES[me.role]}` : ''} className="grid h-9 w-9 place-items-center rounded-full bg-info/20 text-xs font-bold text-info">{initials}</span>
    </>
  )
  return (
    <ChromeCtx.Provider value={chrome}>
      <div className="flex h-full">
        <aside className="flex w-[248px] shrink-0 flex-col overflow-y-auto border-r border-line bg-surface px-3 py-5" aria-label="Разделы">
          <div className="mb-4 flex items-center gap-2.5 px-2"><Logo size={34} /><div className="leading-tight"><div className="text-lg font-bold">Holescope</div><div className="text-[10px] font-semibold tracking-[0.18em] text-muted">АДМИНКА</div></div></div>
          <nav className="flex flex-col gap-0.5">
            {GROUPS.map((g) => {
              const items = g.items.filter((n) => can(n.min))
              if (!items.length) return null
              return (
                <div key={g.title} className="mb-1.5">
                  <div className="px-3 pb-1 pt-3 text-[10px] font-semibold tracking-[0.18em] text-muted">{g.title}</div>
                  {items.map((n) => {
                    const cnt = n.badge ? badges.data?.[n.badge] : 0
                    return (
                      <NavLink key={n.to} to={n.to} end={n.to === '/'} className={({ isActive }) => cx('flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition', isActive ? 'bg-amber-dim font-semibold text-amber-text' : 'text-ink/85 hover:bg-raised')}>
                        <Icon name={n.icon} size={19} />
                        <span>{n.label}</span>
                        {!!cnt && <span className="ml-auto rounded-full bg-amber/20 px-2 py-0.5 text-[11px] font-bold text-amber-text">{cnt}</span>}
                      </NavLink>
                    )
                  })}
                </div>
              )
            })}
          </nav>
          <div className="mt-auto flex items-center gap-2 border-t border-line px-2 pt-4">
            <div className="min-w-0 flex-1"><div className="truncate text-sm font-semibold">{me?.username}</div><div className="text-xs text-muted">{me ? ROLE_NAMES[me.role] : ''}</div></div>
            <Button small onClick={toggle} aria-label="Переключить тему"><Icon name={theme === 'dark' ? 'sun' : 'moon'} size={15} /></Button>
            <Button small kind="ghost" onClick={logout} aria-label="Выйти"><Icon name="logout" size={15} /></Button>
          </div>
        </aside>
        <main className="min-w-0 flex-1 overflow-auto p-8">
          <motion.div key={loc.pathname} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.18 }} className="h-full">
            <Outlet />
          </motion.div>
        </main>
      </div>
    </ChromeCtx.Provider>
  )
}
