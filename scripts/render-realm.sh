#!/bin/bash
# Renders identity/portal-realm.template.json into a Keycloak-import
# ConfigMap for one overlay, substituting placeholders with that overlay's
# real hostname + secret values. Output is written to
# k8s/overlays/<overlay>/02a-keycloak-realm-cm.generated.yaml, which is
# git-ignored (it contains rendered secret values) and referenced as a
# Kustomize resource by that overlay's kustomization.yaml.
#
# Usage: scripts/render-realm.sh [overlay]   (default: sit)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
OVERLAY="${1:-sit}"
KUBECTL="kubectl"
command -v kubectl >/dev/null 2>&1 || KUBECTL="kubectl.exe"  # WSL Docker Desktop interop
OVERLAY_DIR="$DIR/k8s/overlays/$OVERLAY"
SECRETS_DIR="$OVERLAY_DIR/secrets"

for f in "$OVERLAY_DIR/hansacore-env.properties" "$SECRETS_DIR/keycloak-clients.env" "$SECRETS_DIR/seed-users.env" "$SECRETS_DIR/keycloak-smtp.env"; do
  if [ ! -f "$f" ]; then
    echo "Missing $f — run scripts/bootstrap-secrets.sh $OVERLAY first." >&2
    exit 1
  fi
done

# tr strips CR so files saved with Windows line endings don't leak "\r" into URLs.
get_val() { grep -m1 "^$1=" "$2" | cut -d= -f2- | tr -d '\r'; }

ERP_HOSTNAME="$(get_val ERP_HOSTNAME "$OVERLAY_DIR/hansacore-env.properties")"
PORTAL_HOSTNAME="$(get_val PORTAL_HOSTNAME "$OVERLAY_DIR/hansacore-env.properties")"
if [ -z "$ERP_HOSTNAME" ] || [ -z "$PORTAL_HOSTNAME" ]; then
  echo "ERP_HOSTNAME and PORTAL_HOSTNAME must be set in $OVERLAY_DIR/hansacore-env.properties" >&2
  exit 1
fi
PORTAL_GATEWAY_CLIENT_SECRET="$(get_val PORTAL_GATEWAY_CLIENT_SECRET "$SECRETS_DIR/keycloak-clients.env")"
HANSACORE_API_CLIENT_SECRET="$(get_val HANSACORE_API_CLIENT_SECRET "$SECRETS_DIR/keycloak-clients.env")"
MICROSOFT_CLIENT_SECRET="$(get_val MICROSOFT_CLIENT_SECRET "$SECRETS_DIR/keycloak-clients.env")"
MICROSOFT_CLIENT_ID="$(get_val MICROSOFT_CLIENT_ID "$SECRETS_DIR/keycloak-clients.env")"
# Application (client) ID of the app registration that is the platform's Microsoft
# login. Until MICROSOFT_CLIENT_ID is set, the legacy registration (in Forty2's
# directory) keeps working; move to the HansaCore-owned one (docs/sit-sso-rollout.md).
LEGACY_MICROSOFT_CLIENT_ID="74741127-2028-4328-a8cf-057363b92b42"
if [ -z "$MICROSOFT_CLIENT_ID" ] || [[ "$MICROSOFT_CLIENT_ID" == PASTE_* ]]; then
  echo "WARNING: MICROSOFT_CLIENT_ID is not set in $SECRETS_DIR/keycloak-clients.env — using the legacy app registration." >&2
  MICROSOFT_CLIENT_ID="$LEGACY_MICROSOFT_CLIENT_ID"
fi
SEED_USER_PASSWORD="$(get_val SEED_USER_PASSWORD "$SECRETS_DIR/seed-users.env")"
SMTP_HOST="$(get_val SMTP_HOST "$SECRETS_DIR/keycloak-smtp.env")"
SMTP_PORT="$(get_val SMTP_PORT "$SECRETS_DIR/keycloak-smtp.env")"
SMTP_FROM="$(get_val SMTP_FROM "$SECRETS_DIR/keycloak-smtp.env")"
SMTP_USER="$(get_val SMTP_USER "$SECRETS_DIR/keycloak-smtp.env")"
SMTP_PASSWORD="$(get_val SMTP_PASSWORD "$SECRETS_DIR/keycloak-smtp.env")"

