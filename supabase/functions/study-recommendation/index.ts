import { asErrorResponse, fail, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'
import { studyRecommendation } from '../_shared/recommendation.ts'

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    return ok({ recommendation: await studyRecommendation(auth.admin, auth.user.id) })
  } catch (error) { return asErrorResponse(error) }
})
