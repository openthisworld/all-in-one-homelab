# Roles

Each role is a markdown file with YAML frontmatter, mirroring the
[claude-skills](https://github.com/jeffallan/claude-skills) `SKILL.md`
format so that mining specific role-prompts from upstream stays
mechanical (drop file in, fix the `Modified from upstream:` header,
adjust scope to pocsmith's role taxonomy).

## File shape

```yaml
---
name: pm
description: >
  Decomposes a CEO-set goal into an ordered list of tasks the implementing
  roles can act on. Surfaces ambiguities back to the CEO before
  decomposition rather than guessing.
role: specialist        # see ADR-0010 for taxonomy
scope: discovery        # discovery | architecture | implementation | review
inputs:
  - ceo_brief: str      # CEO-approved goal, includes constraints
outputs:
  - tasks: list[Task]   # pydantic-validated structured output
caps:
  max_tokens: 30000
  max_iterations: 1
upstream_source: jeffallan/claude-skills/skills/feature-forge/SKILL.md
---

# PM role

[free-form markdown — the body is the system prompt]
```

The frontmatter is loaded by `pocsmith.roles.load_role()` (not yet
implemented) and used to:

- Set per-role token caps that feed into the global run budget.
- Validate the role's structured output against the declared `outputs`
  pydantic schema.
- Render attribution chains in run postmortems.

## Initial roster (v0)

Each will get a real file in a follow-up commit. Marked here so the
plan is visible:

- `ceo.md` — accepts/rejects iteration outputs, owns success criteria
- `pm.md` — decomposes goal into tasks
- `architect.md` — picks the shape (k8s manifests, Helm chart, language)
- `backend.md` — implements server-side code
- `qa.md` — writes tests, runs them, reports pass/fail back to CEO

`frontend.md` joins in v1 when a PoC needs UI; until then CEO accepts
backend-only or CLI PoCs.

## Mining checklist

When pulling a role from `claude-skills`:

1. Copy the source `SKILL.md` into this directory under the pocsmith
   role name (e.g., `feature-forge/SKILL.md` → `roles/pm.md`).
2. Add `Modified from upstream:` header on the first line of the body
   referencing the upstream commit SHA.
3. Adjust the frontmatter `scope` to pocsmith's vocabulary
   (`discovery | architecture | implementation | review`).
4. Replace the upstream `metadata.role` (e.g., `specialist`) only if
   our taxonomy disagrees — usually it lines up.
5. Add the file to `ATTRIBUTIONS.md` at the project root.
6. Verify the role produces structured output (pydantic model) — if
   not, add a "Return JSON matching `<ModelName>`" instruction at the
   end of the body.
