export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json; charset=utf-8',
}

export type ApiErrorCode = 'UNAUTHORIZED' | 'INVALID_INPUT' | 'NOT_FOUND' | 'FORBIDDEN' | 'AI_RATE_LIMIT' | 'AI_UNAVAILABLE' | 'PROCESSING_FAILED' | 'INTERNAL_ERROR'

export function ok(data: unknown, status = 200): Response {
  return new Response(JSON.stringify({ success: true, data }), { status, headers: corsHeaders })
}

export function fail(code: ApiErrorCode, message: string, status = 400): Response {
  return new Response(JSON.stringify({ success: false, error: { code, message } }), { status, headers: corsHeaders })
}

export function options(request: Request): Response | null {
  return request.method === 'OPTIONS' ? new Response('ok', { headers: corsHeaders }) : null
}

export async function jsonBody<T>(request: Request): Promise<T> {
  try { return await request.json() as T } catch { throw new InputError('El cuerpo de la solicitud no es válido.') }
}

export class InputError extends Error {
  constructor(message: string) { super(message) }
}

export function asErrorResponse(error: unknown): Response {
  if (error instanceof InputError) return fail('INVALID_INPUT', error.message)
  if (error instanceof Error && error.message === 'AI_RATE_LIMIT') return fail('AI_RATE_LIMIT', 'La IA alcanzó temporalmente su límite gratuito. Intentá nuevamente más tarde.', 429)
  console.error(error)
  return fail('INTERNAL_ERROR', 'No pudimos completar la operación. Revisá tu conexión e intentá nuevamente.', 500)
}
