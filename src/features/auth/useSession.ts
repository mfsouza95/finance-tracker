import { useEffect, useState } from 'react'
import type { Session } from '@supabase/supabase-js'

import { clearQueryCache } from '@/lib/queryClient'
import { supabase } from '@/lib/supabase'

export function useSession() {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setLoading(false)
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, next) => {
      setSession(next)
      if (event === 'SIGNED_OUT') {
        clearQueryCache()
      }
    })

    return () => subscription.unsubscribe()
  }, [])

  return { session, loading }
}

export async function signOut() {
  await supabase.auth.signOut()
}
