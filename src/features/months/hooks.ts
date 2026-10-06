import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import type { Tables, TablesUpdate } from '@/lib/database.types'
import { supabase } from '@/lib/supabase'

export type Month = Tables<'months'>

export function useMonth(year: number, month: number) {
  return useQuery({
    queryKey: ['months', year, month],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('months')
        .select('*')
        .eq('year', year)
        .eq('month', month)
        .maybeSingle()
      if (error) throw error
      return data
    },
  })
}

export function useOpenMonth() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: {
      year: number
      month: number
      netIncomeCents: number
    }) => {
      const { data, error } = await supabase.rpc('open_month', {
        year: vars.year,
        month: vars.month,
        net_income_cents: vars.netIncomeCents,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries(),
  })
}

export function useUpdateMonth() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: {
      monthId: string
      patch: TablesUpdate<'months'>
    }) => {
      const { data, error } = await supabase
        .from('months')
        .update(vars.patch)
        .eq('id', vars.monthId)
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries(),
  })
}

export function useReopenMonth() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (monthId: string) => {
      const { data, error } = await supabase.rpc('reopen_month', {
        month_id: monthId,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries(),
  })
}

export function useCloseMonth() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: { monthId: string; investedCents: number }) => {
      const { data, error } = await supabase.rpc('close_month', {
        month_id: vars.monthId,
        invested_cents: vars.investedCents,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries(),
  })
}
