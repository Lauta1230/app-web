import { createClient, type SupabaseClient, type User } from 'npm:@supabase/supabase-js@2'
import { fail } from './http.ts'

const url = Deno.env.get('SUPABASE_URL')
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

function configured(value: string | undefined, key: string): string {
  if (!value) throw new Error(`${key} is not configured`)
  return value
}

export function adminClient(): SupabaseClient {
  return createClient(configured(url, 'SUPABASE_URL'), configured(serviceKey, 'SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false, autoRefreshToken: false } })
}

export async function requireUser(request: Request): Promise<{ user: User; admin: SupabaseClient } | Response> {
  const authorization = request.headers.get('Authorization')
  if (!authorization?.startsWith('Bearer ')) return fail('UNAUTHORIZED', 'Tu sesión expiró. Iniciá sesión nuevamente.', 401)
  const userClient = createClient(configured(url, 'SUPABASE_URL'), configured(anonKey, 'SUPABASE_ANON_KEY'), { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } })
  const { data: { user }, error } = await userClient.auth.getUser()
  if (error || !user) return fail('UNAUTHORIZED', 'Tu sesión expiró. Iniciá sesión nuevamente.', 401)
  return { user, admin: adminClient() }
}

export function isResponse(value: unknown): value is Response { return value instanceof Response }

export async function ownedRow<T>(admin: SupabaseClient, table: string, id: string, userId: string): Promise<T | null> {
  const { data, error } = await admin.from(table).select('*').eq('id', id).eq('user_id', userId).maybeSingle()
  if (error) throw error
  return data as T | null
}
