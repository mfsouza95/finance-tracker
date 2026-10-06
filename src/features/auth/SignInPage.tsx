import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { z } from 'zod'
import { zodResolver } from '@hookform/resolvers/zod'

import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { supabase } from '@/lib/supabase'

const schema = z.object({
  email: z.email('Informe um e-mail válido'),
})
type FormData = z.infer<typeof schema>

export function SignInPage() {
  const [sentTo, setSentTo] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormData>({ resolver: zodResolver(schema) })

  const onSubmit = async ({ email }: FormData) => {
    setError(null)
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: window.location.origin },
    })
    if (error) {
      setError(error.message)
    } else {
      setSentTo(email)
    }
  }

  return (
    <main>
      <h1>Entrar</h1>
      {sentTo ? (
        <p>
          Link enviado para {sentTo}. Abra o e-mail para entrar (em dev, veja o
          Mailpit em http://127.0.0.1:54324).
        </p>
      ) : (
        <form onSubmit={handleSubmit(onSubmit)}>
          <label htmlFor="email">E-mail</label>
          <Input
            id="email"
            type="email"
            autoComplete="email"
            {...register('email')}
          />
          {errors.email && <p role="alert">{errors.email.message}</p>}
          {error && <p role="alert">{error}</p>}
          <Button type="submit" disabled={isSubmitting}>
            {isSubmitting ? 'Enviando…' : 'Enviar link de acesso'}
          </Button>
        </form>
      )}
    </main>
  )
}
