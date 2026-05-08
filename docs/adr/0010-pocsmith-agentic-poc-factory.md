# 10. Pocsmith — agentic PoC factory in `projects/pocsmith`

Date: 2026-05-08

## Status

Proposed

## Context

The platform is the substrate. The point of having a substrate is to put real
projects on it. The first project is a system that produces small, in-cluster
proof-of-concepts on demand: the user describes what they want to try
("a Slack bot that summarises GitHub PRs", "a vector-search demo over my
notes"), and the system delivers something deployable to this homelab cluster
without the user writing the boilerplate.

The system is not a chat assistant. It is an **agent loop with role-based
specialists**: a CEO sets goals and accepts/rejects work, a PM decomposes
goals into tasks, an Architect picks the shape, Backend/Frontend specialists
implement, QA verifies. The loop continues until the CEO accepts a working
PoC. The accepted PoC is then handed to the human user (the actual user, who
is the customer of this internal team) to play with in the cluster.

Two orthogonal capabilities are needed to build this:

1. **Per-agent reasoning + tool use** — each role needs to be a Claude
   instance with a focused system prompt and access to a defined toolset
   (read repo, write files, run tests, kubectl probe, etc.).
2. **Cross-agent orchestration** — explicit state, deterministic transitions
   ("if QA fails, return to Backend"), checkpoints, and an approval gate
   the CEO controls.

Frameworks considered:

- **Claude Agent SDK alone** — solves (1) elegantly. The orchestration story
  is whatever you build with subagents and message passing. Maximum learning,
  most code.
- **CrewAI** — opinionated role/task abstraction. Solves (1) and (2) at the
  cost of locking us to its mental model and its abstraction over the API.
- **LangGraph** — explicit graph-of-states orchestration. Solves (2)
  excellently. Each node can call any LLM provider — solves (1) by being
  agnostic, but doesn't give Claude-specific niceties (tool use ergonomics,
  citation handling, prompt caching coordination).
- **Hybrid: Claude Agent SDK + LangGraph** — Claude Agent SDK runs the
  inside of each role (tools, context, prompts). LangGraph runs the outside
  (CEO loop, transitions, persisted state, retries). Each tool stays in
  the layer where it is strongest.

The hybrid path is more code than CrewAI, but the boundaries are sharp:
LangGraph nodes are dumb wrappers that call into a `Role` class implemented
on Claude Agent SDK. The two libraries do not fight each other — one owns
state, the other owns reasoning.

## Decision

### Project layout and tooling

- New self-contained project at `projects/pocsmith/` (per ADR-0002, ready for
  extraction to its own repo if it grows up).
- **Python 3.12**, pinned in `projects/pocsmith/.mise.toml`.
- **uv** as the dependency manager (modern, fast, lockfile-based; no Poetry,
  no pip-tools). Project metadata in `pyproject.toml`, lock in `uv.lock`.
- Core deps: `claude-agent-sdk`, `langgraph`, `pydantic`, `typer` (CLI),
  `rich` (output), `sqlmodel` (state persistence). Test stack: `pytest`,
  `pytest-asyncio`. Lint/format: `ruff`.
- Entry point: `python -m pocsmith` (CLI built with Typer).

### Architecture

```
                         ┌──────────────────────────────┐
                         │   LangGraph state machine    │
 user prompt ──→  CEO   ─┤  (intake → plan → execute    │
                         │   → review → ship │ retry)   │
                         └──────────────────────────────┘
                                    │
                  ┌─────────────────┼─────────────────┐
                  ↓                 ↓                 ↓
           ┌──────────┐      ┌──────────┐      ┌──────────┐
           │   PM     │      │ Backend  │      │   QA     │
           │ (CASDK)  │      │ (CASDK)  │      │ (CASDK)  │
           └──────────┘      └──────────┘      └──────────┘
                                    │
                                    ↓
                        sandbox/pocs/<poc-name>/
                        ├── README.md
                        ├── manifests/  (k8s manifests / Helm chart)
                        ├── src/        (PoC code)
                        └── tests/
```

- **LangGraph** owns the cycle: nodes for each phase, conditional edges
  ("CEO accepts? → ship; otherwise → re-plan"), persistent checkpoints in
  SQLite (`projects/pocsmith/.state/<run-id>.sqlite`), and timeouts.
- **Claude Agent SDK** owns each role: a `Role` base class with a system
  prompt loaded from a markdown file under `projects/pocsmith/roles/`, a
  declared tool surface (read/write within a sandboxed work dir, run
  shell, query Vault read-only, etc.), and a `run(input) → output`
  signature that LangGraph nodes await.
- **Roles to ship in v0**: CEO, PM, Architect, Backend, QA. Frontend role
  is added in v1 once a PoC needs UI; until then the CEO accepts
  backend-only or CLI PoCs.

