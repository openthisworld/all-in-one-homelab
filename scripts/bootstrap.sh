#!/usr/bin/env bash
# scripts/bootstrap.sh
# One-shot bring-up of the HomeLab platform: kind -> Cilium -> ArgoCD -> root App.
# Idempotent: each step checks for existing state before acting.
# Run from the repo root: bash scripts/bootstrap.sh

set -euo pipefail

# --- Constants ---
CLUSTER_NAME="${KIND_CLUSTER_NAME:-homelab}"
KIND_CONFIG="platform/bootstrap/kind-cluster.yaml"
CILIUM_VERSION="1.16.5"
CILIUM_VALUES="platform/bootstrap/cilium-values.yaml"
ARGOCD_VERSION="v2.13.3"
ARGOCD_NS="argocd"
ROOT_APP_MANIFEST="platform/gitops/root-app.yaml"

# --- Pretty output ---
log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

confirm() {
  local prompt="${1:-Continue?}"
  read -r -p "$prompt [y/N] " ans
  [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]]
}

# --- Steps ---

check_prereqs() {
  log "TODO: check prerequisites"
  # Intent:
  #   - Verify required tools exist: docker, kind, kubectl, helm, cilium-cli (optional), yq.
  #   - Verify Docker Desktop is running and has >=8 GiB allocated.
  #   - Verify no port conflicts on 80/443/8080.
  #   - Verify ~/.kube/config is writable (or KUBECONFIG points somewhere we can write).
  #   - Verify root-app.yaml's repoURL is no longer the REPLACE_ME placeholder.
  local missing=0
  for cmd in docker kind kubectl helm yq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      err "missing required command: $cmd"
      missing=1
    fi
  done
  if (( missing )); then
    err "install missing tools (try: mise install) and re-run"
    exit 1
  fi
  log "prereqs OK (placeholder — not all checks implemented yet)"
}

create_cluster() {
  log "TODO: create kind cluster"
  # Intent:
  #   - If kind cluster '$CLUSTER_NAME' exists, ask whether to reuse or recreate.
  #   - Otherwise: kind create cluster --config $KIND_CONFIG --name $CLUSTER_NAME
  #   - Wait until API server responds (kubectl cluster-info).
  #   - Note: nodes will be NotReady until Cilium is installed — expected.
  if kind get clusters | grep -qx "$CLUSTER_NAME"; then
    warn "cluster '$CLUSTER_NAME' already exists — reusing (TODO: prompt)"
    return 0
  fi
  warn "(would run) kind create cluster --config $KIND_CONFIG --name $CLUSTER_NAME"
}

install_cilium() {
  log "TODO: install Cilium $CILIUM_VERSION"
  # Intent:
  #   - helm repo add cilium https://helm.cilium.io && helm repo update
  #   - helm upgrade --install cilium cilium/cilium --version $CILIUM_VERSION \
  #       --namespace kube-system --values $CILIUM_VALUES --wait
  #   - kubectl wait --for=condition=Ready nodes --all --timeout=300s
  #   - cilium status --wait (if cilium-cli installed)
  warn "(would install Cilium with values from $CILIUM_VALUES)"
}

install_argocd() {
  log "TODO: install ArgoCD $ARGOCD_VERSION"
  # Intent:
  #   - kubectl apply -f platform/bootstrap/argocd-install.yaml  (creates namespace)
  #   - kubectl apply -n $ARGOCD_NS \
  #       -f https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml
  #   - kubectl wait --for=condition=Available deployment --all -n $ARGOCD_NS --timeout=300s
  #   - Print initial admin password (just argocd-pwd).
  warn "(would install ArgoCD $ARGOCD_VERSION)"
}

apply_root_app() {
  log "TODO: apply root App-of-Apps"
  # Intent:
  #   - Verify $ROOT_APP_MANIFEST has a real repoURL (not REPLACE_ME).
  #   - kubectl apply -f $ROOT_APP_MANIFEST
  #   - Wait until the root Application reports Synced + Healthy.
  if grep -q REPLACE_ME "$ROOT_APP_MANIFEST"; then
    err "$ROOT_APP_MANIFEST still contains REPLACE_ME — set repoURL before applying"
    exit 1
  fi
  warn "(would apply $ROOT_APP_MANIFEST)"
}

print_next_steps() {
  cat <<'EOF'

------------------------------------------------------------
HomeLab bootstrap complete (placeholder run).

Next steps:
  just argocd-ui            # port-forward ArgoCD UI to https://localhost:8080
  just argocd-pwd           # print initial admin password
  kubectl get applications -n argocd

Add components by dropping new Application manifests in:
  platform/gitops/applications/
ArgoCD will reconcile them on the next refresh cycle.
------------------------------------------------------------
EOF
}

main() {
  log "starting bootstrap (cluster=$CLUSTER_NAME)"
  check_prereqs
  create_cluster
  install_cilium
  install_argocd
  apply_root_app
  print_next_steps
}

main "$@"
