# 6. Secrets management: HashiCorp Vault + External Secrets Operator

Date: 2026-05-02

## Status

Accepted

## Context

Platform components need secrets: Dex OAuth client secrets, database passwords,
ArgoCD repo credentials, API keys. Options considered:

1. **Sealed Secrets** — kubeseal encrypts k8s Secrets with cluster public key.
   Encrypted SealedSecret YAML committed to git. Simple, no external dependency.
   Low learning value; rotation is manual; tight cluster coupling.

2. **External Secrets Operator + HashiCorp Vault (self-hosted)** — industry gold
   standard. Vault stores secrets centrally; ESO syncs them into k8s Secrets.
   Full control, offline-capable, high learning value, audit log. ~256 MiB RSS.

3. **External Secrets Operator + 1Password Connect** — requires paid 1Password
   Teams/Business plan. Ruled out for cost.

4. **External Secrets Operator + Bitwarden Secrets Manager** — newer product,
   less battle-tested ESO integration. Ruled out for stability reasons.

Learning goals of this homelab include understanding enterprise secret management
patterns. Vault is the reference implementation used at most serious tech companies.
The RAM cost (~256 MiB) is accepted as a learning investment.

## Decision

Deploy **HashiCorp Vault** (self-hosted, in-cluster) with **Raft integrated storage**,
managed by **External Secrets Operator** as the bridge to Kubernetes Secrets.

### Vault configuration

- **Mode:** server (not dev — dev mode loses data on restart)
- **Storage:** Raft (integrated, no external database)
- **Replicas:** 1 (HA is overkill for a single-node-effective lab)
- **Auto-unseal:** none — manual unseal after cluster restart (see below)
- **Namespace:** `vault`

### Unsealing strategy

Vault seals itself on every restart (pod restart, cluster rebuild). This is a
deliberate security feature — the encryption key is never stored on disk.

For this homelab: **manual unseal**, intentionally simple.

Procedure (after cluster start or Vault pod restart):
```bash
kubectl exec -n vault vault-0 -- vault operator unseal <key1>
kubectl exec -n vault vault-0 -- vault operator unseal <key2>
kubectl exec -n vault vault-0 -- vault operator unseal <key3>
```

Unseal keys and root token storage: **outside the repo**. Options:
- macOS Notes (encrypted, synced via iCloud)
- Any local password manager
- A physical piece of paper (not a joke — this is how enterprises store root keys)

Never commit unseal keys to git. Never store them in Kubernetes Secrets.

### ESO configuration

External Secrets Operator deployed via ArgoCD Application (namespace: `external-secrets`).
A `ClusterSecretStore` resource points to Vault's KV v2 engine.
ESO authenticates to Vault via Kubernetes auth method (pod ServiceAccount token).

```
Vault (KV v2 engine) ← ClusterSecretStore (ESO) ← ExternalSecret CRDs ← k8s Secrets
```

### Secret path convention in Vault

```
secret/homelab/platform/<service>/<key>
# examples:
secret/homelab/platform/dex/github-client-secret
secret/homelab/platform/grafana/admin-password
secret/homelab/platform/cnpg/postgres-password
```

## Consequences

- All secrets managed centrally in Vault — single place to rotate, audit, view.
- `ExternalSecret` CRDs are safe to commit to git (they contain paths, not values).
- Manual unseal on restart is the main operational burden. Acceptable for a homelab
  where kind is not always running. Document in `just vault-unseal` target.
- If Vault is down, ESO cannot create new Secrets (but existing Secrets in cluster
  remain until deleted). Plan: Vault is in wave 1, comes up before workloads.
- Bootstrap requires a manual `vault operator init` + `vault operator unseal` sequence
  on first install. Document fully in `platform/vault/README.md`.
- Future: if manual unseal becomes annoying, can add Transit auto-unseal (second
  Vault instance — academic exercise) or file-based unseal sidecar.
- Sealed Secrets not needed — skip entirely in favour of this approach.
