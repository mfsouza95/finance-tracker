import { ActiveBankCard } from '@/features/funds/ActiveBankCard'
import { BanksPanel } from '@/features/funds/BanksPanel'
import { PiggySummaryCard } from '@/features/funds/PiggySummaryCard'
import { RecurringPanel } from '@/features/recurring/RecurringPanel'
import { OpenMonthPrompt } from '@/features/months/OpenMonthPrompt'
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

  // Three visual bands: summary-ish cards (3 cols), the two spending
  // buckets side by side (2 cols), then fund management (3 cols again).
  // Each band collapses to 2/1 columns below 2xl/md respectively.
  return (
    <div className="flex flex-col gap-4 sm:gap-6">
      <div className="grid grid-cols-1 items-stretch gap-4 sm:gap-6 md:grid-cols-2 2xl:grid-cols-3">
        <MonthSummary month={month} />
        <RecurringPanel />
        <ActiveBankCard month={month} />
      </div>
      <div className="grid grid-cols-1 items-stretch gap-4 sm:gap-6 md:grid-cols-2">
        <BucketPanel month={month} bucket="essential" title="Essencial" />
        <BucketPanel month={month} bucket="fun" title="Lazer" />
      </div>
      <div className="grid grid-cols-1 items-stretch gap-4 sm:gap-6 md:grid-cols-2 2xl:grid-cols-3">
        <BanksPanel month={month} />
        <PiggySummaryCard />
      </div>
    </div>
  )
}
