import { useState } from 'react'
import { Plus } from 'lucide-react'

import { EmptyState } from '@/components/EmptyState'
import { Money } from '@/components/Money'
import { Badge } from '@/components/ui/badge'
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
import { currentYearMonth, monthLabel } from '@/lib/dates'
import { parseBrlToCents } from '@/lib/money'
import { useCategories, type Category } from '@/features/categories/hooks'

import {
  installmentIndexAt,
  useCreateTemplate,
  useRecurringTemplates,
  useSetTemplateActive,
  type TemplateWithCategory,
} from './hooks'

// Recurring templates + installment plans. A bounded template (parcelas)
// generates one entry per opened month and stops after installments_total;
// an unbounded one recurs forever. Progress is position-based, so skipped
// or backfilled months never shift the numbering.
export function RecurringPanel() {
  const { data: templates, isLoading } = useRecurringTemplates()
  const { data: categories } = useCategories()
  const [createOpen, setCreateOpen] = useState(false)

  const current = currentYearMonth()

  return (
    <section className="flex h-full flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <div className="flex items-center justify-between">
        <h2 className="text-sm font-medium tracking-wide text-muted-foreground uppercase">
          Recorrentes
        </h2>
        <Dialog open={createOpen} onOpenChange={setCreateOpen}>
          <DialogTrigger asChild>
            <Button variant="outline" size="sm">
              <Plus className="size-4" />
              Novo
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Novo recorrente</DialogTitle>
              <DialogDescription>
                Gera uma entrada todo mês. Informe o número de parcelas para um
                plano parcelado — a primeira cai no mês atual ou no mês que você
                escolher.
              </DialogDescription>
            </DialogHeader>
            <CreateTemplateForm
              categories={categories?.filter((c) => !c.archived) ?? []}
              onDone={() => setCreateOpen(false)}
            />
          </DialogContent>
        </Dialog>
      </div>

      {isLoading ? (
        <p className="text-muted-foreground text-sm">Carregando…</p>
      ) : !templates?.length ? (
        <EmptyState
          title="Sem recorrentes"
          description="Assinaturas e parcelas geram entradas automaticamente ao abrir o mês."
        />
      ) : (
        <ul className="flex flex-col gap-2">
          {templates.map((t) => {
            const idx = installmentIndexAt(t, current.year, current.month)
            return (
              <TemplateRow
                key={t.id}
                template={t}
                progress={
                  idx !== null
                    ? `${idx}/${t.installments_total}`
                    : null
                }
              />
            )
          })}
        </ul>
      )}
    </section>
  )
}

function TemplateRow({
  template: t,
  progress,
}: {
  template: TemplateWithCategory
  progress: string | null
}) {
  const setActive = useSetTemplateActive()
  const done = progress !== null && t.installments_total !== null &&
    progress.split('/')[0] === String(t.installments_total)

  return (
    <li
      className={`rounded-lg border border-border bg-card p-3 ${!t.active ? 'opacity-50' : ''}`}
    >
      <div className="flex items-baseline justify-between gap-2">
        <span className="truncate text-sm font-medium">{t.label}</span>
        <Money cents={t.amount_cents} size="sm" tone="negative" />
      </div>
      <div className="mt-1 flex items-center justify-between gap-2">
        <span className="text-muted-foreground text-xs">
          {t.categories.name} · dia {t.day_of_month}
          {progress !== null &&
            ` · desde ${monthLabel(t.first_year!, t.first_month!)}`}
        </span>
        <span className="flex items-center gap-1.5">
          {progress !== null && (
            <Badge variant={done ? 'secondary' : 'outline'}>{progress}</Badge>
          )}
          {!t.active && <Badge variant="secondary">inativa</Badge>}
          <Button
            variant="ghost"
            size="sm"
            className="h-6 px-2 text-xs"
            onClick={() =>
              setActive.mutate({ templateId: t.id, active: !t.active })
            }
          >
            {t.active ? 'Cancelar' : 'Reativar'}
          </Button>
        </span>
      </div>
    </li>
  )
}

