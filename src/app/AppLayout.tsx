import { useState } from 'react'
import { Link, Outlet, useLocation } from 'react-router-dom'
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
import { useCategories } from '@/features/categories/hooks'
import { AddEntryForm } from '@/features/entries/AddEntryForm'
import { useMonth } from '@/features/months/hooks'
import { MonthNav } from '@/features/months/MonthNav'
import { useSelectedMonth } from '@/features/months/selectedMonth'

// Shared chrome for the authed app: header with the app name, the centered
// month switcher, page nav, global "Lançar gasto" sheet and sign-out.
// Pages render inside <Outlet/>.
export function AppLayout() {
  const [addOpen, setAddOpen] = useState(false)
  const { ym } = useSelectedMonth()
  const { data: month } = useMonth(ym.year, ym.month)
  const { data: categories } = useCategories()
  const { pathname } = useLocation()

  return (
    <div className="flex min-h-dvh flex-col">
      <AppHeader
        title="finance-tracker"
        center={<MonthNav />}
        actions={
          <>
            {(
              [
                ['/', 'Mês'],
                ['/reservas', 'Reservas'],
                ['/cofrinhos', 'Cofrinhos'],
                ['/historico', 'Histórico'],
              ] as const
            )
              .filter(([to]) => to !== pathname)
              .map(([to, label]) => (
                <Button key={to} variant="ghost" size="sm" asChild>
                  <Link to={to}>{label}</Link>
                </Button>
              ))}
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
                  {!month ? (
                    <p className="text-muted-foreground text-sm">
                      Abra o mês para lançar gastos.
                    </p>
                  ) : month.status === 'closed' ? (
                    <p className="text-muted-foreground text-sm">
                      Mês fechado — entradas são somente leitura.
                    </p>
                  ) : (
                    <AddEntryForm
                      month={month}
                      categories={categories ?? []}
                      onDone={() => setAddOpen(false)}
                    />
                  )}
                </div>
              </SheetContent>
            </Sheet>
            <Button variant="ghost" onClick={() => void signOut()}>
              Sair
            </Button>
          </>
        }
      />

      <main className="flex-1 p-4 sm:p-6">
        <Outlet />
      </main>
    </div>
  )
}
