# Deployment seguro de Supabase Edge Functions

Este procedimiento prepara **solamente** el deployment de las Edge Functions al proyecto Supabase `jqogsofwodvgfqvbpcza`. No aplica migraciones SQL, no modifica secretos del proyecto y no habilita facturación ni proveedores pagos.

El workflow [`.github/workflows/deploy-edge-functions.yml`](../.github/workflows/deploy-edge-functions.yml) es manual (`workflow_dispatch`) para que un push nunca publique una Function por accidente. Despliega únicamente el inventario revisado y no usa `--prune`, por lo que tampoco borra Functions remotas fuera de ese inventario. GitHub habilita el despacho manual de un workflow cuando el archivo ya está en la rama por defecto: integrar este cambio a la rama por defecto no despliega nada, sólo deja disponible el botón **Run workflow** protegido.

## Estado de revisión

La validación se ejecuta en cada ejecución de Quality mediante `scripts/check-edge-functions.sh` y `deno check` con Deno `2.6.1`. También es el primer job del workflow manual de deployment. La revisión confirmó que cada handler:

- atiende sólo `POST` (con `OPTIONS` limitado al preflight CORS);
- llama a `requireUser(request)` antes de leer o modificar datos;
- valida el bearer token en Supabase Auth con `auth.getUser()` y obtiene el `user.id` del token, no del cuerpo enviado por el cliente;
- usa el cliente service-role sólo después de establecer esa identidad y restringe lecturas/escrituras por ese `user.id`, o delega la comprobación atómica de pertenencia al RPC correspondiente;
- está configurado con `verify_jwt = false` en `supabase/config.toml` y usa la validación explícita anterior. El flag `--no-verify-jwt` del deploy mantiene esa configuración deliberada: el preflight puede ser anónimo, pero ninguna operación de aplicación puede ejecutarse sin `requireUser`.

| Function | Autenticación y límite de autoridad | Estado de compilación | Estado remoto |
| --- | --- | --- | --- |
| `ai-chat` | Token validado; conversación, materia, apunte y documento se buscan para el usuario autenticado. | Correcta | No desplegada por este procedimiento |
| `ai-quiz` | Token validado; la materia pertenece al usuario y los registros nuevos usan su identidad. | Correcta | No desplegada por este procedimiento |
| `submit-quiz` | Token validado; `submit_quiz_atomic` recibe el `user.id` autenticado y valida el quiz/preguntas dentro de la transacción. | Correcta | No desplegada por este procedimiento |
| `award-xp` | Token validado; `award_xp_for_verified_event_atomic` recibe el `user.id` autenticado y verifica el evento antes de asignar XP. | Correcta | No desplegada por este procedimiento |
| `complete-task` | Token validado; `complete_task_atomic` usa el `user.id` autenticado y bloquea/verifica la tarea en una transacción. | Correcta | No desplegada por este procedimiento |
| `complete-study-session` | Token validado; `complete_study_session_atomic` usa el `user.id` autenticado y valida la materia en la base. | Correcta | No desplegada por este procedimiento |
| `ocr-document` | Token validado; el documento se lee y actualiza para el usuario autenticado, incluido el camino de error. | Correcta | No desplegada por este procedimiento |
| `process-document` | Token validado; la materia y el documento se restringen al usuario autenticado. | Correcta | No desplegada por este procedimiento |
| `humanize-text` | Token validado; procesa sólo el texto suministrado por el usuario y no concede acceso a datos ajenos. | Correcta | No desplegada por este procedimiento |
| `analyze-ai-text` | Token validado; procesa sólo el texto suministrado por el usuario y no concede acceso a datos ajenos. | Correcta | No desplegada por este procedimiento |
| `study-recommendation` | Token validado; todas las consultas de recomendación se filtran por el `user.id` autenticado. | Correcta | No desplegada por este procedimiento |
| `process-exam` | Token validado; los RPCs de guardado/XP reciben el `user.id` autenticado y verifican examen y materia en la base. | Correcta | No desplegada por este procedimiento |
| `pet-care` | Token validado; busca y actualiza sólo la mascota del usuario autenticado. | Correcta | No desplegada por este procedimiento |
| `dashboard` | Token validado; todas las lecturas, incluido XP, se filtran por el `user.id` autenticado. | Correcta | No desplegada por este procedimiento |
| `notifications` | Token validado; lista y marca como leídas sólo notificaciones del usuario autenticado. | Correcta | No desplegada por este procedimiento |

No hay ningún `user_id` recibido desde el frontend que se use como fuente de autoridad. Los parámetros `p_user_id` de RPC se completan exclusivamente desde `auth.user.id` obtenido del token validado.

## Variables del runtime

### Inyectadas automáticamente por Supabase

Las Functions usan estas variables de runtime administradas por Supabase. **No se cargan en GitHub, no se agregan al frontend y no deben configurarse manualmente para este deployment.**

