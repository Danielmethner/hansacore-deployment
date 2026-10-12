# SIT rollout: provider-neutral SSO and onboarding

Runbook for taking the SSO onboarding work live on SIT (UAT and PROD later use
the same steps with another `<env>`). Nothing of this has run against SIT yet, so
every step below is still open.

Who is who:
- **HansaCore** runs the SaaS. Its staff sign in with a Keycloak username and
  password and have no identity provider.
- **Forty2** is a customer (one MASTER_CLIENT, a sub-tenant per country). Its
  staff sign in with Microsoft Entra.
- Other customers are enterprises (any identity provider later) or private
  individuals (personal workspace, Keycloak username and password).

Run the scripts on the SIT VM (where `kubectl` reaches the cluster), as
`scripts/manage-env.sh` does. Steps marked **you** need access only you have.

## Order at a glance

1. Create the HansaCore Entra directory and register the Microsoft login app there (**you**)
2. SMTP relay (**you**)
3. Deploy the code and reset the SIT database
4. Register Forty2 as a customer
5. Point Keycloak at the new app and apply the realm changes
6. Fix the seed user, then smoke test

Steps 1 and 2 can be done in parallel and do not touch SIT. Do step 4 before
step 5: once the realm uses the multitenant endpoints, people from other
directories can reach `/onboarding`, and until Forty2 is registered one of them
could claim Forty2's directory and domain.

## 1. The HansaCore Entra directory and the login app — **you**

The platform's Microsoft login is one **app registration**. It must live in a
directory HansaCore owns, not in Forty2's: whoever administers the directory can
delete the app or rotate its secret, and sign-in then breaks for every customer.

The HansaCore directory (see 1a) contains no users of the platform and needs **no Azure
subscription and no payment method**. App registrations are free, and without a
subscription nothing can be created that costs money.

### 1a. Use the Default Directory of your private Microsoft account

Creating a *new* directory is not an option without paying: Microsoft requires a
paid licence for a workforce tenant and a subscription for an External one. Your
private Microsoft account (`daniel.methner@outlook.com`) already has a free
**Default Directory** and is its administrator, so use that. A company is not
required.

