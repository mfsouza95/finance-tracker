import { useQuery } from '@tanstack/react-query'

import type { Tables } from '@/lib/database.types'
import { supabase } from '@/lib/supabase'

export type SummaryWithMonth = Tables<'month_summaries'> & {
  months: Pick<Tables<'months'>, 'year' | 'month'>
}

export function useSummaries() {
  return useQuery({
    queryKey: ['month_summaries'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('month_summaries')
        .select('*, months!inner(year, month)')
      if (error) throw error
      return (data as SummaryWithMonth[]).sort(
        (a, b) => b.months.year - a.months.year || b.months.month - a.months.month,
      )
    },
  })
}