| Variable usada por el código | Uso |
| --- | --- |
| `SUPABASE_URL` | URL del proyecto para crear clientes server-side. |
| `SUPABASE_ANON_KEY` | Cliente usado solamente para validar el bearer token con Supabase Auth. |
| `SUPABASE_SERVICE_ROLE_KEY` | Cliente server-side para operaciones autorizadas después de obtener el usuario. Nunca se expone al navegador. |

El runtime hosted mantiene estas claves legacy disponibles. Las claves service-role no se escriben en código, archivos de CI ni variables `VITE_*`.

### Configuración adicional del proyecto

| Variable | Dónde vive | ¿Obligatoria antes de deploy? | Motivo |
| --- | --- | --- | --- |
| `FRONTEND_ORIGIN` | Supabase Edge Function secret/configuration | Sí | Debe contener el origen HTTPS exacto del frontend de producción para el CORS. Sin ella el código sólo permite el fallback local `http://localhost:5173`, que no es apto para producción. |
| `GEMINI_API_KEY` | No configurar en esta etapa | No para publicar el código | Sólo sería necesaria en tiempo de ejecución para `ai-chat`, `ai-quiz`, `ocr-document`, `humanize-text` y `analyze-ai-text`. Sin ella, esas cinco Functions responden controladamente `AI_UNAVAILABLE` (503); las otras diez continúan operativas. |

`FRONTEND_ORIGIN` no es un secreto criptográfico, pero se usa como Edge Function secret/configuration para no incorporar la URL de producción al código. Un administrador debe configurarla en el proyecto destino antes de ejecutar el workflow, por ejemplo:

```bash
supabase secrets set FRONTEND_ORIGIN=https://app.example.com --project-ref jqogsofwodvgfqvbpcza
```

No ejecutar el ejemplo hasta contar con el origen real de producción. El workflow comprueba únicamente que la variable exista; no imprime su valor.

## Credencial mínima de GitHub Actions

El único secreto que debe existir en GitHub para publicar es:

| Secret | Alcance recomendado | Propósito |
| --- | --- | --- |
| `SUPABASE_ACCESS_TOKEN` | **GitHub Environment** `supabase-production`, no secret de repositorio global | Autentica Supabase CLI para desplegar al project ref fijo. |

Un administrador del proyecto Supabase debe generar ese personal access token con permisos para desplegar Functions y guardarlo como secret del Environment `supabase-production`. Debe configurar también revisores requeridos para ese Environment. Esto evita que un cambio de workflow o un dispatch sin aprobación pueda usar la credencial de producción.

No se crea, pega, revela ni guarda ningún token en este repositorio. Si el secret no está configurado, el job `deploy` termina antes de invocar Supabase CLI.

## Ejecución reproducible

1. Integrar el commit revisado a la rama por defecto. Esto no ejecuta deployment porque el workflow no escucha `push`; sólo habilita el despacho manual en GitHub Actions.
2. Un administrador crea/protege el GitHub Environment `supabase-production`, configura revisores requeridos y agrega allí únicamente `SUPABASE_ACCESS_TOKEN`.
3. Un administrador configura `FRONTEND_ORIGIN` con el origen HTTPS real en el proyecto `jqogsofwodvgfqvbpcza`.
4. No configurar `GEMINI_API_KEY` en esta etapa.
5. En GitHub Actions, seleccionar **Deploy Supabase Edge Functions** y usar **Run workflow** desde el commit revisado que ya está en la rama por defecto.
6. Aprobar el Environment cuando GitHub lo solicite.

El workflow:

1. instala las dependencias exactas del lockfile con `npm ci`, comprueba que el inventario local sea exactamente las 15 Functions autorizadas, que cada una tenga el guard de autenticación manual y que coincida con la configuración JWT;
2. ejecuta `deno check` para los 15 entrypoints;
3. verifica que `SUPABASE_ACCESS_TOKEN` y `FRONTEND_ORIGIN` estén presentes sin mostrar valores;
4. usa Supabase CLI `2.116.0` y `--use-api` para publicar una por una las 15 Functions contra el project ref fijado;
5. aplica explícitamente `--no-verify-jwt`, consistente con la autenticación manual comprobada, y no configura secretos ni ejecuta SQL;
6. publica un resumen con los nombres de las Functions, sin valores sensibles.

## Faltantes actuales para desplegar

- Este cambio debe integrarse a la rama por defecto antes de que GitHub habilite el despacho manual del workflow.
- El secret de Environment `SUPABASE_ACCESS_TOKEN` debe ser creado y cargado por un administrador de Supabase/GitHub.
- `FRONTEND_ORIGIN` debe estar configurada con el origen HTTPS final del frontend.
- `GEMINI_API_KEY` permanece deliberadamente sin configurar. No bloquea el deployment, pero deja degradadas de forma segura las cinco rutas de IA indicadas arriba.

No se activó billing, no se agregó ningún proveedor pago y no se realizó ningún deployment remoto de Functions durante esta preparación.
