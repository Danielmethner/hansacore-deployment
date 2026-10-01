#!/bin/bash
# Prepares a fresh GCP VM (created by infra/envs/<env>) for HansaCore:
# Docker, k3s, kubectl config, the Postgres data disk, the four repos and a
# pinned cert-manager. Idempotent: every step checks before it acts, so it is
# safe to re-run after a failure.
#
# Run ON THE VM as your normal user (not root). The repos are not cloned yet
# on a fresh VM, so copy this file over first (README §7):
#   gcloud compute scp scripts/bootstrap-vm.sh hansacore-uat-vm:~ --project=hansacore-uat --zone=europe-west6-a --tunnel-through-iap
#   bash ~/bootstrap-vm.sh
# The first `git clone` asks for your GitHub username and the fine-grained
# token; the credential helper stores it for the other repos and later pulls.
set -euo pipefail

GITHUB_OWNER="${GITHUB_OWNER:-Danielmethner}"
REPOS=(hansacore-deployment hansacore-api hansacore-web hansacore-portal)
CODE_DIR="${CODE_DIR:-$HOME/hansacore}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.2}"
K3S_CHANNEL="${K3S_CHANNEL:-stable}"
DATA_DISK="/dev/disk/by-id/google-postgres-data"
DATA_MOUNT="/mnt/disks/postgres-data"

step() { printf '\n==> %s\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Run as your normal user, not root; the script uses sudo where needed." >&2
  exit 1
fi

step "Base packages"
sudo apt-get update -qq
sudo apt-get install -y -qq git curl ca-certificates

step "Swap space (4GB)"
if [ ! -f /swapfile ]; then
  sudo fallocate -l 4G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
  fi
  echo "Swap configured: $(free -h | grep -i swap)"
else
  echo "Swap file already exists"
fi

step "Docker"
if command -v docker >/dev/null 2>&1; then
  echo "already installed: $(docker --version)"
else
  sudo apt-get install -y -qq docker.io
  sudo systemctl enable --now docker
fi

step "k3s ($K3S_CHANNEL channel)"
if command -v k3s >/dev/null 2>&1; then
  echo "already installed: $(k3s --version | head -1)"
else
  curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL="$K3S_CHANNEL" sh -
fi

step "kubectl config for $USER"
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
# k3s' kubectl otherwise reads the root-only /etc/rancher/k3s/k3s.yaml.
grep -q 'KUBECONFIG=' "$HOME/.bashrc" || echo 'export KUBECONFIG=$HOME/.kube/config' >> "$HOME/.bashrc"
export KUBECONFIG="$HOME/.kube/config"

echo "waiting for the node to register..."
until kubectl get nodes -o name 2>/dev/null | grep -q node/; do sleep 5; done
kubectl wait --for=condition=Ready node --all --timeout=300s

step "Postgres data disk"
if [ ! -e "$DATA_DISK" ]; then
  echo "$DATA_DISK not found. Is the data disk attached with device name 'postgres-data'?" >&2
  exit 1
fi
if sudo blkid "$DATA_DISK" >/dev/null 2>&1; then
  echo "already has a filesystem, not formatting"
else
  sudo mkfs.ext4 -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard "$DATA_DISK"
fi
sudo mkdir -p "$DATA_MOUNT"
DISK_UUID="$(sudo blkid -s UUID -o value "$DATA_DISK")"
if grep -q "UUID=$DISK_UUID" /etc/fstab; then
  echo "fstab entry exists"
else
  # nofail: a missing disk must not block the boot. Check the mount after
  # every restart instead (README §5).
  echo "UUID=$DISK_UUID $DATA_MOUNT ext4 discard,defaults,nofail 0 2" | sudo tee -a /etc/fstab >/dev/null
fi
sudo systemctl daemon-reload
sudo mount -a
if ! findmnt "$DATA_MOUNT" >/dev/null; then
  echo "$DATA_MOUNT is not mounted." >&2
  exit 1
fi
findmnt "$DATA_MOUNT"

step "Repositories under $CODE_DIR"
git config --global credential.helper store
mkdir -p "$CODE_DIR"
for repo in "${REPOS[@]}"; do
  if [ -d "$CODE_DIR/$repo/.git" ]; then
    echo "$repo: already cloned"
  else
    git clone "https://github.com/$GITHUB_OWNER/$repo.git" "$CODE_DIR/$repo"
  fi
done

step "cert-manager $CERT_MANAGER_VERSION"
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.yaml"
for d in cert-manager cert-manager-cainjector cert-manager-webhook; do
  kubectl -n cert-manager rollout status "deploy/$d" --timeout=300s
done

cat <<EOF

Done. Next (README §7):
  source ~/.bashrc
  cd $CODE_DIR/hansacore-deployment
  scripts/bootstrap-secrets.sh <overlay>
EOF
