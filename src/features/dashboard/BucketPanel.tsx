import { BucketCard } from '@/components/BucketCard'
import { EmptyState } from '@/components/EmptyState'
import { computeBuckets } from '@/lib/money'
import {
  CategoryManager,
} from '@/features/categories/CategoryManager'
import { useCategories, type Bucket } from '@/features/categories/hooks'
import {
  CategoryGroup,
} from '@/features/entries/CategoryGroup'
import { useEntries } from '@/features/entries/hooks'
import { extrasTotal, useExtras } from '@/features/extras/hooks'
import type { Month } from '@/features/months/hooks'

interface BucketPanelProps {
  month: Month
  bucket: Bucket
  title: string
}

export function BucketPanel({ month, bucket, title }: BucketPanelProps) {
  const { data: categories } = useCategories()
  const { data: entries } = useEntries(month.id)
  const { data: extras } = useExtras(month.id)
  const isOpen = month.status === 'open'

  const buckets = computeBuckets(month.net_income_cents, {
    essentialPct: month.essential_pct,
    funPct: month.fun_pct,
    investPct: month.invest_pct,
  })
  // Extras bypass the split and raise only the fun budget.
  const budget =
    buckets[bucket] + (bucket === 'fun' ? extrasTotal(extras) : 0)

  const bucketEntries = (entries ?? []).filter((e) => e.bucket === bucket)
  const uncategorized = bucketEntries.filter((e) => e.category_id === null)
  const spent = bucketEntries.reduce((acc, e) => acc + e.amount_cents, 0)
  const bucketCategories = (categories ?? []).filter((c) => c.bucket === bucket)
  const activeCategories = bucketCategories.filter((c) => !c.archived)

  return (
    <BucketCard
      title={title}
      bucket={bucket}
      budgetCents={budget}
      spentCents={spent}
      action={
        isOpen ? (
          <CategoryManager bucket={bucket} categories={bucketCategories} />
        ) : undefined
      }
    >
      {activeCategories.length === 0 && uncategorized.length === 0 ? (
        <EmptyState
          title="Nenhuma categoria"
          description="Crie categorias para organizar os gastos deste pote."
        />
      ) : (
        <div className="flex flex-col">
          {activeCategories.map((c) => (
            <CategoryGroup
              key={c.id}
              category={c}
              entries={bucketEntries.filter((e) => e.category_id === c.id)}
              editable={isOpen}
            />
          ))}
          {uncategorized.length > 0 && (
            <CategoryGroup
              category={{
                id: '',
                user_id: '',
                bucket,
                name: 'Sem categoria',
                archived: false,
                created_at: '',
              }}
              entries={uncategorized}
              editable={isOpen}
            />
          )}
        </div>
      )}
    </BucketCard>
  )
}
