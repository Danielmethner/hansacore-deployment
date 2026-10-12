#!/bin/bash
# Applies the SSO onboarding realm changes (multi-tenant Microsoft Entra, the
# provider-neutral idp_* claim mappers, self-registration, SMTP, HansaCore
# theme) to an already running
# Keycloak. The realm import only runs on an empty Keycloak database, so
# identity/portal-realm.template.json alone does not reach SIT/UAT/PROD.
#
# Idempotent: safe to run again. Requires kubectl access to the cluster and jq.
# Deploy the hansacore-keycloak:local image first (scripts/build-images.sh
# keycloak), otherwise the theme step is skipped.
#
# Usage: scripts/apply-realm-sso-onboarding.sh [overlay]   (default: sit)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
OVERLAY="${1:-sit}"
SECRETS_DIR="$DIR/k8s/overlays/$OVERLAY/secrets"
NAMESPACE=hansacore
REALM=portal
KUBECTL="kubectl"
command -v kubectl >/dev/null 2>&1 || KUBECTL="kubectl.exe"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required (apt-get install jq)." >&2
  exit 1
fi
for f in "$SECRETS_DIR/keycloak-admin.env" "$SECRETS_DIR/keycloak-smtp.env"; do
  if [ ! -f "$f" ]; then
    echo "Missing $f — run scripts/bootstrap-secrets.sh $OVERLAY first." >&2
    exit 1
  fi
done

get_val() { grep -m1 "^$1=" "$2" | cut -d= -f2- | tr -d '\r'; }

ADMIN_PASSWORD="$(get_val KEYCLOAK_ADMIN_PASSWORD "$SECRETS_DIR/keycloak-admin.env")"
SMTP_HOST="$(get_val SMTP_HOST "$SECRETS_DIR/keycloak-smtp.env")"
SMTP_PORT="$(get_val SMTP_PORT "$SECRETS_DIR/keycloak-smtp.env")"
SMTP_FROM="$(get_val SMTP_FROM "$SECRETS_DIR/keycloak-smtp.env")"
SMTP_USER="$(get_val SMTP_USER "$SECRETS_DIR/keycloak-smtp.env")"
SMTP_PASSWORD="$(get_val SMTP_PASSWORD "$SECRETS_DIR/keycloak-smtp.env")"

kc() {
  "$KUBECTL" exec -i -n "$NAMESPACE" deploy/keycloak -- \
    /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config
}

echo "==> Logging in to Keycloak admin API"
kc config credentials --server http://localhost:8080 --realm master \
  --user admin --password "$ADMIN_PASSWORD" >/dev/null

MS=https://login.microsoftonline.com

SMTP_ARGS=()
if [ -n "$SMTP_HOST" ] && [[ "$SMTP_HOST" != PASTE_* ]]; then
  SMTP_ARGS=(
    -s "smtpServer.host=$SMTP_HOST"
    -s "smtpServer.port=${SMTP_PORT:-587}"
    -s "smtpServer.from=$SMTP_FROM"
    -s smtpServer.fromDisplayName=HansaCore
    -s smtpServer.auth=true
    -s "smtpServer.user=$SMTP_USER"
    -s "smtpServer.password=$SMTP_PASSWORD"
    -s smtpServer.starttls=true
    -s smtpServer.ssl=false
  )
else
  echo "    (SMTP not configured in keycloak-smtp.env - leaving the realm's mail settings unchanged)"
fi

echo "==> Realm: self-registration, email verification, password policy, SMTP"
kc update "realms/$REALM" \
  -s displayName=HansaCore \
  -s registrationAllowed=true \
  -s registrationEmailAsUsername=true \
  -s verifyEmail=true \
  -s resetPasswordAllowed=true \
  -s duplicateEmailsAllowed=false \
  -s bruteForceProtected=true \
  -s 'passwordPolicy=length(12) and notUsername(undefined) and notEmail(undefined)' \
  -s internationalizationEnabled=true \
  -s 'supportedLocales=["en","de"]' \
  -s defaultLocale=en \
  ${SMTP_ARGS[@]+"${SMTP_ARGS[@]}"}

