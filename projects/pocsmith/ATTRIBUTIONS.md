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

_None yet — this section is populated as `roles/*.md` files are mined. Each
entry pairs a local file with its upstream source._

| Local file | Upstream source (SHA + path) | Modifications |
| ---------- | ---------------------------- | ------------- |
| _(pending)_ | _(pending)_ | _(pending)_ |

### Mining procedure

See `projects/pocsmith/roles/README.md` for the per-file checklist.

### Licence note

The upstream MIT licence permits derivative work including modification and
redistribution provided attribution is preserved. The `Modified from
upstream:` header at the top of each derived file plus this attribution
file together satisfy that obligation. The pocsmith project itself is also
MIT-licensed (see `pyproject.toml`).
