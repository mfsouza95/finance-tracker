import { useEffect, useState } from 'react'
import { RotateCcw } from 'lucide-react'

import { Money } from '@/components/Money'
import { Button } from '@/components/ui/button'
import { monthLabel } from '@/lib/dates'
import { computeBuckets } from '@/lib/money'
import { useEntries } from '@/features/entries/hooks'
import { extrasTotal, useExtras } from '@/features/extras/hooks'
import { useLatestOpenMonth } from '@/features/months/hooks'

import { useEnsurePace, usePaceSnapshots, useRecalcPace } from './hooks'
import {
  mondayOf,
  scopeBudgetCents,
  scopeSpentCents,
  spentInWindow,
  todayISO,
  type PaceScope,
} from './pace'

const SCOPES = [
  ['all', 'Todos'],
  ['essential', 'Essencial'],
  ['fun', 'Lazer'],
] as const

// Daily + weekly spending pace. The pod tracks the LATEST open month — the
// same canonical target money movements use — so the header names it.
// Figures are fixed per period (midnight / Monday) snapshots in
// pace_snapshots; what you see is allowance − already spent in the window.
export function PaceCard() {
  const { data: month } = useLatestOpenMonth()
  const { data: entries } = useEntries(month?.id)
  const { data: extras } = useExtras(month?.id)
  const { data: snapshots } = usePaceSnapshots(month?.id)
  const [scope, setScope] = useState<PaceScope>('all')
  const ensure = useEnsurePace()
  const recalc = useRecalcPace()

  const today = todayISO()
  const monday = mondayOf(today)
  const extrasCents = extrasTotal(extras)

  const dayRow = snapshots?.find(
    (s) => s.kind === 'day' && s.scope === scope && s.period_start === today,
  )
  const weekRow = snapshots?.find(
    (s) =>
      s.kind === 'week' && s.scope === scope && s.period_start === monday,
  )

  // Write the current period's fixed figures once the inputs are in —
  // missing rows (new day, new Monday, first time on a scope) get created
  // here; existing rows are never touched outside Recalcular.
  useEffect(() => {
    if (!month || !entries || !extras || !snapshots) return
    if (dayRow && weekRow) return
    ensure.mutate({ month, entries, extrasCents, scope, existing: snapshots })
  }, [month, entries, extras, snapshots, dayRow, weekRow, extrasCents, scope, ensure])

  if (!month) return null

  const buckets = computeBuckets(month.net_income_cents, {
    essentialPct: month.essential_pct,
    funPct: month.fun_pct,
    investPct: month.invest_pct,
  })
  const monthEntries = entries ?? []
  const spentToday = spentInWindow(monthEntries, scope, today, today)
  const spentWeek = spentInWindow(monthEntries, scope, monday, today)
  const hoje = dayRow ? dayRow.allowance_cents - spentToday : null
  const semana = weekRow ? weekRow.allowance_cents - spentWeek : null
  const remaining =
    scopeBudgetCents(buckets, extrasCents, scope) -
    scopeSpentCents(monthEntries, scope)
  const restE =
    buckets.essential - scopeSpentCents(monthEntries, 'essential')
  const restF =
    buckets.fun + extrasCents - scopeSpentCents(monthEntries, 'fun')

  return (
    <section
      aria-label="Ritmo de gastos"
      className="flex h-full flex-col rounded-lg border border-border bg-card p-4"
    >
      <header className="flex items-center justify-between gap-2">
        <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
          Ritmo — <span className="capitalize">{monthLabel(month.year, month.month)}</span>
        </h2>
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label="Recalcular ritmo"
          title="Recalcular com o saldo atual"
          disabled={recalc.isPending}
          onClick={() =>
            month &&
            recalc.mutate({
              month,
              entries: monthEntries,
              extrasCents,
              scope,
            })
          }
        >
          <RotateCcw className="size-3.5" />
        </Button>
      </header>

      <div className="mt-2 flex gap-1">
        {SCOPES.map(([key, label]) => (
          <Button
            key={key}
            variant={scope === key ? 'secondary' : 'ghost'}
            size="sm"
            onClick={() => setScope(key)}
          >
            {label}
          </Button>
        ))}
      </div>

      <p className="mt-3 text-sm text-muted-foreground">Hoje</p>
      {hoje !== null ? (
        <Money
          cents={hoje}
          size="xl"
          sign="sign"
          className="block pod-metric"
        />
      ) : (
        <span className="text-2xl font-semibold text-muted-foreground">…</span>
      )}

      <div className="mt-2 flex items-baseline justify-between gap-2">
        <span className="text-sm text-muted-foreground">Esta semana</span>
        {semana !== null ? (
          <Money cents={semana} size="lg" sign="sign" />
        ) : (
          <span className="text-lg text-muted-foreground">…</span>
        )}
      </div>

      <div className="mt-auto pt-3 text-xs text-muted-foreground">
        {scope === 'all' ? (
          <>
            Resta Essencial <Money cents={restE} size="sm" /> · Lazer{' '}
            <Money cents={restF} size="sm" />
          </>
        ) : (
          <>
            Resta no pote <Money cents={remaining} size="sm" sign="sign" />
          </>
        )}
      </div>
    </section>
  )
}
