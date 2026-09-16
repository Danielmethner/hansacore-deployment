# HansaCore Deployment (`hansacore-deployment`)

Infrastructure-as-Code and Kubernetes manifests for deploying the **HansaCore** platform on a single-node **k3s Kubernetes cluster**.

This deployment setup is designed for:
1. **Local Development / Simulation**: Running inside an Ubuntu 24.04 VM via **Canonical Multipass** on Windows 11 Hyper-V.
2. **Cloud Target (GCP ACE Exam)**: Deployable directly to a single-node **Google Cloud Compute Engine VM** running k3s.

---

## 1. System Architecture

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
         │ /                 │ /login, /oauth2,   │ /realms, /js,     │ /admin (separate
         │                   │ /api, /be          │ /resources        │ Ingress + BasicAuth)
         ▼                   ▼                    ▼                   ▼
 ┌──────────────┐    ┌────────────────┐   ┌───────────────┐   ┌───────────────┐
 │hansacore-web │    │ portal-gateway │   │   keycloak    │   │   keycloak    │
 │ (Angular 20) │    │  (Spring BFF)  │   │  (Keycloak 24)│   │ admin console │
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
| **`postgres`** | PostgreSQL 16 Alpine | `5432` | Dual database instance (`tradingintf` and `keycloak`) with persistent storage |
| **`keycloak`** | Keycloak 24.0 (`start`, not `start-dev`) | `8080` | Identity and Access Management with Microsoft Entra ID OIDC identity broker |
| **`hansacore-api`** | Spring Boot 3.4 / Java 21 | `8081` | Core trading and backoffice REST API resource server |
| **`portal-gateway`** | Spring Cloud Gateway / BFF | `8080` | Secure session gateway, OAuth2 token relay, and reverse proxy |
| **`hansacore-web`** | Angular 20 SPA / Nginx | `80` | Frontend web interface |
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
│   │   ├── 06-ingress.yaml             # everything except /admin; forces HTTPS
│   │   ├── 07-ingress-admin.yaml       # /admin only, + BasicAuth middleware
│   │   ├── 08-middlewares.yaml         # Traefik: HTTPS redirect, BasicAuth, HSTS
│   │   └── 09-networkpolicies.yaml     # default-deny + explicit pod-to-pod allows
│   └── overlays/
│       ├── local-vm/                   # Multipass VM target
│       │   ├── kustomization.yaml
│       │   ├── hansacore-env.properties    # the ONE file with this env's hostname
│       │   └── secrets/*.env.example       # templates; real .env files are git-ignored
│       └── gcp/                        # GCP VM target (fill in hostname before use)
│           └── ... (same shape as local-vm)
├── identity/
│   └── portal-realm.template.json      # Keycloak realm export, WITH PLACEHOLDERS
│                                        # (__BASE_URL__, __*_CLIENT_SECRET__, ...)
├── scripts/
│   ├── bootstrap-secrets.sh            # generates git-ignored secret files per overlay
│   └── render-realm.sh                 # renders the realm template -> per-overlay ConfigMap
├── ssl/                                 # TLS Certificate & Java Truststore automation
│   ├── generate-certs.sh
│   ├── cert.conf
│   └── csr.conf
├── .gitignore
└── README.md
```

**Nothing in `k8s/base/` hardcodes a secret, IP, or hostname.** Everything
environment-specific lives in exactly one place per environment:
`k8s/overlays/<env>/hansacore-env.properties` (hostname/CORS/issuer) and
`k8s/overlays/<env>/secrets/*.env` (passwords/client secrets, git-ignored).
That's what makes the local Multipass VM and the future GCP VM both usable
from the same base manifests.

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

3. **Generate TLS certificates & Java truststore:**
   ```bash
   bash ssl/generate-certs.sh
   ```
   This automatically:
   - Detects the active VM IP.
   - Generates the Root CA and a server certificate with SANs (`IP:<ip>`, `DNS:k3s-lab.mshome.net`, `DNS:localhost`).
   - Exports the Root CA into a Java PKCS12 truststore (`truststore.p12`), protected by a randomly generated password (not the well-known "changeit" default).
   - Creates the `hansacore-tls` and `hansacore-ca-trust` Kubernetes secrets in namespace `hansacore`.

4. **Apply everything** via Kustomize:
   ```bash
   kubectl apply -k k8s/overlays/local-vm
   ```
   This replaces the old "apply each file in order" workflow — Kustomize
   handles namespace, generated ConfigMaps/Secrets, and ordering.

5. **Verify all pods are running:**
   ```bash
   kubectl get pods -n hansacore
   ```

6. **Browse to `https://k3s-lab.mshome.net`** (prefer the stable hostname
   over the raw VM IP — the IP is DHCP-assigned and can change on VM
   restart, the hostname doesn't). Log in with one of the seeded users
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
3. Under **Authentication** $\rightarrow$ **Redirect URIs**, add:
   ```text
   https://<VM-IP-or-hostname>/realms/portal/broker/microsoft/endpoint
   ```
   *(Prefer `https://k3s-lab.mshome.net/realms/portal/broker/microsoft/endpoint`, since it's stable across VM restarts.)*

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

1. Provision the GCP Compute Engine VM and point a real DNS name at its
   static external IP (don't rely on the raw IP the way the original setup
   did — it made every re-IP a multi-file hand-edit).
2. Fill in `k8s/overlays/gcp/hansacore-env.properties` with that hostname,
   and the `tls.hosts` patches in `k8s/overlays/gcp/kustomization.yaml`.
3. `scripts/bootstrap-secrets.sh gcp` (generates a **separate** set of
   secrets — never reuse the local-vm ones in a semi-public environment).
4. `scripts/render-realm.sh gcp`.
5. Re-run `ssl/generate-certs.sh` against the GCP VM, or better: switch to
   cert-manager + Let's Encrypt now that there's a real, publicly resolvable
   domain (see `Architecture/security_review_and_remediation_plan.md`,
   Phase 4).
6. `kubectl apply -k k8s/overlays/gcp`.

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

### Checking Health & Logs
```bash
# Gateway health
curl -k -I https://k3s-lab.mshome.net/actuator/health

# Keycloak OIDC Discovery
curl -k https://k3s-lab.mshome.net/realms/portal/.well-known/openid-configuration

# Service logs
kubectl logs -n hansacore deploy/portal-gateway --tail=50 -f
kubectl logs -n hansacore deploy/hansacore-api --tail=50 -f
```

### Security notes
See `Architecture/security_review_and_remediation_plan.md` in the main
workspace for the full findings/remediation plan this restructuring
implements (secrets management, the Keycloak `hansacore-api` client fix,
NetworkPolicies, ingress hardening, etc.) and what's still outstanding
(git history scrubbing for the secrets that were previously committed, and
GCP-specific hardening like cert-manager and Cloud SQL).
