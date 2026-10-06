import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import type { Tables } from '@/lib/database.types'
import { supabase } from '@/lib/supabase'

export type Fund = Tables<'funds'>
export type FundKind = Fund['kind']

export function useFunds(kind?: FundKind) {
  return useQuery({
    queryKey: ['funds', kind ?? 'all'],
    queryFn: async () => {
      let q = supabase.from('funds').select('*').order('created_at')
      if (kind) q = q.eq('kind', kind)
      const { data, error } = await q
      if (error) throw error
      return data
    },
  })
}

/** fund_id -> balance (deposits - spends). Missing fund = 0. */
export function useFundBalances() {
  return useQuery({
    queryKey: ['fund_balances'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('fund_balances')
        .select('fund_id, balance_cents')
      if (error) throw error
      return new Map(
        data
          .filter((r): r is { fund_id: string; balance_cents: number } =>
            r.fund_id !== null && r.balance_cents !== null,
          )
          .map((r) => [r.fund_id, r.balance_cents]),
      )
    },
  })
}

/** Fund-linked entries (deposits and spends) for a month. */
export function useFundEntries(monthId: string | undefined) {
  return useQuery({
    enabled: monthId !== undefined,
    queryKey: ['fund_entries', monthId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('entries')
        .select('*')
        .eq('month_id', monthId!)
        .not('fund_id', 'is', null)
        .order('paid_on')
      if (error) throw error
      return data
    },
  })
}

export function useCreateFund() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: {
      userId: string
      kind: FundKind
      name: string
      goalCents?: number
    }) => {
      const { data, error } = await supabase
        .from('funds')
        .insert({
          user_id: vars.userId,
          kind: vars.kind,
          name: vars.name,
          goal_cents: vars.goalCents ?? null,
        })
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['funds'] }),
  })
}

export function useUpdateFund() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: {
      fundId: string
      patch: { active?: boolean; achieved_at?: string | null }
    }) => {
      const { error } = await supabase
        .from('funds')
        .update(vars.patch)
        .eq('id', vars.fundId)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['funds'] }),
  })
}

export function useDepositToFund() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: {
      fundId: string
      monthId: string
      essentialCents?: number
      funCents?: number
      paidOn?: string
      note?: string
    }) => {
      const { error } = await supabase.rpc('deposit_to_fund', {
        p_fund_id: vars.fundId,
        p_month_id: vars.monthId,
        p_essential_cents: vars.essentialCents ?? 0,
        p_fun_cents: vars.funCents ?? 0,
        p_paid_on: vars.paidOn,
        p_note: vars.note,
      })
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['entries'] })
      qc.invalidateQueries({ queryKey: ['fund_entries'] })
      qc.invalidateQueries({ queryKey: ['fund_balances'] })
      qc.invalidateQueries({ queryKey: ['categories'] })
    },
  })
}

export function useDeleteFund() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: { fundId: string; moveToExtras: boolean }) => {
      const { error } = await supabase.rpc('delete_fund', {
        p_fund_id: vars.fundId,
        p_move_to_extras: vars.moveToExtras,
      })
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['funds'] })
      qc.invalidateQueries({ queryKey: ['fund_balances'] })
      qc.invalidateQueries({ queryKey: ['fund_entries'] })
      qc.invalidateQueries({ queryKey: ['entries'] })
      qc.invalidateQueries({ queryKey: ['extras'] })
    },
  })
}
