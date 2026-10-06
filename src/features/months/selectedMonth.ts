import { createContext, useContext } from 'react'

export type YearMonth = { year: number; month: number }

export interface SelectedMonthValue {
  ym: YearMonth
  navigate: (year: number, month: number) => void
}

export const SelectedMonthContext = createContext<SelectedMonthValue | null>(
  null,
)

export function useSelectedMonth() {
  const ctx = useContext(SelectedMonthContext)
  if (!ctx)
    throw new Error('useSelectedMonth must be used inside SelectedMonthProvider')
  return ctx
}
