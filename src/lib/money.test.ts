import { describe, expect, it } from 'vitest'

import {
  DEFAULT_SPLIT,
  SPLIT_PRESETS,
  bucketRest,
  computeBuckets,
  expectedInvestment,
  formatCents,
  monthTotalToSpend,
  parseBrlToCents,
} from './money'

// Keep this list aligned with the math_cases VALUES in
// supabase/tests/007_bucket_math.sql — same inputs must produce the
// same buckets in TS and in close_month (domain rule 10).
const CASES: Array<[net: number, ep: number, fp: number, ip: number]> = [
  [10003, 50, 30, 20], [9999, 55, 25, 20],
  [7, 60, 20, 20], [101, 70, 20, 10],
  [250001, 50, 30, 20], [33333, 55, 25, 20],
  [1, 60, 20, 20], [99, 70, 20, 10],
  [50000, 33, 33, 34], [876543, 0, 50, 50],
  [42, 100, 0, 0], [77777, 1, 1, 98],
  [10001, 50, 30, 20], [200003, 55, 25, 20],
  [999, 60, 20, 20], [88888, 70, 20, 10],
  [3, 25, 45, 30], [999999, 80, 10, 10],
  [54321, 50, 30, 20], [0, 55, 25, 20],
  [11, 60, 20, 20], [123457, 70, 20, 10],
  [60001, 33, 33, 34], [5, 0, 50, 50],
  [90001, 100, 0, 0], [17, 1, 1, 98],
  [44444, 50, 30, 20], [2, 55, 25, 20],
  [654321, 60, 20, 20], [100000, 70, 20, 10],
  [29, 25, 45, 30], [765432, 80, 10, 10],
  [100, 50, 30, 20], [55555, 55, 25, 20],
  [99999, 60, 20, 20], [8, 70, 20, 10],
  [300003, 50, 30, 20], [13, 55, 25, 20],
  [199999, 60, 20, 20], [777, 70, 20, 10],
]

describe('computeBuckets', () => {
  it.each(CASES)(
    'net %i split %i/%i/%i: floor math, non-negative, sums to net',
    (net, ep, fp, ip) => {
      const b = computeBuckets(net, { essentialPct: ep, funPct: fp, investPct: ip })
      expect(b.essential).toBe(Math.floor((net * ep) / 100))
      expect(b.fun).toBe(Math.floor((net * fp) / 100))
      expect(b.invest).toBe(net - b.essential - b.fun)
      expect(b.essential).toBeGreaterThanOrEqual(0)
      expect(b.fun).toBeGreaterThanOrEqual(0)
      expect(b.invest).toBeGreaterThanOrEqual(0)
      expect(b.essential + b.fun + b.invest).toBe(net)
    },
  )

  it('50/30/20 on 10003: essential 5001, fun 3000, invest absorbs 2002', () => {
    expect(computeBuckets(10003, DEFAULT_SPLIT)).toEqual({
      essential: 5001,
      fun: 3000,
      invest: 2002,
    })
  })

  it('60/20/20 on 10007 (remainder to invest)', () => {
    expect(computeBuckets(10007, SPLIT_PRESETS['60/20/20'])).toEqual({
      essential: 6004,
      fun: 2001,
      invest: 2002,
    })
  })

  it('70/20/10 on 9999', () => {
    expect(computeBuckets(9999, SPLIT_PRESETS['70/20/10'])).toEqual({
      essential: 6999,
      fun: 1999,
      invest: 1001,
    })
  })

  it.each([
    [0, { essential: 0, fun: 0, invest: 0 }],
    [1, { essential: 0, fun: 0, invest: 1 }],
    [99, { essential: 49, fun: 29, invest: 21 }],
  ])('edge net %i', (net, expected) => {
    expect(computeBuckets(net, DEFAULT_SPLIT)).toEqual(expected)
  })

  it('all presets sum to net on an awkward net', () => {
    for (const split of Object.values(SPLIT_PRESETS)) {
      const b = computeBuckets(99997, split)
      expect(b.essential + b.fun + b.invest).toBe(99997)
    }
  })
})

describe('rests and expected investment', () => {
  it('rest is budget minus spent, negative when overspent', () => {
    expect(bucketRest(5000, 4000)).toBe(1000)
    expect(bucketRest(5000, 6000)).toBe(-1000)
  })

  it('month total to spend is net minus invest target', () => {
    const b = computeBuckets(10000, DEFAULT_SPLIT)
    expect(monthTotalToSpend(10000, b)).toBe(8000)
  })

  it('expected investment adds leftover and subtracts overspend', () => {
    const b = computeBuckets(10000, DEFAULT_SPLIT) // 5000/3000/2000
    expect(expectedInvestment(b, 4500, 3000)).toBe(2500) // 2000 + 500 + 0
    expect(expectedInvestment(b, 6000, 3000)).toBe(1000) // 2000 - 1000 + 0
  })

  it('extras raise total to spend and fun rest, never the split', () => {
    const b = computeBuckets(10000, DEFAULT_SPLIT) // 5000/3000/2000
    expect(monthTotalToSpend(10000, b, 750)).toBe(8750) // 8000 + 750
    // extras land 100% in fun: fun rest = (3000 + 750) - 3500 = 250
    expect(expectedInvestment(b, 5000, 3500, 750)).toBe(2250) // 2000 + 0 + 250
    // unspent extras flow to investment entirely
    expect(expectedInvestment(b, 5000, 3000, 750)).toBe(2750) // 2000 + 0 + 750
  })
})

describe('formatCents', () => {
  it.each([
    [123456, 'R$ 1.234,56'],
    [0, 'R$ 0,00'],
    [-500, '-R$ 5,00'],
    [99, 'R$ 0,99'],
  ])('formats %i as %s', (cents, expected) => {
    // pt-BR puts a NBSP between R$ and the amount; normalise for compare.
    expect(formatCents(cents).replace(/\u00a0/g, ' ')).toBe(expected)
  })
})

describe('parseBrlToCents', () => {
  it.each([
    ['0', 0],
    ['1', 100],
    ['12,50', 1250],
    ['12.5', 1250],
    ['1.234,56', 123456],
    ['R$ 1.234,56', 123456],
    [',50', 50],
    ['1.234', 123400],
    ['1.234.567', 123456700],
    ['-5,00', -500],
    ['99', 9900],
    ['0,99', 99],
  ])('parses %s as %i cents', (input, expected) => {
    expect(parseBrlToCents(input)).toBe(expected)
  })

  it.each(['', 'abc', '12,', '12,345', 'R$', '12..5', ','])(
    'rejects %s',
    (input) => {
      expect(parseBrlToCents(input)).toBeNull()
    },
  )

  it('round-trips through formatCents', () => {
    for (const s of ['1.234,56', '12,50', '999,99']) {
      expect(parseBrlToCents(formatCents(parseBrlToCents(s)!))).toBe(
        parseBrlToCents(s),
      )
    }
  })
})
