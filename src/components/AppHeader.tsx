import type { ReactNode } from 'react'

import { cn } from '@/lib/utils'

export interface AppHeaderProps {
  title: string
  /** Rendered in the exact center of the header. */
  center?: ReactNode
  actions?: ReactNode
  className?: string
}

export function AppHeader({ title, center, actions, className }: AppHeaderProps) {
  return (
    <header
      className={cn(
        'bg-background/80 sticky top-0 z-40 grid min-h-14 grid-cols-[1fr_auto_1fr] items-center border-b border-border px-3 py-1 backdrop-blur sm:px-4 lg:px-6',
        className,
      )}
    >
      <h1 className="justify-self-start text-base font-semibold tracking-tight">
        {title}
      </h1>
      {center ? <div className="justify-self-center">{center}</div> : null}
      {actions ? (
        <div className="flex flex-wrap items-center justify-end gap-1 justify-self-end sm:gap-2">
          {actions}
        </div>
      ) : null}
    </header>
  )
}
