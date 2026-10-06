import { useState, type ReactNode } from 'react'
import { Plus } from 'lucide-react'

import { AppHeader } from '@/components/AppHeader'
import { Button } from '@/components/ui/button'
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { signOut } from '@/features/auth/useSession'

// Desktop-first layout per the design system: summary / essential / fun
// panels side by side, history below, add-entry sheet from the header
// button. The mobile tab layout comes later, once the desktop version is
// established.
// Content is injected via slots so the layout stays data-agnostic.

interface AppShellProps {
  summary: ReactNode
  essential: ReactNode
  fun: ReactNode
  history: ReactNode
  recurring: ReactNode
  /** Render prop — called with a closer so the form can dismiss the sheet. */
  addEntry: (onDone: () => void) => ReactNode
}

export function AppShell({
  summary,
  essential,
  fun,
  history,
  recurring,
  addEntry,
}: AppShellProps) {
  const [addOpen, setAddOpen] = useState(false)

  return (
    <div className="flex min-h-dvh flex-col">
      <AppHeader
        title="finance-tracker"
        actions={
          <>
            <Sheet open={addOpen} onOpenChange={setAddOpen}>
              <SheetTrigger asChild>
                <Button size="sm">
                  <Plus className="size-4" />
                  Lançar gasto
                </Button>
              </SheetTrigger>
              <SheetContent side="bottom">
                <SheetHeader>
                  <SheetTitle>Adicionar gasto</SheetTitle>
                  <SheetDescription className="sr-only">
                    Lançar uma nova entrada no mês atual
                  </SheetDescription>
                </SheetHeader>
                <div className="mx-auto w-full max-w-md px-4 pb-6">
                  {addEntry(() => setAddOpen(false))}
                </div>
              </SheetContent>
            </Sheet>
            <Button variant="ghost" onClick={() => void signOut()}>
              Sair
            </Button>
          </>
        }
      />

      <main className="flex-1 p-6">
        <div className="grid grid-cols-3 items-start gap-6">
          {summary}
          {essential}
          {fun}
        </div>
        <div className="mt-6 grid grid-cols-2 items-start gap-6">
          {recurring}
          {history}
        </div>
      </main>
    </div>
  )
}
