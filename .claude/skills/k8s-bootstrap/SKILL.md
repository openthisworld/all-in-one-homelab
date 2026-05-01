---
name: k8s-bootstrap
description: Walk through bringing up the local kind+Cilium+ArgoCD platform from scratch on this Mac mini. Use when the cluster doesn't exist yet, the user asked to "rebuild from zero", or after a destructive teardown. Coordinates the manual one-time steps in platform/bootstrap/ and hands off to ArgoCD.
---

# k8s-bootstrap

End-to-end bring-up of the homelab platform. This is the **only** sequence that runs `kubectl apply` outside of ArgoCD — once ArgoCD is up, everything else flows through the App-of-Apps.

## Pre-flight

Confirm with the user before proceeding:

- Docker Desktop is running and has at least 8 GiB allocated (`Settings → Resources → Memory`).
- No existing kind cluster named `homelab` (`kind get clusters`). If one exists, ask whether to delete or reuse.
- Ollama is either stopped or has a small model loaded — heavy models (70B+) will starve the cluster.
- ~10 GiB free disk for kind node images and pulled containers.

## Sequence

Each step is a separate destructive operation — pause and confirm before each.

### 1. Create the kind cluster

```bash
kind create cluster --config platform/bootstrap/kind-cluster.yaml --name homelab
```

Notes:
- `disableDefaultCNI: true` is set — nodes will be `NotReady` until Cilium is installed. This is expected.
- Multi-node: 1 control + 2 workers. The control node is tainted by default; we keep it that way.

### 2. Install Cilium

```bash
helm repo add cilium https://helm.cilium.io
helm repo update
helm install cilium cilium/cilium \
  --version <pinned-in-cilium-values.yaml> \
  --namespace kube-system \
  --values platform/bootstrap/cilium-values.yaml
```

Wait for nodes to go `Ready`:

```bash
kubectl wait --for=condition=Ready nodes --all --timeout=300s
cilium status --wait
```

### 3. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f platform/bootstrap/argocd-install.yaml
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
```

Capture the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### 4. Apply the root App-of-Apps

```bash
kubectl apply -f platform/gitops/root-app.yaml
```

From this point on, all platform components are reconciled by ArgoCD. **Do not `kubectl apply` anything else manually** — write an Application manifest and let ArgoCD pick it up.

## Verification checklist

After bootstrap, confirm:

- `kubectl get nodes` — all `Ready`
- `cilium status` — green
- `kubectl -n argocd get applications` — root app is `Synced` and `Healthy`
- `just argocd-ui` — UI accessible at https://localhost:8080
- `kubectl top nodes` works (after metrics-server is synced)

## Troubleshooting

- **Nodes stuck `NotReady`**: Cilium not yet ready. Check `kubectl -n kube-system get pods -l k8s-app=cilium`.
- **ArgoCD can't reach git repo**: If repo is private, the `argocd repo add` step needs a token. We haven't set this up yet — flag to user.
- **OOMKilled pods**: 16 GiB is tight. Drop replicas in the offending Application's values, or pause non-essential apps via the ArgoCD UI.

## What this skill does NOT do

- It does NOT install brew packages or modify the user's shell.
- It does NOT create a GitHub repository or push code.
- It does NOT delete an existing cluster without explicit confirmation.
