import { ChevronRight } from 'lucide-react'

import { EmptyState } from '@/components/EmptyState'
import { Money } from '@/components/Money'
import { Badge } from '@/components/ui/badge'
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible'
import { formatISODate } from '@/lib/dates'
import { useMonth } from '@/features/months/hooks'
import { useSelectedMonth } from '@/features/months/selectedMonth'

import type { Fund } from './hooks'
import { useFundBalances, useFundHistory, useFunds } from './hooks'
import { BankRow, CreateFundDialog } from './BanksPanel'

// Full bank (reserva) management: create, activate/deactivate, deposit,
// complete and delete. Completed banks keep their rows below with the
// full entry history — unlike deleted ones, which lose the link.
export function BanksPage() {
  const { ym } = useSelectedMonth()
  const { data: month } = useMonth(ym.year, ym.month)
  const { data: banks, isLoading } = useFunds('bank')
  const { data: balances } = useFundBalances()

  const live = (banks ?? []).filter((b) => b.completed_at === null)
  const completed = (banks ?? []).filter((b) => b.completed_at !== null)

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-6">
      <section className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
            Reservas
          </h2>
          <CreateFundDialog kind="bank" />
        </div>

        {isLoading ? (
          <p className="text-muted-foreground text-sm">Carregando…</p>
        ) : !live.length ? (
          <EmptyState
            title="Sem reservas"
            description="Crie uma reserva para guardar dinheiro fora dos potes."
          />
        ) : (
          <ul className="flex flex-col divide-y divide-border">
            {live.map((b) => (
              <BankRow
                key={b.id}
                fund={b}
                balance={balances?.[b.id] ?? 0}
                month={month}
              />
            ))}
          </ul>
        )}
      </section>

      {completed.length > 0 && (
        <section className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4">
          <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
            Concluídas
          </h2>
          <div className="flex flex-col">
            {completed.map((b) => (
              <CompletedBankRow key={b.id} fund={b} />
            ))}
          </div>
        </section>
      )}
    </div>
  )
}

function CompletedBankRow({ fund }: { fund: Fund }) {
  const { data: history } = useFundHistory(fund.id)

  return (
    <Collapsible>
      <CollapsibleTrigger className="group flex w-full items-center gap-2 rounded-md px-2 py-2 text-left hover:bg-muted">
        <ChevronRight className="size-4 shrink-0 transition-transform group-data-[state=open]:rotate-90" />
        <span className="flex-1 truncate text-sm font-medium">{fund.name}</span>
        <span className="text-muted-foreground text-xs tabular-nums">
          {history?.length ?? 0}
        </span>
        <Badge variant="secondary">
          {fund.completed_at
            ? formatISODate(fund.completed_at.slice(0, 10))
            : 'Concluída'}
        </Badge>
      </CollapsibleTrigger>
      <CollapsibleContent>
        <ul className="border-border mt-1 ml-6 flex max-h-64 flex-col divide-y overflow-y-auto border-l pl-2">
          {(history ?? []).map((e) => (
            <li
              key={e.id}
              className="flex items-center gap-2 py-1.5 pr-1 text-sm"
            >
              <span className="text-muted-foreground shrink-0 text-xs tabular-nums">
                {formatISODate(e.paid_on)}
              </span>
              <span className="flex-1 truncate">{e.note ?? '—'}</span>
              <Money
                cents={e.fund_flow === 'in' ? e.amount_cents : -e.amount_cents}
                size="sm"
                sign="sign"
                tone={e.fund_flow === 'in' ? 'positive' : 'negative'}
              />
            </li>
          ))}
          {(history ?? []).length === 0 && (
            <li className="text-muted-foreground py-1.5 text-xs">
              Nenhuma entrada
            </li>
          )}
        </ul>
      </CollapsibleContent>
    </Collapsible>
  )
}
