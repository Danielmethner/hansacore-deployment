#!/bin/bash
# k3s-node-ip-guard: heal a single-node k3s cluster after the VM's IP changes
# (Multipass/Hyper-V DHCP renumbering on host sleep, reboot, or network switch).
#
# Compares the VM's primary outbound IP against the k3s node InternalIP. On a
# confirmed, persistent mismatch it restarts k3s so the node re-converges
# (flannel, kube-proxy, klipper LB), then restarts CoreDNS. Does nothing otherwise.
#
# The CoreDNS restart is required: its pod copies the node's resolv.conf at
# creation, so after a renumber it keeps forwarding to the old Hyper-V DNS
# server and all pod DNS times out even once k3s itself has re-converged.
#
# Safety: acts only when BOTH sides are readable, the mismatch persists across
# checks CONFIRM_AFTER_SEC apart, and no restart happened within COOLDOWN_SEC.
# Scoped to single-node clusters; refuses to act on multi-node ones.
#
# LOCAL MULTIPASS DEV CLUSTER ONLY. Staging/production use static IPs where
# renumbering cannot happen; do not install this there.
#
# Usage: k3s-node-ip-guard.sh [--dry-run]   (root; uses k3s kubeconfig)
# Testing: FAKE_VM_IP / FAKE_NODE_IP override discovery (use with --dry-run).
set -euo pipefail

CONFIRM_AFTER_SEC=60
COOLDOWN_SEC=900
API_READY_TIMEOUT_SEC=120
STATE_DIR=/var/lib/k3s-node-ip-guard
MISMATCH_FILE="$STATE_DIR/mismatch"   # "VM_IP NODE_IP FIRST_SEEN_EPOCH"
RESTART_FILE="$STATE_DIR/last-restart" # epoch
KUBECTL=${KUBECTL:-kubectl}
KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; fi

log() { echo "k3s-node-ip-guard: $*"; logger -t k3s-node-ip-guard "$*"; }
die() { log "ERROR: $*"; exit 1; }

vm_ip() {
  if [ -n "${FAKE_VM_IP:-}" ]; then echo "$FAKE_VM_IP"; return; fi
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}'
}

node_ip() {
  if [ -n "${FAKE_NODE_IP:-}" ]; then echo "$FAKE_NODE_IP"; return; fi
  export KUBECONFIG
  local out
  out=$($KUBECTL get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null) || return 1
  [ "$(printf '%s' "$out" | grep -c .)" = "1" ] || return 1
  printf '%s' "$out"
}

mkdir -p "$STATE_DIR"
VM_IP=$(vm_ip) || die "cannot determine VM primary IP"
NODE_IP=$(node_ip) || { log "cannot read node IP (kubectl/API unavailable or not single-node); doing nothing"; exit 0; }
NOW=$(date +%s)

if [ "$VM_IP" = "$NODE_IP" ]; then
  rm -f "$MISMATCH_FILE"
  log "OK: VM IP ($VM_IP) matches k3s node IP; no action"
  exit 0
fi

# Mismatch: confirm persistence before acting.
FIRST_SEEN=""
if [ -f "$MISMATCH_FILE" ]; then
  read -r OLD_VM OLD_NODE FIRST_SEEN < "$MISMATCH_FILE" || true
  if [ "${OLD_VM:-}" != "$VM_IP" ] || [ "${OLD_NODE:-}" != "$NODE_IP" ]; then
    FIRST_SEEN="" # different mismatch than last time: restart confirmation
  fi
fi
if [ -z "${FIRST_SEEN:-}" ]; then
  echo "$VM_IP $NODE_IP $NOW" > "$MISMATCH_FILE"
  log "MISMATCH (first sighting): VM=$VM_IP node=$NODE_IP; will act only if still mismatched in ${CONFIRM_AFTER_SEC}s"
  exit 0
fi
AGE=$((NOW - FIRST_SEEN))
if [ "$AGE" -lt "$CONFIRM_AFTER_SEC" ]; then
  log "MISMATCH (unconfirmed, ${AGE}s < ${CONFIRM_AFTER_SEC}s): VM=$VM_IP node=$NODE_IP; waiting"
  exit 0
fi
if [ -f "$RESTART_FILE" ]; then
  LAST=$(cat "$RESTART_FILE")
  if [ $((NOW - LAST)) -lt "$COOLDOWN_SEC" ]; then
    log "MISMATCH persists but cooldown active (last restart $((NOW - LAST))s ago); not restarting"
    exit 0
  fi
fi

log "MISMATCH confirmed (${AGE}s): VM=$VM_IP node=$NODE_IP"
if [ "$DRY_RUN" = "1" ]; then
  log "DRY-RUN: would restart k3s now; no action taken"
  exit 0
fi
log "restarting k3s to re-converge on $VM_IP"
date +%s > "$RESTART_FILE"
rm -f "$MISMATCH_FILE"
systemctl restart k3s

export KUBECONFIG
log "waiting up to ${API_READY_TIMEOUT_SEC}s for the API server"
DEADLINE=$(( $(date +%s) + API_READY_TIMEOUT_SEC ))
until $KUBECTL get --raw /readyz >/dev/null 2>&1; do
  [ "$(date +%s)" -lt "$DEADLINE" ] || die "API server not ready after ${API_READY_TIMEOUT_SEC}s; CoreDNS NOT restarted"
  sleep 5
done

log "restarting CoreDNS so it picks up the new upstream DNS server"
$KUBECTL -n kube-system rollout restart deploy/coredns
$KUBECTL -n kube-system rollout status deploy/coredns --timeout=120s \
  || die "CoreDNS rollout did not finish within 120s"
log "recovery complete: node on $VM_IP, CoreDNS restarted"
