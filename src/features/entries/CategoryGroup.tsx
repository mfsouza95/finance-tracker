import { ChevronRight, Trash2 } from 'lucide-react'

import { Money } from '@/components/Money'
import { Button } from '@/components/ui/button'
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible'
import { formatISODate } from '@/lib/dates'
import type { Category } from '@/features/categories/hooks'

import { useDeleteEntry, type EntryWithCategory } from './hooks'

interface CategoryGroupProps {
  category: Category
  entries: EntryWithCategory[]
  editable: boolean
}

// Domain rule 6: grouping is a query, not stored data — the group row is
// just SUM/COUNT over the entries passed in, expanded on demand.
export function CategoryGroup({
  category,
  entries,
  editable,
}: CategoryGroupProps) {
  const deleteEntry = useDeleteEntry()
  const sum = entries.reduce((acc, e) => acc + e.amount_cents, 0)

  return (
    <Collapsible>
      <CollapsibleTrigger className="group flex w-full items-center gap-2 rounded-md px-2 py-2 text-left hover:bg-muted">
        <ChevronRight className="size-4 shrink-0 transition-transform group-data-[state=open]:rotate-90" />
        <span className="flex-1 truncate text-sm font-medium">
          {category.name}
        </span>
        <span className="text-muted-foreground text-xs tabular-nums">
          {entries.length}
        </span>
        <Money cents={sum} size="sm" tone="negative" />
      </CollapsibleTrigger>
      <CollapsibleContent>
        <ul className="border-border mt-1 ml-6 flex flex-col divide-y border-l pl-2">
          {entries.map((e) => (
            <li
              key={e.id}
              className="flex items-center gap-2 py-1.5 text-sm"
            >
              <span className="text-muted-foreground w-12 shrink-0 text-xs tabular-nums">
                {formatISODate(e.paid_on)}
              </span>
              <span className="flex-1 truncate">{e.note ?? '—'}</span>
              {e.installment_index !== null && (
                <span className="text-muted-foreground shrink-0 text-xs tabular-nums">
                  {e.installment_index}/
                  {e.recurring_templates?.installments_total ?? '?'}
                </span>
              )}
              <Money cents={e.amount_cents} size="sm" tone="negative" />
              {editable && (
                <Button
                  variant="ghost"
                  size="icon-sm"
                  aria-label="Excluir entrada"
                  onClick={() => {
                    if (confirm('Excluir esta entrada?')) {
                      deleteEntry.mutate(e.id)
                    }
                  }}
                >
                  <Trash2 className="size-3.5" />
                </Button>
              )}
            </li>
          ))}
          {entries.length === 0 && (
            <li className="text-muted-foreground py-1.5 text-xs">
              Nenhuma entrada
            </li>
          )}
        </ul>
      </CollapsibleContent>
    </Collapsible>
  )
}
