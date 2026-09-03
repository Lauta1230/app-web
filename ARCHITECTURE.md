# Arquitectura

## Principio de confianza

```text
React/Vite (UI) → servicios tipados → Supabase Edge Functions → Gemini/Supabase admin
                         │
                         └──────────── Supabase PostgREST (CRUD privado bajo RLS)
```

El navegador solamente recibe la URL pública y anon key de Supabase. Los datos académicos de CRUD ordinario se escriben con el JWT del usuario y RLS; las reglas críticas (Gemini, corrección de quiz, XP, estados de mascota, OCR) pasan por una Edge Function.

## Frontend

- `src/app`: router y guardas de configuración/sesión.
- `src/layouts`: shell responsive con navegación inferior móvil.
- `src/pages`: rutas de producto; no contienen datos mock.
- `src/services/api.ts`: única puerta para CRUD y `functions.invoke`.
- `src/lib/ai`: contrato browser-safe `AIProvider`, `GeminiProvider`, `AIService`, contexto y validación. El provider es un adaptador a Edge Functions, no Gemini directo.
- `src/lib/audio`: contratos TTS/STT e implementación Web Speech.
- `src/lib/storage`: validación de MIME/tamaño/ruta privada para documentos.

Estado React sólo representa una interacción activa, formularios y cache de pantalla. No se usa localStorage como base académica; la persistencia de sesión es responsabilidad de Supabase Auth.

## Backend

`supabase/functions/_shared` contiene CORS, formato de respuesta, autenticación y la abstracción backend:

```ts
interface AIProvider {
  generateText(...)
  generateStructured(...)
  analyzeImage(...)
  analyzeDocument(...)
}
```

`GeminiProvider` es la única implementación concreta. Reemplazar proveedor no cambia funciones ni UI.

## Flujos principales

### Tarea → XP

1. Cliente invoca `complete-task` con sólo `task_id`.
2. Función obtiene la tarea filtrando por `user_id` del JWT.
3. Marca la tarea completada y llama `award_xp_internal` con recompensa fija.
4. El unique `(user_id, source, source_id)` vuelve la recompensa idempotente si el cliente reintenta.
5. La función SQL actualiza racha según timezone y mejora la mascota acotada 0–100.

### Quiz

Las opciones/preguntas viven en `quiz_questions`; las respuestas aceptadas viven en `quiz_answer_keys`, sin política de lectura de navegador. `submit-quiz` verifica ownership, conjunto completo de preguntas, guarda respuestas, calcula puntaje y entrega XP dentro del backend.

### Documento

El cliente valida el archivo (tipo permitido, hasta 10MB), crea metadata y sube a `documents/{user}/{document}/{safe-name}`. `ocr-document` vuelve a validar ownership, descarga con service role, consulta Gemini y deja el resultado en estado `completed`. `process-document` requiere que la persona revise/edite y confirme: no crea registros académicos automáticamente a partir de OCR.

### Recomendación

`study-recommendation` prioriza una evaluación próxima, luego una tarea próxima, luego la materia con menor promedio registrado. Si no existen datos, devuelve `null`; el dashboard muestra el empty state real.

## Errores

Toda Edge Function responde `{success,data}` o `{success:false,error:{code,message}}`. La UI traduce fallos a textos comprensibles. `429` de Gemini se convierte en `AI_RATE_LIMIT` sin impedir el uso de agenda, apuntes, tareas o mascota.
