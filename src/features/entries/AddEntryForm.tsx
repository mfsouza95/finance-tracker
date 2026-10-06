import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { zodResolver } from '@hookform/resolvers/zod'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { todayInMonthISO } from '@/lib/dates'
import { parseBrlToCents } from '@/lib/money'
import type { Month } from '@/features/months/hooks'
import type { Category } from '@/features/categories/hooks'
import { useSession } from '@/features/auth/useSession'
import { useFunds } from '@/features/funds/hooks'

import { useAddEntry } from './hooks'

interface AddEntryFormProps {
  month: Month
  categories: Category[]
  onDone?: () => void
}

// Bank options use a `fund:` prefix and category-less entries a `uncat:`
// prefix so they can share the select — the DB keeps them in separate
// columns.
const FUND_PREFIX = 'fund:'
const UNCAT_PREFIX = 'uncat:'

export function AddEntryForm({ month, categories, onDone }: AddEntryFormProps) {
  const { session } = useSession()
  const addEntry = useAddEntry()
  const { data: banks } = useFunds('bank')

  const monthPrefix = `${month.year}-${String(month.month).padStart(2, '0')}`
  const schema = z.object({
    categoryId: z.string().min(1, 'Escolha um pote ou categoria'),
    amount: z
      .string()
      .refine(
        (s) => {
          const c = parseBrlToCents(s)
          return c !== null && c > 0
        },
        { message: 'Informe um valor válido (ex.: 25,90)' },
      ),
    paidOn: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/, 'Informe uma data')
      .refine((d) => d.startsWith(monthPrefix), {
        message: 'A data precisa ser dentro do mês',
      }),
    note: z.string(),
  })
  type FormData = z.infer<typeof schema>

  const active = categories.filter((c) => !c.archived)
  const activeBanks = (banks ?? []).filter((b) => b.active)
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: {
      categoryId: '',
      amount: '',
      paidOn: todayInMonthISO(month.year, month.month),
      note: '',
    },
  })

  const submit = (data: FormData) => {
    const cents = parseBrlToCents(data.amount)
    if (cents === null || !session) return
    const isFund = data.categoryId.startsWith(FUND_PREFIX)
    const isUncat = data.categoryId.startsWith(UNCAT_PREFIX)
    addEntry.mutate(
      {
        userId: session.user.id,
        monthId: month.id,
        amountCents: cents,
        paidOn: data.paidOn,
        note: data.note.trim() || undefined,
        ...(isFund
          ? { fundId: data.categoryId.slice(FUND_PREFIX.length) }
          : isUncat
            ? {
                bucket: data.categoryId.slice(UNCAT_PREFIX.length) as
                  | 'essential'
                  | 'fun',
              }
            : { categoryId: data.categoryId }),
      },
      {
        onSuccess: () => {
          reset()
          onDone?.()
        },
      },
    )
  }

  return (
    <form onSubmit={handleSubmit(submit)} className="flex flex-col gap-3">
      <div className="flex flex-col gap-1.5">
        <label htmlFor="category" className="text-sm font-medium">
          Pote ou categoria
        </label>
        <select
          id="category"
          className="border-input bg-background h-9 rounded-md border px-3 text-sm"
          {...register('categoryId')}
        >
          <option value="">Selecionar…</option>
          <optgroup label="Essencial">
            <option value="uncat:essential">Sem categoria</option>
            {active
              .filter((c) => c.bucket === 'essential')
              .map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
          </optgroup>
          <optgroup label="Diversão">
            <option value="uncat:fun">Sem categoria</option>
            {active
              .filter((c) => c.bucket === 'fun')
              .map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
          </optgroup>
          {activeBanks.length > 0 && (
            <optgroup label="Reservas">
              {activeBanks.map((b) => (
                <option key={b.id} value={`${FUND_PREFIX}${b.id}`}>
                  {b.name}
                </option>
              ))}
            </optgroup>
          )}
        </select>
        {errors.categoryId && (
          <p role="alert" className="text-negative text-xs">
            {errors.categoryId.message}
          </p>
        )}
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="amount" className="text-sm font-medium">
          Valor
        </label>
        <Input
          id="amount"
          inputMode="decimal"
          placeholder="0,00"
          {...register('amount')}
        />
        {errors.amount && (
          <p role="alert" className="text-negative text-xs">
            {errors.amount.message}
          </p>
        )}
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="paidOn" className="text-sm font-medium">
          Data
        </label>
        <Input id="paidOn" type="date" {...register('paidOn')} />
        {errors.paidOn && (
          <p role="alert" className="text-negative text-xs">
            {errors.paidOn.message}
          </p>
        )}
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="note" className="text-sm font-medium">
          Nota (opcional)
        </label>
        <Input id="note" placeholder="Ex.: mercado" {...register('note')} />
      </div>

      {addEntry.error && (
        <p role="alert" className="text-negative text-sm">
          {addEntry.error.message}
        </p>
      )}
      <Button type="submit" disabled={addEntry.isPending}>
        {addEntry.isPending ? 'Salvando…' : 'Lançar'}
      </Button>
    </form>
  )
}
