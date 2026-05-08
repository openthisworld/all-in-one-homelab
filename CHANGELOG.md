# Changelog

All notable changes to the HomeLab platform are recorded here.

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html),
applied to the platform as a whole — see "Versioning policy" at the bottom of
this file for what each major/minor/patch step means here.

A new entry is added per release. Use [`docs/releases/RELEASE_TEMPLATE.md`](docs/releases/RELEASE_TEMPLATE.md)
as the starting point.

## [Unreleased]

_Nothing yet — list upcoming changes here as they merge to main._

## [0.0.1] — 2026-05-08

First tagged state. The platform is bootstrappable end-to-end on a Mac mini M4
(16 GB) via the procedure in `platform/bootstrap/README.md`. SSO via Dex →
GitHub OAuth is verified working for ArgoCD; Vault OIDC is configured but
end-to-end browser login is not yet user-verified.

### Added

- **Foundation**
  - Monorepo layout with extraction path (ADR-0002): `platform/`, `projects/`, `sandbox/`, `docs/`, `scripts/`.
  - `mise` as toolchain manager with pinned versions in `.mise.toml`.
  - Pre-commit hooks: yamllint, gitleaks, OpenTofu fmt/validate, shellcheck, shfmt.
  - `Justfile` as the entry point for repeatable operations.

- **Local cluster** (ADR-0003)
  - `kind` cluster definition (1 control + 2 workers) at `platform/bootstrap/kind-cluster.yaml`.
  - **Cilium** as CNI from day one (`disableDefaultCNI: true`), values at `platform/platform-services/cilium/values.yaml`.
  - Cilium under ArgoCD with manual sync only (ADR-0008).

- **GitOps** (ArgoCD App-of-Apps)
  - ArgoCD installed via Helm with config-as-code values (`platform/platform-services/argocd/values.yaml`).
  - Root Application at `platform/gitops/root-app.yaml` reconciles everything in `platform/gitops/applications/`.
  - Sync waves wired up so Vault unseals before ESO connects, ESO connects before Dex starts, etc.

- **Secrets management** (ADR-0006)
  - HashiCorp Vault (Raft single-node, manual unseal) at `platform/platform-services/vault/`.
  - External Secrets Operator with a `ClusterSecretStore` pointing at Vault.
  - Vault OIDC auth method backed by Dex (`scripts/vault-setup-oidc.sh`).

- **SSO** (ADR-0007, ADR-0009)
  - Dex deployed as the OIDC provider with a GitHub OAuth App upstream.
  - Static OAuth2 clients for ArgoCD and Vault defined in `dex/values.yaml` using `secretEnv`; plaintext `client_secret` lives in Vault and is delivered via ESO.
  - GitHub username `openthisworld` mapped to ArgoCD admin via RBAC `policy.csv`.

- **Networking & DNS**
  - `ingress-nginx` listening on host port 80 via kind portMappings.
  - macOS-side `dnsmasq` wildcard for `*.homelab.local → 127.0.0.1`.
  - In-cluster CoreDNS patch (`scripts/coredns-homelab-patch.sh`) so pods can resolve `*.homelab.local` to the ingress-nginx ClusterIP — required for the OIDC token-exchange leg.
  - Ingresses for `argocd.homelab.local`, `dex.homelab.local`, `vault.homelab.local`, `hubble.homelab.local`.

- **Supporting components**
  - `cert-manager` (installed; TLS not yet integrated).
  - `metrics-server` (enables `kubectl top` and HPA).
  - `stakater/reloader` (restarts pods when their ConfigMaps/Secrets change).

- **Documentation**
  - 9 ADRs covering architecture decisions to date (`docs/adr/0001`…`0009`).
  - Bootstrap runbook at `platform/bootstrap/README.md` (Steps 1–9).
  - Vault operations runbook at `platform/platform-services/vault/OPERATIONS.md`.
  - Learning note on local ingress + DNS architecture (`docs/learning-notes/local-ingress-dns-architecture.md`).

### Fixed

- **Dex `Invalid client_id` on every login** — the previous setup defined OAuth2 clients as `dex.coreos.com/v1` `OAuth2Client` CRD manifests with fields under a `spec:` block and a bcrypt `secretHash`. Both were wrong: the CRD storage uses a flat schema (fields at resource root) and a plaintext `secret` field. Replaced with `staticClients` + `secretEnv` in `dex/values.yaml`. Plaintext stays out of git via Vault + ESO. See ADR-0009.

### Known issues / follow-ups

These are deliberately deferred — call them out so the next release knows what's still on the table:

- Bootstrap is **not zero-touch on cluster recreation**. Manual steps: Cilium handover (`helm uninstall` then ArgoCD sync), CoreDNS patch, Vault init/unseal/setup, Vault OIDC config, secret seeding from `.vault-secrets.env`. Tracked for v0.1.0.
- `scripts/bootstrap.sh` is a stub.
- Vault must be manually unsealed after every pod restart (no auto-unseal yet).
- ADR-0007 mentions "client secrets stored as SealedSecrets in git" — that decision was effectively superseded by ADR-0006 (Vault + ESO) before this release was tagged. ADR-0009 records the correction; ADR-0007 itself is left as-is per ADR immutability.
- Vault OIDC end-to-end (browser login) not yet user-verified for this release. Configuration is in place; verification is part of v0.0.2 or v0.1.0 as part of bootstrap automation.
- `platform/observability/`, `platform/databases/`, `platform/ai-gateway/` are placeholders (per ADRs 0004, 0005). No services deployed under them yet.

[Unreleased]: https://github.com/openthisworld/all-in-one-homelab/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/openthisworld/all-in-one-homelab/releases/tag/v0.0.1

---

## Versioning policy

The platform as a whole is versioned. Projects under `projects/*` are versioned
independently when they exist (none do as of v0.0.1).

- **Patch (`0.0.x`)** — bug fixes, doc corrections, ADR amendments, no new components.
- **Minor (`0.x.0`)** — new platform component, new ADR introducing a new architectural concern, breaking change to bootstrap procedure.
- **Major (`x.0.0`)** — first major version when the platform is bootstrappable zero-touch on a clean kind cluster, _and_ at least one `projects/*` is running end-to-end.

Pre-1.0 the API (Justfile targets, manifest paths, secret paths in Vault) is not stable — breaking changes are documented in the changelog but do not force a major bump.

## How to release

1. Move entries from `[Unreleased]` into a new `[X.Y.Z] — YYYY-MM-DD` section using `docs/releases/RELEASE_TEMPLATE.md`.
2. Update the comparison links at the bottom of `CHANGELOG.md`.
3. Open a PR titled `release: vX.Y.Z`, merge after review.
4. On `main`: `git tag -a vX.Y.Z -m 'Release vX.Y.Z' && git push origin vX.Y.Z`.
5. Optionally create a GitHub Release from the tag — body = the section from `CHANGELOG.md`.
