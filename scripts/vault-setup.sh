#!/usr/bin/env bash
# scripts/vault-setup.sh
# Configure Vault for ESO: KV v2 + kubernetes auth method + ESO policy/role.
# Run once after vault operator init + unseal.
# Usage: bash scripts/vault-setup.sh [namespace] [pod]

set -euo pipefail

VAULT_NS="${1:-vault}"
VAULT_POD="${2:-vault-0}"

printf "Enter Vault root token (hvs.xxx from vault-init output): "
read -r ROOT_TOKEN
echo ""

echo "Configuring Vault in pod ${VAULT_NS}/${VAULT_POD}..."

kubectl exec -i -n "$VAULT_NS" "$VAULT_POD" \
  -- env VAULT_TOKEN="$ROOT_TOKEN" sh -s << 'SCRIPT'
set -e

echo "--- Enabling KV v2 at secret/ ---"
vault secrets enable -path=secret kv-v2 2>/dev/null \
  && echo "  enabled" || echo "  already enabled"

echo "--- Enabling kubernetes auth ---"
vault auth enable kubernetes 2>/dev/null \
  && echo "  enabled" || echo "  already enabled"

echo "--- Configuring kubernetes auth ---"
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"
echo "  done"

echo "--- Creating ESO read policy ---"
vault policy write eso-policy - <<'POLICY'
path "secret/data/homelab/*"     { capabilities = ["read"] }
path "secret/metadata/homelab/*" { capabilities = ["list", "read"] }
POLICY
echo "  done"

echo "--- Creating ESO role ---"
vault write auth/kubernetes/role/eso-role \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso-policy \
  ttl=1h
echo "  done"

echo ""
echo "Vault configured successfully."
echo "ClusterSecretStore will connect automatically via ArgoCD (wave 2)."
SCRIPT
