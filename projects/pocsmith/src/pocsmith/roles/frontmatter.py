"""Pydantic schema for role-file frontmatter.

The role files (`projects/pocsmith/roles/*.md`) start with a YAML
frontmatter block, then a markdown body that serves as the system
prompt. This module defines the typed shape of that frontmatter and
the parsing helpers that turn a file path into a `(frontmatter, body)`
pair.

Validation is strict on purpose: a missing `caps` field or an unknown
`scope` value should fail at load time, before any LLM call burns
tokens, not at run time. The caps in particular feed into the global
run budget enforced by the LangGraph state machine — silent defaults
would hide budget creep.
"""

from __future__ import annotations

from enum import StrEnum
from pathlib import Path

import yaml
from pydantic import BaseModel, Field, ValidationError


class RoleScope(StrEnum):
    """Vocabulary for what phase of the CEO loop a role contributes to.

    Mirrors the pocsmith taxonomy from ADR-0010, deliberately narrower
    than upstream `claude-skills` (which uses scope values like
    `analysis`, `optimization`, etc. that don't map cleanly to the
    CEO loop stages).
    """

    discovery = "discovery"
    architecture = "architecture"
    implementation = "implementation"
    review = "review"


class RoleCaps(BaseModel):
    """Per-role budget caps. Sum of role caps is bounded by the run cap
    in `pocsmith.runtime` — see ADR-0010 § 'Loop semantics and hard caps'.
    """

    max_tokens: int = Field(gt=0, description="Hard cap on tokens this role may consume per call.")
    max_iterations: int = Field(
        ge=1,
        default=1,
        description="How many times the CEO loop may re-enter this role in a single run.",
    )


class RoleFrontmatter(BaseModel):
    """Typed shape of the YAML block at the top of a role file.

    Extra fields are allowed — when mining from upstream `claude-skills`,
    the original frontmatter contains `metadata.author`, `version`,
    `triggers`, `related-skills` etc. Pocsmith does not depend on
    those, but they are preserved verbatim in the file so the
    `Modified from upstream:` audit trail stays intact.
    """

    model_config = {"extra": "allow"}

    name: str = Field(min_length=1, description="Role identifier (matches the filename stem).")
    description: str = Field(min_length=1)
    role: str = Field(min_length=1, description="Free-form role designation, e.g. 'specialist'.")
    scope: RoleScope
    caps: RoleCaps
    upstream_source: str | None = Field(
        default=None,
        description="If derived from another work, the upstream source path. "
        "Required for entries in ATTRIBUTIONS.md.",
    )


def _split_frontmatter(text: str) -> tuple[str, str]:
    """Split a markdown file with YAML frontmatter into (yaml_block, body).

    The frontmatter block is fenced by a `---` line at the very top of
    the file and another `---` line on its own. Any other shape raises
    `ValueError`.
    """

    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\n") != "---":
        msg = "Role file must start with a YAML frontmatter fence ('---')."
        raise ValueError(msg)

    closing_idx: int | None = None
    for idx, line in enumerate(lines[1:], start=1):
        if line.rstrip("\n") == "---":
            closing_idx = idx
            break
    if closing_idx is None:
        msg = "Role file frontmatter is not closed by a '---' fence."
        raise ValueError(msg)

    yaml_block = "".join(lines[1:closing_idx])
    body = "".join(lines[closing_idx + 1 :]).lstrip("\n")
    return yaml_block, body


def parse_role_file(path: Path) -> tuple[RoleFrontmatter, str]:
    """Read a role file and return (validated frontmatter, body).

    Raises `ValueError` for structural problems and
    `pydantic.ValidationError` for schema violations.
    """

    text = path.read_text(encoding="utf-8")
    yaml_block, body = _split_frontmatter(text)
    try:
        data = yaml.safe_load(yaml_block) or {}
    except yaml.YAMLError as exc:
        msg = f"Invalid YAML frontmatter in {path}: {exc}"
        raise ValueError(msg) from exc

    if not isinstance(data, dict):
        msg = f"Frontmatter in {path} must be a mapping, got {type(data).__name__}."
        raise ValueError(msg)

    try:
        frontmatter = RoleFrontmatter.model_validate(data)
    except ValidationError as exc:
        msg = f"Frontmatter in {path} failed validation: {exc}"
        raise ValueError(msg) from exc

    if not body.strip():
        msg = f"Role file {path} has empty body — the body is the system prompt."
        raise ValueError(msg)

    return frontmatter, body
