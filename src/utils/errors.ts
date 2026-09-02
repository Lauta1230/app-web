export function friendlyError(error: unknown, fallback = 'No pudimos completar la operación. Revisá tu conexión e intentá nuevamente.'): string {
  const raw = error instanceof Error ? error.message : ''
  if (raw === 'CONFIGURATION_REQUIRED') return 'Configurá Supabase para comenzar a usar tu cuenta.'
  if (/invalid login credentials/i.test(raw)) return 'El email o la contraseña no son correctos.'
  if (/email not confirmed/i.test(raw)) return 'Confirmá tu email antes de ingresar.'
  if (/user already registered/i.test(raw)) return 'Ya existe una cuenta con este email.'
  if (/network|fetch/i.test(raw)) return 'No pudimos conectarnos. Revisá tu conexión e intentá nuevamente.'
  return fallback
}

export class AppError extends Error {
  constructor(public readonly code: string, message: string) { super(message) }
}
