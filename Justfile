# HomeLab task runner.
# Run `just` (no args) to list targets.
# Each target should be idempotent and safe to re-run.

set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false

cluster_name := env_var_or_default("KIND_CLUSTER_NAME", "homelab")
argocd_ns    := "argocd"

# Default target — list available recipes.
default:
    @just --list --unsorted

# --- Setup ---

# Install pinned toolchain via mise.
install-tools:
    mise install
    pre-commit install

# Run all pre-commit hooks across the repo.
lint:
    pre-commit run --all-files

# --- Cluster lifecycle ---

# Full bootstrap: kind + Cilium + ArgoCD + root App-of-Apps. Interactive prompts.
bootstrap:
    bash scripts/bootstrap.sh

# Create kind cluster (no CNI).
kind-up:
    kind create cluster --config platform/bootstrap/kind-cluster.yaml --name {{cluster_name}}

# Delete kind cluster. Destructive — confirms first.
kind-down:
    @read -r -p "Delete kind cluster '{{cluster_name}}'? [y/N] " ans && [[ "$ans" == "y" ]] || exit 1
    kind delete cluster --name {{cluster_name}}

# Show kind cluster status.
kind-status:
    kind get clusters
    kubectl --context kind-{{cluster_name}} get nodes -o wide

# --- ArgoCD helpers ---

# Port-forward ArgoCD UI to https://localhost:8080
argocd-ui:
    kubectl -n {{argocd_ns}} port-forward svc/argocd-server 8080:443

# Print initial admin password.
argocd-pwd:
    kubectl -n {{argocd_ns}} get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d
    @echo

# Apply (or update) the root App-of-Apps. Idempotent.
argocd-root-apply:
    kubectl apply -f platform/gitops/root-app.yaml

# --- Vault helpers ---

vault_ns := "vault"
vault_pod := "vault-0"

# Initialize Vault — run once after first ArgoCD sync. SAVE the output.
vault-init:
    kubectl exec -n {{vault_ns}} {{vault_pod}} -- \
        vault operator init -key-shares=3 -key-threshold=2

# Unseal Vault — run after every pod restart. Prompts for keys inside the container.
vault-unseal:
    @echo "=== Unseal key 1 of 2 ==="
    kubectl exec -it -n {{vault_ns}} {{vault_pod}} -- vault operator unseal
    @echo "=== Unseal key 2 of 2 ==="
    kubectl exec -it -n {{vault_ns}} {{vault_pod}} -- vault operator unseal

# Show Vault seal/init status.
vault-status:
    kubectl exec -n {{vault_ns}} {{vault_pod}} -- vault status 2>&1 || true

# Configure Vault for ESO: KV v2 + kubernetes auth + policy (run once after init).
# Passes VAULT_TOKEN as env var — all commands run in a single exec session.
vault-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    printf "Enter Vault root token (hvs.xxx from vault-init output): "
    read -r ROOT_TOKEN
    echo ""

    kubectl exec -i -n {{vault_ns}} {{vault_pod}} \
        -- env VAULT_TOKEN="$ROOT_TOKEN" sh << 'EOF'
set -e

echo "--- Enabling KV v2 at secret/ ---"
vault secrets enable -path=secret kv-v2 2>/dev/null && echo "enabled" || echo "already enabled"

echo "--- Enabling kubernetes auth ---"
vault auth enable kubernetes 2>/dev/null && echo "enabled" || echo "already enabled"

echo "--- Configuring kubernetes auth ---"
vault write auth/kubernetes/config \
    kubernetes_host="https://kubernetes.default.svc:443"

echo "--- Creating ESO read policy ---"
vault policy write eso-policy - << 'POLICY'
path "secret/data/homelab/*" { capabilities = ["read"] }
path "secret/metadata/homelab/*" { capabilities = ["list", "read"] }
POLICY

echo "--- Creating ESO role bound to external-secrets ServiceAccount ---"
vault write auth/kubernetes/role/eso-role \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=eso-policy \
    ttl=1h

echo ""
echo "Vault configured. ClusterSecretStore will connect automatically via ArgoCD."
EOF

# Write a secret to Vault KV (interactive). Usage: just vault-put path/to/key
vault-put key:
    @echo "Enter value for secret/homelab/{{key}}:"
    @read -rs VAL; \
    kubectl exec -n {{vault_ns}} {{vault_pod}} -- \
        vault kv put "secret/homelab/{{key}}" value="$$VAL"

# Read a secret from Vault KV. Usage: just vault-get path/to/key
vault-get key:
    kubectl exec -n {{vault_ns}} {{vault_pod}} -- \
        vault kv get "secret/homelab/{{key}}"

# --- Observability helpers ---

# Port-forward Grafana to http://localhost:3000
grafana-ui:
    kubectl -n observability port-forward svc/grafana 3000:80

# --- Misc ---

# Show memory pressure on Mac + cluster nodes.
mem:
    @echo "--- macOS ---"
    @vm_stat | head -20
    @echo
    @echo "--- Cluster nodes ---"
    @kubectl top nodes 2>/dev/null || echo "metrics-server not yet installed"
