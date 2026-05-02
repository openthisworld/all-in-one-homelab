# Local ingress + DNS architecture for a kind cluster

Date: 2026-05-02
Context: homelab on Mac mini M4, kind cluster with Cilium + ingress-nginx.

## The problem

Running Kubernetes locally, you want to access services by name
(`argocd.homelab.local`, `hubble.homelab.local`) instead of `kubectl port-forward`
every time. This mirrors how real clusters work behind a load balancer.

## The full request path

```
Browser: http://argocd.homelab.local
           │
           │ (1) DNS resolution
           ▼
  macOS checks /etc/resolver/homelab.local → "ask 127.0.0.1:53"
  dnsmasq (running on the Mac) has rule: address=/.homelab.local/127.0.0.1
  → returns 127.0.0.1 for ANY *.homelab.local hostname
           │
           │ (2) TCP connection to 127.0.0.1:80
           ▼
  kind extraPortMappings (in kind-cluster.yaml):
    containerPort: 80 ↔ hostPort: 80
  → traffic enters the kind control-plane container
           │
           │ (3) ingress-nginx DaemonSet (hostPort: 80)
           ▼
  nginx reads the HTTP Host header: "argocd.homelab.local"
  looks up Ingress resources in the cluster for this hostname
  finds: Ingress/argocd in namespace argocd → argocd-server:80
           │
           │ (4) Service routing
           ▼
  argocd-server Pod responds
```

## Why each piece is needed

### dnsmasq
`/etc/hosts` doesn't support wildcards — you'd have to add a line per service.
dnsmasq with `address=/.homelab.local/127.0.0.1` covers every possible subdomain
automatically. Adding a new service = add an Ingress resource, no DNS change needed.

### /etc/resolver/homelab.local
macOS doesn't use a single global DNS server for everything. The `/etc/resolver/`
directory lets you route specific domains to specific nameservers. This file says:
"for anything ending in .homelab.local, ask 127.0.0.1 (our dnsmasq)".
Everything else goes to your router/ISP DNS as usual.

### kind extraPortMappings
kind runs nodes as Docker containers. Without portMappings, ports inside the
containers are not reachable from the Mac. The mapping in kind-cluster.yaml:
```yaml
extraPortMappings:
  - containerPort: 80
    hostPort: 80
```
means `127.0.0.1:80` on the Mac → port 80 of the control-plane container.
We put this on the control-plane because that's where ingress-nginx runs
(it needs the `ingress-ready=true` label we set on that node).

### ingress-nginx
A reverse proxy running inside the cluster. Listens on port 80/443 using
hostPort (direct binding to the container's network interface).
Reads `Ingress` Kubernetes resources to know which hostname goes to which Service.
IngressClass `nginx` is the default — referenced in every Ingress manifest.

### Ingress resource
Kubernetes CRD that declares routing rules:
```yaml
rules:
  - host: argocd.homelab.local   # match this Host header
    http:
      paths:
        - path: /
          backend:
            service:
              name: argocd-server
              port: 80           # forward to this Service
```
Lives in the same namespace as the target Service (or cross-namespace with
additional config). Managed by ArgoCD via the `platform-ingresses` Application.

### ArgoCD insecure mode
ArgoCD server normally listens on 443 (TLS) and redirects port 80 → 443.
This breaks nginx proxying, because nginx would receive a redirect instead of content.
`server.insecure=true` in `argocd-cmd-params-cm` makes argocd-server serve plain
HTTP on port 80. Acceptable on loopback — no TLS needed for local-only access.

## How to add a new service

1. Deploy the service (via ArgoCD Application as usual).
2. Add a file to `platform/platform-services/ingresses/<service>.yaml`:
   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: <service>
     namespace: <service-namespace>
   spec:
     ingressClassName: nginx
     rules:
       - host: <service>.homelab.local
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: <service-svc-name>
                   port:
                     number: 80
   ```
3. Commit and push. ArgoCD reconciles `platform-ingresses` Application automatically.
4. Open `http://<service>.homelab.local` — it works, no port-forward needed.

## Comparison with other approaches

| | This setup | kubectl port-forward | Cloudflare tunnel |
|---|---|---|---|
| URL | http://name.homelab.local | http://localhost:PORT | https://name.yourdomain.com |
| DNS | dnsmasq wildcard, local only | none (just a port) | Cloudflare public DNS |
| TLS | none (HTTP, loopback) | none | Cloudflare-managed |
| Survives pod restart | yes (Ingress is persistent) | no (you re-run the command) | yes |
| Accessible outside Mac | no | no | yes (public URL) |
| Requires internet | no | no | yes |

port-forward is fine for one-off debugging. Ingress is the right tool when you
want a service to feel like a real endpoint — always available, right URL.

## What we don't have yet (future improvements)

- **TLS**: cert-manager + a self-signed CA would give us `https://` with a trusted
  cert (trusted by adding the CA to the macOS keychain). Needed before anything
  that sends credentials (ArgoCD login without TLS is fine on loopback, but
  becomes a habit to break).
- **ExternalDNS**: automatically creates DNS records when an Ingress is created.
  Not useful here since we use a wildcard, but worth knowing exists.
