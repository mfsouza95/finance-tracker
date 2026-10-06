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
        'bg-background/80 sticky top-0 z-40 grid h-14 grid-cols-[1fr_auto_1fr] items-center border-b border-border px-4 backdrop-blur lg:px-6',
        className,
      )}
    >
      <h1 className="justify-self-start text-base font-semibold tracking-tight">
        {title}
      </h1>
      {center ? <div className="justify-self-center">{center}</div> : null}
      {actions ? (
        <div className="flex items-center gap-2 justify-self-end">
          {actions}
        </div>
      ) : null}
    </header>
  )
}
