import { useState } from 'react'
import { Plus, Trash2 } from 'lucide-react'

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
import { Input } from '@/components/ui/input'
import { formatISODate, todayInMonthISO } from '@/lib/dates'
import { parseBrlToCents } from '@/lib/money'
import { useSession } from '@/features/auth/useSession'
import type { Month } from '@/features/months/hooks'

import { useAddExtra, useDeleteExtra, useExtras } from './hooks'

// Extra income rows for a month — receipts that bypass the split and go 100%
// to the fun bucket (a friend paying back a written-off loan, cashback, ...).
// Lives in the Resumo card's action row; read-only when the month is closed.
export function ExtrasDialog({ month }: { month: Month }) {
  const { data: extras } = useExtras(month.id)
  const deleteExtra = useDeleteExtra()
  const isOpen = month.status === 'open'

  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <Plus className="size-4" />
          Extras
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Extras recebidos</DialogTitle>
          <DialogDescription>
            Valores fora da renda — vão 100% para Diversão.
          </DialogDescription>
        </DialogHeader>

        {extras && extras.length > 0 ? (
          <ul className="flex flex-col divide-y divide-border">
            {extras.map((x) => (
              <li key={x.id} className="flex items-center gap-2 py-1.5 text-sm">
                <span className="text-muted-foreground w-12 shrink-0 text-xs tabular-nums">
                  {formatISODate(x.received_on)}
                </span>
                <span className="flex-1 truncate">{x.note ?? '—'}</span>
                <Money cents={x.amount_cents} size="sm" sign="sign" />
                {isOpen && (
                  <Button
                    variant="ghost"
                    size="icon-sm"
                    aria-label="Excluir extra"
                    onClick={() => {
                      if (confirm('Excluir este extra?')) {
                        deleteExtra.mutate(x.id)
                      }
                    }}
                  >
                    <Trash2 className="size-3.5" />
                  </Button>
                )}
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-muted-foreground text-sm">
            Nenhum extra neste mês.
          </p>
        )}

        {isOpen && <AddExtraForm month={month} />}
      </DialogContent>
    </Dialog>
  )
}

function AddExtraForm({ month }: { month: Month }) {
  const { session } = useSession()
  const addExtra = useAddExtra()
  const [amount, setAmount] = useState('')
  const [note, setNote] = useState('')
  const [receivedOn, setReceivedOn] = useState(() =>
    todayInMonthISO(month.year, month.month),
  )
  const [error, setError] = useState<string | null>(null)

  const monthPrefix = `${month.year}-${String(month.month).padStart(2, '0')}`

  const submit = () => {
    const cents = parseBrlToCents(amount)
    if (cents === null || cents <= 0) {
      setError('Informe um valor válido (ex.: 250,00)')
      return
    }
    if (!receivedOn.startsWith(monthPrefix)) {
      setError('A data precisa ser dentro do mês')
      return
    }
    if (!session) return
    setError(null)
    addExtra.mutate(
      {
        userId: session.user.id,
        monthId: month.id,
        amountCents: cents,
        receivedOn,
        note: note.trim() || undefined,
      },
      {
        onSuccess: () => {
          setAmount('')
          setNote('')
        },
        onError: (e) => setError(e.message),
      },
    )
  }

  return (
    <div className="flex flex-col gap-2">
      <div className="grid grid-cols-2 gap-2">
        <Input
          inputMode="decimal"
          placeholder="Valor (ex.: 250,00)"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          aria-label="Valor do extra"
        />
        <Input
          type="date"
          value={receivedOn}
          onChange={(e) => setReceivedOn(e.target.value)}
          aria-label="Data do recebimento"
        />
      </div>
      <Input
        placeholder="Nota (ex.: João pagou o empréstimo)"
        value={note}
        onChange={(e) => setNote(e.target.value)}
        onKeyDown={(e) => e.key === 'Enter' && submit()}
        aria-label="Nota do extra"
      />
      {error && (
        <p role="alert" className="text-negative text-xs">
          {error}
        </p>
      )}
      <Button onClick={submit} disabled={addExtra.isPending}>
        {addExtra.isPending ? 'Salvando…' : 'Adicionar'}
      </Button>
    </div>
  )
}
