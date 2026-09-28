#!/bin/bash
# Install the k3s node-IP guard into this VM (LOCAL MULTIPASS DEV CLUSTER ONLY).
# Run with sudo from the repo mount inside the VM:
#   sudo bash /home/ubuntu/hansacore/hansacore-deployment/vm/node-ip-guard/install.sh
set -euo pipefail
if [ "$(id -u)" != "0" ]; then echo "run with sudo" >&2; exit 1; fi
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SRC/k3s-node-ip-guard.sh" /usr/local/bin/k3s-node-ip-guard.sh
chmod 755 /usr/local/bin/k3s-node-ip-guard.sh
cp "$SRC/k3s-node-ip-guard.service" /etc/systemd/system/
cp "$SRC/k3s-node-ip-guard.timer" /etc/systemd/system/
chmod 644 /etc/systemd/system/k3s-node-ip-guard.*
mkdir -p /var/lib/k3s-node-ip-guard
systemctl daemon-reload
systemctl enable k3s-node-ip-guard.service k3s-node-ip-guard.timer
systemctl start k3s-node-ip-guard.timer
echo "installed. timer status:"
systemctl list-timers k3s-node-ip-guard.timer --no-pager
echo "dry-run check:"
/usr/local/bin/k3s-node-ip-guard.sh --dry-run
