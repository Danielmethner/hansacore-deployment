#!/bin/bash
# Renders identity/portal-realm.template.json into a Keycloak-import
# ConfigMap for one overlay, substituting placeholders with that overlay's
# real hostname + secret values. Output is written to
# k8s/overlays/<overlay>/02a-keycloak-realm-cm.generated.yaml, which is
# git-ignored (it contains rendered secret values) and referenced as a
# Kustomize resource by that overlay's kustomization.yaml.
#
# Usage: scripts/render-realm.sh [overlay]   (default: local-vm)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
OVERLAY="${1:-local-vm}"
KUBECTL="kubectl"
command -v kubectl >/dev/null 2>&1 || KUBECTL="kubectl.exe"  # WSL Docker Desktop interop
OVERLAY_DIR="$DIR/k8s/overlays/$OVERLAY"
SECRETS_DIR="$OVERLAY_DIR/secrets"

for f in "$OVERLAY_DIR/hansacore-env.properties" "$SECRETS_DIR/keycloak-clients.env" "$SECRETS_DIR/seed-users.env"; do
  if [ ! -f "$f" ]; then
    echo "Missing $f — run scripts/bootstrap-secrets.sh $OVERLAY first." >&2
    exit 1
  fi
done

get_val() { grep -m1 "^$1=" "$2" | cut -d= -f2-; }

PUBLIC_HOSTNAME="$(get_val PUBLIC_HOSTNAME "$OVERLAY_DIR/hansacore-env.properties")"
PORTAL_GATEWAY_CLIENT_SECRET="$(get_val PORTAL_GATEWAY_CLIENT_SECRET "$SECRETS_DIR/keycloak-clients.env")"
HANSACORE_API_CLIENT_SECRET="$(get_val HANSACORE_API_CLIENT_SECRET "$SECRETS_DIR/keycloak-clients.env")"
SEED_USER_PASSWORD="$(get_val SEED_USER_PASSWORD "$SECRETS_DIR/seed-users.env")"
BASE_URL="https://${PUBLIC_HOSTNAME}"

# Use a temp file inside the repo tree (not /tmp) so it resolves correctly
# whether this runs under Git Bash, WSL, or a real Linux shell, and whether
# `kubectl` is a native binary or a Windows .exe invoked via WSL interop.
TMP_JSON="$OVERLAY_DIR/.portal-realm.rendered.json.tmp"
trap 'rm -f "$TMP_JSON"' EXIT

sed \
  -e "s#__BASE_URL__#${BASE_URL}#g" \
  -e "s#__PORTAL_GATEWAY_CLIENT_SECRET__#${PORTAL_GATEWAY_CLIENT_SECRET}#g" \
  -e "s#__HANSACORE_API_CLIENT_SECRET__#${HANSACORE_API_CLIENT_SECRET}#g" \
  -e "s#__SEED_USER_PASSWORD__#${SEED_USER_PASSWORD}#g" \
  "$DIR/identity/portal-realm.template.json" > "$TMP_JSON"

"$KUBECTL" create configmap keycloak-realm \
  --from-file=portal-realm.json="$TMP_JSON" \
  -n hansacore \
  --dry-run=client -o yaml > "$OVERLAY_DIR/02a-keycloak-realm-cm.generated.yaml"

echo "Wrote $OVERLAY_DIR/02a-keycloak-realm-cm.generated.yaml (base URL: $BASE_URL)"
