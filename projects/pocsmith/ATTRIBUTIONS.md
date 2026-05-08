# Attributions

Pocsmith's role definitions and workflow shape are derived from open-source
work. This file lists each upstream source, the licence, and what was taken.

## claude-skills (jeffallan)

- **Repository**: https://github.com/jeffallan/claude-skills
- **Licence**: MIT
- **Author**: jeffallan
- **What we use**: role frontmatter taxonomy (domain / role / scope /
  output-format), workflow DAG shape, skill-validation script pattern, and
  individual role system prompts (PM, Backend, QA reviewer, etc.)

### Specific files derived (kept in sync as roles are added)

Each entry pairs a local file with its upstream source. Modifications are
summarised here; full per-file detail lives in the `Modified from upstream:`
header at the top of each derived file.

| Local file | Upstream (SHA + path) | Modifications |
| ---------- | --------------------- | ------------- |
| `roles/pm.md` | `5e8b6b8` `skills/feature-forge/SKILL.md` | Removed `AskUserQuestions` tool guidance (PM is invoked agent-to-agent, not interactively); removed PM-Hat/Dev-Hat split (Architect and QA cover those); tightened output to a typed `TaskList` schema; inlined EARS + acceptance-criteria conventions (replaces upstream `references/`). |

### Mining procedure

See `projects/pocsmith/roles/README.md` for the per-file checklist.

### Licence note

The upstream MIT licence permits derivative work including modification and
redistribution provided attribution is preserved. The `Modified from
upstream:` header at the top of each derived file plus this attribution
file together satisfy that obligation. The pocsmith project itself is also
MIT-licensed (see `pyproject.toml`).
