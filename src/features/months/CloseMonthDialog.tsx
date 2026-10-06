import { useState } from 'react'

import { Money } from '@/components/Money'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { computeBuckets, expectedInvestment, parseBrlToCents } from '@/lib/money'
import { useEntries } from '@/features/entries/hooks'
import { extrasTotal, useExtras } from '@/features/extras/hooks'

import { useCloseMonth, type Month } from './hooks'

// close_month is one-way: writes month_summaries and makes the month
// read-only. The invested amount defaults to the expected investment and is
// confirmed by the user (domain rule 9).
export function CloseMonthDialog({ month }: { month: Month }) {
  const { data: entries } = useEntries(month.id)
  const { data: extras } = useExtras(month.id)
  const closeMonth = useCloseMonth()
  const [open, setOpen] = useState(false)
  const [invested, setInvested] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const buckets = computeBuckets(month.net_income_cents, {
    essentialPct: month.essential_pct,
    funPct: month.fun_pct,
    investPct: month.invest_pct,
  })
  const spent = { essential: 0, fun: 0 }
  for (const e of entries ?? []) {
    spent[e.bucket] += e.amount_cents
  }
  const expected = expectedInvestment(
    buckets,
    spent.essential,
    spent.fun,
    extrasTotal(extras),
  )
  const investedDefault =
    expected > 0 ? (expected / 100).toFixed(2).replace('.', ',') : '0,00'

  const confirm = () => {
    const cents = parseBrlToCents(invested ?? investedDefault)
    if (cents === null || cents < 0) {
      setError('Informe um valor válido')
      return
    }
    setError(null)
    closeMonth.mutate(
      { monthId: month.id, investedCents: cents },
      {
        onSuccess: () => setOpen(false),
        onError: (e) => setError(e.message),
      },
    )
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="destructive" size="sm">
          Fechar mês
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Fechar o mês?</DialogTitle>
          <DialogDescription>
            O mês vira somente leitura e o resumo fica salvo no histórico.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-3 text-sm">
          <div className="flex justify-between">
            <span className="text-muted-foreground">Investimento previsto</span>
            <Money cents={expected} />
          </div>
          <div className="flex flex-col gap-1.5">
            <label htmlFor="invested" className="font-medium">
              Quanto foi investido de fato
            </label>
            <Input
              id="invested"
              inputMode="decimal"
              placeholder={investedDefault}
              value={invested ?? ''}
              onChange={(e) => setInvested(e.target.value)}
            />
          </div>
          {error && (
            <p role="alert" className="text-negative text-sm">
              {error}
            </p>
          )}
        </div>

        <DialogFooter>
          <Button
            variant="destructive"
            onClick={confirm}
            disabled={closeMonth.isPending}
          >
            {closeMonth.isPending ? 'Fechando…' : 'Confirmar fechamento'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
