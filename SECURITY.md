# Seguridad

## Límites de confianza

| Zona | Permitido | No permitido |
|---|---|---|
| navegador | anon key, JWT gestionado por Supabase, CRUD bajo RLS | Gemini key, service-role key, calcular XP, claves de respuestas |
| Edge Function | validar bearer token, ownership, Gemini, service role | confiar en `user_id`, importes XP o correct answers del body |
| PostgreSQL | constraints, RLS, cálculos, idempotencia | políticas permisivas cruzadas |

## Secretos

`.env` está ignorado. `.env.example` sólo contiene valores públicos de Supabase. `SUPABASE_SERVICE_ROLE_KEY` y `GEMINI_API_KEY` se configuran con `supabase secrets set`; nunca se suben a Git, se almacenan en localStorage ni se envían a React.

## Ownership

Cada función llama `requireUser`, que verifica el JWT ante Supabase Auth. Antes de modificar un recurso filtra por el `user_id` del JWT. La service role es únicamente un mecanismo de servidor para leer keys de quiz o archivos privados tras esa verificación; no es un bypass de producto.

## Datos de entrada

- longitudes de chat, textos y quiz limitadas;
- quiz `1..20`, tipos y dificultad allowlisted;
- mascota usa acciones allowlisted y calcula efectos en servidor;
- tamaño/mime de archivos allowlisted y ruta generada en cliente con UUID;
- no hay SQL construido desde entrada de usuario;
- React escapa contenidos textuales por defecto; no se usa `dangerouslySetInnerHTML`;
- prompts incluyen instrucción para respetar el contexto y no inventar datos.

## Archivos

Storage es privado y su RLS exige prefijo de UUID. OCR vuelve a comprobar ownership en la tabla `documents` antes de descargar. La interfaz permite corregir la extracción, y los fallos no revelan mensajes de proveedor/stack.

## Operación

- Usar HTTPS en producción.
- Configurar redirect URLs exactas en Supabase Auth.
- Mantener dependencias actualizadas y revisar `npm audit` antes de desplegar.
- Ejecutar la prueba de RLS con dos usuarios reales en CI.
- No habilitar billing automáticamente por un error de rate limit: devolver el error seguro y permitir que la persona continúe con el resto de la app.
