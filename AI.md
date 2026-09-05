# IA, OCR y voz

## Gemini sin secreto en cliente

El modelo configurado es `gemini-3.5-flash-lite`. `GEMINI_API_KEY` se lee sólo desde el entorno Deno de Supabase. `src/lib/ai/GeminiProvider` **no** es un SDK Gemini: es un adaptador seguro hacia funciones.

Configuración:

```bash
supabase secrets set GEMINI_API_KEY=...
supabase functions deploy ai-chat --no-verify-jwt
```

No crear `VITE_GEMINI_API_KEY`, no guardar la clave en storage del browser y no activar billing. Con `429`, las funciones devuelven:

```json
{"success":false,"error":{"code":"AI_RATE_LIMIT","message":"La IA alcanzó temporalmente su límite gratuito. Intentá nuevamente más tarde."}}
```

`AI_UNAVAILABLE` también es seguro y la UI mantiene disponibles las funciones offline/no IA.

## Funciones

- `ai-chat`: conserva un historial acotado (últimos mensajes), contexto explícitamente elegido de materia/apunte y personalidad del perfil.
- `ai-quiz`: exige JSON con schema y lo valida antes de persistir. Answer keys no se envían al navegador.
- `submit-quiz`: corrige y otorga XP del lado servidor.
- `study-recommendation`: algoritmos de prioridad basados en exámenes, tareas y rendimiento real.
- `humanize-text`: mejora claridad/naturalidad; nunca se presenta como elusión de detectores.
- `analyze-ai-text`: devuelve señales estilísticas y el disclaimer obligatorio: no determina autoría de IA.

## OCR/documentos

Se utiliza Gemini multimodal sobre un archivo privado que el servidor descarga desde Storage. El flujo es `pending → processing → completed/failed → confirmación humana`. La salida sólo sugiere tipo, materia, fecha/nota y texto; la persona edita y confirma antes de que sea final.

Límite del MVP: archivos compatibles hasta 10 MB; el tiempo y tamaño máximo efectivo también están sujetos al tier gratuito del proveedor. Si no está disponible, el archivo sigue almacenado para retry.

## Voz, sin APIs pagas

`src/lib/audio/speech.ts` define `TextToSpeechProvider` y `SpeechToTextProvider` y usa `SpeechSynthesis` y `SpeechRecognition`/`webkitSpeechRecognition` del navegador. Se puede seleccionar voz y velocidad, pausar/detener. Si el navegador no ofrece dictado o se deniega el micrófono, la entrada de texto siempre permanece disponible.

Las APIs de voz no envían audio a un proveedor propio de la aplicación. Disponibilidad, voces e idioma dependen del navegador/dispositivo.
