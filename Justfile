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

# Configure ArgoCD OIDC via Dex (run once after Dex is Healthy + secrets synced).
# Prereq: ExternalSecret argocd-dex-client must be SecretSynced in namespace argocd.
argocd-oidc-setup:
    @echo "Patching argocd-cm with Dex OIDC config..."
    kubectl patch configmap argocd-cm -n {{argocd_ns}} --type merge -p \
        '{"data":{"url":"http://argocd.homelab.local","oidc.config":"name: Dex\nissuer: http://dex.homelab.local\nclientID: argocd\nclientSecret: $argocd-dex-client:clientSecret\nrequestedScopes:\n  - openid\n  - profile\n  - email\n  - groups\n"}}'
    @echo "Patching argocd-rbac-cm — granting openthisworld admin role..."
    kubectl patch configmap argocd-rbac-cm -n {{argocd_ns}} --type merge -p \
        '{"data":{"policy.csv":"g, openthisworld, role:admin\n","policy.default":"role:readonly"}}'
    @echo "Restarting argocd-server..."
    kubectl rollout restart deployment argocd-server -n {{argocd_ns}}
    kubectl rollout status deployment argocd-server -n {{argocd_ns}} --timeout=60s
    @echo "Done. Open http://argocd.homelab.local and click 'Log in via Dex'."

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
vault-setup:
    bash scripts/vault-setup.sh {{vault_ns}} {{vault_pod}}

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
