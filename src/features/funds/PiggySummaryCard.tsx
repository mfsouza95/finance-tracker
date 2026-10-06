import { Check } from 'lucide-react'
import { Link } from 'react-router-dom'

import { EmptyState } from '@/components/EmptyState'
import { Money } from '@/components/Money'
import { Button } from '@/components/ui/button'

import {
  useFundBalances,
  useFunds,
  useUpdateFund,
} from './hooks'
import { DeleteFundDialog } from './DeleteFundDialog'

// Compact piggy-bank summary for the dashboard — progress, mark-as-done and
// delete. Full management lives on /cofrinhos.
export function PiggySummaryCard() {
  const { data: piggies } = useFunds('piggy')
  const { data: balances } = useFundBalances()
  const update = useUpdateFund()

  const open = (piggies ?? []).filter((p) => p.achieved_at === null)

  return (
    <section className="flex h-full flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
          Cofrinhos
        </h2>
        <Button variant="outline" size="sm" asChild>
          <Link to="/cofrinhos">Ver tudo</Link>
        </Button>
      </div>

      {!open.length ? (
        <EmptyState
          title="Sem cofrinhos"
          description="Crie uma meta na página de cofrinhos."
        />
      ) : (
        <ul className="flex flex-col gap-3">
          {open.map((p) => {
            const saved = balances?.[p.id] ?? 0
            const goal = p.goal_cents ?? 0
            const pct = goal > 0 ? Math.min(100, (saved / goal) * 100) : 0
            return (
              <li key={p.id} className="flex flex-col gap-1.5">
                <div className="flex items-center gap-2">
                  <span className="flex-1 truncate text-sm font-medium">
                    {p.name}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    <Money cents={saved} size="sm" /> de{' '}
                    <Money cents={goal} size="sm" />
                  </span>
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label={`Concluir ${p.name}`}
                    onClick={() =>
                      update.mutate({
                        fundId: p.id,
                        patch: { achieved_at: new Date().toISOString() },
                      })
                    }
                  >
                    <Check className="size-3.5" />
                  </Button>
                  <DeleteFundDialog fund={p} balance={saved} />
                </div>
                <div className="h-1.5 overflow-hidden rounded-full bg-input">
                  <div
                    className="h-full bg-positive transition-all"
                    style={{ width: `${pct}%` }}
                  />
                </div>
              </li>
            )
          })}
        </ul>
      )}
    </section>
  )
}
