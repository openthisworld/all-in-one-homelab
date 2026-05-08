# pocsmith

Agentic PoC factory. A CEO-led loop of role-based agents (PM, Architect,
Backend, QA) that produces small, deployable proofs-of-concept for the
HomeLab cluster.

The user describes what they want to try. Pocsmith iterates internally — PM
breaks it down, Architect sketches, Backend implements, QA verifies, CEO
accepts or sends back — until a working PoC is ready, then opens a PR
against the HomeLab repo with the artefacts under `sandbox/pocs/<name>/`.

See [ADR-0010](../../docs/adr/0010-pocsmith-agentic-poc-factory.md) for the
full architectural rationale, framework choices, and trade-offs. Read that
first.

## Status

**Paused.** Active development is on hold; the project remains in main as
a design archive. See [DESIGN.md](DESIGN.md) for the full intended
architecture, the rationale for pausing (Claude Code + `claude-skills`
plugin already covers most of the value), and a resume checklist.

The scaffold (`pyproject.toml`, role-loading machinery in `src/pocsmith/`,
`roles/pm.md` mined from upstream) is committed but not maintained on a
regular cadence. If `uv lock --upgrade` ever breaks against it, that is
the trigger to either rebuild from the resume checklist or retire the
project entirely.

## Layout

```
projects/pocsmith/
├── .mise.toml              # python + uv pinned, ADR-0010
├── pyproject.toml          # deps, ruff, pytest, mypy config
├── README.md               # you are here
├── ATTRIBUTIONS.md         # MIT mining from claude-skills (jeffallan)
├── src/pocsmith/           # the package
│   ├── __init__.py
│   ├── __main__.py         # `python -m pocsmith` entry
│   └── cli.py              # Typer app — `pocsmith run "<prompt>"`
├── roles/                  # role system prompts (markdown + frontmatter)
│   ├── ceo.md
│   ├── pm.md
│   ├── architect.md
│   ├── backend.md
│   └── qa.md
├── tests/
└── docs/                   # design notes specific to pocsmith
```

PoC outputs land in `sandbox/pocs/<poc-name>/` at the repo root, not inside
this project. See ADR-0010 § "Output contract".

## Toolchain

```bash
mise install   # picks up .mise.toml — installs python 3.13.2 + uv 0.5.x
uv sync        # creates .venv and installs deps from pyproject.toml + uv.lock
uv run pytest  # smoke tests
uv run ruff check src tests
uv run mypy
```

The first `uv sync` run creates `uv.lock`; commit it. Every subsequent
clone uses the locked versions.

## Running (placeholder, v0 not wired yet)

```bash
export ANTHROPIC_API_KEY=...
uv run pocsmith run "a Slack bot that summarises GitHub PRs daily"
```

Pocsmith will:

1. Spin up a run with a SQLite checkpoint at `.state/<run-id>.sqlite`.
2. Iterate the CEO loop — each role producing structured output.
3. On CEO acceptance, write the PoC directory under
   `<repo-root>/sandbox/pocs/<poc-name>/`.
4. Open a PR titled `poc: <poc-name>` against the HomeLab repo.

It will **not**:

- Run `kubectl apply` against the cluster. PRs only.
- Touch anything outside `sandbox/pocs/<run-id>/` during a run.
- Read secrets from Vault (manifests reference Vault paths; resolution
  happens at apply time via ESO).

Hard caps from ADR-0010 § "Loop semantics": 8 outer-loop iterations, 2 M
tokens, 30 min wallclock, $5 estimated cost. First cap hit aborts the run
with a postmortem.

## Mining from upstream

Role system prompts and the workflow DAG shape are derived from
[`jeffallan/claude-skills`](https://github.com/jeffallan/claude-skills)
(MIT). Each derived file carries a `Modified from upstream:` header and
is listed in [ATTRIBUTIONS.md](ATTRIBUTIONS.md).

Pocsmith is **not** a packaging of claude-skills. The skill files are
read at runtime as data; pocsmith is the runtime that drives them.

## Why a separate project (not part of the platform)

`projects/*` are self-contained per ADR-0002 — extractable to their own
repo when they grow up. Pocsmith does not belong in `platform/` because:

- It produces things that go into the platform; it is not part of it.
- It evolves independently and at a different cadence.
- It may eventually be useful outside this homelab — extraction path
  matters.

If pocsmith ever runs in-cluster (as v1 contemplates), it gets its own
ArgoCD `Application` and platform-services entry. That moment is
out of scope for v0.
