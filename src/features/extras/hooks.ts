import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import type { Tables } from '@/lib/database.types'
import { supabase } from '@/lib/supabase'

export type ExtraIncome = Tables<'extra_income'>

export function useExtras(monthId: string | undefined) {
  return useQuery({
    enabled: monthId !== undefined,
    queryKey: ['extras', monthId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('extra_income')
        .select('*')
        .eq('month_id', monthId!)
        .order('received_on')
      if (error) throw error
      return data
    },
  })
}

export function useAddExtra() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: {
      userId: string
      monthId: string
      amountCents: number
      receivedOn: string
      note?: string
    }) => {
      const { data, error } = await supabase
        .from('extra_income')
        .insert({
          user_id: vars.userId,
          month_id: vars.monthId,
          amount_cents: vars.amountCents,
          received_on: vars.receivedOn,
          note: vars.note ?? null,
        })
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['extras'] }),
  })
}

export function useDeleteExtra() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (extraId: string) => {
      const { error } = await supabase
        .from('extra_income')
        .delete()
        .eq('id', extraId)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['extras'] }),
  })
}

export function extrasTotal(extras: ExtraIncome[] | undefined): number {
  return (extras ?? []).reduce((acc, e) => acc + e.amount_cents, 0)
}
