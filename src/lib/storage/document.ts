import { supabase } from '../supabase/client'
import { AppError } from '../../utils/errors'

const allowedTypes = new Set(['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'text/plain'])
export function validateDocument(file: File): void {
  if (!allowedTypes.has(file.type)) throw new AppError('INVALID_FILE', 'Elegí una imagen, PDF o archivo de texto compatible.')
  if (file.size < 1 || file.size > 10 * 1024 * 1024) throw new AppError('INVALID_FILE', 'El archivo debe pesar hasta 10 MB.')
}
export async function uploadPrivateDocument(userId: string, file: File): Promise<{ id: string; path: string }> {
  validateDocument(file)
  const id = crypto.randomUUID(); const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_'); const path = `${userId}/${id}/${safeName}`
  const { error: metadataError } = await supabase.from('documents').insert({ id, user_id: userId, name: file.name, storage_path: path, mime_type: file.type, size_bytes: file.size, document_type: 'document' })
  if (metadataError) throw metadataError
  const { error: uploadError } = await supabase.storage.from('documents').upload(path, file, { contentType: file.type, upsert: false })
  if (uploadError) { await supabase.from('documents').delete().eq('id', id); throw uploadError }
  return { id, path }
}
