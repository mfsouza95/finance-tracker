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

  return (
    <main>
      <h1>{mode === 'signin' ? 'Entrar' : 'Criar conta'}</h1>
      {notice && <p role="status">{notice}</p>}
      <form onSubmit={handleSubmit(onSubmit)}>
        <label htmlFor="email">E-mail</label>
        <Input
          id="email"
          type="email"
          autoComplete="email"
          {...register('email')}
        />
        {errors.email && <p role="alert">{errors.email.message}</p>}

        <label htmlFor="password">Senha</label>
        <Input
          id="password"
          type="password"
          autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
          {...register('password')}
        />
        {errors.password && <p role="alert">{errors.password.message}</p>}

        {mode === 'signup' && (
          <>
            <label htmlFor="confirmPassword">Confirmar senha</label>
            <Input
              id="confirmPassword"
              type="password"
              autoComplete="new-password"
              {...register('confirmPassword')}
            />
          </>
        )}

        {error && <p role="alert">{error}</p>}
        <Button type="submit" disabled={isSubmitting}>
          {isSubmitting
            ? 'Enviando…'
            : mode === 'signin'
              ? 'Entrar'
              : 'Criar conta'}
        </Button>
        <Button
          type="button"
          variant="outline"
          onClick={() => void onMagicLink()}
          disabled={isSubmitting}
        >
          Entrar com link por e-mail
        </Button>
        <Button
          type="button"
          variant="outline"
          onClick={() => void onGoogle()}
          disabled={isSubmitting}
        >
          Entrar com Google
        </Button>
        <p>
          {mode === 'signin' ? (
            <button type="button" onClick={() => switchMode('signup')}>
              Não tem conta? Criar conta
            </button>
          ) : (
            <button type="button" onClick={() => switchMode('signin')}>
              Já tem conta? Entrar
            </button>
          )}
        </p>
      </form>
    </main>
  )
}
