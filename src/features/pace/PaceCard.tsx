import { useEffect } from 'react'
import { RotateCcw } from 'lucide-react'

import { EmptyState } from '@/components/EmptyState'
import { Money } from '@/components/Money'
import { ProgressBar } from '@/components/ProgressBar'
import { Button } from '@/components/ui/button'
import { monthLabel } from '@/lib/dates'
import { useEntries } from '@/features/entries/hooks'
import { extrasTotal, useExtras } from '@/features/extras/hooks'
import {
  useLatestOpenMonth,
  type Month,
} from '@/features/months/hooks'
import { useSelectedMonth } from '@/features/months/selectedMonth'

import { useEnsurePace, usePaceSnapshots, useRecalcPace } from './hooks'
import {
  mondayOf,
  paceLeft,
  spentInWindow,
  todayISO,
  type PaceKind,
  type PaceScope,
} from './pace'

// Daily + weekly spending pace. The pod tracks the LATEST open month — the
// same canonical target money movements use — so the header names it.
// Figures are fixed per period (midnight / Monday) snapshots in
// pace_snapshots; what you see is allowance − already spent in the window,
// with a bar filling toward 100% of the allowance.
export function PaceCard({ viewedMonth }: { viewedMonth: Month }) {
  const { data: month } = useLatestOpenMonth()
  const { navigate } = useSelectedMonth()
  const { data: entries } = useEntries(month?.id)
  const { data: extras } = useExtras(month?.id)
  const { data: snapshots } = usePaceSnapshots(month?.id)
  const ensure = useEnsurePace()
  const recalc = useRecalcPace()

  const today = todayISO()
  const monday = mondayOf(today)
  const extrasCents = extrasTotal(extras)
  const monthEntries = entries ?? []

  const snap = (kind: PaceKind, scope: PaceScope, start: string) =>
    snapshots?.find(
      (s) =>
        s.kind === kind && s.scope === scope && s.period_start === start,
    )

  const dayAll = snap('day', 'all', today)
  const weekAll = snap('week', 'all', monday)
  const dayEss = snap('day', 'essential', today)
  const dayFun = snap('day', 'fun', today)

  // Write the current period's fixed figures once the inputs are in —
  // missing rows (new day, new Monday) get created here for every scope;
  // existing rows are never touched outside Recalcular.
  useEffect(() => {
    if (!month || !entries || !extras || !snapshots) return
    const have = new Set(
      snapshots.map((s) => `${s.scope}:${s.kind}:${s.period_start}`),
    )
    const missing = (['all', 'essential', 'fun'] as PaceScope[]).some(
      (s) =>
        !have.has(`${s}:day:${today}`) || !have.has(`${s}:week:${monday}`),
    )
    if (!missing) return
    ensure.mutate({ month, entries, extrasCents, existing: snapshots })
  }, [month, entries, extras, snapshots, today, monday, extrasCents, ensure])

  if (!month) return null

  // The pod's figures belong to the latest open month only — on any other
  // month show a pointer back instead of foreign numbers.
  if (viewedMonth.id !== month.id) {
    return (
      <section
        aria-label="Ritmo de gastos"
        className="flex h-full flex-col rounded-lg border border-border bg-card p-4"
      >
        <header className="flex items-center justify-between gap-2">
          <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
            Ritmo —{' '}
            <span className="capitalize">
              {monthLabel(month.year, month.month)}
            </span>
          </h2>
        </header>
        <EmptyState
          className="mt-3 flex-1"
          title={
            viewedMonth.status === 'closed'
              ? 'Mês já fechado, não possui orçamento semanal e diário.'
              : `O ritmo é calculado sobre ${monthLabel(month.year, month.month)}.`
          }
          description="Volte para o mês atual para ver o valor."
        >
          <Button
            size="lg"
            className="mt-2 bg-negative px-6 text-background hover:bg-negative/80"
            onClick={() => navigate(month.year, month.month)}
          >
            Voltar para o mês atual
          </Button>
        </EmptyState>
      </section>
    )
  }

  const spentToday = spentInWindow(monthEntries, 'all', today, today)
  const spentWeek = spentInWindow(monthEntries, 'all', monday, today)
  const hoje = dayAll
    ? paceLeft(dayAll.allowance_cents, spentToday, dayAll.spent_baseline_cents)
    : null
  const semana = weekAll
    ? paceLeft(
        weekAll.allowance_cents,
        spentWeek,
        weekAll.spent_baseline_cents,
      )
    : null
  const essHoje =
    dayEss === undefined
      ? null
      : paceLeft(
          dayEss.allowance_cents,
          spentInWindow(monthEntries, 'essential', today, today),
          dayEss.spent_baseline_cents,
        )
  const funHoje =
    dayFun === undefined
      ? null
      : paceLeft(
          dayFun.allowance_cents,
          spentInWindow(monthEntries, 'fun', today, today),
          dayFun.spent_baseline_cents,
        )

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
            })
          }
        >
          <RotateCcw className="size-3.5" />
        </Button>
      </header>

      <div className="mt-3">
        <p className="text-sm text-muted-foreground">Diário — resta hoje</p>
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
        <UsageBar
          spent={spentToday - (dayAll?.spent_baseline_cents ?? 0)}
          allowance={dayAll?.allowance_cents}
        />
      </div>

      <div className="mt-3">
        <p className="text-sm text-muted-foreground">Semanal — resta</p>
        {semana !== null ? (
          <Money
            cents={semana}
            size="xl"
            sign="sign"
            className="block pod-metric"
          />
        ) : (
          <span className="text-2xl font-semibold text-muted-foreground">…</span>
        )}
        <UsageBar
          spent={spentWeek - (weekAll?.spent_baseline_cents ?? 0)}
          allowance={weekAll?.allowance_cents}
        />
      </div>

      <div className="mt-auto pt-3 text-xs text-muted-foreground">
        Essencial hoje <Money cents={essHoje ?? 0} size="sm" sign="sign" /> ·
        Lazer hoje <Money cents={funHoje ?? 0} size="sm" sign="sign" />
      </div>
    </section>
  )
}

// Bar of allowance usage: empty on a fresh period, fills as scope spending
// lands, goes negative-red once the fixed figure is busted.
function UsageBar({
  spent,
  allowance,
}: {
  spent: number
  allowance: number | undefined
}) {
  const busted = allowance !== undefined && allowance - spent < 0
  const pct =
    allowance === undefined || allowance <= 0
      ? busted
        ? 100
        : 0
      : Math.min(100, (spent / allowance) * 100)
  return (
    <ProgressBar
      pct={pct}
      tone={busted ? 'negative' : 'default'}
      className="mt-1.5"
    />
  )
}
