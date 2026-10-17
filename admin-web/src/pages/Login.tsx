import { useState, type FormEvent } from 'react'
import { Logo } from '../components/Layout'
import { Button, Card, Field, Input } from '../components/ui'
import { useAuth } from '../lib/auth'

export default function Login() {
  const { login } = useAuth()
  const [u, setU] = useState('')
  const [p, setP] = useState('')
  const [err, setErr] = useState('')
  const [busy, setBusy] = useState(false)
  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setErr('')
    try {
      await login(u.trim(), p)
    } catch (x) {
      setErr(x instanceof Error ? x.message : 'Ошибка входа')
    } finally {
      setBusy(false)
    }
  }
  return (
    <div className="flex h-full items-center justify-center p-6">
      <Card className="w-full max-w-sm">
        <form onSubmit={submit} className="flex flex-col gap-4">
          <div className="flex items-center gap-3">
            <Logo size={36} />
            <div>
              <div className="text-xl font-bold">Holescope</div>
              <div className="text-xs tracking-widest text-muted">АДМИНКА</div>
            </div>
          </div>
          <Field label="Логин"><Input autoFocus autoComplete="username" value={u} onChange={(e) => setU(e.target.value)} required /></Field>
          <Field label="Пароль"><Input type="password" autoComplete="current-password" value={p} onChange={(e) => setP(e.target.value)} required /></Field>
          {err && <div role="alert" className="text-sm text-crater">{err}</div>}
          <Button kind="primary" type="submit" disabled={busy || !u || !p}>{busy ? 'Входим…' : 'Войти'}</Button>
        </form>
      </Card>
    </div>
  )
}
