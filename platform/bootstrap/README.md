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

## Step 2 — Install Cilium (bootstrap only)

Cilium must be installed manually here because ArgoCD needs a working CNI to run.
After ArgoCD is up, it takes over Cilium management — see Step 7.

```bash
helm repo add cilium https://helm.cilium.io
helm repo update
helm install cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --values platform/platform-services/cilium/values.yaml \
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

## Step 5 — Exclude Cilium auto-generated resources from ArgoCD

Cilium automatically creates `CiliumIdentity` resources in every namespace that has pods.
Without this exclusion ArgoCD marks every Application as OutOfSync and may prune them,
breaking pod networking.

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"resource.exclusions":"- apiGroups:\n  - cilium.io\n  kinds:\n  - CiliumIdentity\n  clusters:\n  - \"*\"\n"}}'
```

## Step 6 — Enable ArgoCD insecure mode (for HTTP Ingress)

By default ArgoCD server redirects all HTTP traffic to HTTPS internally.
This conflicts with nginx proxying plain HTTP. Switch it off:

```bash
kubectl patch configmap argocd-cmd-params-cm -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd --timeout=60s
```

## Step 7 — Hand Cilium over to ArgoCD

ArgoCD now has a `cilium` Application (sync-wave -5, manual sync only — see ADR-008).
Transfer management from the bootstrap helm install to ArgoCD:

```bash
# Brief network disruption (~30-60s) while Cilium is reinstalled by ArgoCD.
helm uninstall cilium -n kube-system
```

Then in the ArgoCD UI: open the **cilium** Application → click **Sync**.
Watch nodes recover:
```bash
kubectl wait --for=condition=Ready nodes --all --timeout=300s
```

After this, all future Cilium changes go through git + manual ArgoCD sync.
Never run `helm upgrade cilium` directly again.

**That's it.** ArgoCD now reconciles everything in `platform/gitops/applications/`.
Add a new component by dropping an `Application` manifest there, commit, and push.
Ingress rules live in `platform/platform-services/ingresses/` — add a file there
to expose a new service at `<name>.homelab.local`.

## macOS host prerequisites (one-time, survives cluster rebuild)

These are set up on the Mac itself, not in the cluster. Do them once.

### DNS — dnsmasq wildcard

Routes `*.homelab.local` to `127.0.0.1` so any subdomain hits the local cluster.

```bash
brew install dnsmasq
echo "address=/.homelab.local/127.0.0.1" >> /opt/homebrew/etc/dnsmasq.conf
sudo brew services start dnsmasq   # needs root to bind port 53
sudo bash -c 'mkdir -p /etc/resolver && echo "nameserver 127.0.0.1" > /etc/resolver/homelab.local'
# Verify:
ping -c 1 anything.homelab.local   # should resolve to 127.0.0.1
```

Why `sudo brew services start` and not `brew services start`:
port 53 is a privileged port (< 1024). macOS blocks non-root processes from
binding it. Running as root installs a LaunchDaemon in `/Library/LaunchDaemons/`
instead of `~/Library/LaunchAgents/`.

## Teardown

```bash
kind delete cluster --name homelab
```

Re-running steps 1–4 restores the full platform. Steps 2–4 take ~5 minutes.
