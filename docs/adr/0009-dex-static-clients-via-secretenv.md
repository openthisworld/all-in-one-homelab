# 9. Dex OAuth2 clients via staticClients + secretEnv

Date: 2026-05-05

## Status

Accepted. Amends ADR-0007.

## Context

ADR-0007 chose Dex as the OIDC provider. The original implementation tried to
keep `client_secret` plaintext out of git by:

1. Defining each OAuth2 client as a `dex.coreos.com/v1` `OAuth2Client` CRD
   manifest in `platform/platform-services/dex/manifests/oauth2clients.yaml`,
   with a bcrypt `secretHash` field.
2. Storing the matching plaintext in Vault, synced to the relying party
   (ArgoCD, Vault) via ESO.

It did not work. Login to ArgoCD failed with:

```
dex level=ERROR msg="failed to parse authorization request"
err="Invalid client_id (\"argocd\")."
```

Two bugs in the OAuth2Client manifest:

- **Schema misuse.** Dex's kubernetes storage CRDs are flat — `id`, `secret`,
  `name`, `redirectURIs` live at the resource root next to `metadata`, not
  under a `spec:` block. We wrote them under `spec:`, so Dex deserialised
  every client as having empty `id` and silently could not match the incoming
  `client_id=argocd`.
- **Wrong field.** The CRD storage backend uses a plaintext `secret` field.
  The bcrypt `secretHash` shape is a feature of the `staticClients`
  config-file path, not of CRD storage. Even after fixing the `spec:` wrapper,
  the bcrypt hash would have been ignored and `secret` would have been empty.

A separate, earlier comment in the values file claimed "$VAR expansion does not
work in `staticClients`". That is true for the generic `secret: $FOO` form, but
Dex provides a dedicated `secretEnv` field on each static client that explicitly
reads from a named environment variable. This field has been in Dex since
v2.27.0 (2020) and is the documented way to inject client secrets from outside
the config file.

## Decision

Define Dex OAuth2 clients as `staticClients` entries in
`platform/platform-services/dex/values.yaml`, using `secretEnv` to point at
environment variables provided by the `dex-secrets` ExternalSecret:

```yaml
config:
  staticClients:
    - id: argocd
      name: ArgoCD
      secretEnv: ARGOCD_CLIENT_SECRET
      redirectURIs:
        - http://argocd.homelab.local/auth/callback
        - https://argocd.homelab.local/auth/callback
    - id: vault
      name: Vault
      secretEnv: VAULT_CLIENT_SECRET
      redirectURIs:
        - http://vault.homelab.local/ui/vault/auth/oidc/oidc/callback
        - http://localhost:8250/oidc/callback

envFrom:
  - secretRef:
      name: dex-secrets
```

Plaintext `client_secret` for each client lives at `secret/homelab/platform/dex/<service>`
in Vault. ESO syncs it into the `dex-secrets` Secret in the `dex` namespace and
into a per-service Secret (e.g., `argocd-dex-client` in `argocd`). The relying
party reads its copy and sends it on the OAuth2 token exchange; Dex compares
plaintext against the `secretEnv`-resolved value at request time.

The `OAuth2Client` CRD manifests, the bcrypt-hash regeneration tooling, and the
Application's third source path are removed.

Also amends ADR-0007's incidental note about "client secrets stored as
SealedSecrets in git" — the implementation used Vault + ESO from the start
(ADR-0006), and SealedSecrets are not part of this stack.

## Consequences

- One source of truth per Dex client: the `staticClients` block in
  `values.yaml`. Adding a relying party = one entry plus one Vault path. ✅
- No bcrypt hashing step, no out-of-band hash regeneration, no Justfile target
  for it. ✅
- The Dex Application loses one of its three sources (the `manifests/` path).
  `multiSource` is still needed for the chart + git-values pattern. ✅
- Plaintext client secrets never touch git. They live only in Vault and in
  in-memory env vars on the relevant pods. ✅
- Trade-off: plaintext is in pod environment, visible to anyone with `exec`
  into the Dex pod. Acceptable for a homelab; in a multi-tenant cluster
  prefer file-based `secretFile` with a tightly-scoped Secret mount and
  PodSecurityPolicy / RBAC restricting `exec`.
- Rotation procedure: `just vault-put platform/dex/<service>` with new value,
  ESO refreshes within `refreshInterval` (1h) — or restart Dex + relying
  party for immediate effect. No bcrypt regeneration, no git commit needed
  for rotation.
- ADR-0007 stays accepted; this ADR amends the implementation details
  (client storage mechanism and the SealedSecrets-vs-Vault claim) without
  changing the higher-level decision (Dex + GitHub OAuth).
