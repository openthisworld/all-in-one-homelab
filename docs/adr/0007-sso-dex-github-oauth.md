# 7. SSO for platform UIs: Dex with GitHub OAuth

Date: 2026-05-02

## Status

Accepted

## Context

Platform UIs (ArgoCD, Grafana, Hubble UI) each have their own authentication.
Without SSO, every UI has a separate admin password stored somewhere, login is
manual per tool, and there's no centralised access control.

Enterprise standard: a central OIDC provider that all services trust. Users
authenticate once (via their identity provider) and get access to all tools.

Options:

1. **Per-service passwords** — status quo. Simple but doesn't scale and is
   error-prone (where is the Grafana admin password again?).

2. **Dex with GitHub OAuth** — Dex is a lightweight OIDC/OAuth2 identity provider
   (~50 MiB) that federates to upstream identity providers. Here: GitHub OAuth App.
   ArgoCD, Grafana, and other OIDC-capable services delegate authentication to Dex.
   One GitHub login grants access to all platform UIs.

3. **Keycloak** — full-featured IAM (~512 MiB+). Overkill for a homelab and exceeds
   RAM budget without strong justification.

Dex is purpose-built for Kubernetes and is the reference implementation used by
projects like kind itself. It integrates natively with ArgoCD (built-in OIDC support)
and Grafana (generic OAuth2 provider).

## Decision

Deploy **Dex** as the cluster's OIDC provider, configured with a **GitHub OAuth App**
as the upstream identity provider.

Architecture:
```
Browser → ArgoCD / Grafana / ... → Dex (OIDC)
                                       ↓
                                GitHub OAuth
                                       ↓
                              GitHub identity confirmed
                                       ↓
                         Dex issues OIDC token → service grants access
```

Configuration:
- Dex deployed in namespace `dex` via ArgoCD Application.
- GitHub OAuth App callback URL: `http://dex.homelab.local/callback`
- Dex OIDC issuer URL: `http://dex.homelab.local`
- Dex client secrets stored as SealedSecrets in git.
- ArgoCD OIDC: configured via `argocd-cm` to use Dex as OIDC issuer.
- Grafana OAuth2: configured in Grafana values to use Dex.
- Access control: GitHub organisation or specific GitHub users allowed
  (configured in Dex's GitHub connector `orgs` or `usernames` filter).

## Consequences

- Single GitHub login for all platform UIs. No per-service passwords.
- ArgoCD admin password (`argocd-initial-admin-secret`) remains as emergency
  fallback — keep it, but don't use it day-to-day.
- Requires a GitHub OAuth App (free, created in GitHub Developer Settings).
- Dex runs in the cluster — if Dex is down, no one can log in to UIs.
  Mitigation: ArgoCD local admin account as fallback; Grafana anonymous viewer mode.
- HTTP only (no TLS) acceptable for loopback-only homelab. When TLS is added
  (cert-manager phase), update Dex issuer URL to https://.
- Hubble UI: limited OIDC support — likely stays without SSO for now.
- Adding a new platform UI = configure its OIDC/OAuth2 client in Dex values
  and add a client entry. No new passwords to manage.
