import { QueryClient } from '@tanstack/react-query'
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister'

export const QUERY_CACHE_KEY = 'finance-tracker-query-cache'

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: 1,
    },
  },
})

export const persister = createSyncStoragePersister({
  storage: window.localStorage,
  key: QUERY_CACHE_KEY,
})

// Multi-user device safety: a different account signing in on the same
// browser must never see the previous user's cached rows.
export function clearQueryCache() {
  queryClient.clear()
  window.localStorage.removeItem(QUERY_CACHE_KEY)
}
