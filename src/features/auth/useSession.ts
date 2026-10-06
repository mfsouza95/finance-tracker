import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'

import { clearQueryCache } from '@/lib/queryClient'
import { supabase } from '@/lib/supabase'

export function useSession() {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  const [recovery, setRecovery] = useState(false)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, next) => {
      setSession(next)
      if (event === 'PASSWORD_RECOVERY') {
        setRecovery(true)
      }
      if (event === 'SIGNED_OUT') {
        setRecovery(false)
        clearQueryCache()
      }
    })

    return () => subscription.unsubscribe()
  }, [])

  return { session, loading, recovery, clearRecovery: () => setRecovery(false) }
}

export async function signOut() {
  await supabase.auth.signOut()
}
