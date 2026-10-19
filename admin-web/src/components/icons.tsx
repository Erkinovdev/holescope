import type { ReactNode } from 'react'

/** Небольшой набор линейных иконок (24×24, обводка currentColor). */
const P: Record<string, ReactNode> = {
  home: <><path d="M3 11l9-8 9 8" /><path d="M5 10v10h14V10" /><path d="M10 20v-6h4v6" /></>,
  map: <><path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2-6-2z" /><path d="M9 4v14M15 6v14" /></>,
  pulse: <path d="M3 12h4l3-8 4 16 3-8h4" />,
  flag: <><path d="M5 21V4" /><path d="M5 4h12l-2 4 2 4H5" /></>,
  road: <><circle cx="6" cy="6" r="2.5" /><circle cx="18" cy="18" r="2.5" /><path d="M8.5 6H15a3 3 0 010 6H9a3 3 0 000 6h6.5" /></>,
  layers: <><path d="M12 3l9 5-9 5-9-5 9-5z" /><path d="M3 13l9 5 9-5" /></>,
  phone: <><rect x="7" y="2.5" width="10" height="19" rx="2.5" /><path d="M11 18.5h2" /></>,
  wheel: <><circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="2.2" /><path d="M12 3v6.8M4.2 16.5L10 13.2M19.8 16.5L14 13.2" /></>,
  car: <><path d="M5 16V11l2-5h10l2 5v5" /><path d="M3 16h18v3H3z" /><circle cx="7.5" cy="12.5" r="0.8" /><circle cx="16.5" cy="12.5" r="0.8" /></>,
  brain: <><path d="M12 4v16" /><path d="M12 6a3 3 0 00-5.5-1.5A3.5 3.5 0 004 8a3 3 0 00.5 5A3.5 3.5 0 007 18a3 3 0 005 1" /><path d="M12 6a3 3 0 015.5-1.5A3.5 3.5 0 0120 8a3 3 0 01-.5 5A3.5 3.5 0 0117 18a3 3 0 01-5 1" /></>,
  chip: <><rect x="6" y="6" width="12" height="12" rx="2" /><rect x="9.5" y="9.5" width="5" height="5" rx="1" /><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3" /></>,
  help: <><circle cx="12" cy="12" r="9" /><path d="M9.5 9.5a2.5 2.5 0 114 2c-.9.6-1.5 1.1-1.5 2.3" /><path d="M12 17h.01" /></>,
  db: <><ellipse cx="12" cy="6" rx="7" ry="3" /><path d="M5 6v6c0 1.7 3.1 3 7 3s7-1.3 7-3V6" /><path d="M5 12v6c0 1.7 3.1 3 7 3s7-1.3 7-3v-6" /></>,
  sliders: <><path d="M5 3v18M12 3v18M19 3v18" /><path d="M3 9h4M10 15h4M17 7h4" /></>,
  doc: <><path d="M6 3h8l4 4v14H6z" /><path d="M14 3v4h4M9 12h6M9 16h6" /></>,
  trophy: <><path d="M8 4h8v5a4 4 0 01-8 0z" /><path d="M8 6H4v1a4 4 0 004 4M16 6h4v1a4 4 0 01-4 4M12 13v4M8 21h8M10 17h4" /></>,
  key: <><circle cx="8" cy="15" r="4" /><path d="M11 12l8-8M16 7l3 3M14 9l2 2" /></>,
  wrench: <path d="M14.7 6.3a4 4 0 005 5l-9.4 9.4a2.1 2.1 0 01-3-3zM14.7 6.3L17 4l3 3-2.3 2.3" />,
  calendar: <><rect x="3.5" y="5" width="17" height="15" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4" /></>,
  download: <><path d="M12 4v11M7.5 10.5L12 15l4.5-4.5" /><path d="M4 19h16" /></>,
  play: <path d="M7 4l13 8-13 8z" />,
  check: <path d="M5 12.5l4.5 4.5L19 7" />,
  sun: <><circle cx="12" cy="12" r="4" /><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19" /></>,
  moon: <path d="M20 14.5A8 8 0 019.5 4 8 8 0 1020 14.5z" />,
  logout: <><path d="M10 4H5v16h5" /><path d="M15 8l4 4-4 4M19 12H9" /></>,
}

export type IconName = keyof typeof P
export function Icon({ name, size = 20, className }: { name: IconName; size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round" className={className} aria-hidden>
      {P[name]}
    </svg>
  )
}
