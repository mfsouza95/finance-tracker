import { SignInPage } from '@/features/auth/SignInPage'
import { useSession } from '@/features/auth/useSession'
import { Dashboard } from '@/features/dashboard/Dashboard'

export default function App() {
  const { session, loading } = useSession()

  if (loading) {
    return <p className="text-muted-foreground p-6">Carregando…</p>
  }
  if (!session) {
    return <SignInPage />
  }
  return <Dashboard />
}
