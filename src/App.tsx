import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'

import { AppLayout } from '@/app/AppLayout'
import { ResetPasswordPage } from '@/features/auth/ResetPasswordPage'
import { SignInPage } from '@/features/auth/SignInPage'
import { useSession } from '@/features/auth/useSession'
import { Dashboard } from '@/features/dashboard/Dashboard'
import { HistoryPage } from '@/features/history/HistoryPage'
import { SelectedMonthProvider } from '@/features/months/SelectedMonthProvider'

export default function App() {
  const { session, loading, recovery, clearRecovery } = useSession()

  if (loading) {
    return <p className="text-muted-foreground p-6">Carregando…</p>
  }
  if (recovery) {
    return <ResetPasswordPage onDone={clearRecovery} />
  }
  if (!session) {
    return <SignInPage />
  }
  return (
    <BrowserRouter>
      <SelectedMonthProvider>
        <Routes>
          <Route element={<AppLayout />}>
            <Route index element={<Dashboard />} />
            <Route path="historico" element={<HistoryPage />} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </SelectedMonthProvider>
    </BrowserRouter>
  )
}
