# Release notes template

Copy this block into `CHANGELOG.md` under a new `[X.Y.Z] — YYYY-MM-DD` heading,
above the previous release. Drop sections that have no entries — empty headings
are noise.

The convention is **Keep a Changelog**: human-written, terse, present-tense,
each bullet stands alone (no "see also" chains).

---

```markdown
## [X.Y.Z] — YYYY-MM-DD

One- or two-sentence framing of what this release is about. State whether
bootstrap is still needed, whether anything user-facing changed, whether a
breaking change to runbooks is included.

### Added

- New components, ADRs, scripts, ArgoCD Applications, Justfile targets.
  Be specific — name the file/path so a reader can navigate without git log.

### Changed

- Behaviour or interface changes to existing components. Include the
  user-visible impact in plain English (not just a chart version bump).

### Deprecated

- Things still working but slated for removal in a future release.
  Name the replacement and the target version.

### Removed

- Files, ADRs (rare — usually amended, not removed), Justfile targets.

### Fixed

- Bug fixes. Lead with the symptom, then the cause, then the fix —
  same shape as the v0.0.1 Dex entry.

### Security

- CVEs, secret exposure remediations, RBAC tightening, anything that
  would matter if this were a real production system.

### Known issues / follow-ups

- Things deliberately not done in this release. Pin them here so the next
  release knows what's still on the table.
```

---

## Conventions

- **Date format:** ISO 8601 (`YYYY-MM-DD`).
- **Past tense in headings, present tense in bullets:** `### Added` then "Adds X" or just "X". Match existing entries.
- **Link to ADRs and file paths,** not commit hashes — readers shouldn't need git to understand a release.
- **Drop empty sections.** No `### Security: nothing to report here.`
- **One bullet per change,** even if several files are touched. Combine related items rather than listing each file.
- **Update the comparison links** at the bottom of `CHANGELOG.md` after adding a new section:
  ```
  [Unreleased]: https://github.com/openthisworld/all-in-one-homelab/compare/vX.Y.Z...HEAD
  [X.Y.Z]: https://github.com/openthisworld/all-in-one-homelab/compare/vPREV...vX.Y.Z
  ```
- **Move from `[Unreleased]`,** don't write new entries directly into the dated section — `[Unreleased]` is the working buffer between releases.

## What is NOT a changelog entry

- Internal refactors with no user-visible effect.
- Doc typos or formatting fixes.
- Changes to this template.
- CI / pre-commit hook updates that don't change the contributor workflow.

If in doubt, ask: would a future-you reading this 6 months from now care?
If no — leave it out.
