#!/usr/bin/env bash
# scripts/vault-seed.sh
# Write all platform secrets to Vault from a local .vault-secrets.env file.
#
# Run after: vault-init + vault-unseal + vault-setup (repeat on every cluster rebuild
# because kind deletes the Vault PVC when the cluster is destroyed).
#
# Usage: bash scripts/vault-seed.sh [path/to/secrets.env]
# Default env file: .vault-secrets.env  (gitignored)
# Template:         .vault-secrets.env.example

set -euo pipefail

SECRETS_FILE="${1:-.vault-secrets.env}"
VAULT_NS="${VAULT_NS:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"

if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "ERROR: $SECRETS_FILE not found."
  echo "Copy .vault-secrets.env.example → .vault-secrets.env and fill in real values."
  exit 1
fi

# shellcheck source=.vault-secrets.env.example
# shellcheck disable=SC1090
source "$SECRETS_FILE"

: "${VAULT_ROOT_TOKEN:?VAULT_ROOT_TOKEN must be set in $SECRETS_FILE}"
: "${DEX_GITHUB_CLIENT_ID:?DEX_GITHUB_CLIENT_ID must be set}"
: "${DEX_GITHUB_CLIENT_SECRET:?DEX_GITHUB_CLIENT_SECRET must be set}"
: "${DEX_ARGOCD_CLIENT_SECRET:?DEX_ARGOCD_CLIENT_SECRET must be set}"
: "${DEX_VAULT_CLIENT_SECRET:?DEX_VAULT_CLIENT_SECRET must be set}"

echo "Seeding secrets into Vault (${VAULT_NS}/${VAULT_POD})..."

kubectl exec -i -n "$VAULT_NS" "$VAULT_POD" \
  -- env \
    VAULT_TOKEN="$VAULT_ROOT_TOKEN" \
    DEX_GITHUB_CLIENT_ID="$DEX_GITHUB_CLIENT_ID" \
    DEX_GITHUB_CLIENT_SECRET="$DEX_GITHUB_CLIENT_SECRET" \
    DEX_ARGOCD_CLIENT_SECRET="$DEX_ARGOCD_CLIENT_SECRET" \
    DEX_VAULT_CLIENT_SECRET="$DEX_VAULT_CLIENT_SECRET" \
  sh -s << 'SCRIPT'
set -e

echo "--- secret/homelab/platform/dex/github (GitHub OAuth App) ---"
vault kv put secret/homelab/platform/dex/github \
  client_id="$DEX_GITHUB_CLIENT_ID" \
  client_secret="$DEX_GITHUB_CLIENT_SECRET"
echo "  done"

echo "--- secret/homelab/platform/dex/argocd (ArgoCD OIDC client) ---"
vault kv put secret/homelab/platform/dex/argocd \
  client_secret="$DEX_ARGOCD_CLIENT_SECRET"
echo "  done"

echo "--- secret/homelab/platform/dex/vault (Vault OIDC client) ---"
vault kv put secret/homelab/platform/dex/vault \
  client_secret="$DEX_VAULT_CLIENT_SECRET"
echo "  done"

echo ""
echo "All secrets seeded. ESO will sync them to k8s Secrets within ~60s."
SCRIPT
