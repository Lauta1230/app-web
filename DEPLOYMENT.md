# Despliegue

## Checklist de entorno gratuito

1. Crear o identificar el proyecto gratuito correcto de Supabase. **No habilitar billing ni asociar una tarjeta.**
2. Confirmar el project ref e historial remoto; nunca ejecutar migraciones sobre un proyecto no identificado. Respaldar los datos según la operación disponible.
3. En una pila local efímera, ejecutar `supabase start && supabase db reset --local && supabase test db --local`. La suite cubre RLS A/B y transacciones críticas.
4. Sólo después de esa revisión, enlazar el proyecto y aplicar el esquema: `supabase link --project-ref ... && supabase db push`.
5. Configurar Supabase Auth: Site URL, redirect de recuperación y confirmación de email según el entorno.
6. Configurar el secreto de Functions `FRONTEND_ORIGIN` con el origen HTTPS exacto de la aplicación. No usar wildcard ni configurarlo como variable `VITE_*`.
7. Desplegar las 15 Edge Functions desde README y comprobar cada una con un JWT de cuenta de prueba.
8. En el host del frontend, definir sólo `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.
9. Ejecutar `npm run lint && npm run test && npm run build`.
10. Servir `dist/` bajo HTTPS y probar instalación PWA, login, refresh de sesión y logout.

La configuración de Gemini no forma parte de este procedimiento de endurecimiento. Si se autoriza en una fase posterior, `GEMINI_API_KEY` debe existir sólo como secreto de Edge Functions, sin billing ni exposición al navegador.

## Edge Functions

Las funciones tienen `verify_jwt = false` porque implementan autenticación consistente en `_shared/supabase.ts`. Esto no equivale a acceso público: sin header `Authorization: Bearer <JWT>` retornan `401`, y cada mutación comprueba ownership.

Para desarrollo local:

```bash
supabase start
supabase db reset
supabase functions serve --env-file supabase/.env.local
```

`supabase/.env.local` debe estar ignorado y contener valores locales de `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, más `GEMINI_API_KEY` si se quiere probar IA. No lo crees ni publiques con valores de producción.

## PWA y APK

El plugin genera service worker/manifest durante `npm run build`. Verificá con DevTools → Application que el SW esté activo en HTTPS. La PWA no intenta simular IA offline: cachea shell y assets estáticos; APIs requieren red.

Para Android futuro se puede usar una Trusted Web Activity con Bubblewrap contra el dominio HTTPS PWA. No se requiere una base de código Android separada.

## Límites gratuitos conocidos

- Gemini puede aplicar rate limit/cuotas; `AI_RATE_LIMIT` permite retry posterior.
- Supabase gratuito tiene límites de base/storage/egress; el cliente no borra ni inventa datos para ocultarlos.
- Web Speech depende del browser; se ofrece teclado si falta STT.
- OCR está limitado a 10 MB y formatos permitidos, y requiere conexión/cuota Gemini.
