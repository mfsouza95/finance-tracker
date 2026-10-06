import type { ReactNode } from 'react'

import { cn } from '@/lib/utils'

export interface AppHeaderProps {
  title: string
  actions?: ReactNode
  className?: string
}

export function AppHeader({ title, actions, className }: AppHeaderProps) {
  return (
    <header
      className={cn(
        'bg-background/80 sticky top-0 z-40 flex h-14 items-center justify-between border-b border-border px-4 backdrop-blur lg:px-6',
        className,
      )}
    >
      <h1 className="text-base font-semibold tracking-tight">
        {title}
      </h1>
      {actions ? <div className="flex items-center gap-2">{actions}</div> : null}
    </header>
  )
}
