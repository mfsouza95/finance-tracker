import { ResetPasswordPage } from '@/features/auth/ResetPasswordPage'
import { SignInPage } from '@/features/auth/SignInPage'
import { useSession } from '@/features/auth/useSession'
import { Dashboard } from '@/features/dashboard/Dashboard'

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
  return <Dashboard />
}
