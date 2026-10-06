import { ChevronLeft, ChevronRight } from 'lucide-react'

import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { monthLabel } from '@/lib/dates'

import { useMonth } from './hooks'
import { useSelectedMonth } from './selectedMonth'

// Centered month switcher in the app header — the single place that shows
// which month is selected, with its open/closed status.
export function MonthNav() {
  const { ym, navigate } = useSelectedMonth()
  const { data: month } = useMonth(ym.year, ym.month)

  const prev =
    ym.month === 1
      ? { year: ym.year - 1, month: 12 }
      : { year: ym.year, month: ym.month - 1 }
  const next =
    ym.month === 12
      ? { year: ym.year + 1, month: 1 }
      : { year: ym.year, month: ym.month + 1 }

  return (
    <div className="flex items-center gap-1">
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label="Mês anterior"
        onClick={() => navigate(prev.year, prev.month)}
      >
        <ChevronLeft className="size-4" />
      </Button>
      {/* Fixed width keeps the chevrons from jumping between short/long
          month names. */}
      <span className="w-36 text-center text-sm font-semibold capitalize">
        {monthLabel(ym.year, ym.month)}
      </span>
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label="Próximo mês"
        onClick={() => navigate(next.year, next.month)}
      >
        <ChevronRight className="size-4" />
      </Button>
      {month && (
        <Badge
          variant={month.status === 'open' ? 'secondary' : 'outline'}
          className="ml-1"
        >
          {month.status === 'open' ? 'Aberto' : 'Fechado'}
        </Badge>
      )}
    </div>
  )
}