1. Go to [entra.microsoft.com](https://entra.microsoft.com/), sign in with the
   private account, and check the directory is the Default Directory (your
   own, not Forty2's).
2. *Entra ID* → *Overview* → *Properties*: set the name to `HansaCore` and save.
   Only the display name changes; the generated `….onmicrosoft.com` domain stays.
   Note the domain under *Domain names*.
3. Do not leave your private account as the only admin:
   - *Users* → *New user*: create `admin@<that domain>` (a work account inside
     the directory) and assign **Global Administrator** (*Roles & admins*).
   - Sign in as that user once, set a password, and set up MFA.
   - Optionally add `hansacore.com` as a custom domain (DNS TXT record) and
     create `admin@hansacore.com` instead. Later add a second admin so one lost
     account does not lock you out.
4. Do **not** use this admin account to sign in to the SaaS. Use your operator
   login (a local Keycloak account) for that.
5. Keep the directory free: no Azure subscription, no payment method.

### 1b. Register the login app (in the HansaCore directory)

1. *App registrations* → *New registration*. Name `HansaCore Login`. Supported
   account types: **Accounts in any organizational directory (Multitenant)**
   (not personal Microsoft accounts).
2. Redirect URI (type *Web*), one per environment you use:
   ```text
   https://sit.auth.hansacore.com/realms/portal/broker/microsoft/endpoint
   https://uat.auth.hansacore.com/realms/portal/broker/microsoft/endpoint
   https://dev.auth.hansacore.com/realms/portal/broker/microsoft/endpoint
   ```
3. *Token configuration* → *Add optional claim* → **ID** token: `email`,
   `xms_edov`, `given_name`, `family_name`. Accept the prompt to add the Microsoft
   Graph `email` permission.
4. *Manifest*: set `"authenticationBehaviors": { "removeUnverifiedEmailClaim": true }`.
5. *Certificates & secrets* → *New client secret*, description `hansacore-sit`.
   Copy the secret **Value** now (not the Secret ID).
6. From the *Overview* page copy the **Application (client) ID**.
7. Put both into `k8s/overlays/sit/secrets/keycloak-clients.env`:
   ```text
   MICROSOFT_CLIENT_ID=<application (client) ID>
   MICROSOFT_CLIENT_SECRET=<secret value>
   ```
   (`scripts/bootstrap-secrets.sh sit` creates the file with placeholders.)
8. Customers whose directory blocks user consent need their own admin to approve
   the app once:
   `https://login.microsoftonline.com/organizations/adminconsent?client_id=<MICROSOFT_CLIENT_ID>`

The old registration in Forty2's directory stays untouched until step 6 works;
afterwards its owner can delete it.

## 2. SMTP (needed by self-registration) — **you**

```bash
bash scripts/bootstrap-secrets.sh sit      # creates k8s/overlays/sit/secrets/keycloak-smtp.env if missing
```

Edit `k8s/overlays/sit/secrets/keycloak-smtp.env`: `SMTP_HOST`, `SMTP_PORT`
(587, STARTTLS), `SMTP_FROM`, `SMTP_USER`, `SMTP_PASSWORD`. Without a working
relay nobody can verify their email, so registration cannot finish. This has
nothing to do with Entra.

## 3. Deploy the code and reset the SIT database

```bash
bash scripts/manage-env.sh deploy sit          # pulls repos, builds images, renders realm, applies, restarts api/gateway/web
bash scripts/manage-env.sh build sit keycloak  # rebuilds the theme image and restarts Keycloak
```

**SIT status (checked 12 Oct 2026):** changelog 14 has never run there (no
`tenant_domain` or other onboarding tables, no `databasechangelog` row), so the
database reset below is **not needed on SIT**. The server also had no git clones
(the four repos had been copied by hand) and no `jq`; set both up first:
```bash
cd /root/hansacore
for r in hansacore-deployment hansacore-api hansacore-web hansacore-portal; do mv $r $r.old; done
git config --global credential.helper store
git clone https://github.com/Danielmethner/hansacore-deployment.git
git clone https://github.com/Danielmethner/hansacore-api.git
git clone https://github.com/Danielmethner/hansacore-web.git
git clone https://github.com/Danielmethner/hansacore-portal.git
# git-ignored files the server needs
cp -an hansacore-deployment.old/k8s/overlays/sit/secrets/. hansacore-deployment/k8s/overlays/sit/secrets/
cp -an hansacore-deployment.old/k8s/components/demo-data/demo-data.yml hansacore-deployment/k8s/components/demo-data/
cp -an hansacore-api.old/src/main/resources/vpn_templates hansacore-api/src/main/resources/
apt-get install -y jq
bash hansacore-deployment/scripts/bootstrap-secrets.sh sit   # adds the SMTP placeholder file
```

For UAT and PROD, or any environment where an older version of changelog 14 may
have run: the changelog (`14_tenant_domain_and_onboarding.xml`) was edited in
place before it had ever been deployed. Liquibase keeps a fingerprint of every
script it has run; if SIT already ran an older version the API refuses to start
(checksum error). SIT holds only test data, so the simplest fix is to wipe the
application database and let the API rebuild it. This does not touch Keycloak
(its own database), so logins and the realm survive.

```bash
bash scripts/manage-env.sh db-shell sit
\c hansacore
DROP SCHEMA hansacore CASCADE;
CREATE SCHEMA hansacore AUTHORIZATION hansacore_api;
GRANT ALL ON SCHEMA hansacore TO hansacore_api;
\q
kubectl rollout restart deploy/hansacore-api -n hansacore
kubectl logs deploy/hansacore-api -n hansacore --tail=50     # wait for a clean start
```

The API recreates all tables and demo data, including Forty2 and its tenants.
Only do this if the application data in SIT does not matter. If it does, check
first whether the old script ran: `SELECT id FROM databasechangelog WHERE
filename LIKE '%14_tenant_domain_and_onboarding%';` and if it did, drop only
`tenant_invite_code`, `tenant_join_request`, `tenant_idp_binding`, `tenant_domain`
and delete those `databasechangelog` rows before restarting the API.

## 4. Register Forty2 as a customer

Forty2's MASTER_CLIENT exists, but nothing says its Entra directory and domains
belong to it. Record that now, before anyone else can sign in. The directory ID is
Forty2's own (Entra admin center of **Forty2's** directory → Overview → *Tenant
ID*); it is not the HansaCore directory.

```bash
bash scripts/register-customer-directory.sh sit "Forty2" <forty2-entra-tenant-id> forty2.ch [more domains...]
```

The output lists the binding and the verified domains. Re-running changes
nothing. It stops if the directory or a domain belongs to another customer.

## 5. Apply the realm changes to the running Keycloak

```bash
bash scripts/apply-realm-sso-onboarding.sh sit
```

Applies, to the live realm: the new `MICROSOFT_CLIENT_ID` and secret, the
`/organizations/` endpoints of the `microsoft` provider, the mappers (`tid` →
`idp_directory_id`, `xms_edov` → `idp_domain_verified`, `email` → `idp_email`),
the gateway token mappers, self-registration with email verification, the password
policy, SMTP, the HansaCore theme, and it removes the auto-link flow. Safe to
re-run. It needs `jq`; the theme step needs the image from step 3.

## 6. Seed user, then smoke test

A running realm keeps the values it was first imported with. The seed user
`daniel.methner@forty2.ch` is still `emailVerified=false` there and the API
rejects it. In the Keycloak admin console: *Users* → `daniel.methner@forty2.ch`
→ switch **Email verified** on → *Save*. (`consultant@hansacore.com` is
already verified.) Operator accounts are created the same way, always with
**Email verified** on; see `README.md` §4.

| # | Action | Expected |
|---|--------|----------|
| 1 | Sign in with a Forty2 Entra work account | Recognised as Forty2. An existing user with the same email is linked; a new colleague lands in Forty2's quarantine and waits for approval |
| 2 | Register on the Keycloak page with a private address (e.g. outlook.com) | Verification email arrives; after verifying, `/onboarding` offers a personal workspace only |
| 3 | Log in locally without verifying the email | Rejected: "Email address is not verified" |
| 4 | `consultant@hansacore.com` logs in with username and password | Works as before, operator permissions intact |
| 5 | Sign in with a personal Microsoft account (outlook.com) through the Microsoft button | Rejected: "Personal Microsoft accounts are not supported" |
| 6 | Admin creates an invite code, a new user redeems it | Request appears in Access Requests |

With a second Microsoft work directory (a free Microsoft 365 developer tenant):

| # | Action | Expected |
|---|--------|----------|
| 7 | Sign in with a work account from that directory | `/onboarding` offers "Create your organisation" for its domain |
| 8 | Create the organisation | Tenant admin area shows the directory (Microsoft Entra ID) and the verified domain |
| 9 | A second user of that directory signs in | Recognised, in quarantine; the admin approves in Access Requests |
| 10 | Sign in with an Entra account whose email domain is `hansacore.com` | Cannot create an organisation or claim the domain |

Test 1 and 9 prove the Entra optional claims arrive. If a person whose domain is
verified still lands in `/onboarding`, check the token claims `idp_directory_id`,
`idp_email`, `idp_domain_verified` and `identity_provider`.

## 7. Rolling back

The API accepts old sessions unchanged. To undo the realm changes, reset the
Keycloak database and re-import (`README.md` §6); customer bindings and domains
live in the `hansacore` database and survive that. To fall back to the old Microsoft
app, remove `MICROSOFT_CLIENT_ID` from `keycloak-clients.env` and re-render.
