// Money is integer cents everywhere (bigint in Postgres, number here).
// Never store or compute money as floats.

export interface Split {
  essentialPct: number
  funPct: number
  investPct: number
}

export interface Buckets {
  essential: number
  fun: number
  invest: number
}

// Presets selectable in the UI (domain rule 11). Constants, not a table.
export const SPLIT_PRESETS = {
  '50/30/20': { essentialPct: 50, funPct: 30, investPct: 20 },
  '55/25/20': { essentialPct: 55, funPct: 25, investPct: 20 },
  '60/20/20': { essentialPct: 60, funPct: 20, investPct: 20 },
  '70/20/10': { essentialPct: 70, funPct: 20, investPct: 10 },
} as const satisfies Record<string, Split>

export const DEFAULT_SPLIT = SPLIT_PRESETS['50/30/20']

// Must stay identical to the SQL in close_month (domain rule 10):
//   essential = floor(net * essential_pct / 100)
//   fun       = floor(net * fun_pct / 100)
//   invest    = net - essential - fun      (absorbs rounding)
// net >= 0, so floor == trunc. net * pct stays below 2**53 for any
// realistic net, and net * pct / 100 always lands at least 0.01 away
// from an integer boundary, so the double division rounds correctly.
// The 40-case sweep in money.test.ts mirrors supabase/tests/007_bucket_math.sql.
export function computeBuckets(netCents: number, split: Split): Buckets {
  const essential = Math.floor((netCents * split.essentialPct) / 100)
  const fun = Math.floor((netCents * split.funPct) / 100)
  return { essential, fun, invest: netCents - essential - fun }
}

// Domain rule 3: rest per bucket = budget - spent (negative = overspent).
export function bucketRest(budgetCents: number, spentCents: number): number {
  return budgetCents - spentCents
}

// Domain rule 4: month total to spend = net - invest_target + extras.
// Extra income bypasses the split and lands 100% in the fun bucket, so the
// effective fun budget is buckets.fun + extras and the month's spendable
// total grows by the same amount.
export function monthTotalToSpend(
  netCents: number,
  buckets: Buckets,
  extrasCents = 0,
): number {
  return netCents - buckets.invest + extrasCents
}

// Domain rule 5: expected investment = invest_target + leftover of each bucket.
// Extras raise the fun rest one-for-one — unspent extras flow to investment.
export function expectedInvestment(
  buckets: Buckets,
  essentialSpentCents: number,
  funSpentCents: number,
  extrasCents = 0,
): number {
  return (
    buckets.invest +
    bucketRest(buckets.essential, essentialSpentCents) +
    bucketRest(buckets.fun + extrasCents, funSpentCents)
  )
}

const brl = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
})

export function formatCents(cents: number): string {
  return brl.format(cents / 100)
}

// Parses a typed BRL amount into integer cents without ever using floats.
// Accepts: "1234" (reais), "12,50", "1.234,56", "R$ 1.234,56", ",50",
// "-5,00". A lone dot is treated as decimal when 1-2 digits follow
// ("12.5" -> 1250) and as a thousands separator otherwise.
// Returns null on malformed input (e.g. "12,", "abc", "12,345").
export function parseBrlToCents(input: string): number | null {
  let s = input.trim().replace(/^R\$\s*/u, '')
  const negative = s.startsWith('-')
  if (negative) s = s.slice(1).trim()
  if (s === '') return null

  const hasComma = s.includes(',')
  const hasDot = s.includes('.')
  let whole: string
  let frac = ''
  let hadDecimal = false
  if (hasComma && hasDot) {
    const i = s.lastIndexOf(',')
    const intPart = s.slice(0, i)
    // Dots are thousands separators only in groups of three.
    if (!/^\d{1,3}(\.\d{3})*$/.test(intPart)) return null
    whole = intPart.replace(/\./g, '')
    frac = s.slice(i + 1)
    hadDecimal = true
  } else if (hasComma) {
    const i = s.lastIndexOf(',')
    whole = s.slice(0, i)
    frac = s.slice(i + 1)
    hadDecimal = true
  } else if (hasDot) {
    const i = s.lastIndexOf('.')
    const after = s.slice(i + 1)
    if (s.indexOf('.') === i && after.length <= 2) {
      whole = s.slice(0, i)
      frac = after
      hadDecimal = true
    } else {
      if (!/^\d{1,3}(\.\d{3})+$/.test(s)) return null
      whole = s.replace(/\./g, '')
    }
  } else {
    whole = s
  }

  if (whole === '' && frac !== '') whole = '0'
  if (!/^\d+$/.test(whole)) return null
  if (hadDecimal && frac === '') return null
  if (frac !== '' && !/^\d{1,2}$/.test(frac)) return null

  const cents =
    BigInt(whole) * 100n + BigInt(frac === '' ? '0' : (frac + '00').slice(0, 2))
  const signed = negative ? -cents : cents
  if (signed > BigInt(Number.MAX_SAFE_INTEGER)) return null
  return Number(signed)
}
