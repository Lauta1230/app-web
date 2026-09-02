-- Run in local Supabase / pgTAP-aware CI after creating two auth users.
-- Regression intent: a user can never read or alter another user's private data.
begin;
-- Replace IDs in a CI harness and set request.jwt.claim.sub for each role.
-- Expected assertions:
-- 1. user A sees only subjects where user_id = A.
-- 2. user A cannot update/delete tasks, notes, pets, documents or conversations owned by B.
-- 3. user A cannot select quiz_answer_keys or insert xp_transactions.
-- 4. an Edge Function using service_role validates its JWT user before querying by ownership.
rollback;
