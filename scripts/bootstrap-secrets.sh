#!/bin/bash
# Generates the git-ignored local secret files an overlay needs, if they
# don't already exist. Safe to re-run — never overwrites existing files, so
# rotating a secret is a matter of deleting the specific file and re-running.
#
# Usage: scripts/bootstrap-secrets.sh [overlay]   (default: local-vm)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
OVERLAY="${1:-local-vm}"
SECRETS_DIR="$DIR/k8s/overlays/$OVERLAY/secrets"
mkdir -p "$SECRETS_DIR"

randpw() {
  # Alphanumeric-only so it's always safe to interpolate into SQL/YAML/URLs
  # without extra quoting logic.
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c1-32
}

write_if_missing() {
  local file="$1"
  shift
  if [ -f "$file" ]; then
    echo "Skipping $file (already exists)"
    return
  fi
  printf '%s\n' "$@" > "$file"
  chmod 600 "$file"
  echo "Generated $file"
}

write_if_missing "$SECRETS_DIR/postgres.env" \
  "POSTGRES_PASSWORD=$(randpw)" \
  "KEYCLOAK_PASSWORD=$(randpw)" \
  "MERCHANT_PASSWORD=$(randpw)"

write_if_missing "$SECRETS_DIR/keycloak-admin.env" \
  "KEYCLOAK_ADMIN_PASSWORD=$(randpw)"

write_if_missing "$SECRETS_DIR/keycloak-clients.env" \
  "PORTAL_GATEWAY_CLIENT_SECRET=$(randpw)" \
  "HANSACORE_API_CLIENT_SECRET=$(randpw)" \
  "MICROSOFT_CLIENT_SECRET=PASTE_REAL_VALUE_FROM_ENTRA_PORTAL"

# Migration for setups bootstrapped before the Microsoft IdP secret was
# managed here: the file exists but has no such key yet.
if [ -f "$SECRETS_DIR/keycloak-clients.env" ] && ! grep -q '^MICROSOFT_CLIENT_SECRET=' "$SECRETS_DIR/keycloak-clients.env"; then
  echo "MICROSOFT_CLIENT_SECRET=PASTE_REAL_VALUE_FROM_ENTRA_PORTAL" >> "$SECRETS_DIR/keycloak-clients.env"
  echo "Added MICROSOFT_CLIENT_SECRET placeholder to $SECRETS_DIR/keycloak-clients.env"
fi

write_if_missing "$SECRETS_DIR/seed-users.env" \
  "SEED_USER_PASSWORD=$(randpw)"

if [ ! -f "$SECRETS_DIR/admin-basicauth.htpasswd" ]; then
  UI_PASSWORD="$(randpw)"
  HASH="$(openssl passwd -apr1 "$UI_PASSWORD")"
  printf 'admin:%s\n' "$HASH" > "$SECRETS_DIR/admin-basicauth.htpasswd"
  chmod 600 "$SECRETS_DIR/admin-basicauth.htpasswd"
  echo "Generated $SECRETS_DIR/admin-basicauth.htpasswd"
  echo "  BasicAuth in front of /admin -> username: admin  password: $UI_PASSWORD"
  echo "  (save this now — the plaintext password is not stored anywhere else)"
else
  echo "Skipping $SECRETS_DIR/admin-basicauth.htpasswd (already exists)"
fi

echo ""
echo "Done. Review the generated files under $SECRETS_DIR, then run:"
echo "  scripts/render-realm.sh $OVERLAY"
echo "  kubectl apply -k k8s/overlays/$OVERLAY"

if grep -q '^MICROSOFT_CLIENT_SECRET=PASTE_REAL_VALUE_FROM_ENTRA_PORTAL' "$SECRETS_DIR/keycloak-clients.env" 2>/dev/null; then
  echo ""
  echo "ACTION NEEDED: paste the real Entra client secret *value* into"
  echo "  $SECRETS_DIR/keycloak-clients.env  (MICROSOFT_CLIENT_SECRET=...)"
  echo "A placeholder there fails Microsoft login with AADSTS7000215."
fi
