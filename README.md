# HansaCore Deployment (`hansacore-deployment`)

Infrastructure-as-Code and Kubernetes manifests for deploying the **HansaCore** platform on a single-node **k3s Kubernetes cluster**.

This deployment setup is designed for:
1. **Local Development / Simulation**: Running inside an Ubuntu 24.04 VM via **Canonical Multipass** on Windows 11 Hyper-V.
2. **Cloud Target (GCP ACE Exam)**: Deployable directly to a single-node **Google Cloud Compute Engine VM** running k3s.

---

## 1. System Architecture

### Hostnames

Pattern: `<env>.<app>.hansacore.com`; production has no environment label.

| Environment | Portal | ERP (`hansacore-web`) | Keycloak |
| :--- | :--- | :--- | :--- |
| PROD | `hansacore.com` | `erp.hansacore.com` | `auth.hansacore.com` |
| UAT | `uat.hansacore.com` | `uat.erp.hansacore.com` | `uat.auth.hansacore.com` |
| SIT (GCP, `overlays/gcp`) | `sit.hansacore.com` | `sit.erp.hansacore.com` | `sit.auth.hansacore.com` |
| DEV (Multipass, `overlays/local-vm`) | `dev.hansacore.com` | `dev.erp.hansacore.com` | `dev.auth.hansacore.com` |

One login for all app hosts: each app host has its own host-only gateway
session (`PORTAL_SESSION`), and single sign-on between them comes from
Keycloak's session on the auth host — opening the portal after logging in to
the ERP bounces through Keycloak once, without a password prompt. Future
portal sub-apps go under the portal host as subpaths.

```text
                                       Internet / Host Browser
                                                  │
                                                  ▼
                               ┌─────────────────────────────────────┐
                               │       Traefik Ingress (k3s)         │
                               │  Port 80 (HTTP, redirected) / 443   │
                               └──────────────────┬──────────────────┘
                                                  │
         ┌───────────────────┬────────────────────┼───────────────────┐
         │ ERP host: /       │ ERP + portal host: │ auth host:        │ auth host: /admin
         │ portal host: /    │ /oauth2, /logout,  │ /realms, /js,     │ (separate Ingress
         │ (placeholder)     │ /login/oauth2,     │ /resources        │  + BasicAuth)
         │                   │ /api, /be          │                   │
         ▼                   ▼                    ▼                   ▼
 ┌──────────────┐    ┌────────────────┐   ┌───────────────┐   ┌───────────────┐
 │hansacore-web │    │ portal-gateway │   │   keycloak    │   │   keycloak    │
 │portal-placeh.│    │  (Spring BFF)  │   │  (Keycloak 24)│   │ admin console │
 │   Port 80    │    │   Port 8080    │   │   Port 8080   │   └───────────────┘
 └──────────────┘    └───────┬────────┘   └───────┬───────┘
                             │                    │
                             ▼                    │
                     ┌────────────────┐           │
                     │ hansacore-api  │           │
                     │ (Spring Boot)  │           │
                     │   Port 8081    │           │
                     └───────┬────────┘           │
                             │                    │
                             └──────────┬─────────┘
                                        ▼
                              ┌──────────────────┐          ┌───────────────────┐
                              │     postgres     │          │  Microsoft Entra  │
                              │  (Postgres 16)   │          │ (Azure AD OAuth2) │
                              │    Port 5432     │          └───────────────────┘
                              └──────────────────┘
```

### Components

| Service | Technology | Port | Purpose |
| :--- | :--- | :--- | :--- |
| **`postgres`** | PostgreSQL 16 Alpine | `5432` | Dual database instance (`hansacore` and `keycloak`) with persistent storage |
| **`keycloak`** | Keycloak 24.0 (`start`, not `start-dev`) | `8080` | Identity and Access Management with Microsoft Entra ID OIDC identity broker |
| **`hansacore-api`** | Spring Boot 3.4 / Java 21 | `8081` | Core trading and backoffice REST API resource server |
| **`portal-gateway`** | Spring Cloud Gateway / BFF | `8080` | Secure session gateway, OAuth2 token relay, and reverse proxy |
| **`hansacore-web`** | Angular 20 SPA / Nginx | `80` | ERP frontend, on the ERP host |
| **`portal-placeholder`** | Nginx + static page (ConfigMap) | `80` | Stand-in for the portal frontend on the portal host; shows the sign-in state |
| **`traefik`** | Traefik Ingress Controller | `80 / 443` | Reverse proxy, TLS termination, HTTPS redirect, admin BasicAuth |

