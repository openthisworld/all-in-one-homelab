# HomeLab task runner.
set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false

cluster_name  := env_var_or_default("KIND_CLUSTER_NAME", "homelab")
argocd_ns      := "argocd"
argocd_chart   := "7.7.14"

default:
    @just --list --unsorted

# --- Setup ---
install-tools:
    mise install
    pre-commit install

lint:
    pre-commit run --all-files

# --- Cluster lifecycle ---
bootstrap:
    bash scripts/bootstrap.sh

kind-up:
    kind create cluster --config platform/bootstrap/kind-cluster.yaml --name {{cluster_name}}

kind-down:
    @read -r -p "Delete kind cluster '{{cluster_name}}'? [y/N] " ans && [[ "$ans" == "y" ]] || exit 1
    kind delete cluster --name {{cluster_name}}

kind-status:
    kind get clusters
    kubectl --context kind-{{cluster_name}} get nodes -o wide

# --- ArgoCD helpers ---
argocd-ui:
    kubectl -n {{argocd_ns}} port-forward svc/argocd-server 8080:80

argocd-pwd:
    kubectl -n {{argocd_ns}} get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d
    @echo

argocd-root-apply:
    kubectl apply -f platform/gitops/root-app.yaml

argocd-bootstrap:
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update argo
    helm install argocd argo/argo-cd \
        --namespace {{argocd_ns}} \
        --create-namespace \
        --version {{argocd_chart}} \
        --values platform/platform-services/argocd/values.yaml \
        --wait

argocd-upgrade:
    helm upgrade argocd argo/argo-cd \
        --namespace {{argocd_ns}} \
        --version {{argocd_chart}} \
        --values platform/platform-services/argocd/values.yaml \
        --wait

# --- CoreDNS ---
coredns-patch:
    bash scripts/coredns-homelab-patch.sh

# --- Vault helpers ---
vault_ns  := "vault"
vault_pod := "vault-0"

vault-init:
    kubectl exec -n {{vault_ns}} {{vault_pod}} -- \
        vault operator init -key-shares=3 -key-threshold=2

vault-unseal:
    @echo "=== Unseal key 1 of 2 ==="
    kubectl exec -it -n {{vault_ns}} {{vault_pod}} -- vault operator unseal
    @echo "=== Unseal key 2 of 2 ==="
    kubectl exec -it -n {{vault_ns}} {{vault_pod}} -- vault operator unseal

vault-status:
    kubectl exec -n {{vault_ns}} {{vault_pod}} -- vault status 2>&1 || true

vault-setup:
    bash scripts/vault-setup.sh {{vault_ns}} {{vault_pod}}

vault-seed:
    bash scripts/vault-seed.sh

vault-setup-oidc:
    bash scripts/vault-setup-oidc.sh {{vault_ns}} {{vault_pod}}

vault-put key:
    @echo "Enter value for secret/homelab/{{key}}:"
    @read -rs VAL; \
    kubectl exec -n {{vault_ns}} {{vault_pod}} -- \
        vault kv put "secret/homelab/{{key}}" value="$$VAL"

# --- Misc ---
mem:
    @echo "--- macOS ---"
    @vm_stat | head -20
    @echo ""
    @echo "--- Cluster nodes ---"
    @kubectl top nodes 2>/dev/null || echo "metrics-server not yet installed"

# --- Cilium ---
cilium_version := "1.16.5"

cilium-install:
    helm repo add cilium https://helm.cilium.io
    helm repo update cilium
    helm install cilium cilium/cilium \
        --version {{cilium_version}} \
        --namespace kube-system \
        --values platform/platform-services/cilium/values.yaml \
        --wait
    kubectl wait --for=condition=Ready nodes --all --timeout=300s

cilium-uninstall:
    helm uninstall cilium -n kube-system

# --- Debug & Testing ---
# Перевірка резолвінгу доменів всередині кластера
dns-test:
    kubectl run -it --rm dns-test --image=busybox --restart=Never -- \
        nslookup dex.homelab.local

# Слідкувати за станом ArgoCD застосунків
watch-apps:
    kubectl get applications -n {{argocd_ns}} --watch

# Перегляд логів Cilium (корисно при дебазі лаби)
cilium-logs:
    kubectl logs -n kube-system -l k8s-app=cilium
