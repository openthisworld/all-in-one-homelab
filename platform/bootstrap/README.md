# Bootstrap — manual one-time steps

Everything in this directory is executed **once by hand** to bring up the platform.
After `root-app.yaml` is applied, ArgoCD reconciles the rest — no more `kubectl apply`.

## Prerequisites

- Docker Desktop running, ≥8 GiB allocated to Docker VM
- Tools installed: `kind`, `helm`, `kubectl` (via `mise install`)
- Ollama: stop or use a small model — big models fight the cluster for RAM

## Step 1 — Create the kind cluster

```bash
kind create cluster --config platform/bootstrap/kind-cluster.yaml --name homelab
```

Nodes will be `NotReady` until Cilium is installed. Expected.

## Step 2 — Install Cilium

```bash
helm repo add cilium https://helm.cilium.io
helm repo update
helm install cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --values platform/bootstrap/cilium-values.yaml \
  --wait
```

Wait for nodes:
```bash
kubectl wait --for=condition=Ready nodes --all --timeout=300s
```

## Step 3 — Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.3/manifests/install.yaml
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
```

Get initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

## Step 4 — Apply the root App-of-Apps

```bash
kubectl apply -f platform/gitops/root-app.yaml
```

**That's it.** ArgoCD will now reconcile everything in `platform/gitops/applications/`.
Add a new component by dropping an `Application` manifest there, commit, and push.

## Teardown

```bash
kind delete cluster --name homelab
```

Re-running steps 1–4 restores the full platform. Steps 2–4 take ~5 minutes.
