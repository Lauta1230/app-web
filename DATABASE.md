# Base de datos y RLS

Las migraciones se aplican en orden: `202609020001_initial_schema.sql` crea el modelo y `202609020002_security_integrity.sql` endurece integridad y privilegios. La segunda es aditiva y primero detecta inconsistencias que impedirían crear sus restricciones; no borra ni fusiona datos. Revisá el proyecto enlazado, ejecutá una copia/respaldo y corré las pruebas locales antes de usar `supabase db push`.

## Modelo

| Área | Tablas |
|---|---|
| identidad | `profiles`, `streaks` |
| académico | `subjects`, `notes`, `documents`, `tasks`, `calendar_events`, `exams`, `attendance_records`, `study_sessions` |
| IA | `ai_conversations`, `ai_messages`, `quizzes`, `quiz_questions`, `quiz_answer_keys`, `quiz_answers` |
| progreso | `levels`, `xp_transactions`, `achievements`, `user_achievements`, `pets`, `pet_items`, `user_pet_items` |
| comunicación | `notifications` |

Todas las claves de dominio son UUID y sus foreign keys usan `cascade` o `set null` según el ciclo de vida apropiado. Hay índices por dueño, fechas y relaciones de conversación/quiz.

## Restricciones importantes

- `happiness` y `energy`: `0..100`.
- documentos: peso positivo y hasta `10,485,760` bytes.
- `question_count`: validado por Edge Function `1..20`; las posiciones SQL también están en ese rango.
- notas: `grade >= 0`, `max_grade > 0`, porcentaje `0..100`.
- asistencia: un registro por usuario, materia y fecha, con mañana/tarde por separado; la restricción usa `UNIQUE NULLS NOT DISTINCT`, por lo que también protege el registro general sin materia.
- cada mascota: `unique(user_id)`.
- XP: importe `1..1000`; único por `(user_id, source, source_id)`.

El trigger de evaluaciones calcula `percentage` y `status` a partir de `grade`, `max_grade` y `passing_percentage`. El cliente no decide esos resultados.

## RLS

RLS está habilitado sobre todas las tablas privadas. La regla directa habitual es:

```sql
auth.uid() = user_id
```

Para filas indirectas se atraviesa la relación segura:

- `ai_messages` → `ai_conversations.user_id`
- `quiz_questions` y `quiz_answers` → `quizzes.user_id`

No hay políticas de insert/update/delete para `xp_transactions`, `quiz_answer_keys`, `quiz_answers`, ni `pets`. Sus mutaciones son exclusivamente service-role desde funciones que verifican JWT/ownership primero. La migración de integridad bloquea al navegador la inserción directa y cambios de estado/completado de tareas: `create_task_atomic` deriva el dueño desde `auth.uid()` y `complete_task_atomic` corre desde Edge Function. También bloquea creación/edición de sesiones y evaluaciones mediante RPCs atómicas. `notifications` permite al navegador únicamente actualizar `read_at`. Las definiciones globales `levels`, `achievements` y `pet_items` sólo son legibles.

## XP y rachas

`award_xp_internal` es una función `security definer` sin permisos para `anon`, `authenticated` o `public`; recibe llamadas desde service role. `award_xp_for_verified_event_atomic` acepta únicamente una fuente permitida, comprueba bajo bloqueo que el evento propio está completado y calcula una recompensa fija. Inserta con `ON CONFLICT DO NOTHING`, calcula el total, actualiza racha usando el timezone almacenado en `profiles`, y ajusta la mascota dentro de límites. Esto mantiene los retries seguros.

## Storage

Los buckets son privados. Las políticas de `storage.objects` requieren que `storage.foldername(name)[1] = auth.uid()::text` y sólo se aplican a `documents`, `avatars` y `audio`. La ruta recomendada de documentos es `documents/{user_id}/{document_id}/{safe_name}`.

## Prueba RLS

`supabase/tests/database/security_rls.test.sql` ejecuta pruebas pgTAP con dos usuarios A/B en una base Supabase local: lectura y mutación cruzada, Storage, FKs cross-user, privilegios de XP y tareas, y reintentos atómicos de tareas/quizzes. Se corre con `supabase test db --local` y está incluido en CI. La ejecución contra el proyecto remoto requiere credenciales de administrador y cuentas de prueba autorizadas; nunca se debe apuntar la suite a datos de usuarios.
