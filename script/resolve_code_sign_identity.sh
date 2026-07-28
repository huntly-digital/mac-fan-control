#!/usr/bin/env bash
set -euo pipefail

REQUESTED_IDENTITY="${CODE_SIGN_IDENTITY:-}"

if [[ "$REQUESTED_IDENTITY" == "-" ]]; then
  echo "Ad-hoc signing is incompatible with the privileged helper." >&2
  echo "Use an Apple Development identity for both the app and helper." >&2
  exit 1
fi

if [[ -n "$REQUESTED_IDENTITY" ]]; then
  echo "$REQUESTED_IDENTITY"
  exit 0
fi

IDENTITIES="$(
  /usr/bin/security find-identity -v -p codesigning \
    | /usr/bin/awk '/^[[:space:]]*[0-9]+\)/ { print $2 }'
)"
IDENTITY_COUNT="$(
  printf '%s\n' "$IDENTITIES" \
    | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }'
)"

case "$IDENTITY_COUNT" in
  1)
    printf '%s\n' "$IDENTITIES"
    ;;
  0)
    echo "No valid Apple Development code-signing identity was found." >&2
    exit 1
    ;;
  *)
    echo "Multiple code-signing identities were found." >&2
    echo "Set CODE_SIGN_IDENTITY to the intended identity or SHA-1 hash." >&2
    exit 1
    ;;
esac
