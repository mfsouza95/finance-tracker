import { useState } from 'react'
import { X } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { daysUntilISO } from '@/lib/dates'

import { useLatestOpenMonth } from './hooks'

// Fatura deadline nudge for the latest open month — informational only, the
// month is never forced to close. Shows once per page load when the
// deadline is 10 days out or past; X dismisses in memory (reappears on the
// next load). <=10d warning, <=5d caution, <=3d or overdue negative.
export function DeadlineBanner() {
  const { data: month } = useLatestOpenMonth()
  const [dismissed, setDismissed] = useState(false)
  if (dismissed || !month?.closes_on) return null

  const daysLeft = daysUntilISO(month.closes_on)
  if (daysLeft > 10) return null

  const severity =
    daysLeft <= 3 ? 'negative' : daysLeft <= 5 ? 'caution' : 'warning'
  const tone = {
    warning: 'border-warning bg-warning text-warning-foreground',
    caution: 'border-caution bg-caution text-caution-foreground',
    negative: 'border-negative bg-negative text-negative-foreground',
  }[severity]

  const text =
    daysLeft < 0
      ? `A fatura fechou há ${-daysLeft} ${pluralDia(-daysLeft)} — feche quando quiser`
      : daysLeft === 0
        ? 'A fatura fecha hoje'
        : `A fatura fecha em ${daysLeft} ${pluralDia(daysLeft)}`

  return (
    <div
      role="status"
      className={`fixed bottom-4 left-1/2 z-50 flex -translate-x-1/2 items-center gap-3 rounded-lg border px-4 py-2 text-sm font-medium shadow-lg ${tone}`}
    >
      <span>{text}</span>
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label="Dispensar aviso"
        onClick={() => setDismissed(true)}
      >
        <X className="size-3.5" />
      </Button>
    </div>
  )
}

function pluralDia(n: number) {
  return n === 1 ? 'dia' : 'dias'
}
