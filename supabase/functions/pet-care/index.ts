import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { action: 'feed' | 'play' | 'rest' }
const effects = { feed: { happiness: 6, energy: 2, message: 'Disfrutó mucho su comida.' }, play: { happiness: 12, energy: -8, message: '¡Se divirtió muchísimo!' }, rest: { happiness: 2, energy: 18, message: 'Descansó y recuperó energía.' } } as const

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input.action || !Object.hasOwn(effects, input.action)) throw new InputError('Elegí una acción válida para tu mascota.')
    const { data: pet, error } = await auth.admin.from('pets').select('*').eq('user_id', auth.user.id).maybeSingle()
    if (error) throw error
    if (!pet) return fail('NOT_FOUND', 'Primero elegí una mascota durante el onboarding.', 404)
    const effect = effects[input.action]
    const happiness = Math.min(100, Math.max(0, pet.happiness + effect.happiness))
    const energy = Math.min(100, Math.max(0, pet.energy + effect.energy))
    const { data: updated, error: updateError } = await auth.admin.from('pets').update({ happiness, energy }).eq('id', pet.id).eq('user_id', auth.user.id).select().single()
    if (updateError) throw updateError
    return ok({ pet: updated, reaction: effect.message })
  } catch (error) { return asErrorResponse(error) }
})
