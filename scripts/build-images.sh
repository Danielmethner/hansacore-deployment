#!/bin/bash
# Builds the HansaCore :local images and imports them into k3s' containerd,
# which is where the Deployments (imagePullPolicy: IfNotPresent) look for them.
# Run INSIDE the Multipass VM from the repo mount, e.g.:
#   bash /home/ubuntu/hansacore/hansacore-deployment/scripts/build-images.sh [api|gateway|web ...]
# No arguments builds all three. Afterwards restart the affected Deployments:
#   sudo kubectl rollout restart deploy/<name> -n hansacore
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd)"

declare -A CONTEXTS=(
  [api]="$ROOT/hansacore-api"
  [gateway]="$ROOT/hansacore-portal/gateway"
  [web]="$ROOT/hansacore-web"
)
declare -A IMAGES=(
  [api]="hansacore-api:local"
  [gateway]="portal-gateway:local"
  [web]="hansacore-web:local"
)

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=(api gateway web)
fi

for target in "${TARGETS[@]}"; do
  context="${CONTEXTS[$target]:-}"
  image="${IMAGES[$target]:-}"
  if [ -z "$context" ]; then
    echo "Unknown target '$target' (expected: api, gateway, web)" >&2
    exit 1
  fi
  echo "==> Building $image from $context"
  sudo docker build -t "$image" "$context"
  echo "==> Importing $image into k3s containerd"
  sudo docker save "$image" | sudo k3s ctr images import -
done

echo "Done. Imported: ${TARGETS[*]}"
