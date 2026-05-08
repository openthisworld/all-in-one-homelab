# Pocsmith — design archive

**Status: paused. Not under active development.** This document records the
full design intent so that future-us (or anyone reading the repo) can
either resume or formally retire the project with full context.

The currently-merged scaffold (`pyproject.toml`, `src/pocsmith/roles/`,
`roles/pm.md`, tests, ADR-0010) stays in main as a footprint. It is not
imported by anything else in the repo and not maintained on a regular
cadence. If `uv lock --upgrade` someday breaks against it, that is the
trigger to either rebuild it or delete the whole `projects/pocsmith/`
directory.

## Why pocsmith was conceived

The original problem statement: produce small, deployable proofs-of-concept
on the homelab cluster on demand, without the user writing the boilerplate
and without a long human-in-the-loop session per attempt. The user
describes what they want; an agent loop produces a working PoC packaged
as an ArgoCD-deployable artefact and opens a PR.

Five role specialists collaborate inside a CEO loop:

- **CEO** — the only role that talks to the human. Owns the brief, accepts
  or rejects each iteration's output, decides when to ship.
- **PM** — decomposes the CEO brief into a typed `TaskList` with
  EARS-format functional requirements and Given/When/Then acceptance
  criteria. Mined from `claude-skills` `feature-forge`.
- **Architect** — picks the technical shape: language, framework,
  k8s-manifest form, which platform services to wire to. Never
  implements.
- **Backend** — implements the code and the manifests. Mined from
  `claude-skills` `fullstack-guardian`.
- **QA** — runs tests (pytest, helm lint, kubectl dry-run) and reports
  pass/fail back to CEO. Mined from `claude-skills` `test-master`.

If a domain demands UI, a sixth **Frontend** role joins. Until then, CEO
accepts CLI / API / cron-only PoCs.

## Why pocsmith is paused

Two facts collided:

1. The user runs **Claude Code (CLI)** with the **`claude-skills` plugin**
   already loaded. That plugin ships 66 specialist skills including the
   exact upstream sources we planned to mine — `feature-forge`,
   `fullstack-guardian`, `test-master`, `code-reviewer`, `devops-engineer`.
2. Claude Code already has the **Task tool** (parallel sub-agent
   dispatch), persistent conversation state, and tool use. The primitives
   that LangGraph would orchestrate already exist in the CLI's runtime.

In other words: **the CEO is the human in front of Claude Code**, the
**roles are the skills auto-activated by claude-skills**, and the
**state machine is the conversation**. Building pocsmith on top of
this would be reimplementing tools the user already pays for under the
Pro plan.

What pocsmith would still uniquely give us:

- **Hands-off looping** — runs unattended for up to 30 min / $5 without
  the user having to keep the chat alive.
- **Hard cost cap** — per-run token / dollar / wallclock budget enforced
  by the runtime, not by self-discipline.
- **Persistent run state** — SQLite checkpoint per run, postmortems on
  abort, the ability to resume a stuck run on a different day.
- **Cron / GitHub-issue triggers** — run pocsmith as a daemon that
  watches a queue and produces PoCs without a human session.

None of these are pressing today. If they become pressing, the
"resume checklist" at the bottom of this doc is the entry point.

## Architecture (had it been built)

```
┌──────────────────────────────────────────────────────────────────┐
│                         pocsmith CLI                              │
│  uv run pocsmith run "<prompt>"  | resume <run-id> | status …    │
└───────────────────────────────┬──────────────────────────────────┘
                                │ Typer
                                ▼
                  ┌──────────────────────────┐
                  │   LangGraph state graph   │
                  │  (CEO loop, transitions)  │
                  └────────────┬──────────────┘
                               │ awaits Role.run()
       ┌───────┬───────┬───────┼───────┬───────┐
       ▼       ▼       ▼       ▼       ▼       ▼
     CEO     PM    Architect  Backend  QA   Shipper
      └──────────── Role base class ────────────┘
                           │
                           │ async query() via Claude Agent SDK
                           ▼
                  Anthropic API (Sonnet/Haiku)
                           │
                           ▼
                .state/<run-id>.sqlite (SQLModel)
                sandbox/pocs/<poc-name>/  (PoC artefacts)
                gh pr create              (final ship)
```

Sharp boundaries:

- LangGraph nodes are dumb wrappers that `await role.run(input)` and
  decide the next edge. They depend on no Claude API types.
- `Role` subclasses depend on `claude_agent_sdk` only. They depend on
  no LangGraph types.
- If LangGraph turns out to be too much abstraction, the state machine
  is replaceable with a hand-rolled typed class without touching the
  role layer. Reverse holds.

## Roles in detail

Each role is a markdown file under `projects/pocsmith/roles/<name>.md`
with strict YAML frontmatter (already implemented in
`pocsmith.roles.frontmatter`). The body is the system prompt sent on
every call.

| Role | Scope | Reads from CEO loop | Returns | Upstream source |
| --- | --- | --- | --- | --- |
| **CEO** | review | user prompt, role outputs | structured `accept / reject + feedback` | None — bespoke |
| **PM** | discovery | CEO brief, optional QA failure report | `TaskList` (typed, pydantic) | `feature-forge/SKILL.md` |
| **Architect** | architecture | `TaskList` + read-only repo view | `ArchitectureDecision` (manifest form, deps, services) | `architecture-designer` (claude-skills) |
| **Backend** | implementation | `ArchitectureDecision` + tasks | files written under `sandbox/pocs/<run-id>/` | `fullstack-guardian` |
| **QA** | review | run-dir + tasks | `QAReport` (pass / fail per task + traces) | `test-master` |
| **Shipper** | review | accepted run-dir | PR URL | None — bespoke |

