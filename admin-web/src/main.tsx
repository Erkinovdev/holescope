import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './App'
import './index.css'
import './loaders.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

// стартовая заставка из index.html: убираем сразу после первой отрисовки приложения
requestAnimationFrame(() =>
  requestAnimationFrame(() => {
    const boot = document.getElementById('hs-boot')
    if (!boot) return
    boot.classList.add('off')
    setTimeout(() => boot.remove(), 300)
  }),
)
