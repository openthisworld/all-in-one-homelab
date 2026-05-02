# 8. Cilium managed by ArgoCD (manual sync only)

Date: 2026-05-02

## Status

Accepted

## Context

Cilium was initially installed via `helm install` during bootstrap (ADR-003).
This means Cilium is invisible to ArgoCD — its version, values drift, and health
are not visible in the GitOps dashboard. Helm values changes require manual
`helm upgrade` runs.

The goal is to bring Cilium under ArgoCD management for:
- Version and values changes tracked in git and visible in ArgoCD UI.
- Drift detection: ArgoCD alerts if the live cluster diverges from git.
- Consistent operational model — one tool for everything.

**Risk:** Cilium is the cluster's CNI. If ArgoCD disrupts Cilium during a sync
(e.g., by pruning a DaemonSet pod at the wrong time), the entire cluster network
can degrade. More critically: if ArgoCD loses network connectivity mid-reconcile
because Cilium is in a broken state, it cannot finish the recovery — deadlock.

## Decision

Manage Cilium via an ArgoCD Application with **manual sync only** and **prune disabled**.

```yaml
syncPolicy:
  # No automated block — every Cilium sync is a deliberate human action.
  syncOptions:
    - ServerSideApply=true
    - RespectIgnoreDifferences=true
    - PrunePropagationPolicy=background
```

Rationale:
- `automated: ~` (absent) — ArgoCD will detect drift and report it, but never
  automatically apply changes to Cilium. A human clicks Sync consciously.
- `prune: false` (default when automated is off) — ArgoCD will not delete
  Cilium-managed resources it doesn't recognise from the chart.
- `RespectIgnoreDifferences=true` — avoid false OutOfSync from Cilium's
  auto-generated fields (e.g., CiliumIdentity, node annotations).
- Sync wave `-5` — if a full cluster rebuild triggers ArgoCD to reconcile
  everything, Cilium syncs first (before any workloads need networking).

Operational procedure for Cilium updates:
1. Update `targetRevision` or `cilium-values.yaml` in git.
2. Open ArgoCD UI → Cilium Application → review the diff.
3. Click Sync manually. Watch `kubectl get nodes` and `cilium status` during sync.
4. If nodes go NotReady: investigate before proceeding, not after.

Migration from manual helm to ArgoCD:
- `helm uninstall cilium -n kube-system` (brief network disruption, ~30s on kind)
- ArgoCD Application is already in git → click Sync in UI to reinstall.

## Consequences

- Cilium visible in ArgoCD alongside all other platform components. ✅
- Cilium values changes are git-tracked and peer-reviewed (even in a solo homelab,
  the git history is the review). ✅
- No automatic Cilium updates — intentional. Cilium is upgraded deliberately.
- Teardown + rebuild: ArgoCD reinstalls Cilium automatically after `kubectl apply root-app.yaml`
  — but only after a manual Sync click. Include this in bootstrap documentation.
- The `CiliumIdentity` exclusion in `argocd-cm` (ADR reference: bootstrap step 5)
  prevents ArgoCD from treating auto-generated Cilium CRs as drift.
