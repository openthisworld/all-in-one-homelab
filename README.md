# HomeLab

Personal DevOps homelab on a Mac mini M4 (16 GB). Local-only, no cloud.

## Mission

A platform where the **full cycle of building, shipping, and observing an
idea lives locally**: write code with Claude Code (claude-skills plugin
loaded) → build → deploy to the in-cluster GitOps stack → test → read
metrics and logs in a local Grafana that you log into via the same Dex SSO
as everything else. All within 16 GB RAM, no cloud, no SaaS.

The repo provides the platform, the conventions, and the golden paths.
Code generation is Claude Code's job; the repo's job is being the place
where that code lands, runs, and is observed.

### What this means in practice

- **Bootstrappable end-to-end** from a clean Mac with one script and one
  set of secrets (`.vault-secrets.env`) — no manual sequencing.
- **Single sign-on via Dex + GitHub OAuth** for every UI: ArgoCD, Vault,
  Grafana, Backstage (when it lands), and any future PoC with a UI.
- **Vault is the only secret store.** Anything that needs a secret reads
  it via External Secrets Operator. Unseal keys themselves live in
  `.vault-secrets.env` (gitignored) so cluster restart is one command.
- **Observability is non-optional.** Every service in the cluster ships
  metrics and logs to the local VictoriaMetrics / VictoriaLogs stack.
  A PoC that does not appear in Grafana is not finished.
- **Justfile is the stable API.** `just` commands are the documented,
  always-working entry points. If a manual procedure exists in a runbook
  but no `just` target wraps it, that's a bug.

### What this is NOT

- Not a SaaS, not a hosted demo, not a multi-tenant cluster. One user,
  one machine, one cluster.
- Not a production-grade reference architecture. RAM-budget and
  single-node concessions are deliberate (see ADRs 0003, 0004, 0006).
- Not an autonomous agent farm. Code generation runs in Claude Code in
  your terminal; the repo does not host a long-running agent runtime.
  See [`projects/pocsmith/DESIGN.md`](projects/pocsmith/DESIGN.md) for
  why pocsmith remains a paused design rather than a built thing.

## Long-running goals

- Practice senior-level system design on real, end-to-end problems.
- Learn AI orchestration patterns (RAG, agentic workflows, gateway/eval)
  on owned infrastructure.
- Build a portfolio of self-contained projects (`projects/*`) that
  `git filter-repo` can extract into their own repos when they grow up.

## Current focus

Closing the platform on the gaps that block "one command, full cycle":

1. **Vault auto-unseal** from `.vault-secrets.env` — no more interactive
   key entry on every cluster restart. (ADR-0011)
2. **Bootstrap automation** — `scripts/bootstrap.sh` from kind-up to
   working cluster with everything reconciled. (ADR-0012)
3. **Justfile audit** — every command works, every common operation has
   one. (ADR-0013)
4. **Observability stack** — VictoriaMetrics + VictoriaLogs + Grafana,
   with Dex SSO for Grafana. (ADR-0014)

After the platform closes, the first real `projects/*` lands — likely
either a Backstage developer portal with golden-path scaffolders, or
the historical-articles AI writer (STORM / GraphRAG / LightRAG).

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
