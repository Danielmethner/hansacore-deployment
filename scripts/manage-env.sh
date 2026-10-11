#!/bin/bash
# Operator CLI for the Hetzner k3s VMs. Run from Git Bash on Windows.
# Requires the hcloud CLI, an active context (hcloud context use hansacore),
# and the same SSH key Terraform uploaded.
#
#   scripts/manage-env.sh status <sit|uat|prod>
#   scripts/manage-env.sh deploy <sit|uat|prod>
#   scripts/manage-env.sh build <sit|uat|prod> [api|gateway|web]
#   scripts/manage-env.sh logs <sit|uat|prod> <api|gateway|web|keycloak|postgres|portal>
#   scripts/manage-env.sh db-shell <sit|uat|prod>
#
# deploy pulls the four repos, builds the :local images, renders the realm,
# applies the overlay, and restarts the app Deployments (the image tag does
# not change, so apply alone leaves the old container running).
set -euo pipefail

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
for key in "${SSH_KEY:-}" "$HOME/.ssh/wsldaniel" "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa"; do
  if [ -n "$key" ] && [ -f "$key" ]; then
    SSH_OPTS+=(-i "$key")
    break
  fi
done
NAMESPACE=hansacore

usage() {
  echo "Usage: scripts/manage-env.sh <status|deploy|build|logs|db-shell> <sit|uat|prod> [args]" >&2
  exit 1
}

need_hcloud() {
  if ! command -v hcloud >/dev/null 2>&1; then
    for candidate in \
      "/mnt/c/Users/DanielMethner/AppData/Local/Microsoft/WinGet/Packages/HetznerCloud.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe/hcloud.exe" \
      "/c/Users/DanielMethner/AppData/Local/Microsoft/WinGet/Packages/HetznerCloud.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe/hcloud.exe" \
      "${LOCALAPPDATA:-}/Microsoft/WinGet/Links/hcloud.exe" \
      "${LOCALAPPDATA:-}/Microsoft/WinGet/Packages/HetznerCloud.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe/hcloud.exe"; do
      if [ -n "$candidate" ] && [ -f "$candidate" ]; then
        PATH="$(dirname "$candidate"):$PATH"
        export PATH
        break
      fi
    done
  fi
  if ! command -v hcloud >/dev/null 2>&1; then
    echo "hcloud is not on PATH. Install it with: winget install HetznerCloud.CLI" >&2
    exit 1
  fi
}

server_name() {
  case "$1" in
    sit|uat|prod) printf 'hansacore-%s' "$1" ;;
    *)
      echo "Unknown environment '$1' (expected sit, uat, or prod)" >&2
      exit 1
      ;;
  esac
}

# hcloud server ssh appends arguments after the IP, so ssh options such as
# -t and BatchMode would be treated as the remote command. Take the address
# from hcloud and run OpenSSH with options in front of the host.
hcloud_ssh() {
  local server="$1"
  shift
  local -a opts=("${SSH_OPTS[@]}")
  while [ "${1:-}" != "${1#-}" ]; do
    opts+=("$1")
    shift
  done
  local ip
  ip="$(hcloud server ip "$server")"
  ssh "${opts[@]}" -l root "$ip" "$@"
}

workload() {
  case "$1" in
    api) echo deploy/hansacore-api ;;
    gateway) echo deploy/portal-gateway ;;
    web) echo deploy/hansacore-web ;;
    keycloak) echo deploy/keycloak ;;
    postgres) echo sts/postgres ;;
    portal) echo deploy/portal-placeholder ;;
    *)
      echo "Unknown service '$1' (expected api, gateway, web, keycloak, postgres, portal)" >&2
      exit 1
      ;;
  esac
}

remote_build_apply() {
  local server="$1"
  local overlay="$2"
  shift 2
  hcloud_ssh "$server" bash -s -- "$overlay" "$@" <<'EOF'
set -euo pipefail
overlay="$1"
shift
export KUBECONFIG=/root/.kube/config
code=/root/hansacore
if [ ! -d "$code/hansacore-deployment/.git" ]; then
  cat >&2 <<MSG
Repos are not on this server yet. SSH in and clone them once (the first
clone asks for your GitHub username and fine-grained token):

  git config --global credential.helper store
  mkdir -p /root/hansacore
  git clone https://github.com/Danielmethner/hansacore-deployment.git /root/hansacore/hansacore-deployment
  git clone https://github.com/Danielmethner/hansacore-api.git /root/hansacore/hansacore-api
  git clone https://github.com/Danielmethner/hansacore-web.git /root/hansacore/hansacore-web
  git clone https://github.com/Danielmethner/hansacore-portal.git /root/hansacore/hansacore-portal

Then copy demo-data.yml into
  /root/hansacore/hansacore-deployment/k8s/components/demo-data/
and run scripts/bootstrap-secrets.sh ${overlay} plus scripts/render-realm.sh ${overlay}
after putting MICROSOFT_CLIENT_SECRET in secrets/keycloak-clients.env.
MSG
  exit 1
fi
for repo in hansacore-deployment hansacore-api hansacore-web hansacore-portal; do
  echo "==> git pull $repo"
  git -C "$code/$repo" pull --ff-only
done
echo "==> build ${*:-all}"
bash "$code/hansacore-deployment/scripts/build-images.sh" "$@"
bash "$code/hansacore-deployment/scripts/render-realm.sh" "$overlay"
kubectl apply -k "$code/hansacore-deployment/k8s/overlays/$overlay"
if [ "$#" -eq 0 ]; then
  set -- api gateway web
fi
restarts=()
for target in "$@"; do
  case "$target" in
    api) restarts+=(deploy/hansacore-api) ;;
    gateway) restarts+=(deploy/portal-gateway) ;;
    web) restarts+=(deploy/hansacore-web) ;;
    *) echo "Unknown build target '$target'" >&2; exit 1 ;;
  esac
done
kubectl -n hansacore rollout restart "${restarts[@]}"
kubectl -n hansacore get pods
EOF
}

[ "$#" -ge 2 ] || usage
cmd="$1"
env_name="$2"
shift 2
need_hcloud
server="$(server_name "$env_name")"

case "$cmd" in
  status)
    hcloud server describe "$server"
    hcloud_ssh "$server" kubectl get nodes -o wide
    hcloud_ssh "$server" kubectl get pods -n "$NAMESPACE" -o wide
    hcloud_ssh "$server" kubectl get ingress -n "$NAMESPACE"
    ;;
  deploy)
    remote_build_apply "$server" "$env_name"
    ;;
  build)
    remote_build_apply "$server" "$env_name" "$@"
    ;;
  logs)
    [ "$#" -eq 1 ] || usage
    target="$(workload "$1")"
    hcloud_ssh "$server" kubectl logs -n "$NAMESPACE" "$target" --tail=100 -f
    ;;
  db-shell)
    hcloud_ssh "$server" -t kubectl exec -it -n "$NAMESPACE" sts/postgres -- psql -U postgres
    ;;
  *)
    usage
    ;;
esac
