import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import type { Tables } from '@/lib/database.types'
import { supabase } from '@/lib/supabase'

export type Entry = Tables<'entries'>
export type EntryWithCategory = Entry & {
  bucket: NonNullable<Entry['bucket']>
  categories: Pick<Tables<'categories'>, 'name' | 'bucket'> | null
  recurring_templates: Pick<Tables<'recurring_templates'>, 'installments_total'> | null
}

// Bucket entries only: the .not(bucket, is, null) filter drops fund 'out'
// spends (they're shown via useFundEntries in the active-bank card) and
// carries no category requirement — categories are organizational.
export function useEntries(monthId: string | undefined) {
  return useQuery({
    enabled: monthId !== undefined,
    queryKey: ['entries', monthId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('entries')
        .select('*, categories(name, bucket), recurring_templates(installments_total)')
        .eq('month_id', monthId!)
        .not('bucket', 'is', null)
        .order('paid_on')
      if (error) throw error
      return data as EntryWithCategory[]
    },
  })
}

export function useAddEntry() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: {
      userId: string
      monthId: string
      amountCents: number
      paidOn: string
      note?: string
      // A normal entry has a bucket and optional categoryId (or bucket is
      // synced from the category server-side); a bank spend has fundId
      // instead and bypasses the buckets (fund_flow='out').
      categoryId?: string
      fundId?: string
      bucket?: 'essential' | 'fun'
    }) => {
      const { data, error } = await supabase
        .from('entries')
        .insert({
          user_id: vars.userId,
          month_id: vars.monthId,
          category_id: vars.categoryId ?? null,
          amount_cents: vars.amountCents,
          paid_on: vars.paidOn,
          note: vars.note ?? null,
          fund_id: vars.fundId ?? null,
          fund_flow: vars.fundId ? 'out' : null,
          bucket: vars.bucket ?? null,
        })
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['entries'] })
      qc.invalidateQueries({ queryKey: ['fund_entries'] })
      qc.invalidateQueries({ queryKey: ['fund_balances'] })
    },
  })
}

export function useDeleteEntry() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (entryId: string) => {
      const { error } = await supabase
        .from('entries')
        .delete()
        .eq('id', entryId)
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['entries'] })
      qc.invalidateQueries({ queryKey: ['fund_entries'] })
      qc.invalidateQueries({ queryKey: ['fund_balances'] })
    },
  })
}
