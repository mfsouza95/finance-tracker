import { useState } from 'react'
import { Plus } from 'lucide-react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { monthLabel, todayInMonthISO } from '@/lib/dates'
import { parseBrlToCents } from '@/lib/money'
import { useLatestOpenMonth } from '@/features/months/hooks'

import type { Fund } from './hooks'
import { useDepositToFund } from './hooks'

// Deposit money into a fund: each nonzero bucket amount becomes an entry
// in that bucket (charged at deposit time) and credits the fund. Deposits
// are a money movement — they always charge the LATEST open month, not the
// one on screen, and the dialog names that target.
export function DepositDialog({ fund }: { fund: Fund }) {
  const { data: month } = useLatestOpenMonth()
  const [open, setOpen] = useState(false)
  const [essential, setEssential] = useState('')
  const [fun, setFun] = useState('')
  const [note, setNote] = useState('')
  // null = untouched, shows the default (today clamped to the target month);
  // follows the latest open month automatically.
  const [paidOnInput, setPaidOnInput] = useState<string | null>(null)
  const paidOn =
    paidOnInput ?? (month ? todayInMonthISO(month.year, month.month) : '')
  const [error, setError] = useState<string | null>(null)
  const deposit = useDepositToFund()

  const submit = () => {
    if (!month) return
    const e = essential.trim() === '' ? 0 : parseBrlToCents(essential)
    const f = fun.trim() === '' ? 0 : parseBrlToCents(fun)
    if (e === null || f === null || e < 0 || f < 0) {
      setError('Informe valores válidos (ex.: 250,00)')
      return
    }
    if (e + f <= 0) {
      setError('Informe um valor em pelo menos um pote')
      return
    }
    setError(null)
    deposit.mutate(
      {
        fundId: fund.id,
        monthId: month.id,
        essentialCents: e,
        funCents: f,
        paidOn: paidOn || undefined,
        note: note.trim() || undefined,
      },
      {
        onSuccess: () => {
          setEssential('')
          setFun('')
          setNote('')
          setPaidOnInput(null)
          setOpen(false)
        },
        onError: (err) => setError(err.message),
      },
    )
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label={`Depositar em ${fund.name}`}
          disabled={!month}
        >
          <Plus className="size-3.5" />
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Depositar em {fund.name}</DialogTitle>
          <DialogDescription>
            {month
              ? `O valor sai dos potes de ${monthLabel(month.year, month.month)} e vai para ${fund.name}.`
              : 'Abra um mês para depositar.'}
          </DialogDescription>
        </DialogHeader>

        <div className="grid grid-cols-2 gap-2">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="dep-essential" className="text-sm font-medium">
              Do Essencial
            </label>
            <Input
              id="dep-essential"
              inputMode="decimal"
              placeholder="0,00"
              value={essential}
              onChange={(e) => setEssential(e.target.value)}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label htmlFor="dep-fun" className="text-sm font-medium">
              Do Lazer
            </label>
            <Input
              id="dep-fun"
              inputMode="decimal"
              placeholder="0,00"
              value={fun}
              onChange={(e) => setFun(e.target.value)}
            />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="dep-date" className="text-sm font-medium">
              Data
            </label>
            <Input
              id="dep-date"
              type="date"
              value={paidOn}
              onChange={(e) => setPaidOnInput(e.target.value)}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <label htmlFor="dep-note" className="text-sm font-medium">
              Nota (opcional)
            </label>
            <Input
              id="dep-note"
              placeholder={fund.name}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && submit()}
            />
          </div>
        </div>

        {error && (
          <p role="alert" className="text-negative text-sm">
            {error}
          </p>
        )}
        <Button onClick={submit} disabled={deposit.isPending || !month}>
          {deposit.isPending ? 'Depositando…' : 'Depositar'}
        </Button>
      </DialogContent>
    </Dialog>
  )
}