### Output contract — what is a "PoC"

A PoC is a directory under `sandbox/pocs/<poc-name>/` (per CLAUDE.md,
sandbox is the right place for ad-hoc work) containing:

- `README.md` — problem statement, what's inside, how to run
- `manifests/` — either an ArgoCD `Application` manifest or a kustomize
  overlay or a Helm chart, deployable to the homelab cluster
- `src/` — the actual code
- `tests/` — at least a smoke test that QA can run

The human user reviews this directory, optionally `kubectl apply -f` (or
adds an Application to `platform/gitops/applications/` if it earns that
status), and tests the PoC in the running cluster. PoCs that prove out
graduate to `projects/<name>/` in a separate, deliberate move.

### Loop semantics and hard caps

The CEO loop must terminate. Caps enforced in LangGraph:

- **Max iterations**: 8 outer-loop cycles per run.
- **Max tokens**: tracked across all role calls; default 2 M tokens / run.
- **Max wallclock**: 30 min / run.
- **Max cost**: estimated USD cap from per-model pricing × token count;
  default $5 / run.

Hitting any cap aborts the run with a `RunStatus.aborted_capped` and
writes a postmortem to `.state/<run-id>.postmortem.md`. The user reads
the postmortem, decides whether to lift caps and resume or kill the run.

### Approval gates

- **Internal**: CEO accepts/rejects each iteration's output. Implemented
  as a LangGraph conditional edge driven by the CEO role's structured
  output (`{accepted: bool, feedback: str}`).
- **External (human)**: Pocsmith does not deploy anything to the cluster
  on its own. It opens a PR against the HomeLab repo with the PoC
  directory and an ArgoCD `Application` manifest. The user reviews,
  merges, and lets ArgoCD reconcile. **No autonomous `kubectl apply`.**

### Mining from `claude-skills`

The MIT-licensed `claude-skills` repo (jeffallan) is mined for:

- Role/domain/scope frontmatter taxonomy
- Workflow DAG shape (`commands/workflow-manifest.yaml`)
- Skill validation script (`scripts/validate-skills.py`)
- Specific role definitions to seed CEO/PM/Backend/QA system prompts
  (e.g., `feature-forge` for PM, `fullstack-guardian` for Backend,
  `test-master` for QA, `code-reviewer` for inner-loop review)

Each adopted file is preserved with its MIT license header and listed in
`projects/pocsmith/ATTRIBUTIONS.md`. Modifications are explicit (a
"Modified from upstream:" header at the top of each derived file).

### Where pocsmith runs

- **v0**: locally on the Mac mini, invoked via CLI (`uv run pocsmith run "<prompt>"`).
- **v1**: containerised, deployable as an ArgoCD Application in the
  cluster, with a Backstage frontend that triggers runs and shows status.
  Out of scope for this ADR; will get its own ADR when we get there.

## Consequences

- A real Python project enters the monorepo at `projects/pocsmith/`. Adds
  ~50–100 MiB of node + venv weight on disk; not in-cluster RAM yet.
- Claude API spend becomes a real (not zero) line item. Hard caps and a
  postmortem-on-abort make the worst case a $5 misfire, not a $500 one.
- Learning two libraries simultaneously is the explicit goal. Trade-off
  is more lines of glue code than a CrewAI-only path. Acceptable.
- PoCs land as PRs, not as live deployments. Slower than full autonomy;
  matches the "no autonomous changes to the cluster" rule from CLAUDE.md.
- The roles' system prompts are derived work from `claude-skills`. We
  honour the MIT license; users of pocsmith (currently: just you) get
  the full attribution chain in `ATTRIBUTIONS.md`.
- The `.state/` directory holds run history with prompts, outputs, and
  costs. It is gitignored — runs are local artefacts, not repo content.
  When a PoC graduates, only the PoC directory is committed, not the
  reasoning trace.
- Future-proofing: if LangGraph proves to be too much abstraction, the
  state machine can be replaced with a hand-rolled typed state class
  without touching the role layer (the role layer is pure Claude Agent
  SDK and depends on no LangGraph types). The reverse is also true.

## Open questions to revisit before v0 ships

- **Tool surface for roles**: how broad? Read-only on the HomeLab repo
  is safe; write access is risky (a role could commit garbage). Initial
  rule: roles write only to `sandbox/pocs/<run-id>/`, not to the rest
  of the repo. PR creation is an explicit final-step action by a
  dedicated `Shipper` role.
- **Vault access**: should agents read from Vault to know what services
  are available (e.g., postgres connection)? For v0: no — pocsmith
  generates manifests that reference Vault paths but never sees secrets.
- **Eval rubric**: how do we measure if pocsmith is actually getting
  better? Tracked in a follow-up ADR after v0 ships and we have data.
