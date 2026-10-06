import { cn } from '@/lib/utils'
import { formatCents } from '@/lib/money'

export interface MoneyProps {
  cents: number
  /** 'auto' colours by sign: >= 0 positive, < 0 negative. */
  tone?: 'positive' | 'negative' | 'auto'
  /** 'sign' adds an explicit + on positive amounts (negatives already show -). */
  sign?: 'sign' | 'none'
  size?: 'sm' | 'base' | 'lg' | 'xl'
  className?: string
}

const sizes = {
  sm: 'text-sm',
  base: 'text-base',
  lg: 'text-lg font-medium',
  xl: 'text-2xl font-semibold tracking-tight',
} as const

export function Money({
  cents,
  tone = 'auto',
  sign = 'none',
  size = 'base',
  className,
}: MoneyProps) {
  const resolved =
    tone === 'auto' ? (cents < 0 ? 'negative' : 'positive') : tone
  const prefix = sign === 'sign' && cents > 0 ? '+' : ''
  return (
    <span
      className={cn(
        'tabular-nums',
        sizes[size],
        resolved === 'negative' ? 'text-negative' : 'text-positive',
        className,
      )}
    >
      {prefix}
      {formatCents(cents)}
    </span>
  )
}
