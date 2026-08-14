#!/usr/bin/env bash
set -uo pipefail

# Scan every tracked and untracked, non-ignored file without printing matched values.
# Public example addresses and vendored upstream notices are not private repository data.
repo_root="$(git rev-parse --show-toplevel)" || exit 2
cd "$repo_root" || exit 2

failed=0
email_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
private_ip_re='(^|[^0-9])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)'
path_re='([A-Za-z]:\\Users\\[^\\/[:space:]]+|/Users/[^/[:space:]]+|/home/[^/[:space:]]+)'
secret_re="(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|api[_-]?key['\"]?[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9_./+=-]{16,}|client[_-]?secret['\"]?[[:space:]]*[:=]|password['\"]?[[:space:]]*[:=][[:space:]]*['\"]?[^[:space:]'\"]{8,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,})"

report_match() {
  local label="$1" pattern="$2" file="$3"
  if grep -IElq -- "$pattern" "$file" 2>/dev/null; then
    printf '%s: %s\n' "$label" "$file"
    failed=1
  fi
}

while IFS= read -r -d '' file; do
  [[ "$file" == "scripts/scan-sensitive.sh" ]] && continue

  report_match "private network address" "$private_ip_re" "$file"
  report_match "personal filesystem path" "$path_re" "$file"
  report_match "possible credential" "$secret_re" "$file"

  # Vendored notices may contain upstream public maintainer addresses.
  if [[ "$file" != scripts/vendor/* ]]; then
    disallowed_email="$({ grep -IEo -- "$email_re" "$file" 2>/dev/null || true; } |
      grep -Eiv '@(example\.(com|org|net)|users\.noreply\.github\.com)$' | head -n 1)"
    if [[ -n "$disallowed_email" ]]; then
      printf 'non-example email: %s\n' "$file"
      failed=1
    fi
  fi
done < <(git ls-files --cached --others --exclude-standard -z)

if (( failed )); then
  printf 'Sensitive-data scan failed.\n' >&2
  exit 1
fi

printf 'Sensitive-data scan passed.\n'
