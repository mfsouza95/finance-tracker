import { EmptyState } from '@/components/EmptyState'
import { useMonth } from '@/features/months/hooks'
import { useSelectedMonth } from '@/features/months/selectedMonth'

import { useFundBalances, useFunds } from './hooks'
import { BankRow, CreateFundDialog } from './BanksPanel'

// Full bank (reserva) management: create, activate/deactivate, deposit and
// delete. Active banks show up as categories when logging entries; the
// dashboard keeps a compact panel + the active-bank card.
export function BanksPage() {
  const { ym } = useSelectedMonth()
  const { data: month } = useMonth(ym.year, ym.month)
  const { data: banks, isLoading } = useFunds('bank')
  const { data: balances } = useFundBalances()

  return (
    <section className="mx-auto flex w-full max-w-2xl flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
          Reservas
        </h2>
        <CreateFundDialog kind="bank" />
      </div>

      {isLoading ? (
        <p className="text-muted-foreground text-sm">Carregando…</p>
      ) : !banks?.length ? (
        <EmptyState
          title="Sem reservas"
          description="Crie uma reserva para guardar dinheiro fora dos potes."
        />
      ) : (
        <ul className="flex flex-col divide-y divide-border">
          {banks.map((b) => (
            <BankRow
              key={b.id}
              fund={b}
              balance={balances?.get(b.id) ?? 0}
              month={month}
            />
          ))}
        </ul>
      )}
    </section>
  )
}
