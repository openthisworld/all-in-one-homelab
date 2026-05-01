# 1. Record architecture decisions

Date: 2026-05-02

## Status

Accepted

## Context

We are making non-trivial architectural decisions in this homelab — IaC tooling, CNI, GitOps strategy, observability stack, AI gateway placement, repo strategy. Even as a personal project, decisions accumulate context that is non-obvious in the code (why OpenTofu instead of Terraform, why VictoriaMetrics instead of Prometheus, why Ollama on the host instead of in the cluster). Without a record, a future revisit — by me or by Claude — will re-litigate decisions that were already settled, potentially undoing them by accident.

## Decision

We will use Architecture Decision Records, in the format described by Michael Nygard in [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

Each ADR is a short markdown file under `docs/adr/`:
- Filename: `NNNN-kebab-case-title.md`, sequentially numbered.
- Sections: Status, Context, Decision, Consequences.
- One screen ideally; never longer than two.
- Status values: `Proposed`, `Accepted`, `Deprecated`, `Superseded by NNNN`.

Decisions get an ADR when they:
- Lock in a tool choice that would be expensive to reverse (CNI, IaC tool, observability stack).
- Make a deliberate trade-off that is not obvious from reading the code (e.g., choosing the lighter component because of RAM constraints).
- Diverge from a common default (Ollama on host, not in cluster).

Routine code or config does NOT get an ADR. The rule of thumb: if I'd be surprised to find this decision reversed in three months, write an ADR.

## Consequences

- All non-trivial decisions are discoverable in one place, in chronological order.
- New ADRs supersede old ones explicitly — old ADRs are kept (not deleted) so the history of thinking is preserved.
- Claude is instructed (via `CLAUDE.md`) to read `docs/adr/` before deviating from a committed architecture choice.
- Lightweight enough that the friction does not discourage writing them.
