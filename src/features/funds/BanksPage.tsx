import { RotateCcw } from 'lucide-react'

import { EmptyState } from '@/components/EmptyState'
import { Money } from '@/components/Money'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { useMonth } from '@/features/months/hooks'
import { useSelectedMonth } from '@/features/months/selectedMonth'

import type { Fund } from './hooks'
import {
  useFundBalances,
  useFundSpendCounts,
  useFunds,
  useRestoreFund,
} from './hooks'
import { BankRow, CreateFundDialog } from './BanksPanel'
import { FundHistoryRow } from './FundHistoryRow'

// Full bank (reserva) management: create, activate/deactivate, deposit,
// complete and delete. Completed banks live in the month history;
// deletion-flagged ones wait here in Excluídas until the month closes —
// recoverable with the restore button.
export function BanksPage() {
  const { ym } = useSelectedMonth()
  const { data: month } = useMonth(ym.year, ym.month)
  const { data: banks, isLoading } = useFunds('bank')
  const { data: balances } = useFundBalances()
  const { data: spendCounts } = useFundSpendCounts()
  const restore = useRestoreFund()

  const live = (banks ?? []).filter(
    (b) => b.completed_at === null && b.deleted_at === null,
  )
  const deleted = (banks ?? []).filter((b) => b.deleted_at !== null)

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
                hasSpends={(spendCounts?.[b.id] ?? 0) > 0}
                month={month}
              />
            ))}
          </ul>
        )}
      </section>

      {deleted.length > 0 && (
        <section className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4">
          <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
            Excluídas
          </h2>
          <p className="text-muted-foreground text-xs">
            Serão excluídas permanentemente quando o mês atual fechar — o
            saldo restante vai para os extras daquele mês.
          </p>
          <div className="flex flex-col">
            {deleted.map((b) => (
              <DeletedBankRow
                key={b.id}
                fund={b}
                balance={balances?.[b.id] ?? 0}
                onRestore={() => restore.mutate(b.id)}
                restoring={restore.isPending}
              />
            ))}
          </div>
        </section>
      )}
    </div>
  )
}

function DeletedBankRow({
  fund,
  balance,
  onRestore,
  restoring,
}: {
  fund: Fund
  balance: number
  onRestore: () => void
  restoring: boolean
}) {
  return (
    <FundHistoryRow
      fund={fund}
      badge={
        <>
          <Money cents={balance} size="sm" />
          <Badge variant="destructive">Excluída</Badge>
        </>
      }
      action={
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label={`Recuperar ${fund.name}`}
          onClick={onRestore}
          disabled={restoring}
        >
          <RotateCcw className="size-3.5" />
        </Button>
      }
    />
  )
}
