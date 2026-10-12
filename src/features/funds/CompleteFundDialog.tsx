import { useState } from 'react'
import { Check } from 'lucide-react'

import { Money } from '@/components/Money'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { currentYearMonth } from '@/lib/dates'
import { useMonth } from '@/features/months/hooks'

import type { Fund } from './hooks'
import { useCompleteFund } from './hooks'

// Completing a bank ends its lifecycle while keeping the history: the
// remainder offers the same extras-or-discard choice as delete, but the
// fund row (and every entry against it) is preserved.
export function CompleteFundDialog({
  fund,
  balance,
}: {
  fund: Fund
  balance: number
}) {
  const [open, setOpen] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const completeFund = useCompleteFund()
  const current = currentYearMonth()
  const { data: currentMonth } = useMonth(current.year, current.month)
  const canTransfer =
    balance > 0 && currentMonth != null && currentMonth.status === 'open'
  const canComplete = balance === 0 || canTransfer

  const run = (moveToExtras: boolean) => {
    setError(null)
    completeFund.mutate(
      { fundId: fund.id, moveToExtras },
      {
        onSuccess: () => setOpen(false),
        onError: (e) => setError(e.message),
      },
    )
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label={`Concluir ${fund.name}`}
        >
          <Check className="size-3.5" />
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Concluir reserva</DialogTitle>
          <DialogDescription>
            {balance > 0 ? (
              <>
                {fund.name} ainda tem <Money cents={balance} size="sm" />. Você
                pode mover esse valor para os extras do mês atual ao concluir.
                O histórico da reserva fica salvo.
              </>
            ) : (
              <>
                Concluir {fund.name}? Ela sai da lista de reservas e o
                histórico fica salvo.
              </>
            )}
          </DialogDescription>
        </DialogHeader>

        {error && (
          <p role="alert" className="text-negative text-sm">
            {error}
          </p>
        )}

        <div className="flex flex-col gap-2">
          {balance > 0 && (
            <Button
              onClick={() => run(true)}
              disabled={!canComplete || completeFund.isPending}
            >
              Mover <Money cents={balance} size="sm" /> para extras e concluir
            </Button>
          )}
          {balance > 0 && !canComplete && (
            <p className="text-muted-foreground text-xs">
              Abra o mês atual para concluir uma reserva com saldo.
            </p>
          )}
          <Button
            variant={balance > 0 ? 'outline' : 'default'}
            onClick={() => run(false)}
            disabled={!canComplete || completeFund.isPending}
          >
            {balance > 0 ? 'Descartar saldo e concluir' : 'Concluir'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