---

## 2. Repository Structure

```text
hansacore-deployment/
├── k8s/
│   ├── base/                           # Environment-agnostic manifests (no
│   │   │                               # secrets, no hardcoded hostnames/IPs)
│   │   ├── kustomization.yaml
│   │   ├── 00-namespace.yaml
│   │   ├── 01-postgres.yaml            # PVC, Deployment, Service (init.sh reads
│   │   │                               # DB passwords from env, not baked in)
│   │   ├── 02-keycloak.yaml            # `start` (not `start-dev`), hostname from
│   │   │                               # hansacore-env ConfigMap, admin pw from Secret
│   │   ├── 03-hansacore-api.yaml
│   │   ├── 04-portal-gateway.yaml
│   │   ├── 05-hansacore-web.yaml
│   │   ├── 06-ingress-erp.yaml         # ERP host: SPA + gateway paths; forces HTTPS
│   │   ├── 06-ingress-portal.yaml      # portal host: placeholder + gateway paths
│   │   ├── 06-ingress-auth.yaml        # auth host: Keycloak OIDC endpoints
│   │   ├── 07-ingress-admin.yaml       # auth host /admin only, + BasicAuth middleware
│   │   ├── 08-middlewares.yaml         # Traefik: HTTPS redirect, BasicAuth, HSTS
│   │   ├── 09-networkpolicies.yaml     # default-deny + explicit pod-to-pod allows
│   │   ├── 10-ingress-http-redirect.yaml
│   │   └── 11-portal-placeholder.yaml  # stand-in portal page (nginx + ConfigMap)
│   ├── components/
│   │   └── demo-data/                  # demo tenants/users for the API (both overlays)
│   │       ├── kustomization.yaml          # ConfigMap generator + api mount/import
│   │       └── demo-data.yml               # git-ignored (real names/emails)
│   └── overlays/
│       ├── local-vm/                   # DEV: Multipass VM target
│       │   ├── kustomization.yaml          # Ingress host patches, api profile `dev`
│       │   ├── dev-ca-trust.patch.yaml     # DEV-only CA truststore for api + gateway
│       │   ├── hansacore-env.properties    # this env's hostnames / issuer / CORS
│       │   └── secrets/*.env.example       # templates; real .env files are git-ignored
│       └── gcp/                        # SIT: GCP VM target
│           └── ... (same shape as local-vm; api profile `sit`, no truststore)
├── identity/
│   └── portal-realm.template.json      # Keycloak realm export, WITH PLACEHOLDERS
│                                        # (__ERP_BASE_URL__, __PORTAL_BASE_URL__,
│                                        #  __*_CLIENT_SECRET__, ...)
├── scripts/
│   ├── bootstrap-secrets.sh            # generates git-ignored secret files per overlay
│   ├── render-realm.sh                 # renders the realm template -> per-overlay ConfigMap
│   └── build-images.sh                 # builds the :local images inside the VM
├── ssl/                                 # TLS Certificate & Java Truststore automation
│   └── generate-certs.sh               # DEV only; reuses the CA, certs for the dev.* hosts
├── vm/                                  # LOCAL MULTIPASS DEV CLUSTER ONLY
│   ├── coredns-custom.yaml             # pods resolve the dev.* names to Traefik
│   ├── update-hosts.ps1                # Windows hosts file entries for the dev.* names
│   └── node-ip-guard/                  # heals k3s + CoreDNS after VM IP changes
├── .gitignore
└── README.md
```

