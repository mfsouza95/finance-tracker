import { cn } from '@/lib/utils'

interface ProgressBarProps {
  /** Fill percentage, 0–100. */
  pct: number
  tone?: 'default' | 'positive' | 'negative'
  className?: string
}

const TONES = {
  default: 'bg-foreground',
  positive: 'bg-positive',
  negative: 'bg-negative',
} as const

// Thin budget/progress bar shared by the bucket, pace and piggy cards.
export function ProgressBar({
  pct,
  tone = 'default',
  className,
}: ProgressBarProps) {
  return (
    <div
      role="progressbar"
      aria-valuenow={Math.round(pct)}
      aria-valuemin={0}
      aria-valuemax={100}
      className={cn(
        'h-1.5 w-full overflow-hidden rounded-full bg-muted',
        className,
      )}
    >
      <div
        className={cn('h-full rounded-full transition-[width]', TONES[tone])}
        style={{ width: `${pct}%` }}
      />
    </div>
  )
}
