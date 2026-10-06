import { useState } from 'react'
import { Settings2 } from 'lucide-react'

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
import { SPLIT_PRESETS, parseBrlToCents } from '@/lib/money'

import { useUpdateMonth, type Month } from './hooks'

// Edits net income and the split on an OPEN month only — the DB snapshot is
// authoritative and closed months reject writes anyway (23514 on bad sums).
export function MonthSettingsDialog({ month }: { month: Month }) {
  const updateMonth = useUpdateMonth()
  const [open, setOpen] = useState(false)
  const [net, setNet] = useState(() => (month.net_income_cents / 100).toFixed(2).replace('.', ','))
  const [pcts, setPcts] = useState({
    essential: String(month.essential_pct),
    fun: String(month.fun_pct),
    invest: String(month.invest_pct),
  })
  const [error, setError] = useState<string | null>(null)

  const applyPreset = (key: keyof typeof SPLIT_PRESETS) => {
    const p = SPLIT_PRESETS[key]
    setPcts({
      essential: String(p.essentialPct),
      fun: String(p.funPct),
      invest: String(p.investPct),
    })
  }

  const save = () => {
    const netCents = parseBrlToCents(net)
    const e = Number.parseInt(pcts.essential, 10)
    const f = Number.parseInt(pcts.fun, 10)
    const i = Number.parseInt(pcts.invest, 10)
    if (netCents === null || netCents < 0) {
      setError('Renda inválida')
      return
    }
    if ([e, f, i].some((n) => !Number.isInteger(n) || n < 0 || n > 100)) {
      setError('Percentuais devem ser inteiros entre 0 e 100')
      return
    }
    if (e + f + i !== 100) {
      setError('Os percentuais precisam somar 100')
      return
    }
    setError(null)
    updateMonth.mutate(
      {
        monthId: month.id,
        patch: {
          net_income_cents: netCents,
          essential_pct: e,
          fun_pct: f,
          invest_pct: i,
        },
      },
      {
        onSuccess: () => setOpen(false),
        onError: (err) => setError(err.message),
      },
    )
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <Settings2 className="size-4" />
          Ajustar mês
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Ajustar mês</DialogTitle>
          <DialogDescription>
            Renda líquida e divisão do mês em aberto.
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="net" className="text-sm font-medium">
              Renda líquida
            </label>
            <Input
              id="net"
              inputMode="decimal"
              value={net}
              onChange={(e) => setNet(e.target.value)}
            />
          </div>

          <div className="flex flex-wrap gap-2">
            {Object.keys(SPLIT_PRESETS).map((key) => (
              <Button
                key={key}
                variant="secondary"
                size="sm"
                onClick={() => applyPreset(key as keyof typeof SPLIT_PRESETS)}
              >
                {key}
              </Button>
            ))}
          </div>

          <div className="grid grid-cols-3 gap-2">
            {(
              [
                ['essential', 'Essencial %'],
                ['fun', 'Diversão %'],
                ['invest', 'Investir %'],
              ] as const
            ).map(([field, label]) => (
              <div key={field} className="flex flex-col gap-1.5">
                <label htmlFor={field} className="text-sm font-medium">
                  {label}
                </label>
                <Input
                  id={field}
                  type="number"
                  min={0}
                  max={100}
                  value={pcts[field]}
                  onChange={(e) =>
                    setPcts((p) => ({ ...p, [field]: e.target.value }))
                  }
                />
              </div>
            ))}
          </div>

          {error && (
            <p role="alert" className="text-negative text-sm">
              {error}
            </p>
          )}
          <Button onClick={save} disabled={updateMonth.isPending}>
            {updateMonth.isPending ? 'Salvando…' : 'Salvar'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
