import { useState } from 'react'
import { ChevronLeft, ChevronRight } from 'lucide-react'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { currentYearMonth, monthLabel } from '@/lib/dates'
import { parseBrlToCents } from '@/lib/money'
import { signOut } from '@/features/auth/useSession'

import { useOpenMonth } from './hooks'

interface OpenMonthPromptProps {
  year: number
  month: number
  onNavigate: (year: number, month: number) => void
}

// Shown for any year/month without a month row — the month only exists after
// open_month, which needs the net income to snapshot the buckets.
export function OpenMonthPrompt({
  year,
  month,
  onNavigate,
}: OpenMonthPromptProps) {
  const [net, setNet] = useState('')
  const [error, setError] = useState<string | null>(null)
  const openMonth = useOpenMonth()
  const current = currentYearMonth()
  const isCurrent = year === current.year && month === current.month
  const isFuture =
    year > current.year || (year === current.year && month > current.month)

  const prev =
    month === 1 ? { year: year - 1, month: 12 } : { year, month: month - 1 }
  const next =
    month === 12 ? { year: year + 1, month: 1 } : { year, month: month + 1 }

  const submit = () => {
    const cents = parseBrlToCents(net)
    if (cents === null || cents < 0) {
      setError('Informe um valor válido (ex.: 5.000,00)')
      return
    }
    setError(null)
    openMonth.mutate(
      { year, month, netIncomeCents: cents },
      { onError: (e) => setError(e.message) },
    )
  }

  return (
    <main className="mx-auto flex max-w-sm flex-col gap-4 p-6">
      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label="Mês anterior"
          onClick={() => onNavigate(prev.year, prev.month)}
        >
          <ChevronLeft className="size-4" />
        </Button>
        <h2 className="text-lg font-semibold capitalize">
          Abrir {monthLabel(year, month)}
        </h2>
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label="Próximo mês"
          onClick={() => onNavigate(next.year, next.month)}
        >
          <ChevronRight className="size-4" />
        </Button>
      </div>

      {isFuture ? (
        <p className="text-muted-foreground text-sm">
          Este mês ainda não começou — só é possível abrir o mês atual ou meses
          passados.
        </p>
      ) : (
        <>
          <p className="text-muted-foreground text-sm">
            Este mês ainda não foi aberto. Informe a renda líquida para gerar os
            orçamentos.
          </p>
          <label htmlFor="net" className="text-sm font-medium">
            Renda líquida
          </label>
          <Input
            id="net"
            inputMode="decimal"
            placeholder="0,00"
            value={net}
            onChange={(e) => setNet(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && submit()}
          />
          {error && (
            <div className="flex flex-col gap-2">
              <p role="alert" className="text-negative text-sm">
                {error}
              </p>
              <p className="text-muted-foreground text-xs">
                Se o banco foi resetado, sua sessão ficou velha — saia e entre
                de novo.
              </p>
              <Button
                variant="ghost"
                size="sm"
                className="self-start"
                onClick={() => void signOut()}
              >
                Sair
              </Button>
            </div>
          )}
          <Button onClick={submit} disabled={openMonth.isPending}>
            {openMonth.isPending ? 'Abrindo…' : 'Abrir mês'}
          </Button>
        </>
      )}
      {!isCurrent && (
        <Button
          variant="link"
          className="self-start px-0"
          onClick={() => onNavigate(current.year, current.month)}
        >
          Voltar para o mês atual
        </Button>
      )}
    </main>
  )
}
