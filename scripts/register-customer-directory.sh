#!/bin/bash
# Registers an existing customer organisation (a MASTER_CLIENT) with the identity
# directory and email domains its staff sign in with, so that people from that
# directory are recognised on first login and nobody else can claim the directory
# or the domains at /onboarding.
#
# Needed once for customers that were created before SSO onboarding existed, for
# example Forty2 (which uses Microsoft Entra): the onboarding schema only creates
# empty tables, it does not know who the existing customers are.
#
# Idempotent: safe to run again. Refuses to touch a directory or domain that
# belongs to a different customer. Everything runs in one transaction.
#
# Usage:
#   scripts/register-customer-directory.sh <sit|uat|prod> "<customer name>" \
#       <directory-id> <domain> [<domain>...]
#
#   <customer name>  display name of the MASTER_CLIENT, exactly as in tenant_profile
#   <directory-id>   Microsoft Entra directory (tenant) ID of the customer
#   <domain>         email domains of that customer; the first is the primary one
#
# Example:
#   scripts/register-customer-directory.sh sit "Forty2" \
#       00000000-0000-0000-0000-000000000000 forty2.ch forty2.de
#
# Environment:
#   IDP_PROVIDER      provider key of the directory (default MICROSOFT)
#   RESERVED_DOMAINS  comma list refused as customer domains (default hansacore.com)
#   KUBECTL           kubectl binary (default kubectl, kubectl.exe as fallback)
#
# Run it where kubectl reaches the environment (on the VM, as scripts/manage-env.sh does).
set -euo pipefail

NAMESPACE=hansacore
DB=hansacore
SCHEMA=hansacore
PROVIDER="${IDP_PROVIDER:-MICROSOFT}"
RESERVED_DOMAINS="${RESERVED_DOMAINS:-hansacore.com}"
CONSUMER_TENANT_ID="9188040d-6c67-4c5b-b112-36a304b66dad"
# Keep in sync with EmailDomains.PUBLIC_DOMAINS in hansacore-api.
PUBLIC_DOMAINS="gmail.com googlemail.com outlook.com hotmail.com live.com msn.com yahoo.com icloud.com me.com gmx.de gmx.net web.de proton.me protonmail.com t-online.de"

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//' >&2
  exit 1
}

[ "$#" -ge 4 ] || usage
OVERLAY="$1"
CUSTOMER="$2"
DIRECTORY_ID="$(printf '%s' "$3" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
shift 3

case "$OVERLAY" in
  sit | uat | prod) ;;
  *)
    echo "Unknown environment '$OVERLAY' (expected sit, uat or prod)." >&2
    exit 1
    ;;
esac

KUBECTL="${KUBECTL:-kubectl}"
command -v "$KUBECTL" >/dev/null 2>&1 || KUBECTL="kubectl.exe"

if [ -z "${CUSTOMER// /}" ]; then
  echo "Customer name must not be empty." >&2
  exit 1
