import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import type { Tables } from '@/lib/database.types'
import { supabase } from '@/lib/supabase'

export type RecurringTemplate = Tables<'recurring_templates'>
export type TemplateWithCategory = RecurringTemplate & {
  categories: Pick<Tables<'categories'>, 'name' | 'bucket'>
}

// Installment progress for a bounded template at a given calendar month:
// 1-based index of the installment due in that month, clamped to [0, total].
// Returns null for unbounded templates.
export function installmentIndexAt(
  t: Pick<RecurringTemplate, 'installments_total' | 'first_year' | 'first_month'>,
  year: number,
  month: number,
): number | null {
  if (t.installments_total === null || t.first_year === null || t.first_month === null) {
    return null
  }
  const idx = year * 12 + month - (t.first_year * 12 + t.first_month) + 1
  return Math.min(Math.max(idx, 0), t.installments_total)
}

export function useRecurringTemplates() {
  return useQuery({
    queryKey: ['recurring_templates'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('recurring_templates')
        .select('*, categories!inner(name, bucket)')
        .order('active', { ascending: false })
        .order('label')
      if (error) throw error
      return data as TemplateWithCategory[]
    },
  })
}

export function useCreateTemplate() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: {
      categoryId: string
      label: string
      amountCents: number
      dayOfMonth: number
      installmentsTotal?: number
      firstYear?: number
      firstMonth?: number
    }) => {
      const { data, error } = await supabase.rpc('create_recurring_template', {
        p_category_id: vars.categoryId,
        p_label: vars.label,
        p_amount_cents: vars.amountCents,
        p_day_of_month: vars.dayOfMonth,
        p_installments_total: vars.installmentsTotal,
        p_first_year: vars.firstYear,
        p_first_month: vars.firstMonth,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries(),
  })
}

// Cancelling a plan = active false; reactivating resumes position-based
// generation, so a plan picks up at the right installment automatically.
export function useSetTemplateActive() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: { templateId: string; active: boolean }) => {
      const { error } = await supabase
        .from('recurring_templates')
        .update({ active: vars.active })
        .eq('id', vars.templateId)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries(),
  })
}