**Nothing in `k8s/base/` hardcodes a secret, IP, or hostname.** Everything
environment-specific lives in exactly one place per environment:
`k8s/overlays/<env>/hansacore-env.properties` (hostnames/CORS/issuer, plus
the matching Ingress host patches in that overlay's `kustomization.yaml`) and
`k8s/overlays/<env>/secrets/*.env` (passwords/client secrets, git-ignored).
That's what makes the local Multipass VM and the future GCP VM both usable
from the same base manifests.

### API profiles, truststore and demo data

The same `hansacore-api` image runs everywhere; the overlay decides how.

| | DEV (`local-vm`) | SIT (`gcp`) |
| :--- | :--- | :--- |
| `SPRING_PROFILES_ACTIVE` (api only) | `dev` (smoke tests run) | `sit` (Swagger off) |
| Custom CA truststore | yes, `dev-ca-trust.patch.yaml` | no, JVM default (public certs) |
| Demo tenants/users | `components/demo-data` | `components/demo-data` |
| `HANSACORE_DEMODATA_ENABLED` | `true` | `true` (for now) |

- **No hidden default profile.** `application.properties` doesn't set one, so
  the profile always comes from the overlay (or `-Dspring-boot.run.profiles=dev`
  / the IDE run configuration locally). It is patched onto the api
  Deployment only, not into `hansacore-env`, because the gateway reads that
  ConfigMap too.
- **No dev credentials in the image.** `hansacore-api/.dockerignore` keeps
  the git-ignored `application-dev.properties` (and `-local`, `-forty2`,
  `vpn_templates/`, `demo-data-local.yml`) out of the build context. In the
  cluster, datasource, issuer and CORS always come from env.
- **Truststore is DEV-only.** `ssl/generate-certs.sh` creates the
  `hansacore-ca-trust` Secret; only the local-vm overlay mounts it and sets
  `JAVA_TOOL_OPTIONS`. Heap flags live in `JDK_JAVA_OPTIONS` in base, so
  they're kept on both environments.
- **Seeding switch.** On a fresh database the API always creates the system
  users and roles, plus reference data (currencies, countries, DAX40). With
  `HANSACORE_DEMODATA_ENABLED=true` it also seeds the tenants/users from
  `demo-data.yml` and sample content. The first start records
  `DEMO_DATA_CREATED` either way, so **changing the switch later has no
  effect** until the `hansacore` database is recreated.
- **`demo-data.yml` is git-ignored** (real names and emails). Copy it into
  `k8s/components/demo-data/` on every machine that renders an overlay,
  otherwise `kubectl apply -k` fails.

---

## 3. Quick Start (Local k3s / Multipass)

### Prerequisites
- Canonical Multipass installed on Windows (`multipass`)
- Hyper-V enabled (`Microsoft-Hyper-V`)
- An Ubuntu 24.04 VM (`k3s-lab`) with k3s installed
- `kubectl` and a bash shell (Git Bash on Windows is fine) on your host
- `openssl` on your host (Git Bash ships one)

### Deployment Steps

1. **Generate secrets** (one-time; safe to re-run, never overwrites existing files):
   ```bash
   scripts/bootstrap-secrets.sh local-vm
   ```
   This writes git-ignored files under `k8s/overlays/local-vm/secrets/` (DB
   passwords, Keycloak admin password, OAuth2 client secrets, the seeded
   demo users' bootstrap password, and an htpasswd file for the `/admin`
   BasicAuth prompt). **Save the printed BasicAuth password** — it's not
   stored anywhere else.

2. **Render the Keycloak realm import** for this overlay (must be re-run any
   time `identity/portal-realm.template.json` or the overlay's hostname/
   secrets change):
   ```bash
   scripts/render-realm.sh local-vm
   ```

3. **Generate TLS certificates & Java truststore** (inside the VM):
   ```bash
   sudo bash /home/ubuntu/hansacore/hansacore-deployment/ssl/generate-certs.sh
   ```
   This automatically:
   - Creates the Root CA on the first run and reuses it afterwards (delete `ssl/ca.key`/`ssl/ca.crt` to force a new one).
   - Issues a server certificate for the three hostnames in `k8s/overlays/local-vm/hansacore-env.properties` (plus `localhost` and the VM IP).
   - Exports the Root CA into a Java PKCS12 truststore (`truststore.p12`), protected by a randomly generated password (not the well-known "changeit" default); only rebuilt when the CA changes.
   - Creates the `hansacore-tls` and `hansacore-ca-trust` Kubernetes secrets in namespace `hansacore`.

   **Name resolution for the `dev.*` hostnames** (they are not in public DNS):
   ```bash
   # pods (gateway/API -> Keycloak): answer the names with Traefik's ClusterIP
   kubectl apply -f vm/coredns-custom.yaml
   kubectl -n kube-system rollout restart deploy/coredns
   ```
   ```powershell
   # Windows browser: elevated PowerShell, re-run after every VM IP change
   .\vm\update-hosts.ps1
   ```

4. **Build the images and import them into k3s** (inside the VM, from the
   repo mount; re-run for a component whenever its code changes):
   ```bash
   bash /home/ubuntu/hansacore/hansacore-deployment/scripts/build-images.sh [api|gateway|web ...]
   ```

5. **Apply everything** via Kustomize:
   ```bash
   kubectl apply -k k8s/overlays/local-vm
   ```
   This replaces the old "apply each file in order" workflow — Kustomize
   handles namespace, generated ConfigMaps/Secrets, and ordering.

6. **Verify all pods are running:**
   ```bash
   kubectl get pods -n hansacore
   ```

7. **Browse to `https://dev.erp.hansacore.com`** (ERP) or
   `https://dev.hansacore.com` (portal placeholder). Log in with one of the seeded users
   (`consultant`, `daniel.methner@forty2.ch`, `milad.g@forty2.ch`,
   `technical_user@hansacore.com`) using the `SEED_USER_PASSWORD` value from
   `k8s/overlays/local-vm/secrets/seed-users.env` — you'll be prompted to
   set a real password on first login (`temporary: true` on those
   credentials forces this).

### Rotating a secret

Delete the specific file under `k8s/overlays/local-vm/secrets/`, re-run
`scripts/bootstrap-secrets.sh local-vm` (only regenerates what's missing),
then `scripts/render-realm.sh local-vm` and `kubectl apply -k
k8s/overlays/local-vm` again. For Postgres/Keycloak-admin passwords that
already exist in the running database, you'll also need to `ALTER USER ...
PASSWORD ...` / update the admin password via `kcadm` — changing the Secret
alone doesn't retroactively change a password already set inside Postgres
or Keycloak's own DB.

---

## 4. Microsoft Entra ID (Azure AD) SSO Integration

Azure AD strictly enforces that all non-localhost redirect URIs must begin with `https://`.

### Azure Portal Configuration
1. Go to [Microsoft Entra Admin Center](https://entra.microsoft.com/) $\rightarrow$ **App registrations**.
2. Select Application ID: `74741127-2028-4328-a8cf-057363b92b42`.
3. Under **Authentication** $\rightarrow$ **Redirect URIs**, add one per environment's auth host:
   ```text
   https://dev.auth.hansacore.com/realms/portal/broker/microsoft/endpoint
   https://sit.auth.hansacore.com/realms/portal/broker/microsoft/endpoint
   ```
   The DEV name does not need to be publicly resolvable — the redirect happens in the browser.

### Entra Client Secret
Under **Certificates & secrets** → **New client secret**, create a secret and copy its
**Value** (not the Secret ID) into the overlay's git-ignored secrets file:
```text
k8s/overlays/<env>/secrets/keycloak-clients.env  →  MICROSOFT_CLIENT_SECRET=<value>
```
Then re-render (`scripts/render-realm.sh <env>`). Note: realm import runs once on an
empty database, so re-rendering only covers fresh installs — for a running cluster,
also update the live `microsoft` identity provider via the Keycloak Admin API (or
reset the keycloak database per §6 to force a re-import).

### Local Windows Trust (Green Padlock)
To trust the local Certificate Authority on your Windows host:
```powershell
Import-Certificate -FilePath "ssl\ca.crt" -CertStoreLocation "Cert:\CurrentUser\Root"
```

---

## 5. GCP Lift

The first GCP environment is SIT; `k8s/overlays/gcp` already carries its
hostnames (`sit.hansacore.com`, `sit.erp.hansacore.com`, `sit.auth.hansacore.com`).

1. Provision the GCP Compute Engine VM and point public DNS records for all
   three SIT hostnames at its static external IP.
2. `scripts/bootstrap-secrets.sh gcp` (generates a **separate** set of
   secrets — never reuse the local-vm ones in a semi-public environment).
3. `scripts/render-realm.sh gcp`.
4. TLS: use cert-manager + Let's Encrypt (the SIT names are publicly
   resolvable) instead of `ssl/generate-certs.sh`, which is DEV-only. The
   gcp overlay has no custom truststore, so the Java services rely on the
   public certificate chain.
5. Add the SIT broker redirect URI in Entra (§4).
6. Copy `demo-data.yml` into `k8s/components/demo-data/` (see §2), and
   decide `HANSACORE_DEMODATA_ENABLED` before the first start.
7. `kubectl apply -k k8s/overlays/gcp`.

---

## 6. Maintenance & Troubleshooting

### Reset Keycloak Database & Re-import Realm
If `identity/portal-realm.template.json` is updated:
```bash
# 1. Re-render the ConfigMap for your overlay
scripts/render-realm.sh local-vm

# 2. Reset keycloak database in postgres
kubectl exec -n hansacore deploy/postgres -- psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'keycloak' AND pid <> pg_backend_pid();"
kubectl exec -n hansacore deploy/postgres -- psql -U postgres -c "DROP DATABASE IF EXISTS keycloak;"
kubectl exec -n hansacore deploy/postgres -- psql -U postgres -c "CREATE DATABASE keycloak OWNER keycloak;"

# 3. Re-apply and restart
kubectl apply -k k8s/overlays/local-vm
kubectl rollout restart deploy/keycloak -n hansacore
```

### VM IP Changes (Host Sleep / Reboot / Network Switch)

The Multipass VM gets its IP via DHCP from Hyper-V's Default Switch, which
Windows recreates whenever the host sleeps, reboots, or changes networks —
the VM IP *will* change regularly (several times observed within two days).
k3s pins the node IP at startup, so after a renumber the cluster keeps
serving the stale address: pod DNS/egress breaks or crawls, and
server-to-server calls (notably Keycloak → Microsoft during SSO) time out
with generic error pages. Inside the cluster the `dev.*` names resolve to
Traefik's ClusterIP (`vm/coredns-custom.yaml`), so they are unaffected; on
Windows re-run `vm/update-hosts.ps1` (elevated) so the browser follows the
new IP.

Fast diagnosis — these two must agree:
```bash
multipass info k3s-lab          # real VM IP
kubectl get nodes -o wide       # INTERNAL-IP as k3s sees it
```

Recovery is one command (also re-establishes the repo file mount if it died):
```bash
multipass restart k3s-lab
```

Without a VM restart, recover in place — both steps are needed, because the
CoreDNS pod keeps forwarding to the old Hyper-V DNS server it copied at start:
```bash
sudo systemctl restart k3s
kubectl rollout restart deploy/coredns -n kube-system
```

A `k3s-node-ip-guard` systemd timer installed in the VM (see
`vm/node-ip-guard/`, LOCAL DEV CLUSTER ONLY — staging/production use static
IPs where renumbering cannot happen) performs this check automatically and,
on confirmed persistent drift, restarts k3s and then CoreDNS. Install it with
`sudo bash /home/ubuntu/hansacore/hansacore-deployment/vm/node-ip-guard/install.sh`. Inspect with
`journalctl -u k3s-node-ip-guard.service` and dry-run with
`sudo /usr/local/bin/k3s-node-ip-guard.sh --dry-run`.

### Checking Health & Logs
```bash
# Gateway health (actuator is not exposed on the public ingress)
kubectl exec -n hansacore deploy/portal-gateway -- wget -qO- http://localhost:8080/actuator/health

# Keycloak OIDC Discovery
curl -k https://dev.auth.hansacore.com/realms/portal/.well-known/openid-configuration

# Service logs
kubectl logs -n hansacore deploy/portal-gateway --tail=50 -f
kubectl logs -n hansacore deploy/hansacore-api --tail=50 -f
```

### Changing hostnames on a running cluster
The realm import only runs on an empty Keycloak database, so after changing
hostnames also update the live `portal-gateway` client (redirect URIs, web
origins, `post.logout.redirect.uris`) with `kcadm.sh` inside the Keycloak pod,
and delete Ingress objects that no longer exist in `k8s/base` —
`kubectl apply -k` does not remove them.

### Security notes
Still outstanding: git history scrubbing (and rotation) for the secrets that
were previously committed, and GCP-specific hardening like cert-manager.
The `hansacore-api` image no longer contains dev credentials (§2).
