# 2. Monorepo with per-project extraction path

Date: 2026-05-02

## Status

Accepted

## Context

The homelab will host:
- Platform infrastructure (cluster bootstrap, GitOps manifests, observability, databases, AI gateway).
- A growing collection of learning projects under `projects/*` — initially small experiments, some of which may mature into standalone systems worth their own repository (and possibly public release).

Three structural options were considered:

1. **One repo per concern.** Separate repos for platform, each project, ADRs. Ergonomic for extraction but adds friction every time a project is created (new repo, new CI, new local clone). Discourages experimentation.
2. **Monorepo with git submodules.** Each project as a submodule. Submodules are notoriously fragile — checkouts get out of sync, contributors miss `--recursive`, history rewrites are awkward. The historical pain is well-documented.
3. **Monorepo with extraction path.** A single repo where every `projects/*` directory is structured to be self-contained: its own README, `.mise.toml`, infra, dependencies. When a project matures, `git filter-repo --subdirectory-filter projects/<name>` extracts it into a new repo with full history preserved.

Option 3 gives us monorepo ergonomics today (one clone, one `mise install`, one ADR set, one CI surface) and preserves the option to spin out mature projects later without repo-level lock-in.

## Decision

Use a single Git repository for the entire homelab. Enforce the following discipline so that extraction stays cheap:

- `projects/<name>/` is self-contained. It owns its `README.md`, `.mise.toml`, `infra/`, `src/`, tests, etc.
- A project does not import code from other projects. Cross-project sharing happens only via published artifacts (container images, Helm charts) — not via relative file paths.
- Project-specific ADRs live in `projects/<name>/docs/adr/`, not in the root `docs/adr/`. Root ADRs are about the homelab as a whole.
- The platform stack (`platform/*`) is shared infrastructure and is **not** intended for extraction. Projects consume it but do not own it.

## Consequences

- One clone, one toolchain installation, one set of pre-commit hooks. Lower friction to start a new experiment.
- ADRs and learning notes accumulate in one searchable location.
- Cross-project refactoring stays atomic in a single commit.
- **Trade-off:** repo size grows over time. Monitored — if `du -sh .git` becomes problematic (>1 GiB), revisit (likely by extracting the largest mature projects).
- **Discipline cost:** must consciously avoid cross-project imports. Easy to violate accidentally; flagged in code review (and by the `iac-reviewer` subagent).
- **Extraction path verified:** `git filter-repo --subdirectory-filter projects/<name>` is the documented escape hatch. We do not actually run it until a project is genuinely ready to leave.
