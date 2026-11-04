import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import type { Tables, TablesInsert } from '@/lib/database.types'
import { computeBuckets } from '@/lib/money'
import { supabase } from '@/lib/supabase'
import { useSession } from '@/features/auth/useSession'
import type { EntryWithCategory } from '@/features/entries/hooks'
import type { Month } from '@/features/months/hooks'

import {
  daysLeft,
  mondayOf,
  paceAllowance,
  paceBound,
  scopeBudgetCents,
  scopeSpentCents,
  todayISO,
  weeksLeft,
  type PaceScope,
} from './pace'

export type PaceSnapshot = Tables<'pace_snapshots'>

export function usePaceSnapshots(monthId: string | undefined) {
  return useQuery({
    enabled: monthId !== undefined,
    queryKey: ['pace_snapshots', monthId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('pace_snapshots')
        .select('*')
        .eq('month_id', monthId!)
      if (error) throw error
      return data
    },
  })
}

const SCOPES: PaceScope[] = ['all', 'essential', 'fun']

// Compute the current day/week rows for every scope from live month data —
// shared by the first-write-wins ensure and the overwriting recalc.
function currentRows(
  month: Month,
  entries: EntryWithCategory[],
  extrasCents: number,
  userId: string,
  today: string,
): TablesInsert<'pace_snapshots'>[] {
  const bound = paceBound(month)
  const buckets = computeBuckets(month.net_income_cents, {
    essentialPct: month.essential_pct,
    funPct: month.fun_pct,
    investPct: month.invest_pct,
  })
  const monday = mondayOf(today)
  const rows: TablesInsert<'pace_snapshots'>[] = []
  for (const scope of SCOPES) {
    const remaining =
      scopeBudgetCents(buckets, extrasCents, scope) -
      scopeSpentCents(entries, scope)
    rows.push(
      {
        month_id: month.id,
        kind: 'day',
        scope,
        period_start: today,
        user_id: userId,
        allowance_cents: paceAllowance(remaining, daysLeft(bound, today)),
      },
      {
        month_id: month.id,
        kind: 'week',
        scope,
        period_start: monday,
        user_id: userId,
        allowance_cents: paceAllowance(remaining, weeksLeft(bound, monday)),
      },
    )
  }
  return rows
}

interface PaceVars {
  month: Month
  entries: EntryWithCategory[]
  extrasCents: number
}

const CONFLICT = 'month_id,kind,scope,period_start'

// Writes the current day/week rows only when missing — first write wins,
// so two racing tabs can never fight over the fixed figure.
export function useEnsurePace() {
  const qc = useQueryClient()
  const { session } = useSession()
  return useMutation({
    mutationFn: async (vars: PaceVars & { existing: PaceSnapshot[] }) => {
      if (!session) throw new Error('not signed in')
      const today = todayISO()
      const have = new Set(
        vars.existing.map((s) => `${s.scope}:${s.kind}:${s.period_start}`),
      )
      const rows = currentRows(
        vars.month,
        vars.entries,
        vars.extrasCents,
        session.user.id,
        today,
      ).filter((r) => !have.has(`${r.scope}:${r.kind}:${r.period_start}`))
      if (!rows.length) return
      const { error } = await supabase
        .from('pace_snapshots')
        .upsert(rows, { onConflict: CONFLICT, ignoreDuplicates: true })
      if (error) throw error
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['pace_snapshots', vars.month.id] })
    },
  })
}

// Manual recalc: overwrites the current-period figures for ALL scopes with
// today's remaining budget — the escape hatch after a planned big spend.
export function useRecalcPace() {
  const qc = useQueryClient()
  const { session } = useSession()
  return useMutation({
    mutationFn: async (vars: PaceVars) => {
      if (!session) throw new Error('not signed in')
      const rows = currentRows(
        vars.month,
        vars.entries,
        vars.extrasCents,
        session.user.id,
        todayISO(),
      )
      const { error } = await supabase
        .from('pace_snapshots')
        .upsert(rows, { onConflict: CONFLICT })
      if (error) throw error
    },
    onSuccess: (_d, vars) => {
      qc.invalidateQueries({ queryKey: ['pace_snapshots', vars.month.id] })
    },
  })
}
