import type { ReactNode } from 'react'
import { ChevronRight } from 'lucide-react'

import { Money } from '@/components/Money'
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible'
import { formatISODate } from '@/lib/dates'

import type { Fund } from './hooks'
import { useFundHistory } from './hooks'

// A fund's full ledger — every deposit, spend and drain it ever had —
// expandable in place. Used for completed banks (month history) and for
// banks waiting to be purged (the Excluídas section).
export function FundHistoryRow({
  fund,
  badge,
  action,
}: {
  fund: Fund
  badge?: ReactNode
  action?: ReactNode
}) {
  const { data: history } = useFundHistory(fund.id)

  return (
    <Collapsible>
      <div className="flex items-center gap-1">
        <CollapsibleTrigger className="group flex flex-1 items-center gap-2 rounded-md px-2 py-2 text-left hover:bg-muted">
          <ChevronRight className="size-4 shrink-0 transition-transform group-data-[state=open]:rotate-90" />
          <span className="flex-1 truncate text-sm font-medium">
            {fund.name}
          </span>
          <span className="text-muted-foreground text-xs tabular-nums">
            {history?.length ?? 0}
          </span>
          {badge}
        </CollapsibleTrigger>
        {action}
      </div>
      <CollapsibleContent>
        <ul className="border-border mt-1 ml-6 flex max-h-64 flex-col divide-y overflow-y-auto border-l pl-2">
          {(history ?? []).map((e) => (
            <li
              key={e.id}
              className="flex items-center gap-2 py-1.5 pr-1 text-sm"
            >
              <span className="text-muted-foreground shrink-0 text-xs tabular-nums">
                {formatISODate(e.paid_on)}
              </span>
              <span className="flex-1 truncate">{e.note ?? '—'}</span>
              <Money
                cents={e.fund_flow === 'in' ? e.amount_cents : -e.amount_cents}
                size="sm"
                sign="sign"
                tone={e.fund_flow === 'in' ? 'positive' : 'negative'}
              />
            </li>
          ))}
          {(history ?? []).length === 0 && (
            <li className="text-muted-foreground py-1.5 text-xs">
              Nenhuma entrada
            </li>
          )}
        </ul>
      </CollapsibleContent>
    </Collapsible>
  )
}
