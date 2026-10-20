import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { lazy, Suspense } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import Layout from './components/Layout'
import { PageLoader } from './components/Loaders'
import { ToastProvider } from './components/ui'
import { AuthProvider, useAuth } from './lib/auth'
import Access from './pages/Access'
import Complaints from './pages/Complaints'
import Devices, { DeviceCard } from './pages/Devices'
import Dictionaries from './pages/Dictionaries'
import Events from './pages/Events'
import Login from './pages/Login'
import Overview from './pages/Overview'
import Roads from './pages/Roads'
import Trips, { TripPage } from './pages/Trips'
import Challenges from './pages/Challenges'
import Districts from './pages/Districts'
import Reports from './pages/Reports'
import System from './pages/System'

// тяжёлые страницы (карта, 3D) грузим по требованию
const MapPage = lazy(() => import('./pages/MapPage'))
const BrainHub = lazy(() => import('./pages/BrainHub'))
const Cars = lazy(() => import('./pages/Wrappers').then((m) => ({ default: m.Cars })))

const qc = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 15_000, refetchOnWindowFocus: false } } })

function Gate() {
  const { me, loading, can } = useAuth()
  if (loading) return <PageLoader label="Проверяем вход…" />
  if (!me) return <Login />
  return (
    <Suspense fallback={<PageLoader />}>
      <Routes>
        <Route element={<Layout />}>
          <Route index element={<Overview />} />
          <Route path="map" element={<MapPage />} />
          <Route path="events" element={<Events />} />
          <Route path="roads" element={<Roads />} />
          <Route path="devices" element={<Devices />} />
          <Route path="devices/:id" element={<DeviceCard />} />
          <Route path="trips" element={<Trips />} />
          <Route path="trips/:id" element={<TripPage />} />
          <Route path="dictionaries" element={<Dictionaries />} />
          <Route path="complaints" element={<Complaints />} />
          <Route path="brain" element={<BrainHub />} />
          <Route path="learning" element={<Navigate to="/brain?tab=learning" replace />} />
          <Route path="questions" element={<Navigate to="/brain?tab=questions" replace />} />
          <Route path="memory" element={<Navigate to="/brain?tab=memory" replace />} />
          <Route path="algo" element={<Navigate to="/brain?tab=algo" replace />} />
          <Route path="districts" element={<Districts />} />
          <Route path="cars" element={<Cars />} />
          <Route path="challenges" element={<Challenges />} />
          <Route path="reports" element={<Reports />} />
          <Route path="system" element={<System />} />
          <Route path="access" element={can('admin') ? <Access /> : <Navigate to="/" replace />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Route>
      </Routes>
    </Suspense>
  )
}

export default function App() {
  return (
    <QueryClientProvider client={qc}>
      <ToastProvider>
        <AuthProvider>
          <BrowserRouter basename="/panel">
            <Gate />
          </BrowserRouter>
        </AuthProvider>
      </ToastProvider>
    </QueryClientProvider>
  )
}
