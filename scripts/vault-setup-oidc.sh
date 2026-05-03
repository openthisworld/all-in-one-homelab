#!/usr/bin/env bash
# scripts/vault-setup-oidc.sh
# Configure Vault OIDC auth method with Dex as the identity provider.
# After this, log in to http://vault.homelab.local → select OIDC → GitHub.
#
# Prerequisites (in order):
#   1. vault-setup    — kubernetes auth + ESO policy configured
#   2. vault-seed     — secret/homelab/platform/dex/vault seeded
#   3. Dex is Healthy — ArgoCD shows dex Application as Healthy
#   4. CoreDNS patch  — just coredns-patch (so Vault pod can reach dex.homelab.local)
#
# Usage: bash scripts/vault-setup-oidc.sh [namespace] [pod]

set -euo pipefail

VAULT_NS="${1:-vault}"
VAULT_POD="${2:-vault-0}"

printf "Enter Vault root token: "
read -rs ROOT_TOKEN
echo ""

echo "Reading vault OIDC client secret from Vault..."
VAULT_CLIENT_SECRET=$(kubectl exec -n "$VAULT_NS" "$VAULT_POD" -- \
  env VAULT_TOKEN="$ROOT_TOKEN" \
  vault kv get -field=client_secret secret/homelab/platform/dex/vault)

echo "Configuring Vault OIDC auth in pod ${VAULT_NS}/${VAULT_POD}..."

kubectl exec -i -n "$VAULT_NS" "$VAULT_POD" \
  -- env VAULT_TOKEN="$ROOT_TOKEN" VAULT_CLIENT_SECRET="$VAULT_CLIENT_SECRET" sh -s << 'SCRIPT'
set -e

echo "--- Creating admin policy ---"
vault policy write admin - << 'POLICY'
# Full access — homelab admin only.
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
POLICY
echo "  done"

echo "--- Enabling OIDC auth method ---"
vault auth enable oidc 2>/dev/null \
  && echo "  enabled" || echo "  already enabled"

echo "--- Configuring OIDC (Dex issuer) ---"
vault write auth/oidc/config \
  oidc_discovery_url="http://dex.homelab.local" \
  oidc_client_id="vault" \
  oidc_client_secret="$VAULT_CLIENT_SECRET" \
  default_role="admin"
echo "  done"

echo "--- Creating admin OIDC role ---"
vault write auth/oidc/role/admin - << 'ROLE'
{
  "bound_audiences": ["vault"],
  "user_claim": "preferred_username",
  "policies": ["admin"],
  "ttl": "8h",
  "allowed_redirect_uris": [
    "http://vault.homelab.local/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}
ROLE
echo "  done"

echo ""
echo "Vault OIDC configured."
echo "Open http://vault.homelab.local → Method: OIDC → Sign in with Dex → GitHub."
SCRIPT
