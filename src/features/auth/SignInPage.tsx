import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { zodResolver } from '@hookform/resolvers/zod'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { supabase } from '@/lib/supabase'

const schema = z.object({
  email: z.email('Informe um e-mail válido'),
  password: z.string().min(6, 'A senha deve ter pelo menos 6 caracteres'),
  confirmPassword: z.string().optional(),
})
type FormData = z.infer<typeof schema>

type Mode = 'signin' | 'signup'

function friendlyError(message: string) {
  if (message.includes('Invalid login credentials'))
    return 'E-mail ou senha incorretos'
  if (message.includes('User already registered'))
    return 'Este e-mail já está cadastrado'
  return message
}

export function SignInPage() {
  const [mode, setMode] = useState<Mode>('signin')
  const [notice, setNotice] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    reset,
    getValues,
    formState: { errors, isSubmitting },
  } = useForm<FormData>({ resolver: zodResolver(schema) })

  const switchMode = (next: Mode) => {
    setMode(next)
    setError(null)
    setNotice(null)
    reset()
  }

  const onSubmit = async ({ email, password, confirmPassword }: FormData) => {
    setError(null)
    setNotice(null)
    if (mode === 'signin') {
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
      })
      if (error) setError(friendlyError(error.message))
    } else {
      if (password !== confirmPassword) {
        setError('As senhas não conferem')
        return
      }
      const { data, error } = await supabase.auth.signUp({ email, password })
      if (error) {
        setError(friendlyError(error.message))
      } else if (!data.session) {
        setNotice(
          `Conta criada. Confirme o e-mail enviado para ${email} para entrar.`,
        )
        switchMode('signin')
      }
      // data.session set means confirmations are off — already signed in.
    }
  }

  const onMagicLink = async () => {
    setError(null)
    setNotice(null)
    const email = getValues('email')
    const parsed = z.email().safeParse(email)
    if (!parsed.success) {
      setError('Informe um e-mail válido para receber o link')
      return
    }
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: window.location.origin },
    })
    if (error) {
      setError(friendlyError(error.message))
    } else {
      setNotice(
        `Link enviado para ${email}. Abra o e-mail para entrar (em dev, veja o Mailpit em http://127.0.0.1:54324).`,
      )
    }
  }

  const onGoogle = async () => {
    setError(null)
    setNotice(null)
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
    })
    // On success the browser leaves for Google; only an error returns here.
    if (error) setError(friendlyError(error.message))
  }

  const fieldError = errors.email?.message ?? errors.password?.message

  return (
    <main className="flex min-h-svh items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm rounded-2xl border bg-card p-8 shadow-sm">
        <div className="mb-6 space-y-1 text-center">
          <p className="text-xs font-medium uppercase tracking-widest text-primary">
            finance tracker
          </p>
          <h1 className="text-xl font-semibold tracking-tight">
            {mode === 'signin' ? 'Entrar' : 'Criar conta'}
          </h1>
          <p className="text-sm text-muted-foreground">
            {mode === 'signin'
              ? 'Acesse seu orçamento mensal'
              : 'Crie sua conta para começar'}
          </p>
        </div>

        {notice && (
          <p role="status" className="mb-4 rounded-lg bg-muted p-3 text-sm">
            {notice}
          </p>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          <div className="space-y-1.5">
            <label htmlFor="email" className="text-sm font-medium">
              E-mail
            </label>
            <Input
              id="email"
              type="email"
              autoComplete="email"
              {...register('email')}
            />
          </div>

          <div className="space-y-1.5">
            <label htmlFor="password" className="text-sm font-medium">
              Senha
            </label>
            <Input
              id="password"
              type="password"
              autoComplete={
                mode === 'signin' ? 'current-password' : 'new-password'
              }
              {...register('password')}
            />
          </div>

          {mode === 'signup' && (
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
          )}

          {(fieldError || error) && (
            <p role="alert" className="text-sm text-destructive">
              {fieldError ?? error}
            </p>
          )}

          <Button type="submit" disabled={isSubmitting} className="w-full">
            {isSubmitting
              ? 'Enviando…'
              : mode === 'signin'
                ? 'Entrar'
                : 'Criar conta'}
          </Button>
        </form>

        <div className="my-4 flex items-center gap-3 text-xs text-muted-foreground">
          <span className="h-px flex-1 bg-border" />
          ou
          <span className="h-px flex-1 bg-border" />
        </div>

        <div className="space-y-2">
          <Button
            type="button"
            variant="outline"
            className="w-full"
            onClick={() => void onMagicLink()}
            disabled={isSubmitting}
          >
            Entrar com link por e-mail
          </Button>
          <Button
            type="button"
            variant="outline"
            className="w-full"
            onClick={() => void onGoogle()}
            disabled={isSubmitting}
          >
            Entrar com Google
          </Button>
        </div>

        <p className="mt-6 text-center text-sm text-muted-foreground">
          {mode === 'signin' ? 'Não tem conta?' : 'Já tem conta?'}{' '}
          <Button
            type="button"
            variant="link"
            className="h-auto p-0 align-baseline"
            onClick={() => switchMode(mode === 'signin' ? 'signup' : 'signin')}
          >
            {mode === 'signin' ? 'Criar conta' : 'Entrar'}
          </Button>
        </p>
      </div>
    </main>
  )
}