echo "==> Realm: sign-in audit events (30 days, written to the Keycloak log)"
kc update "realms/$REALM" \
  -s eventsEnabled=true \
  -s eventsExpiration=2592000 \
  -s 'eventsListeners=["jboss-logging"]' \
  -s 'enabledEventTypes=["LOGIN","LOGIN_ERROR","LOGOUT","LOGOUT_ERROR","REGISTER","REGISTER_ERROR","IDENTITY_PROVIDER_FIRST_LOGIN","IDENTITY_PROVIDER_LOGIN","IDENTITY_PROVIDER_LOGIN_ERROR","IDENTITY_PROVIDER_POST_LOGIN","IDENTITY_PROVIDER_LINK_ACCOUNT","UPDATE_PASSWORD","UPDATE_PASSWORD_ERROR","UPDATE_TOTP","REMOVE_TOTP","RESET_PASSWORD","RESET_PASSWORD_ERROR","VERIFY_EMAIL","CODE_TO_TOKEN_ERROR","REFRESH_TOKEN_ERROR","USER_DISABLED_BY_PERMANENT_LOCKOUT","USER_DISABLED_BY_TEMPORARY_LOCKOUT"]' \
  -s adminEventsEnabled=true \
  -s adminEventsDetailsEnabled=false

if kc get serverinfo | jq -e '.themes.login[] | select(.name == "hansacore")' >/dev/null; then
  echo "==> Realm: HansaCore login and email theme"
  kc update "realms/$REALM" -s loginTheme=hansacore -s emailTheme=hansacore
else
  echo "WARNING: theme 'hansacore' is not installed in the running Keycloak; skipping theme step." >&2
fi

CLIENTS_ENV="$SECRETS_DIR/keycloak-clients.env"
MS_CLIENT_ID=""
MS_CLIENT_SECRET=""
if [ -f "$CLIENTS_ENV" ]; then
  MS_CLIENT_ID="$(get_val MICROSOFT_CLIENT_ID "$CLIENTS_ENV")"
  MS_CLIENT_SECRET="$(get_val MICROSOFT_CLIENT_SECRET "$CLIENTS_ENV")"
fi
MS_CREDENTIALS=()
if [ -n "$MS_CLIENT_ID" ] && [[ "$MS_CLIENT_ID" != PASTE_* ]] \
  && [ -n "$MS_CLIENT_SECRET" ] && [[ "$MS_CLIENT_SECRET" != PASTE_* ]]; then
  echo "==> Using MICROSOFT_CLIENT_ID and MICROSOFT_CLIENT_SECRET from $CLIENTS_ENV"
  MS_CREDENTIALS=(-s "config.clientId=$MS_CLIENT_ID" -s "config.clientSecret=$MS_CLIENT_SECRET")
else
  echo "==> MICROSOFT_CLIENT_ID/SECRET not set in $CLIENTS_ENV: leaving the live app credentials as they are"
fi

echo "==> Identity provider 'microsoft': multi-tenant endpoints, no fixed issuer, default first broker login"
kc update "identity-provider/instances/microsoft" -r "$REALM" \
  ${MS_CREDENTIALS[@]+"${MS_CREDENTIALS[@]}"} \
  -s 'firstBrokerLoginFlowAlias=first broker login' \
  -s trustEmail=true \
  -s "config.authorizationUrl=$MS/organizations/oauth2/v2.0/authorize" \
  -s "config.tokenUrl=$MS/organizations/oauth2/v2.0/token" \
  -s "config.logoutUrl=$MS/organizations/oauth2/v2.0/logout" \
  -s "config.metadataDescriptorUrl=$MS/organizations/v2.0/.well-known/openid-configuration" \
  -s "config.jwksUrl=$MS/common/discovery/v2.0/keys" \
  -s config.useJwksUrl=true \
  -s config.validateSignature=true \
  -s config.issuer= \
  -s config.userInfoUrl= \
  -s config.disableUserInfo=true \
  -s 'config.defaultScope=openid profile email'