The PM role is the only one mined and committed to the repo today
(`roles/pm.md`). If we resume, the others get one PR each, mining one
upstream skill per PR (the same cadence we used for PR #4).

## Hard caps and run budget

From ADR-0010, enforced in LangGraph (had it been built):

| Cap | Default | Why |
| --- | --- | --- |
| Outer-loop iterations | 8 | After this many CEO rejections, the brief is probably wrong, not the implementation |
| Total tokens per run | 2 000 000 | Roughly $4 at Sonnet pricing — bounds dollar cost |
| Wallclock | 30 min | Catches infinite tool-use loops |
| USD estimate | $5 | Belt-and-suspenders against pricing changes |

First cap to hit aborts the run with `RunStatus.aborted_capped`,
writes a postmortem to `.state/<run-id>.postmortem.md`, and exits.
Postmortem includes which cap fired, the role transcript up to that
point, and the cost breakdown by role.

## Output contract — what a "PoC" is

A directory at `<repo-root>/sandbox/pocs/<poc-name>/` containing:

```
sandbox/pocs/<poc-name>/
├── README.md            problem statement, what's inside, how to run
├── manifests/           ArgoCD Application manifest + Helm chart
│                        OR kustomize overlay; deployable as-is
├── src/                 the actual code
└── tests/               at least a smoke test QA could run
```

Pocsmith opens a PR titled `poc: <poc-name>` against the HomeLab repo.
The user reviews the PR — if it looks good, merge → ArgoCD reconciles →
PoC is live. **Pocsmith never runs `kubectl apply`**; that boundary is
deliberate per CLAUDE.md and is the safety belt against an autonomous
agent breaking the cluster.

PoCs that prove out graduate from `sandbox/pocs/` to a real
`projects/<name>/` in a separate, deliberate move done by the human.

## Operational interface (had it been built)

```bash
# Start a new run
uv run pocsmith run "a Slack bot that summarises GitHub PRs daily"

# List runs (live + finished)
uv run pocsmith status
# RUN ID    STATE        ROLE       COST      ELAPSED
# r-2026…   running      backend    $1.42     0:08:14
# r-2026…   accepted     -          $3.18     0:23:01

# Inspect one run
uv run pocsmith show r-2026-05-08-abc123
# (transcript, costs, role outputs, current state)

# Resume an aborted or paused run
uv run pocsmith resume r-2026-05-08-abc123

# Kill a stuck run
uv run pocsmith kill r-2026-05-08-abc123

# Print version (already implemented)
uv run pocsmith version
```

All commands are idempotent and resumable from SQLite checkpoints. The
only side effects outside of `.state/` and `sandbox/pocs/<run-id>/`
are the Claude API calls and the final `gh pr create`.

## File layout (intended end state)

```
projects/pocsmith/
├── .mise.toml              python + uv pinned
├── pyproject.toml          deps, ruff, pytest, mypy
├── README.md               project entry, points at this DESIGN
├── DESIGN.md               you are here
├── ATTRIBUTIONS.md         MIT mining record
├── src/pocsmith/
│   ├── __init__.py
│   ├── __main__.py         python -m pocsmith
│   ├── cli.py              Typer app
│   ├── roles/
│   │   ├── __init__.py
│   │   ├── base.py         Role base class    [implemented]
│   │   └── frontmatter.py  YAML schema        [implemented]
│   ├── runtime/
│   │   ├── graph.py        LangGraph state machine
│   │   ├── caps.py         Budget enforcement
│   │   └── postmortem.py   Abort writer
│   ├── transports/
│   │   └── claude.py       Claude Agent SDK glue
│   ├── types.py            TaskList, ArchitectureDecision, QAReport
│   └── shipper.py          gh PR creation
├── roles/
│   ├── README.md           role-file format     [implemented]
│   ├── ceo.md              bespoke
│   ├── pm.md               from feature-forge   [implemented]
│   ├── architect.md        from architecture-designer
│   ├── backend.md          from fullstack-guardian
│   └── qa.md               from test-master
├── tests/                  one test per non-trivial module
└── docs/                   pocsmith-specific notes (if any)
```

What is implemented today: ADR-0010, this DESIGN, the README, the
frontmatter schema + Role base class, the PM role file. Everything
else is deliberately unimplemented.

## Trade-offs vs Claude Code + claude-skills

| Concern | Pocsmith | Claude Code + skills |
| --- | --- | --- |
| Setup cost | Weeks of dev | Zero — already installed |
| Per-PoC cost | $5 cap | Pro-plan flat |
| Wall time | 30 min unattended | ~1 h interactive, but you steer |
| Failure modes | Hard-cap abort with postmortem | Conversation diverges, you redirect |
| Role coordination | Explicit state machine, persisted | Conversation history + Task tool |
| Cron / queue triggers | Yes, when implemented | No |
| User must be present | No | Yes |

Today's verdict: the unattended-cron axis is the only thing we'd build
pocsmith for. Until that need is concrete (e.g. "auto-generate a daily
PoC for one of last week's GitHub issues"), Claude Code is the better
tool by a wide margin.

## Resume checklist

If returning to active development, the smallest viable next steps in
order:

1. **Refresh dependency snapshot.** `cd projects/pocsmith && uv lock
   --upgrade && uv sync && uv run pytest`. If anything breaks, fix
   before adding new code — don't chain new bugs onto stale ones.
2. **Verify the upstream pinning.** `git -C /Users/vladosiv/github_ideas/claude-skills log -1`
   and update the upstream SHA recorded in role files / ATTRIBUTIONS
   if it has moved meaningfully.
3. **Implement `Role.run`** in a new module `transports/claude.py`,
   backed by the `claude_agent_sdk` async `query()`. Mock the
   transport in tests. Replace the v0 `NotImplementedError`.
4. **Define typed outputs** (`types.py`): `TaskList`, `ArchitectureDecision`,
   `QAReport`. Each role's `run` returns its declared type, validated
   by pydantic before being passed to the next role.
5. **Mine the remaining roles** one PR at a time: Architect, Backend,
   QA, plus a bespoke CEO and Shipper. Same pattern as PR #4.
6. **Build the LangGraph state graph** (`runtime/graph.py`) with
   conditional edges driven by CEO `accept/reject` and the cap
   enforcement.
7. **Wire the Shipper** to `gh pr create` with a templated PR body.
8. **End-to-end smoke**: a hard-coded brief ("write a hello-world
   FastAPI service deployable to the homelab cluster") that runs
   from `pocsmith run` to a green PR without human intervention.
   That smoke is the v1 ship gate.

Each step has a clear acceptance test. None of them require dropping
work in progress on the platform — pocsmith resumes are episodic, not
streaming.

## What would retire this design

If 6+ months pass and pocsmith remains paused, **delete the directory
and this design with it**. Living design archives that nobody intends
to revive accumulate confusion. The git history preserves the decision;
the repo should not.

The trigger for retirement: ADR-0010 logged as superseded, this
directory removed in a deliberate "retire pocsmith" PR, MISSION section
in README updated to drop the reference.
