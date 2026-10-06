import { Check, Undo2 } from 'lucide-react'

import { EmptyState } from '@/components/EmptyState'
import { Money } from '@/components/Money'
import { Button } from '@/components/ui/button'
import { useMonth } from '@/features/months/hooks'
import { useSelectedMonth } from '@/features/months/selectedMonth'

import type { Fund } from './hooks'
import {
  useFundBalances,
  useFunds,
  useUpdateFund,
} from './hooks'
import { CreateFundDialog } from './BanksPanel'
import { DeleteFundDialog } from './DeleteFundDialog'
import { DepositDialog } from './DepositDialog'

// Full piggy-bank management: create with name + goal, deposit from the
// buckets, mark achieved, delete (optionally rescuing the balance into
// extras). The dashboard only shows a compact summary.
export function PiggyPage() {
  const { ym } = useSelectedMonth()
  const { data: month } = useMonth(ym.year, ym.month)
  const { data: piggies, isLoading } = useFunds('piggy')
  const { data: balances } = useFundBalances()

  const open = (piggies ?? []).filter((p) => p.achieved_at === null)
  const done = (piggies ?? []).filter((p) => p.achieved_at !== null)

  return (
    <section className="mx-auto flex w-full max-w-2xl flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
          Cofrinhos
        </h2>
        <CreateFundDialog kind="piggy" />
      </div>

      {isLoading ? (
        <p className="text-muted-foreground text-sm">Carregando…</p>
      ) : !piggies?.length ? (
        <EmptyState
          title="Sem cofrinhos"
          description="Crie um cofrinho com nome e meta para guardar dinheiro."
        />
      ) : (
        <ul className="flex flex-col divide-y divide-border">
          {open.map((p) => (
            <PiggyRow
              key={p.id}
              fund={p}
              saved={balances?.get(p.id) ?? 0}
              month={month}
            />
          ))}
        </ul>
      )}

      {done.length > 0 && (
        <div className="flex flex-col gap-1 border-t border-border pt-3">
          <h3 className="text-xs font-medium tracking-wide text-muted-foreground uppercase">
            Concluídos
          </h3>
          <ul className="flex flex-col divide-y divide-border">
            {done.map((p) => (
              <AchievedRow
                key={p.id}
                fund={p}
                saved={balances?.get(p.id) ?? 0}
              />
            ))}
          </ul>
        </div>
      )}
    </section>
  )
}

function PiggyRow({
  fund,
  saved,
  month,
}: {
  fund: Fund
  saved: number
  month: ReturnType<typeof useMonth>['data']
}) {
  const update = useUpdateFund()
  const goal = fund.goal_cents ?? 0
  const pct = goal > 0 ? Math.min(100, (saved / goal) * 100) : 0

  return (
    <li className="flex flex-col gap-1.5 py-2.5">
      <div className="flex items-center gap-2">
        <span className="flex-1 truncate text-sm font-medium">{fund.name}</span>
        <span className="text-sm text-muted-foreground">
          <Money cents={saved} size="sm" /> de <Money cents={goal} size="sm" />
        </span>
        {month && <DepositDialog fund={fund} month={month} />}
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label={`Concluir ${fund.name}`}
          title="Meta cumprida"
          onClick={() =>
            update.mutate({
              fundId: fund.id,
              patch: { achieved_at: new Date().toISOString() },
            })
          }
        >
          <Check className="size-3.5" />
        </Button>
        <DeleteFundDialog fund={fund} balance={saved} />
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-input">
        <div
          className="h-full bg-positive transition-all"
          style={{ width: `${pct}%` }}
        />
      </div>
    </li>
  )
}

function AchievedRow({ fund, saved }: { fund: Fund; saved: number }) {
  const update = useUpdateFund()

  return (
    <li className="flex items-center gap-2 py-2">
      <span className="flex-1 truncate text-sm text-muted-foreground line-through">
        {fund.name}
      </span>
      <Money cents={saved} size="sm" className="text-muted-foreground" />
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label={`Reabrir ${fund.name}`}
        title="Voltar para a lista"
        onClick={() =>
          update.mutate({
            fundId: fund.id,
            patch: { achieved_at: null },
          })
        }
      >
        <Undo2 className="size-3.5" />
      </Button>
      <DeleteFundDialog fund={fund} balance={saved} />
    </li>
  )
}
