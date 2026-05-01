# 3. Local cluster on kind with Cilium CNI from day one

Date: 2026-05-02

## Status

Accepted

## Context

We need a local Kubernetes cluster on a Mac mini M4 (16 GB RAM) for platform experiments and learning. Three local-cluster options were realistic:

| Option | Pros | Cons |
|---|---|---|
| **kind** | Multi-node, mature, well-supported, identical to upstream k8s | All in containers — RAM accounting per node |
| **k3d / k3s** | Lightest footprint, fast | k3s diverges from upstream (Traefik/SQLite default), some operators behave differently |
| **minikube** | Familiar, drivers for everything | Slowest startup, Docker driver still effectively kind-equivalent |

For CNI, the choice was between the kind default (kindnet — minimal, no NetworkPolicy enforcement), Calico, and Cilium. Cilium is overkill for a 16 GB lab on raw resource cost (Hubble + agent per node), but it is the de facto reference for modern eBPF-based networking, NetworkPolicy enforcement, service mesh integration (with Cilium Service Mesh or as the dataplane for Istio), and observability (Hubble). Learning Cilium on a real multi-node cluster is one of the explicit goals of this homelab.

The Mac mini's 16 GB constraint pushes toward fewer worker nodes. Three nodes (1 control + 2 workers) is the minimum that exercises real scheduling behavior and NetworkPolicy across nodes, while staying within memory.

## Decision

- **Local cluster: kind**, configured as 1 control plane + 2 workers.
- **CNI: Cilium from day one**, installed via Helm during bootstrap. `disableDefaultCNI: true` in the kind config so no kindnet is installed.
- Cilium installed with a minimal-but-non-trivial values file: kube-proxy replacement enabled (for the eBPF lesson), Hubble enabled but with conservative resource requests.
- Bootstrap is one-shot manual (`platform/bootstrap/`); cluster lifecycle is managed via `just kind-up` / `just kind-down` plus the bootstrap script.

## Consequences

- We get real multi-node behavior (cross-node networking, scheduling, NetworkPolicy enforcement) at a memory cost we can manage.
- Cilium's footprint (~200–400 MiB across all components on this size of cluster) is accepted as a learning investment, not optimized away.
- Service mesh is deferrable: Cilium Service Mesh is available without adding Istio. Istio remains an option if a project specifically demands it, but is not added speculatively.
- Trade-off: cluster bring-up is slower than `k3d cluster create` and uses more RAM. We accept this for the realism.
- Failure mode to watch: on memory pressure, Cilium agents have been known to flap. The `k8s-debugger` subagent is instructed to suspect Cilium agent state when nodes go `NotReady` unexpectedly.
- If the 2-worker setup turns out to be too tight in practice, dropping to 1 worker is reversible (`kind delete cluster && kind create ...` with an updated config). Not a permanent commitment.