fi
if ! [[ "$DIRECTORY_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
  echo "Directory id '$DIRECTORY_ID' is not a GUID." >&2
  exit 1
fi
if [ "$PROVIDER" = "MICROSOFT" ] && [ "$DIRECTORY_ID" = "$CONSUMER_TENANT_ID" ]; then
  echo "$DIRECTORY_ID is Microsoft's consumer tenant (personal accounts); it cannot be a customer directory." >&2
  exit 1
fi

DOMAINS=()
for raw in "$@"; do
  domain="$(printf '%s' "$raw" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
  domain="${domain#@}"
  while [[ "$domain" == *. ]]; do domain="${domain%.}"; done
  if ! [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
    echo "'$raw' is not a valid domain (use ASCII or punycode)." >&2
    exit 1
  fi
  for blocked in $PUBLIC_DOMAINS ${RESERVED_DOMAINS//,/ }; do
    if [ "$domain" = "$blocked" ]; then
      echo "'$domain' is a public or reserved domain and cannot be registered for a customer." >&2
      exit 1
    fi
  done
  DOMAINS+=("$domain")
done
DOMAIN_LIST="$(IFS=,; echo "${DOMAINS[*]}")"

echo "==> $OVERLAY: registering '$CUSTOMER' ($PROVIDER directory $DIRECTORY_ID) for: $DOMAIN_LIST"

"$KUBECTL" exec -i -n "$NAMESPACE" sts/postgres -- \
  psql -U postgres -d "$DB" -1 -v ON_ERROR_STOP=1 \
  -v "name=$CUSTOMER" -v "provider=$PROVIDER" -v "directory=$DIRECTORY_ID" \
  -v "domains=$DOMAIN_LIST" -v "schema=$SCHEMA" -f - <<'SQL'
SELECT set_config('search_path', :'schema', true);
SELECT set_config('reg.name', :'name', true),
       set_config('reg.provider', :'provider', true),
       set_config('reg.directory', :'directory', true),
       set_config('reg.domains', :'domains', true) \gset

DO $$
DECLARE
  v_name text := current_setting('reg.name');
  v_provider text := current_setting('reg.provider');
  v_directory text := current_setting('reg.directory');
  v_domains text[] := string_to_array(current_setting('reg.domains'), ',');
  v_master uuid;
  v_count integer;
  v_owner uuid;
  v_has_primary boolean;
  v_domain text;
  v_index integer := 0;
BEGIN
  SELECT count(*) INTO v_count
    FROM tenant_profile
   WHERE tenant_kind = 'MASTER_CLIENT' AND lower(display_name) = lower(v_name);
  IF v_count = 0 THEN
    RAISE EXCEPTION 'No customer (MASTER_CLIENT) named "%" found', v_name;
  ELSIF v_count > 1 THEN
    RAISE EXCEPTION 'Several customers (MASTER_CLIENT) are named "%"; rename one first', v_name;
  END IF;
  SELECT tenant_id INTO v_master
    FROM tenant_profile
   WHERE tenant_kind = 'MASTER_CLIENT' AND lower(display_name) = lower(v_name);

  SELECT tenant_id INTO v_owner
    FROM tenant_idp_binding
   WHERE provider = v_provider AND external_tenant_id = v_directory;
  IF v_owner IS NOT NULL AND v_owner <> v_master THEN
    RAISE EXCEPTION 'Directory % is already bound to another customer (%)', v_directory, v_owner;
  END IF;
  IF v_owner IS NULL THEN
    INSERT INTO tenant_idp_binding (id, tenant_id, provider, external_tenant_id)
    VALUES (gen_random_uuid(), v_master, v_provider, v_directory);
    RAISE NOTICE 'Bound % directory % to %', v_provider, v_directory, v_name;
  ELSE
    RAISE NOTICE 'Directory % is already bound to %', v_directory, v_name;
  END IF;

  -- Check every domain before writing any, so a conflict leaves nothing half done.
  FOREACH v_domain IN ARRAY v_domains LOOP
    SELECT tenant_id INTO v_owner
      FROM tenant_domain
     WHERE domain_name = v_domain AND status = 'VERIFIED';
    IF v_owner IS NOT NULL AND v_owner <> v_master THEN
      RAISE EXCEPTION 'Domain % is already verified for another customer (%)', v_domain, v_owner;
    END IF;
  END LOOP;

  SELECT EXISTS (
           SELECT 1 FROM tenant_domain
            WHERE tenant_id = v_master AND is_primary AND status = 'VERIFIED')
    INTO v_has_primary;

  FOREACH v_domain IN ARRAY v_domains LOOP
    v_index := v_index + 1;
    INSERT INTO tenant_domain
           (id, tenant_id, domain_name, status, verification_method, verified_at, is_primary)
    VALUES (gen_random_uuid(), v_master, v_domain, 'VERIFIED', 'IDP', now(),
            v_index = 1 AND NOT v_has_primary)
    ON CONFLICT (tenant_id, domain_name) DO UPDATE
       SET status = 'VERIFIED',
           verification_method = CASE WHEN tenant_domain.status = 'VERIFIED'
                                      THEN tenant_domain.verification_method ELSE 'IDP' END,
           verified_at = CASE WHEN tenant_domain.status = 'VERIFIED'
                              THEN tenant_domain.verified_at ELSE now() END;
    RAISE NOTICE 'Domain % is verified for %', v_domain, v_name;
  END LOOP;
END
$$;

SELECT b.provider, b.external_tenant_id AS directory
  FROM tenant_idp_binding b
  JOIN tenant_profile p ON p.tenant_id = b.tenant_id
 WHERE lower(p.display_name) = lower(:'name') AND p.tenant_kind = 'MASTER_CLIENT'
 ORDER BY b.created_at;

SELECT d.domain_name, d.status, d.verification_method, d.is_primary
  FROM tenant_domain d
  JOIN tenant_profile p ON p.tenant_id = d.tenant_id
 WHERE lower(p.display_name) = lower(:'name') AND p.tenant_kind = 'MASTER_CLIENT'
 ORDER BY d.created_at;
SQL

echo "Done. Sign-in from this directory and these domains is now recognised for '$CUSTOMER'."
