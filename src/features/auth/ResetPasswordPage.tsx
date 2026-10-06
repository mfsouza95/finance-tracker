import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { zodResolver } from '@hookform/resolvers/zod'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { supabase } from '@/lib/supabase'

const schema = z.object({
  password: z.string().min(6, 'A senha deve ter pelo menos 6 caracteres'),
  confirmPassword: z.string(),
})
type FormData = z.infer<typeof schema>

export function ResetPasswordPage({ onDone }: { onDone: () => void }) {
  const [error, setError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormData>({ resolver: zodResolver(schema) })

  const onSubmit = async ({ password, confirmPassword }: FormData) => {
    setError(null)
    if (password !== confirmPassword) {
      setError('As senhas não conferem')
      return
    }
    const { error } = await supabase.auth.updateUser({ password })
    if (error) setError(error.message)
    else onDone()
  }

  return (
    <main className="flex min-h-svh items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm rounded-2xl border bg-card p-8 shadow-sm">
        <div className="mb-6 space-y-1 text-center">
          <p className="text-xs font-medium uppercase tracking-widest text-primary">
            finance tracker
          </p>
          <h1 className="text-xl font-semibold tracking-tight">Nova senha</h1>
          <p className="text-sm text-muted-foreground">
            Defina uma nova senha para sua conta
          </p>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div className="space-y-1.5">
            <label htmlFor="password" className="text-sm font-medium">
              Senha
            </label>
            <Input
              id="password"
              type="password"
              autoComplete="new-password"
              {...register('password')}
            />
          </div>
          <div className="space-y-1.5">
            <label htmlFor="confirmPassword" className="text-sm font-medium">
              Confirmar senha
            </label>
            <Input
              id="confirmPassword"
              type="password"
              autoComplete="new-password"
              {...register('confirmPassword')}
            />
          </div>

          {(errors.password || errors.confirmPassword || error) && (
            <p role="alert" className="text-sm text-destructive">
              {errors.password?.message ?? errors.confirmPassword?.message ?? error}
            </p>
          )}

          <Button type="submit" disabled={isSubmitting} className="w-full">
            {isSubmitting ? 'Salvando…' : 'Salvar nova senha'}
          </Button>
        </form>
      </div>
    </main>
  )
}
