# Vault operations runbook

## First-time initialization (run once after first ArgoCD sync)

```bash
just vault-init
```

This generates 3 unseal keys (2 required to unseal) and a root token.
**Save the output somewhere secure outside the repo** — macOS Notes, Apple Keychain,
or any password manager. If you lose these keys and the PVC is deleted, all secrets
are gone permanently.

Then unseal:
```bash
just vault-unseal
# Enter key 1 when prompted, then key 2
```

Check status:
```bash
just vault-status
# Initialized: true, Sealed: false → ready
```

## Configure Vault for ESO (run once after init)

```bash
just vault-setup
```

What this does step by step:
1. Logs in as root (prompts for root token)
2. Enables KV v2 secret engine at `secret/`
3. Enables Kubernetes auth method
4. Configures Kubernetes auth to use the cluster's API
5. Creates `eso-policy` — read-only access to `secret/homelab/*`
6. Creates `eso-role` bound to the ESO ServiceAccount

After this, apply the ClusterSecretStore:
```bash
kubectl apply -f platform/platform-services/external-secrets/cluster-secret-store.yaml
```

## After every cluster restart (Vault seals on pod restart)

```bash
just vault-status   # confirm: Sealed: true
just vault-unseal   # enter 2 unseal keys
just vault-status   # confirm: Sealed: false
```

Vault PVC survives cluster delete+create only if the underlying PV data is preserved.
With kind + local-path provisioner: **PVC data is lost when the kind cluster is deleted**.
This means after `kind delete cluster` + `kind create cluster`:
1. Install Vault via ArgoCD sync
2. `just vault-init` again (new keys, new root token)
3. `just vault-unseal`
4. `just vault-setup`
5. Re-populate secrets (they were in the old PVC)

This is the main operational cost of self-hosted Vault on a non-persistent cluster.
Future improvement: mount a hostPath volume outside of kind's lifecycle.

## Writing secrets to Vault

```bash
# Generic pattern
vault kv put secret/homelab/platform/<service>/<key> value="<secret>"

# Examples:
vault kv put secret/homelab/platform/dex/github-client-secret value="ghp_..."
vault kv put secret/homelab/platform/grafana/admin-password value="..."

# Read back
vault kv get secret/homelab/platform/dex/github-client-secret
```

## Vault UI

Open http://vault.homelab.local — log in with root token or a token with UI access.

## Emergency: Vault pod crashed, can't unseal via just vault-unseal

If the pod is not Running:
```bash
kubectl get pod -n vault vault-0
kubectl logs -n vault vault-0 --previous

# Force restart
kubectl delete pod -n vault vault-0
# Wait for it to come back, then unseal
just vault-unseal
```
