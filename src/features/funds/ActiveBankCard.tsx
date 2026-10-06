import { useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'

import { EmptyState } from '@/components/EmptyState'
import { Money } from '@/components/Money'
import { Button } from '@/components/ui/button'
import { monthLabel } from '@/lib/dates'
import type { Month } from '@/features/months/hooks'

import {
  useFundBalances,
  useFundEntries,
  useFunds,
} from './hooks'

// The "active bank" card: shows the balance of the currently active bank and
// the spends it absorbed this month. Arrows cycle through active banks when
// more than one is on.
export function ActiveBankCard({ month }: { month: Month }) {
  const { data: banks } = useFunds('bank')
  const { data: balances } = useFundBalances()
  const { data: fundEntries } = useFundEntries(month.id)
  const [index, setIndex] = useState(0)

  const active = (banks ?? []).filter((b) => b.active)
  const bank = active[index % Math.max(active.length, 1)]

  const spends = bank
    ? (fundEntries ?? []).filter(
        (e) => e.fund_id === bank.id && e.fund_flow === 'out',
      )
    : []
  const spent = spends.reduce((s, e) => s + e.amount_cents, 0)
  const balance = bank ? (balances?.[bank.id] ?? 0) : 0
  const label = monthLabel(month.year, month.month)

  return (
    <section className="flex h-full flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
          Reserva ativa
        </h2>
        {active.length > 1 && (
          <div className="flex items-center">
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="Reserva anterior"
              onClick={() =>
                setIndex((i) => (i - 1 + active.length) % active.length)
              }
            >
              <ChevronLeft className="size-4" />
            </Button>
            <span className="min-w-8 text-center text-xs text-muted-foreground">
              {(index % active.length) + 1}/{active.length}
            </span>
            <Button
              variant="ghost"
              size="icon-sm"
              aria-label="Próxima reserva"
              onClick={() => setIndex((i) => (i + 1) % active.length)}
            >
              <ChevronRight className="size-4" />
            </Button>
          </div>
        )}
      </div>

      {!bank ? (
        <EmptyState
          title="Nenhuma reserva ativa"
          description="Ative uma reserva para gastar dela sem contar nos potes."
        />
      ) : (
        <>
          <p className="truncate text-lg font-semibold">{bank.name}</p>

          <div className="flex items-end justify-between">
            <div className="flex flex-col gap-1">
              <span className="text-xs text-muted-foreground">Saldo</span>
              <Money cents={balance} size="xl" />
            </div>
            <div className="flex flex-col items-end gap-1">
              <span className="text-xs text-muted-foreground">
                Gasto em {label}
              </span>
              <Money cents={spent} size="lg" tone="negative" />
            </div>
          </div>

          {spends.length > 0 && (
            <ul className="mt-auto flex flex-col gap-1 border-t border-border pt-2">
              {spends.slice(0, 4).map((e) => (
                <li
                  key={e.id}
                  className="flex items-center justify-between gap-2 text-sm"
                >
                  <span className="text-muted-foreground">
                    {e.paid_on.split('-')[2]}/
                    {e.paid_on.split('-')[1]}
                  </span>
                  <span className="flex-1 truncate text-muted-foreground">
                    {e.note ?? bank.name}
                  </span>
                  <Money cents={e.amount_cents} size="sm" tone="negative" />
                </li>
              ))}
              {spends.length > 4 && (
                <li className="text-xs text-muted-foreground">
                  + {spends.length - 4} lançamento(s)
                </li>
              )}
            </ul>
          )}
        </>
      )}
    </section>
  )
}
