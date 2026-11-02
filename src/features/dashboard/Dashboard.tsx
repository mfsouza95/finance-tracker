import { ActiveBankCard } from '@/features/funds/ActiveBankCard'
import { BanksPanel } from '@/features/funds/BanksPanel'
import { PiggySummaryCard } from '@/features/funds/PiggySummaryCard'
import { RecurringPanel } from '@/features/recurring/RecurringPanel'
import { OpenMonthPrompt } from '@/features/months/OpenMonthPrompt'
import { PaceCard } from '@/features/pace/PaceCard'
import { useMonth } from '@/features/months/hooks'
import { useSelectedMonth } from '@/features/months/selectedMonth'

import { BucketPanel } from './BucketPanel'
import { MonthSummary } from './MonthSummary'

export function Dashboard() {
  const { ym } = useSelectedMonth()
  const { data: month, isLoading, error } = useMonth(ym.year, ym.month)

  if (isLoading) {
    return <p className="text-muted-foreground">Carregando…</p>
  }
  if (error) {
    return (
      <p role="alert" className="text-negative">
        {error.message}
      </p>
    )
  }
  if (!month) {
    // No month row for the selected year/month: the prompt can open it via
    // open_month; navigation lives in the header's MonthNav.
    return <OpenMonthPrompt />
  }

  // One 6-col grid (see .dash-grid in index.css): rows 1/3 hold three
  // 2-col pods, the middle row holds two 3-col pods. Row heights follow
  // --dash-mid; below 1500px the grid collapses to equal columns with
  // auto heights. Pod order is fixed: Resumo, Ritmo, Reserva ativa /
  // Essencial, Lazer / Reservas, Recorrentes, Cofrinhos.
  return (
    <div className="dash-grid flex-1">
      <div className="dash-pod">
        <MonthSummary month={month} />
      </div>
      <div className="dash-pod">
        <PaceCard />
      </div>
      <div className="dash-pod">
        <ActiveBankCard month={month} />
      </div>
      <div className="dash-pod dash-pod--wide">
        <BucketPanel month={month} bucket="essential" title="Essencial" />
      </div>
      <div className="dash-pod dash-pod--wide">
        <BucketPanel month={month} bucket="fun" title="Lazer" />
      </div>
      <div className="dash-pod">
        <BanksPanel />
      </div>
      <div className="dash-pod">
        <RecurringPanel />
      </div>
      <div className="dash-pod">
        <PiggySummaryCard />
      </div>
    </div>
  )
}
