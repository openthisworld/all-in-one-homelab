# HomeLab

Personal DevOps homelab on a Mac mini M4 (16GB). Local-only, no cloud.

## Goals

- Practice senior-level system design on real, end-to-end problems.
- Learn AI orchestration patterns (RAG, agentic workflows, gateway/eval) on owned infra.
- Build a portfolio of self-contained projects that can be extracted into standalone repos.

## Current focus — Track 1: Platform foundation

Bringing up the local Kubernetes platform end-to-end:

1. Multi-node `kind` cluster (1 control + 2 workers) with Cilium CNI
2. ArgoCD installed manually, then App-of-Apps manages everything else
3. Platform services: cert-manager, ingress, secrets management
4. Observability: VictoriaMetrics + VictoriaLogs + Grafana
5. Data: CloudNativePG, Redis, Qdrant, MinIO
6. AI gateway: LiteLLM in-cluster, proxying to Ollama on the macOS host

Track 2 (later): first AI project — historical articles writer with web search and knowledge-graph linking. Likely starting from STORM or GraphRAG/LightRAG composition.

## Repository layout

```
.claude/         Claude Code config: settings, skills, subagents
docs/            ADRs, learning notes, system-design write-ups
platform/        Cluster bootstrap + GitOps manifests for the platform
  bootstrap/     Manual one-time steps (kind, Cilium, ArgoCD)
  gitops/        Root App-of-Apps + Application manifests
  platform-*/    Per-domain manifests synced by ArgoCD
projects/        Self-contained learning projects (extractable)
sandbox/         Throwaway experiments
scripts/         Helper scripts
```

## Getting started

Prereqs (managed by `mise`): see `.mise.toml`.

```bash
mise install              # install pinned toolchain
just                      # list available tasks
just bootstrap            # one-time cluster + ArgoCD setup (interactive)
```

`projects/*` are independent: each has its own `README.md`, `.mise.toml`, and infra. When a project matures, `git filter-repo` extracts it into a standalone repository.

## Conventions

- IaC: OpenTofu (`tofu`), not Terraform.
- Toolchain: `mise` per-project, exact-pinned versions.
- GitOps: Everything past bootstrap is reconciled by ArgoCD. No `kubectl apply` by hand outside `platform/bootstrap/`.
- ADRs in `docs/adr/` — one per non-trivial decision, Nygard format.

## License

Personal project. No license — all rights reserved by default.
