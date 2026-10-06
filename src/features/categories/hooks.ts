import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'

import type { Tables } from '@/lib/database.types'
import { supabase } from '@/lib/supabase'

export type Category = Tables<'categories'>
export type Bucket = Category['bucket']

export function useCategories() {
  return useQuery({
    queryKey: ['categories'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('categories')
        .select('*')
        .order('bucket')
        .order('name')
      if (error) throw error
      return data
    },
  })
}

export function useAddCategory() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: {
      userId: string
      bucket: Bucket
      name: string
    }) => {
      const { data, error } = await supabase
        .from('categories')
        .insert({ user_id: vars.userId, bucket: vars.bucket, name: vars.name })
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['categories'] }),
  })
}

export function useSetCategoryArchived() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (vars: { categoryId: string; archived: boolean }) => {
      const { error } = await supabase
        .from('categories')
        .update({ archived: vars.archived })
        .eq('id', vars.categoryId)
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['categories'] }),
  })
}
