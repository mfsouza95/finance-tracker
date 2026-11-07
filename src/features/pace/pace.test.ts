import { describe, expect, it } from 'vitest'

import type { Buckets } from '@/lib/money'

import {
  daysLeft,
  mondayOf,
  paceAllowance,
  paceBound,
  paceLeft,
  scopeBudgetCents,
  scopeSpentCents,
  spentInWindow,
  weeksLeft,
} from './pace'

const buckets: Buckets = { essential: 5000, fun: 3000, invest: 2000 }

const month = {
  year: 2026,
  month: 11,
  closes_on: '2026-11-25',
}

describe('scopeBudgetCents', () => {
  it('all sums essential + fun + extras', () => {
    expect(scopeBudgetCents(buckets, 700, 'all')).toBe(8700)
  })
  it('essential is the plain bucket', () => {
    expect(scopeBudgetCents(buckets, 700, 'essential')).toBe(5000)
  })
  it('fun includes extras', () => {
    expect(scopeBudgetCents(buckets, 700, 'fun')).toBe(3700)
  })
})

describe('paceBound', () => {
  it('uses closes_on when set', () => {
    expect(paceBound(month)).toBe('2026-11-25')
  })
  it('falls back to the label month end', () => {
    expect(paceBound({ ...month, closes_on: null })).toBe('2026-11-30')
    expect(paceBound({ year: 2026, month: 2, closes_on: null })).toBe(
      '2026-02-28',
    )
  })
})

describe('daysLeft', () => {
  it('counts inclusive days from today to the bound', () => {
    expect(daysLeft('2026-11-10', '2026-11-02')).toBe(9)
    expect(daysLeft('2026-11-02', '2026-11-02')).toBe(1)
  })
  it('clamps to 1 once overdue', () => {
    expect(daysLeft('2026-11-01', '2026-11-02')).toBe(1)
    expect(daysLeft('2026-10-01', '2026-11-02')).toBe(1)
  })
})

describe('weeksLeft', () => {
  it('counts the current partial week', () => {
    // Mon Nov 2 → bound Nov 30: 29 days -> 5 weeks
    expect(weeksLeft('2026-11-30', '2026-11-02')).toBe(5)
    // Mon Nov 24 → bound Nov 30: 7 days -> 1 week
    expect(weeksLeft('2026-11-30', '2026-11-24')).toBe(1)
  })
  it('clamps to 1 overdue', () => {
    expect(weeksLeft('2026-10-30', '2026-11-02')).toBe(1)
  })
})

describe('mondayOf', () => {
  it('returns the ISO week Monday', () => {
    expect(mondayOf('2026-11-02')).toBe('2026-11-02') // already Monday
    expect(mondayOf('2026-11-05')).toBe('2026-11-02')
    expect(mondayOf('2026-11-08')).toBe('2026-11-02') // Sunday stays in week
    expect(mondayOf('2026-11-09')).toBe('2026-11-09') // next Monday
  })
  it('crosses month boundaries', () => {
    expect(mondayOf('2026-11-01')).toBe('2026-10-26') // Sunday
  })
})

describe('paceAllowance', () => {
  it('floors the division', () => {
    expect(paceAllowance(1000, 3)).toBe(333)
    expect(paceAllowance(10000, 7)).toBe(1428)
  })
  it('keeps an honest negative when the budget is blown', () => {
    expect(paceAllowance(-500, 3)).toBe(-167)
    expect(paceAllowance(-1, 2)).toBe(-1)
  })
})

const entries = [
  { bucket: 'essential' as const, amount_cents: 100, paid_on: '2026-11-02' },
  { bucket: 'fun' as const, amount_cents: 200, paid_on: '2026-11-02' },
  { bucket: 'fun' as const, amount_cents: 300, paid_on: '2026-11-05' },
  { bucket: 'essential' as const, amount_cents: 400, paid_on: '2026-10-30' },
]

describe('scopeSpentCents / spentInWindow', () => {
  it('sums the whole month per scope', () => {
    expect(scopeSpentCents(entries, 'all')).toBe(1000)
    expect(scopeSpentCents(entries, 'essential')).toBe(500)
    expect(scopeSpentCents(entries, 'fun')).toBe(500)
  })
  it('filters by paid_on window and scope', () => {
    expect(spentInWindow(entries, 'all', '2026-11-02', '2026-11-02')).toBe(300)
    expect(spentInWindow(entries, 'fun', '2026-11-02', '2026-11-08')).toBe(500)
    expect(spentInWindow(entries, 'essential', '2026-11-02', '2026-11-08')).toBe(100)
    // window edges are inclusive
    expect(spentInWindow(entries, 'all', '2026-10-30', '2026-11-05')).toBe(1000)
  })
  it('paceLeft subtracts only spend past the baseline', () => {
    // plain ensure row (baseline 0) behaves like allowance − spent
    expect(paceLeft(10_000, 3_000)).toBe(7_000)
    expect(paceLeft(10_000, 12_000)).toBe(-2_000)
    // recalc stamps the baseline: the display restarts at the allowance
    // and new spending counts down from it
    expect(paceLeft(5_000, 20_000, 20_000)).toBe(5_000)
    expect(paceLeft(5_000, 21_500, 20_000)).toBe(3_500)
    expect(paceLeft(5_000, 30_000, 20_000)).toBe(-5_000)
  })
  it('ignores fund deposits (fund_flow=in) but keeps them in month spent', () => {
    const withDeposit = [
      ...entries,
      {
        bucket: 'fun' as const,
        amount_cents: 50_000,
        paid_on: '2026-11-02',
        fund_flow: 'in',
      },
    ]
    // Deposits shrink the remaining budget via scopeSpentCents…
    expect(scopeSpentCents(withDeposit, 'all')).toBe(51_000)
    // …but never count as the period's spending — a piggy deposit must
    // not bust today's figure.
    expect(spentInWindow(withDeposit, 'all', '2026-11-02', '2026-11-02')).toBe(300)
    expect(spentInWindow(withDeposit, 'fun', '2026-11-02', '2026-11-08')).toBe(500)
  })
})
