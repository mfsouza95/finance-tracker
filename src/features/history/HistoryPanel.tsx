import { RotateCcw } from 'lucide-react'

import { EmptyState } from '@/components/EmptyState'
import { Money } from '@/components/Money'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { monthLabel } from '@/lib/dates'
import { FundHistoryRow } from '@/features/funds/FundHistoryRow'
import { useFunds, useReopenFund, type Fund } from '@/features/funds/hooks'

import { useSummaries } from './hooks'

// Completed banks become part of the month they were finished in: each
// summary card lists the banks closed that month, expandable to the full
// ledger. Banks completed in a still-open month appear in their own card.
export function HistoryPanel() {
  const { data: summaries, isLoading } = useSummaries()
  const { data: banks } = useFunds('bank')
  const reopen = useReopenFund()

  const completed = (banks ?? []).filter((b) => b.completed_at !== null)
  const byMonth = new Map<string, Fund[]>()
  for (const b of completed) {
    const key = b.completed_at!.slice(0, 7)
    byMonth.set(key, [...(byMonth.get(key) ?? []), b])
  }
  const summarized = new Set(
    (summaries ?? []).map(
      (s) => `${s.months.year}-${String(s.months.month).padStart(2, '0')}`,
    ),
  )
  const orphanMonths = [...byMonth.entries()].filter(
    ([key]) => !summarized.has(key),
  )

  const renderBank = (b: Fund) => (
    <FundHistoryRow
      key={b.id}
      fund={b}
      badge={<Badge variant="secondary">Concluída</Badge>}
      action={
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label={`Reabrir ${b.name}`}
          title="Reabrir reserva"
          onClick={() => reopen.mutate(b.id)}
          disabled={reopen.isPending}
        >
          <RotateCcw className="size-3.5" />
        </Button>
      }
    />
  )

  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-sm font-medium">Histórico</h2>
      {isLoading ? (
        <p className="text-muted-foreground text-sm">Carregando…</p>
      ) : !summaries?.length && orphanMonths.length === 0 ? (
        <EmptyState
          title="Sem meses fechados"
          description="O histórico aparece quando você fecha um mês."
        />
      ) : (
        <ul className="flex flex-col gap-2">
          {orphanMonths.map(([key, monthBanks]) => {
            const [y, m] = key.split('-').map(Number)
            return (
              <li
                key={key}
                className="rounded-lg border border-border bg-card p-3"
              >
                <div className="flex items-baseline justify-between">
                  <span className="text-sm font-medium capitalize">
                    {monthLabel(y, m)}
                  </span>
                  <span className="text-muted-foreground text-xs">
                    mês aberto
                  </span>
                </div>
                <div className="mt-1 flex flex-col">
                  {monthBanks.map(renderBank)}
                </div>
              </li>
            )
          })}
          {summaries?.map((s) => (
            <li
              key={s.month_id}
              className="rounded-lg border border-border bg-card p-3"
            >
              <div className="flex items-baseline justify-between">
                <span className="text-sm font-medium capitalize">
                  {monthLabel(s.months.year, s.months.month)}
                </span>
                <span className="text-muted-foreground text-xs">
                  líquido <Money cents={s.net_income_cents} size="sm" />
                  {s.extra_income_cents > 0 && (
                    <>
                      {' '}
                      · extras{' '}
                      <Money cents={s.extra_income_cents} size="sm" sign="sign" />
                    </>
                  )}
                </span>
              </div>
              <dl className="mt-2 grid grid-cols-3 gap-2 text-xs">
                <div>
                  <dt className="text-muted-foreground">Essencial</dt>
                  <dd>
                    <Money
                      cents={s.essential_rest_cents}
                      size="sm"
                      sign="sign"
                    />
                  </dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Lazer</dt>
                  <dd>
                    <Money cents={s.fun_rest_cents} size="sm" sign="sign" />
                  </dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Investido</dt>
                  <dd>
                    <Money cents={s.invested_cents} size="sm" />
                  </dd>
                </div>
              </dl>
              {(() => {
                const key = `${s.months.year}-${String(s.months.month).padStart(2, '0')}`
                const monthBanks = byMonth.get(key)
                return monthBanks ? (
                  <div className="mt-1 flex flex-col border-t border-border pt-1">
                    {monthBanks.map(renderBank)}
                  </div>
                ) : null
              })()}
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
