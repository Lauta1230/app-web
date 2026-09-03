#!/usr/bin/env bash
# Verifies the fixed Edge Function inventory and the baseline auth configuration.
# This script deliberately contains no credentials and makes no network requests.
set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repository_root"

functions=(
  ai-chat
  ai-quiz
  submit-quiz
  award-xp
  complete-task
  complete-study-session
  ocr-document
  process-document
  humanize-text
  analyze-ai-text
  study-recommendation
  process-exam
  pet-care
  dashboard
  notifications
)

case "${1:-}" in
  --print-names)
    printf '%s\n' "${functions[@]}"
    exit 0
    ;;
  --print-entrypoints)
    for function_name in "${functions[@]}"; do
      printf 'supabase/functions/%s/index.ts\n' "$function_name"
    done
    exit 0
    ;;
  '')
    ;;
  *)
    echo "Usage: $0 [--print-names|--print-entrypoints]" >&2
    exit 2
    ;;
esac

expected=$(printf '%s\n' "${functions[@]}" | sort)
actual=$(find supabase/functions -mindepth 2 -maxdepth 2 -name index.ts -printf '%h\n' | sed 's#supabase/functions/##' | sort)
if [[ "$actual" != "$expected" ]]; then
  echo 'The Edge Function directories do not match the approved deployment inventory.' >&2
  diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
  exit 1
fi

for function_name in "${functions[@]}"; do
  entrypoint="supabase/functions/$function_name/index.ts"
  grep -Fq 'Deno.serve' "$entrypoint" || { echo "$function_name has no Deno handler." >&2; exit 1; }
  grep -Fq 'requireUser(request)' "$entrypoint" || { echo "$function_name does not enforce application-level user authentication." >&2; exit 1; }

  if ! awk -v function_name="$function_name" '
    $0 == "[functions." function_name "]" { in_function = 1; next }
    in_function && /^\[/ { exit }
    in_function && $0 ~ /^verify_jwt[[:space:]]*=[[:space:]]*false[[:space:]]*$/ { found = 1 }
    END { exit !found }
  ' supabase/config.toml; then
    echo "$function_name must explicitly use manual JWT verification in supabase/config.toml." >&2
    exit 1
  fi
done

# A service-role operation may only use the identity established by requireUser().
if grep -R -nE '(input|body|payload)\.user_id' supabase/functions/*/index.ts; then
  echo 'An Edge Function derives user authority from client-controlled user_id input.' >&2
  exit 1
fi

# Regressions in these two service-role paths would expose or modify another user's data.
grep -Fq "auth.admin.from('xp_transactions').select('amount').eq('user_id', auth.user.id)" supabase/functions/dashboard/index.ts || {
  echo 'Dashboard XP aggregation is not scoped to the authenticated user.' >&2
  exit 1
}
grep -Fq "if (documentId && userId && admin)" supabase/functions/ocr-document/index.ts || {
  echo 'OCR failure cleanup is not scoped to the authenticated user.' >&2
  exit 1
}
grep -Fq ".eq('id', documentId).eq('user_id', userId)" supabase/functions/ocr-document/index.ts || {
  echo 'OCR failure cleanup must constrain the document by authenticated user.' >&2
  exit 1
}

echo "Validated ${#functions[@]} approved Edge Functions, their manual authentication guard, and JWT configuration."