if [ -z "$MICROSOFT_CLIENT_SECRET" ]; then
  echo "Missing MICROSOFT_CLIENT_SECRET in $SECRETS_DIR/keycloak-clients.env — paste the Entra client secret *value* there first (see README section 4)." >&2
  exit 1
fi
# Escape sed-replacement metacharacters (&, backslash, and the # delimiter)
# so any Entra-generated secret value renders verbatim.
MICROSOFT_CLIENT_SECRET_ESC="$(printf '%s' "$MICROSOFT_CLIENT_SECRET" | sed -e 's/[\\&#]/\\&/g')"
SMTP_PASSWORD_ESC="$(printf '%s' "$SMTP_PASSWORD" | sed -e 's/[\\&#]/\\&/g')"
# Self-registration requires email verification, so without SMTP nobody can
# finish signing up with a local account (Microsoft logins still work).
if [ -z "$SMTP_HOST" ] || [ "$SMTP_HOST" = "PASTE_SMTP_HOST" ]; then
  echo "WARNING: SMTP_HOST is not set in $SECRETS_DIR/keycloak-smtp.env — Keycloak cannot send verification emails." >&2
fi
ERP_BASE_URL="https://${ERP_HOSTNAME}"
PORTAL_BASE_URL="https://${PORTAL_HOSTNAME}"

# Use a temp file inside the repo tree (not /tmp) so it resolves correctly
# whether this runs under Git Bash, WSL, or a real Linux shell, and whether
# `kubectl` is a native binary or a Windows .exe invoked via WSL interop.
TMP_JSON="$OVERLAY_DIR/.portal-realm.rendered.json.tmp"
trap 'rm -f "$TMP_JSON"' EXIT

sed \
  -e "s#__ERP_BASE_URL__#${ERP_BASE_URL}#g" \
  -e "s#__PORTAL_BASE_URL__#${PORTAL_BASE_URL}#g" \
  -e "s#__PORTAL_GATEWAY_CLIENT_SECRET__#${PORTAL_GATEWAY_CLIENT_SECRET}#g" \
  -e "s#__HANSACORE_API_CLIENT_SECRET__#${HANSACORE_API_CLIENT_SECRET}#g" \
  -e "s#__MICROSOFT_CLIENT_ID__#${MICROSOFT_CLIENT_ID}#g" \
  -e "s#__MICROSOFT_CLIENT_SECRET__#${MICROSOFT_CLIENT_SECRET_ESC}#g" \
  -e "s#__SEED_USER_PASSWORD__#${SEED_USER_PASSWORD}#g" \
  -e "s#__SMTP_HOST__#${SMTP_HOST}#g" \
  -e "s#__SMTP_PORT__#${SMTP_PORT:-587}#g" \
  -e "s#__SMTP_FROM__#${SMTP_FROM}#g" \
  -e "s#__SMTP_USER__#${SMTP_USER}#g" \
  -e "s#__SMTP_PASSWORD__#${SMTP_PASSWORD_ESC}#g" \
  "$DIR/identity/portal-realm.template.json" > "$TMP_JSON"

if grep -q '__[A-Z_]*__' "$TMP_JSON"; then
  echo "Unrendered placeholders left in the realm:" >&2
  grep -o '__[A-Z_]*__' "$TMP_JSON" | sort -u >&2
  exit 1
fi

"$KUBECTL" create configmap keycloak-realm \
  --from-file=portal-realm.json="$TMP_JSON" \
  -n hansacore \
  --dry-run=client -o yaml > "$OVERLAY_DIR/02a-keycloak-realm-cm.generated.yaml"

echo "Wrote $OVERLAY_DIR/02a-keycloak-realm-cm.generated.yaml (ERP: $ERP_BASE_URL, portal: $PORTAL_BASE_URL)"
