#!/usr/bin/env bash
# scripts/coredns-homelab-patch.sh
#
# Problem: inside the cluster dex.homelab.local resolves to 127.0.0.1 (Mac loopback)
# which is unreachable from pods. OIDC backends (ArgoCD, Vault) call Dex for token
# validation — they fail without this fix.
#
# Solution: add a CoreDNS zone that returns the ingress-nginx ClusterIP for every
# *.homelab.local query. Requests route through ingress-nginx (Host header routing)
# to the right backend service.
#
# Run once after ingress-nginx is Healthy. Re-run when adding new *.homelab.local
# services (removes and re-adds the zone with the updated hosts block).
# Usage: bash scripts/coredns-homelab-patch.sh

set -euo pipefail

INGRESS_SVC="ingress-nginx-controller"
INGRESS_NS="ingress-nginx"

echo "--- Getting ingress-nginx ClusterIP ---"
INGRESS_IP=$(kubectl get svc "$INGRESS_SVC" -n "$INGRESS_NS" \
  -o jsonpath='{.spec.clusterIP}')
echo "  ${INGRESS_IP}"

echo "--- Checking CoreDNS Corefile ---"
if kubectl get configmap coredns -n kube-system \
    -o jsonpath='{.data.Corefile}' | grep -q "homelab.local"; then
  echo "  homelab.local zone already present — skipping."
  echo "  To re-patch: edit coredns ConfigMap to remove the homelab.local block, then re-run."
  exit 0
fi

echo "--- Patching CoreDNS ConfigMap ---"
python3 - "$INGRESS_IP" << 'PYEOF'
import subprocess, json, sys

ingress_ip = sys.argv[1]

current = subprocess.check_output([
    "kubectl", "get", "configmap", "coredns",
    "-n", "kube-system", "-o", "jsonpath={.data.Corefile}"
]).decode()

# CoreDNS hosts plugin: wildcard *.homelab.local → ingress-nginx ClusterIP.
# Add new services here as the homelab grows.
block = f"""
# In-cluster resolution for *.homelab.local → ingress-nginx ClusterIP.
# Required so OIDC backends (ArgoCD, Vault) can reach Dex for token validation.
# Managed by scripts/coredns-homelab-patch.sh — do not edit manually.
homelab.local:53 {{
    errors
    hosts {{
        {ingress_ip} argocd.homelab.local
        {ingress_ip} dex.homelab.local
        {ingress_ip} vault.homelab.local
        {ingress_ip} hubble.homelab.local
        fallthrough
    }}
    cache 30
}}
"""

patch = json.dumps({"data": {"Corefile": current + block}})
subprocess.run([
    "kubectl", "patch", "configmap", "coredns",
    "-n", "kube-system", "--type=merge", "-p", patch
], check=True)
print("  Corefile updated.")
PYEOF

echo "--- Restarting CoreDNS ---"
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system --timeout=60s

echo ""
echo "Done. *.homelab.local resolves to ${INGRESS_IP} inside the cluster."
echo "Verify: kubectl run -it --rm dns-test --image=busybox --restart=Never -- nslookup dex.homelab.local"
