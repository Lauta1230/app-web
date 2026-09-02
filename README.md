# Companion Study

Aplicación PWA de estudio personal: organización académica, tutor con IA, quizzes, voz del navegador, documentos/OCR, calendario, estadísticas y una mascota que acompaña el progreso. La aplicación **no contiene una key de IA en el navegador** y está diseñada para operar con los tiers gratuitos de Supabase y Gemini.

> Costo operativo objetivo: **USD 0 / ARS 0**. No habilites billing ni agregues una tarjeta para usar este proyecto.

## Stack

- React 18, TypeScript estricto, Vite y Tailwind CSS (con estilos académicos propios).
- Supabase: Auth, PostgreSQL, RLS, Storage y Edge Functions (Deno).
- Gemini `gemini-2.5-flash-lite`, únicamente desde Edge Functions.
- Web Speech API del dispositivo para texto a voz y dictado (con entrada por teclado como fallback).
- PWA mediante `vite-plugin-pwa`.

## Inicio rápido

### 1. Cliente

```bash
cp .env.example .env
# completá VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY con valores públicos de tu proyecto
npm install
npm run dev
```

No uses `VITE_GEMINI_API_KEY`: no existe ni debe existir. Sin las dos variables públicas el cliente muestra una pantalla de configuración en lugar de aparentar que funciona.

### 2. Crear y configurar Supabase (tier gratuito)

1. Creá un proyecto en [Supabase](https://supabase.com) sin habilitar billing.
2. En **Authentication → URL Configuration**, configurá el Site URL y agregá `http://localhost:5173/reset-password` (y la URL de producción) como redirect URL.
3. Instalá Supabase CLI e iniciá sesión: `supabase login`.
4. Enlazá el proyecto: `supabase link --project-ref TU_PROJECT_REF`.
5. Antes de aplicar cambios, confirmá que el proyecto enlazado es el correcto, revisá el historial de migraciones y ejecutá `supabase start && supabase db reset && supabase test db --local`. Luego aplicá las migraciones ordenadas con `supabase db push`.
6. Desplegá las funciones listadas más abajo y verificá cada endpoint autenticado.

La migración crea buckets privados `documents`, `avatars` y `audio`; no hace falta crearlos manualmente. Sus políticas exigen que el primer segmento de la ruta sea el UUID de quien sube el archivo.

### 3. Secrets de Edge Functions

Nunca pongas estos valores en `.env` frontend, Git ni la base:

```bash
# Origen HTTPS exacto del frontend, sin barra final ni wildcard.
supabase secrets set FRONTEND_ORIGIN=https://tu-dominio.example
# SUPABASE_URL, SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY son inyectados/disponibles
# para funciones desplegadas. Para `supabase functions serve`, configurarlos como secretos locales.
```

`FRONTEND_ORIGIN` es obligatorio antes de desplegar a producción: las funciones no aceptan CORS wildcard y el único fallback es `http://localhost:5173`. La configuración de Gemini se mantiene separada y sólo puede autorizarse cuando corresponda; nunca se incluye una key en el frontend. Si llega un `429`, la UI recibe `AI_RATE_LIMIT` y el resto de la aplicación sigue usable.

### 4. Desplegar funciones

```bash
for fn in ai-chat ai-quiz submit-quiz award-xp complete-task complete-study-session \
  ocr-document process-document humanize-text analyze-ai-text study-recommendation \
  process-exam pet-care dashboard notifications; do
  supabase functions deploy "$fn" --no-verify-jwt
done
```

`--no-verify-jwt` es intencional: cada función valida el bearer JWT por sí misma para devolver respuestas JSON uniformes, incluso ante expiración. Ninguna acepta acciones sensibles sin verificar la identidad y ownership.

## Validación

GitHub Actions (`.github/workflows/ci.yml`) ejecuta lint, tests y build; además inicia una pila Supabase efímera, aplica las migraciones y ejecuta la suite pgTAP de RLS/atomicidad en cada PR y push de esta rama.

```
npm run lint
npm run test
npm run build
```

La suite pgTAP `supabase/tests/database/security_rls.test.sql` usa cuentas A/B efímeras para verificar aislamiento de tablas y Storage, FKs cross-user, privilegios y reintentos idempotentes. Ejecutala en local/CI con `supabase test db --local`; las pruebas A/B contra producción sólo se realizan con autorización explícita, cuentas de prueba y el proyecto correctamente identificado.

## PWA y APK futuro

`npm run build` genera `manifest.webmanifest`, `sw.js` y precache de recursos estáticos. La navegación y los assets ya visitados funcionan offline; IA, OCR y la sincronización requieren conexión. La PWA puede empaquetarse más adelante con TWA/Bubblewrap sin mantener una app Android separada.

## Documentación

- [ARCHITECTURE.md](ARCHITECTURE.md): límites frontend/backend y flujos.
- [DATABASE.md](DATABASE.md): esquema, restricciones y RLS.
- [AI.md](AI.md): Gemini, OCR, voz y fallbacks.
- [SECURITY.md](SECURITY.md): secretos, ownership y seguridad de archivos.
- [DEPLOYMENT.md](DEPLOYMENT.md): checklist operativo gratuito.

## Alcance consciente del MVP

Incluye una mascota activa, materias, apuntes, tareas, eventos, evaluaciones, asistencia por media jornada, dashboard, estudios/quiz IA, OCR confirmable, estadísticas basadas en datos reales y herramientas de texto. Flashcards con repetición espaciada, notificaciones push programadas, cuentas de docentes/padres, social/rankings y múltiples mascotas están fuera del MVP; el esquema deja espacio para evolucionarlos sin introducir datos ficticios.
