import { useState } from 'react'
import { Trash2 } from 'lucide-react'

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
import { useDeleteFund } from './hooks'

// Deleting a fund offers to rescue its balance into the currently open
// month's extras (goes 100% to fun) — otherwise the money just vanishes.
export function DeleteFundDialog({
  fund,
  balance,
}: {
  fund: Fund
  balance: number
}) {
  const [open, setOpen] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const deleteFund = useDeleteFund()
  const current = currentYearMonth()
  const { data: currentMonth } = useMonth(current.year, current.month)
  const canTransfer =
    balance > 0 && currentMonth != null && currentMonth.status === 'open'

  const kindLabel = fund.kind === 'bank' ? 'reserva' : 'cofrinho'

  const run = (moveToExtras: boolean) => {
    setError(null)
    deleteFund.mutate(
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
        <Button variant="ghost" size="icon-sm" aria-label={`Excluir ${fund.name}`}>
          <Trash2 className="size-3.5" />
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Excluir {kindLabel}</DialogTitle>
          <DialogDescription>
            {balance > 0 ? (
              <>
                {fund.name} ainda tem <Money cents={balance} size="sm" />. Você
                pode mover esse valor para os extras do mês atual antes de
                excluir.
              </>
            ) : (
              <>Excluir {fund.name}? Essa ação não pode ser desfeita.</>
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
              disabled={!canTransfer || deleteFund.isPending}
            >
              Mover <Money cents={balance} size="sm" /> para extras e excluir
            </Button>
          )}
          {balance > 0 && !canTransfer && (
            <p className="text-muted-foreground text-xs">
              Abra o mês atual para receber o valor como extra.
            </p>
          )}
          <Button
            variant="outline"
            onClick={() => run(false)}
            disabled={deleteFund.isPending}
          >
            {balance > 0 ? 'Excluir sem mover' : 'Excluir'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
