# Claude operating instructions for HomeLab

This file is the constitution for Claude Code in this repository. Read it on every session.

## Context

- **Owner profile**: DevOps engineer, strong AWS / Terraform / EKS background. Goal of this repo is growing toward senior level via real system-design exercises and AI orchestration practice.
- **Hardware**: Mac mini M4, 16 GB RAM. Memory is the binding constraint — every component added to the cluster must justify its footprint.
- **Hosting**: Everything local. No cloud. Docker Desktop on macOS.
- **Claude plan**: Pro. Default to Sonnet. Use Opus only for genuinely architectural / multi-file design work.

## Communication

- **Speak Ukrainian to the user**. Code, configs, comments, commit messages, docs — English.
- Be concise. The owner knows DevOps fundamentals — do not explain what a pod, namespace, CRD, or PVC is.
- Correct technical mistakes the user makes. Do not flatter or hedge to be polite.
- When a choice is non-obvious, present 2–3 options with trade-offs and ask which to pick. Don't decide silently.

## Architecture decisions in force

These are committed. Don't deviate without proposing an ADR update first.

- **IaC**: OpenTofu (`tofu` CLI), not Terraform.
- **Toolchain manager**: `mise` with `.mise.toml` per project, exact-pinned versions.
- **Local cluster**: `kind`, 1 control + 2 workers, **Cilium** as CNI from day one (`disableDefaultCNI: true`).
- **GitOps**: ArgoCD with App-of-Apps. Everything past `platform/bootstrap/` is reconciled by ArgoCD.
- **Observability**: VictoriaMetrics + VictoriaLogs + Grafana (NOT Prometheus + Loki — RAM budget).
- **In-cluster data**: CloudNativePG, Redis (Bitnami), Qdrant, MinIO.
- **AI gateway**: LiteLLM in-cluster. **Ollama runs on the macOS host**, not in the cluster — proxied via `host.docker.internal:11434`.
- **Repo strategy**: Monorepo with extraction path. `projects/*` are self-contained so `git filter-repo` can spin them out later. No git submodules.

When in doubt, read `docs/adr/`.

## When to ask before acting

Always ask before:

- `tofu apply`, `tofu destroy`, `terraform apply`
- `kubectl delete`, `helm uninstall`
- `kind delete cluster`, `docker system prune`
- Installing system-level dependencies (`brew install`, global npm, system Python packages)
- Creating GitHub repositories, pushing to remote, opening PRs
- Modifying anything outside the current working directory (e.g., `~/.kube/config`, shell rc files)
- Deleting or rewriting more than ~30 lines of existing code in one shot

Read-only is fine without asking: `kubectl get/describe/logs`, `helm list/status`, `tofu plan`, `git status/diff/log`, `mise ls`, `docker ps`, `gh pr list`.

## Forbidden patterns

- **Never read** `.env*`, `*.tfstate`, `*.tfstate.backup`, anything in `secrets/`, `~/.kube/config`, `~/.aws/`, `~/.ssh/`. These are blocked in `.claude/settings.json` — don't try to work around it.
- **Never commit** secrets, kubeconfig, plaintext credentials. The `.gitignore` and `gitleaks` pre-commit hook back this up — but don't rely on them.
- **Never use** `kubectl apply -f` against the cluster for anything that should live in `platform/gitops/applications/`. If it belongs in GitOps, write the Application manifest and let ArgoCD reconcile.
- **Never auto-bump** pinned versions in `.mise.toml` or Helm charts in passing. Version changes are deliberate and get their own commit + ADR if material.
- **Never use** `kubectl create` imperatively for production-shaped resources. Imperative is OK in `sandbox/` only.

## Documentation discipline

- **ADR per non-trivial decision**. Nygard format: Context / Decision / Consequences. Short — one screen ideally. Number monotonically in `docs/adr/`.
- **Every project under `projects/`** has its own README and `.mise.toml`. Treat each as if it might be extracted next week.
- **Learning notes** for material insights go in `docs/learning-notes/`. Not a journal — write only when the lesson generalizes.
- **System-design write-ups** in `docs/system-designs/` follow a fixed template: requirements → constraints → high-level → deep-dives → trade-offs → what I'd revisit.

## Memory budget reminders

When proposing a new in-cluster component, state its expected RSS in the proposal. Components above ~500 MiB RSS need a justification or an on-demand sync wave (start opted-out, enable manually).

Watch combined load: cluster + Ollama on host + Docker Desktop + IDE + browser. Easy to OOM the Mac. If memory pressure shows up, the first lever is scaling down replicas or pausing the AI stack, not killing observability.

## Tooling specifics

- Justfile is the entry point for repeatable commands. Prefer adding a `just` target over a one-off shell script.
- Pre-commit runs on every commit (`pre-commit install` once per clone). Don't `--no-verify` past failures — fix them.
- `tofu fmt` and `terraform fmt` are interchangeable for formatting `.tf` files; use `tofu` everywhere else.
