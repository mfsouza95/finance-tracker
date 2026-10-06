import { EmptyState } from '@/components/EmptyState'
import { Money } from '@/components/Money'
import { monthLabel } from '@/lib/dates'

import { useSummaries } from './hooks'

export function HistoryPanel() {
  const { data: summaries, isLoading } = useSummaries()

  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-sm font-medium">Histórico</h2>
      {isLoading ? (
        <p className="text-muted-foreground text-sm">Carregando…</p>
      ) : !summaries?.length ? (
        <EmptyState
          title="Sem meses fechados"
          description="O histórico aparece quando você fecha um mês."
        />
      ) : (
        <ul className="flex flex-col gap-2">
      {summaries.map((s) => (
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
                <Money cents={s.essential_rest_cents} size="sm" sign="sign" />
              </dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Diversão</dt>
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
        </li>
      ))}
        </ul>
      )}
    </section>
  )
}
