import type { ReactNode } from 'react'

import { cn } from '@/lib/utils'
import { bucketRest } from '@/lib/money'

import { Money } from './Money'

export interface BucketCardProps {
  title: string
  bucket: 'essential' | 'fun'
  budgetCents: number
  spentCents: number
  /** Small action rendered on the left of the Gasto/Orçamento row. */
  action?: ReactNode
  /** Categories/entries — rendered inside the same card, below the stats. */
  children?: ReactNode
  className?: string
}

export function BucketCard({
  title,
  bucket,
  budgetCents,
  spentCents,
  action,
  children,
  className,
}: BucketCardProps) {
  const rest = bucketRest(budgetCents, spentCents)
  const pct = budgetCents > 0 ? Math.min(100, (spentCents / budgetCents) * 100) : 0
  const overspent = rest < 0

  return (
    <section
      data-bucket={bucket}
      className={cn(
        'flex h-full flex-col rounded-lg border border-border bg-card p-4',
        className,
      )}
    >
      <header className="flex items-baseline justify-between gap-2">
        <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
          {title}
        </h2>
        <Money cents={rest} size="xl" sign="sign" />
      </header>

      <div
        role="progressbar"
        aria-valuenow={Math.round(pct)}
        aria-valuemin={0}
        aria-valuemax={100}
        className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-muted"
      >
        <div
          className={cn(
            'h-full rounded-full',
            overspent ? 'bg-negative' : 'bg-foreground',
          )}
          style={{ width: `${overspent ? 100 : pct}%` }}
        />
      </div>

      <div className="mt-3 flex items-baseline justify-between gap-4">
        {action}
        <dl className="flex items-baseline gap-4 text-sm">
          <div className="flex items-baseline gap-1.5">
            <dt className="text-muted-foreground">Gasto</dt>
            <dd>
              <Money cents={spentCents} tone="negative" size="sm" />
            </dd>
          </div>
          <div className="flex items-baseline gap-1.5">
            <dt className="text-muted-foreground">Orçamento</dt>
            <dd>
              <Money cents={budgetCents} size="sm" />
            </dd>
          </div>
        </dl>
      </div>

      {children && (
        <div className="mt-3 flex-1 border-t border-border pt-1">
          {children}
        </div>
      )}
    </section>
  )
}
