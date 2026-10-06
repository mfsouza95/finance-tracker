import { useState } from 'react'
import { Archive, ArchiveRestore, Tags } from 'lucide-react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { useSession } from '@/features/auth/useSession'

import {
  useAddCategory,
  useSetCategoryArchived,
  type Bucket,
  type Category,
} from './hooks'

interface CategoryManagerProps {
  bucket: Bucket
  categories: Category[]
}

export function CategoryManager({ bucket, categories }: CategoryManagerProps) {
  const { session } = useSession()
  const addCategory = useAddCategory()
  const setArchived = useSetCategoryArchived()
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)

  const active = categories.filter((c) => !c.archived)
  const archived = categories.filter((c) => c.archived)

  const submit = () => {
    const trimmed = name.trim()
    if (!trimmed || !session) return
    setError(null)
    addCategory.mutate(
      { userId: session.user.id, bucket, name: trimmed },
      {
        onSuccess: () => setName(''),
        onError: (e) =>
          setError(
            // 23505 = unique (user_id, bucket, name)
            (e as { code?: string }).code === '23505'
              ? 'Já existe uma categoria com esse nome'
              : e.message,
          ),
      },
    )
  }

  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <Tags className="size-4" />
          Gerenciar categorias
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            Categorias — {bucket === 'essential' ? 'Essencial' : 'Diversão'}
          </DialogTitle>
          <DialogDescription>
            Crie, arquive ou restaure categorias deste pote.
          </DialogDescription>
        </DialogHeader>

        <ul className="flex flex-col gap-1">
          {active.map((c) => (
            <li key={c.id} className="flex items-center gap-2 text-sm">
              <span className="flex-1 truncate">{c.name}</span>
              <Button
                variant="ghost"
                size="icon-sm"
                aria-label={`Arquivar ${c.name}`}
                onClick={() =>
                  setArchived.mutate({ categoryId: c.id, archived: true })
                }
              >
                <Archive className="size-3.5" />
              </Button>
            </li>
          ))}
          {archived.map((c) => (
            <li
              key={c.id}
              className="text-muted-foreground flex items-center gap-2 text-sm"
            >
              <span className="flex-1 truncate line-through">{c.name}</span>
              <Button
                variant="ghost"
                size="icon-sm"
                aria-label={`Restaurar ${c.name}`}
                onClick={() =>
                  setArchived.mutate({ categoryId: c.id, archived: false })
                }
              >
                <ArchiveRestore className="size-3.5" />
              </Button>
            </li>
          ))}
        </ul>
        <div className="flex gap-2">
          <Input
            placeholder="Nova categoria"
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && submit()}
          />
          <Button
            variant="secondary"
            onClick={submit}
            disabled={!name.trim() || addCategory.isPending}
          >
            Adicionar
          </Button>
        </div>
        {error && (
          <p role="alert" className="text-negative text-xs">
            {error}
          </p>
        )}
      </DialogContent>
    </Dialog>
  )
}
