---
name: argocd-app
description: Generate a new ArgoCD Application manifest for the App-of-Apps pattern in this repo. Use when adding a new component to the platform stack — observability, databases, AI gateway, or platform services. Produces a manifest in platform/gitops/applications/ that the root App-of-Apps will pick up.
---

# argocd-app

Generates a new `Application` manifest under `platform/gitops/applications/` consistent with this repo's App-of-Apps conventions.

## When to use

- Adding a new in-cluster component (e.g., cnpg, victoria-metrics, litellm).
- Splitting an existing component into separate Apps (e.g., separating `cnpg-operator` from `cnpg-clusters`).
- NOT for one-off `kubectl apply` testing — that goes in `sandbox/`.

## Inputs to gather before generating

1. **App name** — short, kebab-case (e.g., `victoria-metrics`).
2. **Source type** — Helm chart (most common), Kustomize, or plain manifests.
3. **Repo + path or chart coords** — for Helm: repo URL, chart name, version. For local: path under `platform/`.
4. **Destination namespace** — exact name. Confirm whether namespace is created by ArgoCD (`CreateNamespace=true`) or pre-existing.
5. **Sync wave** — integer. Lower runs first. Defaults: CRDs/operators `-2`, platform services `0`, workloads `5`, AI/data `10`.
6. **Auto-sync?** — yes for everything stable, **no** for components that should be opt-in (heavy AI components on 16 GB).
7. **Helm values** — inline in the Application or via a values file in `platform/<domain>/<app>/values.yaml`.

## Manifest skeleton

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "<wave>"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    # --- Helm variant ---
    repoURL: https://<chart-repo>
    chart: <chart-name>
    targetRevision: <version>
    helm:
      releaseName: <app-name>
      valueFiles:
        - $values/platform/<domain>/<app-name>/values.yaml
    # --- OR Kustomize / raw manifests variant ---
    # repoURL: https://github.com/<owner>/HomeLab.git
    # path: platform/<domain>/<app-name>
    # targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: <namespace>
  syncPolicy:
    # automated only for stable, cheap components
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 3
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 2m
```

## Conventions enforced

- Every Application has a `sync-wave` annotation. Don't leave it default.
- `prune: true` is the default — but warn the user when applying it to anything stateful (CNPG, Qdrant, MinIO).
- `ServerSideApply=true` to avoid annotation bloat on large CRDs.
- Helm values files live in `platform/<domain>/<app>/values.yaml`, referenced via a separate `repoURL` source if multi-source, or inline if simple.
- Heavy components (>500 MiB RSS expected) get `automated:` removed and require manual sync. Document this in the App's neighboring README.
- Output path: `platform/gitops/applications/<wave>-<app-name>.yaml` so listing is naturally ordered by wave.

## After generating

1. Show the user the manifest.
2. Run `kubectl --dry-run=client -o yaml apply -f <path>` to validate (read-only, allowed).
3. Remind them: commit + push, then ArgoCD root app will reconcile automatically. Don't `kubectl apply` it manually.
