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

  return (
    <div className="grid grid-cols-3 items-stretch gap-6">
      <MonthSummary month={month} />
      <BucketPanel month={month} bucket="essential" title="Essencial" />
      <BucketPanel month={month} bucket="fun" title="Diversão" />
      <RecurringPanel />
    </div>
  )
}
