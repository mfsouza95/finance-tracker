import { useCallback, useState } from 'react'
import type { ReactNode } from 'react'

import { currentYearMonth } from '@/lib/dates'

import type { YearMonth } from './selectedMonth'
import { SelectedMonthContext } from './selectedMonth'

// Which month is being viewed lives above the router so the header nav,
// dashboard and prompts all share it, and it survives page changes.
export function SelectedMonthProvider({ children }: { children: ReactNode }) {
  const [ym, setYm] = useState<YearMonth>(currentYearMonth)
  const navigate = useCallback(
    (year: number, month: number) => setYm({ year, month }),
    [],
  )
  return (
    <SelectedMonthContext.Provider value={{ ym, navigate }}>
      {children}
    </SelectedMonthContext.Provider>
  )
}
