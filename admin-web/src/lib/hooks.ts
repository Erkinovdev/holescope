import { useMutation, useQuery, useQueryClient, type QueryKey } from '@tanstack/react-query'
import { api } from './api'
import { useToast } from '../components/ui'

type Query = Record<string, string | number | boolean | undefined | null>

export function useGet<T>(path: string, query?: Query, opts: { enabled?: boolean; refetchMs?: number } = {}) {
  return useQuery<T>({ queryKey: [path, query ?? {}], queryFn: () => api.get<T>(path, query), enabled: opts.enabled ?? true, refetchInterval: opts.refetchMs, placeholderData: (p) => p })
}

/** Мутация с уведомлением об успехе/ошибке и сбросом кэша по префиксам путей. */
export function useSave<B, R = unknown>(fn: (b: B) => Promise<R>, opts: { ok?: string; invalidate?: string[]; onDone?: (r: R) => void } = {}) {
  const qc = useQueryClient()
  const toast = useToast()
  return useMutation<R, Error, B>({
    mutationFn: fn,
    onSuccess: (r) => {
      if (opts.ok) toast(opts.ok, 'ok')
      for (const p of opts.invalidate ?? []) qc.invalidateQueries({ predicate: (q) => String((q.queryKey as QueryKey)[0]).startsWith(p) })
      opts.onDone?.(r)
    },
    onError: (e) => toast(e.message, 'err'),
  })
}