echo "==> Identity provider mappers"
existing_idp_mappers="$(kc get identity-provider/instances/microsoft/mappers -r "$REALM" | jq -r '.[].name')"
add_idp_mapper() {
  local name="$1" claim="$2" attribute="$3"
  if grep -qx "$name" <<<"$existing_idp_mappers"; then
    echo "    $name exists"
    return
  fi
  kc create identity-provider/instances/microsoft/mappers -r "$REALM" \
    -s "name=$name" \
    -s identityProviderAlias=microsoft \
    -s identityProviderMapper=oidc-user-attribute-idp-mapper \
    -s config.syncMode=FORCE \
    -s "config.claim=$claim" \
    -s "config.\"user.attribute\"=$attribute"
  echo "    $name created"
}
add_idp_mapper microsoft-directory-id-mapper tid idp_directory_id
add_idp_mapper microsoft-domain-verified-mapper xms_edov idp_domain_verified
add_idp_mapper microsoft-email-mapper email idp_email

echo "==> User profile: admin-only identity provider attributes"
EXTRA_ATTRIBUTES='[
  {"name":"idp_directory_id","displayName":"Identity provider directory ID","permissions":{"view":["admin"],"edit":["admin"]},"multivalued":false},
  {"name":"idp_domain_verified","displayName":"Identity provider email domain verified","permissions":{"view":["admin"],"edit":["admin"]},"multivalued":false},
  {"name":"idp_email","displayName":"Identity provider email","permissions":{"view":["admin"],"edit":["admin"]},"multivalued":false},
  {"name":"country","displayName":"Country","permissions":{"view":["admin"],"edit":["admin"]},"multivalued":false}
]'
kc get users/profile -r "$REALM" \
  | jq --argjson extra "$EXTRA_ATTRIBUTES" \
    '.attributes as $a | .attributes = $a + [$extra[] | select(.name as $n | ($a | map(.name) | index($n)) == null)]' \
  | kc update users/profile -r "$REALM" -f -

echo "==> portal-gateway access-token mappers"
GATEWAY_ID="$(kc get clients -r "$REALM" -q clientId=portal-gateway | jq -r '.[0].id')"
existing_client_mappers="$(kc get "clients/$GATEWAY_ID/protocol-mappers/models" -r "$REALM" | jq -r '.[].name')"
add_attribute_mapper() {
  local name="$1" attribute="$2"
  if grep -qx "$name" <<<"$existing_client_mappers"; then
    echo "    $name exists"
    return
  fi
  kc create "clients/$GATEWAY_ID/protocol-mappers/models" -r "$REALM" \
    -s "name=$name" \
    -s protocol=openid-connect \
    -s protocolMapper=oidc-usermodel-attribute-mapper \
    -s "config.\"user.attribute\"=$attribute" \
    -s "config.\"claim.name\"=$attribute" \
    -s 'config."jsonType.label"=String' \
    -s 'config."access.token.claim"=true' \
    -s 'config."id.token.claim"=false' \
    -s 'config."userinfo.token.claim"=false' \
    -s 'config."introspection.token.claim"=true'
  echo "    $name created"
}
add_attribute_mapper idp-directory-id idp_directory_id
add_attribute_mapper idp-domain-verified idp_domain_verified
add_attribute_mapper idp-email idp_email
if grep -qx identity-provider <<<"$existing_client_mappers"; then
  echo "    identity-provider exists"
else
  kc create "clients/$GATEWAY_ID/protocol-mappers/models" -r "$REALM" \
    -s name=identity-provider \
    -s protocol=openid-connect \
    -s protocolMapper=oidc-usersessionmodel-note-mapper \
    -s 'config."user.session.note"=identity_provider' \
    -s 'config."claim.name"=identity_provider' \
    -s 'config."jsonType.label"=String' \
    -s 'config."access.token.claim"=true' \
    -s 'config."id.token.claim"=false' \
    -s 'config."introspection.token.claim"=true'
  echo "    identity-provider created"
fi

echo "==> Removing the auto-link first broker login flow"
AUTO_LINK_ID="$(kc get authentication/flows -r "$REALM" | jq -r '.[] | select(.alias == "first-broker-login-auto-link") | .id')"
if [ -n "$AUTO_LINK_ID" ]; then
  kc delete "authentication/flows/$AUTO_LINK_ID" -r "$REALM"
  echo "    deleted"
else
  echo "    already gone"
fi

echo "Done. Realm '$REALM' on overlay '$OVERLAY' is up to date."