function CreateTemplateForm({
  categories,
  onDone,
}: {
  categories: Category[]
  onDone: () => void
}) {
  const createTemplate = useCreateTemplate()
  const [label, setLabel] = useState('')
  const [amount, setAmount] = useState('')
  const [categoryId, setCategoryId] = useState('')
  const [day, setDay] = useState('')
  const [installments, setInstallments] = useState('')
  const [firstMonth, setFirstMonth] = useState(() => {
    const c = currentYearMonth()
    return `${c.year}-${String(c.month).padStart(2, '0')}`
  })
  const [error, setError] = useState<string | null>(null)

  const submit = () => {
    const cents = parseBrlToCents(amount)
    const dayN = Number.parseInt(day, 10)
    const n = installments.trim() === '' ? null : Number.parseInt(installments, 10)
    if (!label.trim()) {
      setError('Informe um nome')
      return
    }
    if (cents === null || cents <= 0) {
      setError('Informe um valor válido (ex.: 89,90)')
      return
    }
    if (!categoryId) {
      setError('Escolha uma categoria')
      return
    }
    if (!Number.isInteger(dayN) || dayN < 1 || dayN > 31) {
      setError('Dia entre 1 e 31')
      return
    }
    if (n !== null && (!Number.isInteger(n) || n < 2)) {
      setError('Parcelas devem ser um número >= 2 (ou deixe vazio para recorrente)')
      return
    }
    let firstYear: number | undefined
    let firstMon: number | undefined
    if (n !== null) {
      const [y, m] = firstMonth.split('-').map(Number)
      if (!y || !m) {
        setError('Informe o mês da primeira parcela')
        return
      }
      firstYear = y
      firstMon = m
    }
    setError(null)
    createTemplate.mutate(
      {
        categoryId,
        label: label.trim(),
        amountCents: cents,
        dayOfMonth: dayN,
        installmentsTotal: n ?? undefined,
        firstYear,
        firstMonth: firstMon,
      },
      {
        onSuccess: onDone,
        onError: (e) => setError(e.message),
      },
    )
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col gap-1.5">
        <label htmlFor="tpl-label" className="text-sm font-medium">
          Nome
        </label>
        <Input
          id="tpl-label"
          placeholder="Ex.: Netflix, Notebook 6x"
          value={label}
          onChange={(e) => setLabel(e.target.value)}
        />
      </div>

      <div className="grid grid-cols-2 gap-2">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="tpl-amount" className="text-sm font-medium">
            Valor
          </label>
          <Input
            id="tpl-amount"
            inputMode="decimal"
            placeholder="0,00"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="tpl-day" className="text-sm font-medium">
            Dia do mês
          </label>
          <Input
            id="tpl-day"
            type="number"
            min={1}
            max={31}
            placeholder="10"
            value={day}
            onChange={(e) => setDay(e.target.value)}
          />
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor="tpl-category" className="text-sm font-medium">
          Categoria
        </label>
        <select
          id="tpl-category"
          className="border-input bg-background h-9 rounded-md border px-3 text-sm"
          value={categoryId}
          onChange={(e) => setCategoryId(e.target.value)}
        >
          <option value="">Selecionar…</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name} ({c.bucket === 'essential' ? 'Essencial' : 'Diversão'})
            </option>
          ))}
        </select>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <div className="flex flex-col gap-1.5">
          <label htmlFor="tpl-installments" className="text-sm font-medium">
            Parcelas (opcional)
          </label>
          <Input
            id="tpl-installments"
            type="number"
            min={2}
            placeholder="vazio = recorrente"
            value={installments}
            onChange={(e) => setInstallments(e.target.value)}
          />
        </div>
        {installments.trim() !== '' && (
          <div className="flex flex-col gap-1.5">
            <label htmlFor="tpl-first" className="text-sm font-medium">
              1ª parcela
            </label>
            <Input
              id="tpl-first"
              type="month"
              value={firstMonth}
              onChange={(e) => setFirstMonth(e.target.value)}
            />
          </div>
        )}
      </div>

      {error && (
        <p role="alert" className="text-negative text-sm">
          {error}
        </p>
      )}
      <Button onClick={submit} disabled={createTemplate.isPending}>
        {createTemplate.isPending ? 'Salvando…' : 'Criar'}
      </Button>
    </div>
  )
}
