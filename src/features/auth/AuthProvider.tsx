import { createContext, useCallback, useContext, useEffect, useMemo, useState, type PropsWithChildren } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabase } from '../../lib/supabase/client'

type AuthContextValue = { user: User | null; session: Session | null; loading: boolean; configured: boolean; signOut: () => Promise<void>; refresh: () => Promise<void> }
const AuthContext = createContext<AuthContextValue | undefined>(undefined)

export function AuthProvider({ children }: PropsWithChildren) {
  const [session, setSession] = useState<Session | null>(null)
  const [loading, setLoading] = useState(true)
  const refresh = useCallback(async () => {
    if (!isSupabaseConfigured) { setLoading(false); return }
    const { data } = await supabase.auth.getSession()
    setSession(data.session)
    setLoading(false)
  }, [])
  useEffect(() => {
    void refresh()
    if (!isSupabaseConfigured) return undefined
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, nextSession) => { setSession(nextSession); setLoading(false) })
    return () => subscription.unsubscribe()
  }, [refresh])
  const signOut = useCallback(async () => { await supabase.auth.signOut(); setSession(null) }, [])
  const value = useMemo(() => ({ user: session?.user ?? null, session, loading, configured: isSupabaseConfigured, signOut, refresh }), [session, loading, signOut, refresh])
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

// A hook is intentionally exported beside its provider for this feature boundary.
// eslint-disable-next-line react-refresh/only-export-components
export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside AuthProvider')
  return context
}
