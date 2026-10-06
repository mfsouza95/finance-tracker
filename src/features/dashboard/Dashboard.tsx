import { useState } from 'react'

import { AppHeader } from '@/components/AppHeader'
import { AppShell } from '@/app/AppShell'
import { Button } from '@/components/ui/button'
import { useCategories } from '@/features/categories/hooks'
import { AddEntryForm } from '@/features/entries/AddEntryForm'
import { HistoryPanel } from '@/features/history/HistoryPanel'
import { RecurringPanel } from '@/features/recurring/RecurringPanel'
import { OpenMonthPrompt } from '@/features/months/OpenMonthPrompt'
import { useMonth } from '@/features/months/hooks'
import { signOut } from '@/features/auth/useSession'
import { currentYearMonth } from '@/lib/dates'

import { BucketPanel } from './BucketPanel'
import { MonthSummary } from './MonthSummary'

export function Dashboard() {
  const [ym, setYm] = useState(currentYearMonth)
  const { data: month, isLoading, error } = useMonth(ym.year, ym.month)
  const { data: categories } = useCategories()

  const navigate = (year: number, month: number) => setYm({ year, month })

  if (isLoading) {
    return <p className="text-muted-foreground p-6">Carregando…</p>
  }
  if (error) {
    return (
      <p role="alert" className="text-negative p-6">
        {error.message}
      </p>
    )
  }
  if (!month) {
    // No month row for the selected year/month: header stays so the user can
    // always sign out (a wiped DB leaves a stale session behind), and the
    // prompt can open that month via open_month.
    return (
      <div className="flex min-h-dvh flex-col">
        <AppHeader
          title="finance-tracker"
          actions={
            <Button variant="ghost" onClick={() => void signOut()}>
              Sair
            </Button>
          }
        />
        <OpenMonthPrompt
          year={ym.year}
          month={ym.month}
          onNavigate={navigate}
        />
      </div>
    )
  }

  return (
    <AppShell
      summary={<MonthSummary month={month} onNavigate={navigate} />}
      essential={
        <BucketPanel month={month} bucket="essential" title="Essencial" />
      }
      fun={<BucketPanel month={month} bucket="fun" title="Diversão" />}
      history={<HistoryPanel />}
      recurring={<RecurringPanel />}
      addEntry={(onDone) =>
        month.status === 'open' ? (
          <AddEntryForm
            month={month}
            categories={categories ?? []}
            onDone={onDone}
          />
        ) : (
          <p className="text-muted-foreground text-sm">
            Mês fechado — entradas são somente leitura.
          </p>
        )
      }
    />
  )
}
