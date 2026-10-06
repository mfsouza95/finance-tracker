import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Plus } from 'lucide-react'

import { EmptyState } from '@/components/EmptyState'
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
import { parseBrlToCents } from '@/lib/money'
import { useSession } from '@/features/auth/useSession'
import type { Month } from '@/features/months/hooks'

import type { Fund } from './hooks'
import {
  useCreateFund,
  useFundBalances,
  useFunds,
  useUpdateFund,
} from './hooks'
import { DeleteFundDialog } from './DeleteFundDialog'
import { DepositDialog } from './DepositDialog'

// All banks the user has, each with an active switch, deposit and delete.
// Active banks show up as "categories" when logging entries.
export function BanksPanel({ month }: { month: Month }) {
  const { data: banks, isLoading } = useFunds('bank')
  const { data: balances } = useFundBalances()

  return (
    <section className="flex h-full flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
          Reservas
        </h2>
        <Button variant="outline" size="sm" asChild>
          <Link to="/reservas">Ver tudo</Link>
        </Button>
      </div>

      {isLoading ? (
        <p className="text-muted-foreground text-sm">Carregando…</p>
      ) : !banks?.length ? (
        <EmptyState
          title="Sem reservas"
          description="Crie uma reserva para guardar dinheiro fora dos potes."
        />
      ) : (
        <ul className="flex flex-col divide-y divide-border">
          {banks.map((b) => (
            <BankRow
              key={b.id}
              fund={b}
              balance={balances?.get(b.id) ?? 0}
              month={month}
            />
          ))}
        </ul>
      )}
    </section>
  )
}

export function BankRow({
  fund,
  balance,
  month,
}: {
  fund: Fund
  balance: number
  month: Month | null | undefined
}) {
  const update = useUpdateFund()

  return (
    <li className="flex items-center gap-2 py-2">
      <button
        type="button"
        role="switch"
        aria-checked={fund.active}
        aria-label={`${fund.active ? 'Desativar' : 'Ativar'} ${fund.name}`}
        onClick={() =>
          update.mutate({ fundId: fund.id, patch: { active: !fund.active } })
        }
        className={`relative h-5 w-9 shrink-0 rounded-full transition-colors ${
          fund.active ? 'bg-primary' : 'bg-input'
        }`}
      >
        <span
          className={`absolute top-0.5 size-4 rounded-full bg-white shadow transition-all ${
            fund.active ? 'left-4.5' : 'left-0.5'
          }`}
        />
      </button>
      <span className="flex-1 truncate text-sm font-medium">{fund.name}</span>
      <Money cents={balance} size="sm" />
      {month && <DepositDialog fund={fund} month={month} />}
      <DeleteFundDialog fund={fund} balance={balance} />
    </li>
  )
}

export function CreateFundDialog({ kind }: { kind: 'bank' | 'piggy' }) {
  const { session } = useSession()
  const createFund = useCreateFund()
  const [open, setOpen] = useState(false)
  const [name, setName] = useState('')
  const [goal, setGoal] = useState('')
  const [error, setError] = useState<string | null>(null)

  const isBank = kind === 'bank'

  const submit = () => {
    const trimmed = name.trim()
    if (!trimmed || !session) return
    let goalCents: number | undefined
    if (!isBank) {
      const c = parseBrlToCents(goal)
      if (c === null || c <= 0) {
        setError('Informe a meta (ex.: 3.000,00)')
        return
      }
      goalCents = c
    }
    setError(null)
    createFund.mutate(
      {
        userId: session.user.id,
        kind,
        name: trimmed,
        goalCents,
      },
      {
        onSuccess: () => {
          setName('')
          setGoal('')
          setOpen(false)
        },
        onError: (e) =>
          setError(
            (e as { code?: string }).code === '23505'
              ? 'Já existe um item com esse nome'
              : e.message,
          ),
      },
    )
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <Plus className="size-4" />
          Novo
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            {isBank ? 'Nova reserva' : 'Novo cofrinho'}
          </DialogTitle>
          <DialogDescription>
            {isBank
              ? 'Uma reserva guarda dinheiro fora dos potes. Ative para gastar dela.'
              : 'Defina uma meta e acompanhe o progresso.'}
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="fund-name" className="text-sm font-medium">
              Nome
            </label>
            <Input
              id="fund-name"
              placeholder={isBank ? 'Ex.: Viagem' : 'Ex.: Notebook'}
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
          </div>
          {!isBank && (
            <div className="flex flex-col gap-1.5">
              <label htmlFor="fund-goal" className="text-sm font-medium">
                Meta
              </label>
              <Input
                id="fund-goal"
                inputMode="decimal"
                placeholder="0,00"
                value={goal}
                onChange={(e) => setGoal(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && submit()}
              />
            </div>
          )}
          {error && (
            <p role="alert" className="text-negative text-sm">
              {error}
            </p>
          )}
          <Button onClick={submit} disabled={createFund.isPending}>
            {createFund.isPending ? 'Salvando…' : 'Criar'}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
