// Pace math — pure functions only (money math stays out of components).
// All money is integer cents; all dates are 'YYYY-MM-DD' strings compared
// lexicographically, so no Date/timezone math leaks in.

import type { Buckets } from '@/lib/money'
import { toISODate } from '@/lib/dates'
import type { Month } from '@/features/months/hooks'

export function todayISO(now = new Date()): string {
  return toISODate(now)
}

export type PaceScope = 'all' | 'essential' | 'fun'
export type PaceKind = 'day' | 'week'

// Budget the pod paces against. Invest is never spendable; extras land
// 100% in fun (same convention as close_month and the summary card).
export function scopeBudgetCents(
  buckets: Buckets,
  extrasCents: number,
  scope: PaceScope,
): number {
  switch (scope) {
    case 'essential':
      return buckets.essential
    case 'fun':
      return buckets.fun + extrasCents
    case 'all':
      return buckets.essential + buckets.fun + extrasCents
  }
}

export function scopeSpentCents(
  entries: { bucket: 'essential' | 'fun'; amount_cents: number }[],
  scope: PaceScope,
): number {
  let total = 0
  for (const e of entries) {
    if (scope === 'all' || e.bucket === scope) total += e.amount_cents
  }
  return total
}

// The period the pace runs to: the fatura closing date when set, else the
// label month's calendar end. Returns 'YYYY-MM-DD'.
export function paceBound(month: Pick<Month, 'year' | 'month' | 'closes_on'>): string {
  if (month.closes_on) return month.closes_on
  const last = new Date(month.year, month.month, 0).getDate()
  return `${month.year}-${String(month.month).padStart(2, '0')}-${String(last).padStart(2, '0')}`
}

function utcDay(iso: string): number {
  const [y, m, d] = iso.split('-').map(Number)
  return Date.UTC(y, m - 1, d)
}

// Whole days from `from` to bound, inclusive of `from`, clamped to >= 1 so
// an overdue month asks for the entire remaining budget instead of
// dividing by zero or going negative on the DAY count (the allowance
// itself may still be negative when the budget is blown).
export function daysLeft(bound: string, from: string): number {
  return Math.max(1, Math.round((utcDay(bound) - utcDay(from)) / 86_400_000) + 1)
}

// Number of pace-weeks left including the current partial one — the last
// week is clipped by the bound instead of running to Sunday.
export function weeksLeft(bound: string, weekStart: string): number {
  return Math.max(1, Math.ceil(daysLeft(bound, weekStart) / 7))
}

// Monday of the ISO week containing `iso`, on date parts only.
export function mondayOf(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1, d))
  dt.setUTCDate(dt.getUTCDate() - ((dt.getUTCDay() + 6) % 7))
  const yy = dt.getUTCFullYear()
  const mm = String(dt.getUTCMonth() + 1).padStart(2, '0')
  const dd = String(dt.getUTCDate()).padStart(2, '0')
  return `${yy}-${mm}-${dd}`
}

// remaining ÷ periods — the fixed allowance for the period. Floor so a
// busted budget keeps an honest negative figure.
export function paceAllowance(remainingCents: number, periodsLeft: number): number {
  return Math.floor(remainingCents / periodsLeft)
}

// Sum of scope entries with paid_on inside [from, to] (inclusive, string
// compare on ISO dates). Fund deposits (fund_flow='in') are NOT spending:
// they already shrink the remaining budget via scopeSpentCents, which is
// where the allowance absorbs them — counting them here too would bust a
// period for what is really a transfer to savings.
export function spentInWindow(
  entries: {
    bucket: 'essential' | 'fun'
    amount_cents: number
    paid_on: string
    fund_flow?: string | null
  }[],
  scope: PaceScope,
  from: string,
  to: string,
): number {
  let total = 0
  for (const e of entries) {
    if (scope !== 'all' && e.bucket !== scope) continue
    if (e.fund_flow === 'in') continue
    if (e.paid_on >= from && e.paid_on <= to) total += e.amount_cents
  }
  return total
}
