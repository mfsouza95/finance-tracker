import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Money } from '@/components/Money'
import {
  computeBuckets,
  expectedInvestment,
  monthTotalToSpend,
} from '@/lib/money'
import { useEntries } from '@/features/entries/hooks'
import { ExtrasDialog } from '@/features/extras/ExtrasDialog'
import { extrasTotal, useExtras } from '@/features/extras/hooks'
import { CloseMonthDialog } from '@/features/months/CloseMonthDialog'
import { MonthSettingsDialog } from '@/features/months/MonthSettingsDialog'
import { useReopenMonth } from '@/features/months/hooks'
import type { Month } from '@/features/months/hooks'

export function MonthSummary({ month }: { month: Month }) {
  const { data: entries } = useEntries(month.id)
  const { data: extras } = useExtras(month.id)
  const reopenMonth = useReopenMonth()
  const isOpen = month.status === 'open'

  const buckets = computeBuckets(month.net_income_cents, {
    essentialPct: month.essential_pct,
    funPct: month.fun_pct,
    investPct: month.invest_pct,
  })
  const spent = { essential: 0, fun: 0 }
  for (const e of entries ?? []) {
    spent[e.categories.bucket] += e.amount_cents
  }
  const totalSpent = spent.essential + spent.fun
  const extrasCents = extrasTotal(extras)
  const toSpend = monthTotalToSpend(month.net_income_cents, buckets, extrasCents)
  const expected = expectedInvestment(
    buckets,
    spent.essential,
    spent.fun,
    extrasCents,
  )

  return (
    <section
      aria-label="Resumo do mês"
      className="rounded-lg border border-border bg-card p-4"
    >
      <header className="flex items-center justify-between gap-2">
        <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
          Resumo
        </h2>
        <Badge variant={isOpen ? 'secondary' : 'outline'}>
          {isOpen ? 'Aberto' : 'Fechado'}
        </Badge>
      </header>

      <p className="mt-3 text-sm text-muted-foreground">Restante do mês</p>
      <Money
        cents={toSpend - totalSpent}
        size="xl"
        sign="sign"
        className="block"
      />

      <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
        <div>
          <dt className="text-muted-foreground text-xs">Renda líquida</dt>
          <dd>
            <Money cents={month.net_income_cents} size="sm" />
          </dd>
        </div>
        {extrasCents > 0 && (
          <div>
            <dt className="text-muted-foreground text-xs">Extras</dt>
            <dd>
              <Money cents={extrasCents} size="sm" sign="sign" />
            </dd>
          </div>
        )}
        <div>
          <dt className="text-muted-foreground text-xs">Total para gastar</dt>
          <dd>
            <Money cents={toSpend} size="sm" />
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground text-xs">Gasto no mês</dt>
          <dd>
            <Money cents={totalSpent} size="sm" tone="negative" />
          </dd>
        </div>
        <div>
          <dt className="text-muted-foreground text-xs">
            Investimento previsto
          </dt>
          <dd>
            <Money cents={expected} size="sm" />
          </dd>
        </div>
      </dl>

      <div className="mt-4 flex gap-2">
        {isOpen ? (
          <>
            <MonthSettingsDialog month={month} />
            <ExtrasDialog month={month} />
            <CloseMonthDialog month={month} />
          </>
        ) : (
          <>
            <Button
              variant="outline"
              size="sm"
              disabled={reopenMonth.isPending}
              onClick={() => {
                if (
                  confirm(
                    'Reabrir o mês? O resumo salvo será descartado e recalculado no próximo fechamento.',
                  )
                ) {
                  reopenMonth.mutate(month.id)
                }
              }}
            >
              {reopenMonth.isPending ? 'Reabrindo…' : 'Reabrir mês'}
            </Button>
            <ExtrasDialog month={month} />
          </>
        )}
      </div>
    </section>
  )
}
