# Bootstrap — manual one-time steps

Everything in this directory is executed **once by hand** to bring up the platform.
After `root-app.yaml` is applied, ArgoCD reconciles the rest — no more `kubectl apply`.

## Prerequisites

- Docker Desktop running, ≥8 GiB allocated to Docker VM
- Tools installed: `kind`, `helm`, `kubectl` (via `mise install`)
- Ollama: stop or use a small model — big models fight the cluster for RAM

## Step 1 — Create the kind cluster

```bash
just kind-up
```

Nodes will be `NotReady` until Cilium is installed. Expected.

## Step 2 — Install Cilium (bootstrap only)

Cilium must be installed manually because ArgoCD needs a working CNI to run.
After ArgoCD is up, it takes over Cilium management — see Step 5.

```bash
helm repo add cilium https://helm.cilium.io
helm repo update
helm install cilium cilium/cilium \
  --version 1.16.5 \
  --namespace kube-system \
  --values platform/platform-services/cilium/values.yaml \
  --wait
kubectl wait --for=condition=Ready nodes --all --timeout=300s
```

## Step 3 — Install ArgoCD via Helm

Config-as-code: OIDC, RBAC, ingress, and server params are all in
`platform/platform-services/argocd/values.yaml` — no manual `kubectl patch` needed.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 7.7.14 \
  --values platform/platform-services/argocd/values.yaml \
  --wait
```

Get initial admin password (still works alongside SSO):
```bash
just argocd-pwd
```

## Step 4 — Apply the root App-of-Apps

```bash
just argocd-root-apply
```

ArgoCD now reconciles everything in `platform/gitops/applications/`.
Watch the sync waves roll out:
```bash
kubectl get applications -n argocd --watch
```

## Step 5 — Hand Cilium over to ArgoCD

```bash
helm uninstall cilium -n kube-system
```

Then in the ArgoCD UI: open the **cilium** Application → click **Sync**.
Watch nodes recover:
```bash
kubectl wait --for=condition=Ready nodes --all --timeout=300s
```

After this, all Cilium changes go through git + manual ArgoCD sync.

## Step 6 — Patch CoreDNS for in-cluster *.homelab.local DNS

**Required for OIDC to work.** Inside the cluster, `dex.homelab.local` resolves to
`127.0.0.1` (the Mac's dnsmasq), which is unreachable from pods. This step adds a
CoreDNS zone that maps `*.homelab.local` → ingress-nginx ClusterIP.

Run after ingress-nginx Application is Healthy:
```bash
just coredns-patch
```

Verify:
```bash
kubectl run -it --rm dns-test --image=busybox --restart=Never -- \
  nslookup dex.homelab.local
# Should return ingress-nginx ClusterIP, not 127.0.0.1
```

## Step 7 — Initialize and configure Vault

```bash
just vault-init    # save the 3 unseal keys + root token somewhere secure
just vault-unseal  # enter any 2 of the 3 keys
just vault-status  # Initialized: true, Sealed: false → ready
just vault-setup   # KV v2 + kubernetes auth + ESO role (prompts for root token)
```

See `platform/platform-services/vault/OPERATIONS.md` for the full runbook.

## Step 8 — Seed secrets

Fill in `.vault-secrets.env` (copy from `.vault-secrets.env.example`):
- Vault root token (from Step 7)
- GitHub OAuth App credentials (create at github.com/settings/developers)
- Two random strings for OIDC client secrets (`openssl rand -hex 32` each)

Then seed:
```bash
just vault-seed
```

ESO syncs secrets to the cluster within ~60 s. Verify:
```bash
kubectl get externalsecret -n dex
kubectl get externalsecret -n argocd argocd-dex-client
# Status: SecretSynced
```

## Step 9 — Configure Vault OIDC (after Dex is Healthy)

```bash
just vault-setup-oidc
```

After this: `http://vault.homelab.local` → select **OIDC** → **Sign in with Dex** → GitHub.

---

**That's it.** The full platform is up with SSO via GitHub → Dex → ArgoCD + Vault.

To add a new service: drop an `Application` manifest in `platform/gitops/applications/`
and an `Ingress` in `platform/platform-services/ingresses/`. Commit and push.

## Upgrading ArgoCD

When changing `platform/platform-services/argocd/values.yaml`:
```bash
just argocd-upgrade
```

## macOS host prerequisites (one-time, survives cluster rebuild)

### DNS — dnsmasq wildcard

Routes `*.homelab.local` to `127.0.0.1` so any subdomain hits the local cluster
from the Mac browser.

```bash
brew install dnsmasq
echo "address=/.homelab.local/127.0.0.1" >> /opt/homebrew/etc/dnsmasq.conf
sudo brew services start dnsmasq   # needs root to bind port 53
sudo bash -c 'mkdir -p /etc/resolver && echo "nameserver 127.0.0.1" > /etc/resolver/homelab.local'
ping -c 1 anything.homelab.local   # should resolve to 127.0.0.1
```

`sudo brew services start` is required because port 53 is privileged (<1024).

## Teardown

```bash
just kind-down
```

Re-running Steps 1–9 fully restores the platform. Steps 1–6 take ~10 minutes.
Steps 7–9 require re-seeding Vault (PVC is lost when kind cluster is deleted).
