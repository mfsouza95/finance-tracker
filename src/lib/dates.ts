export function currentYearMonth(now = new Date()): {
  year: number
  month: number
} {
  return { year: now.getFullYear(), month: now.getMonth() + 1 }
}

export function toISODate(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

// Today clamped inside the given month — default for entry dates.
export function todayInMonthISO(
  year: number,
  month: number,
  now = new Date(),
): string {
  const first = new Date(year, month - 1, 1)
  const last = new Date(year, month, 0)
  const d = now < first ? first : now > last ? last : now
  return toISODate(d)
}

const MONTH_NAMES = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
]

export function monthLabel(year: number, month: number): string {
  return `${MONTH_NAMES[month - 1]} de ${year}`
}

// 'YYYY-MM-DD' -> 'DD/MM/YYYY' without timezone surprises.
export function formatISODate(iso: string): string {
  const [y, m, d] = iso.split('-')
  return `${d}/${m}/${y}`
}
