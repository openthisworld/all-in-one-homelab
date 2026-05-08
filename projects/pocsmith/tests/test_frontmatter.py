"""Tests for `pocsmith.roles.frontmatter`.

Cover the structural-error paths (no fence, unclosed fence, non-mapping
yaml, empty body) and the schema-validation paths (missing required
fields, unknown scope, zero or negative caps). These all feed into
`Role.from_path`, so a regression here breaks every role file at load.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from pydantic import ValidationError

from pocsmith.roles.frontmatter import (
    RoleCaps,
    RoleFrontmatter,
    RoleScope,
    parse_role_file,
)


@pytest.fixture
def tmp_role(tmp_path: Path):
    """Write a role file in `tmp_path` and return its path."""

    def _write(content: str, name: str = "sample.md") -> Path:
        path = tmp_path / name
        path.write_text(content, encoding="utf-8")
        return path

    return _write


def test_minimal_valid_role_parses(tmp_role) -> None:
    path = tmp_role(
        """---
name: pm
description: A PM role.
role: specialist
scope: discovery
caps:
  max_tokens: 1000
  max_iterations: 1
---

# Body

This is the system prompt body.
"""
    )
    fm, body = parse_role_file(path)
    assert fm.name == "pm"
    assert fm.scope is RoleScope.discovery
    assert fm.caps.max_tokens == 1000
    assert fm.caps.max_iterations == 1
    assert body.startswith("# Body")
    assert fm.upstream_source is None


def test_extra_frontmatter_fields_are_preserved(tmp_role) -> None:
    """Upstream `claude-skills` files include `metadata.author`, `version`,
    `triggers`, etc. We allow extras so a mined file's audit trail stays
    intact even if its frontmatter shape predates pocsmith's schema.
    """

    path = tmp_role(
        """---
name: pm
description: Mined.
role: specialist
scope: discovery
caps:
  max_tokens: 1000
upstream_source: jeffallan/claude-skills/skills/feature-forge/SKILL.md
metadata:
  author: https://github.com/Jeffallan
  version: "1.1.0"
triggers: requirements, specs
---
body
"""
    )
    fm, _ = parse_role_file(path)
    assert fm.upstream_source.endswith("feature-forge/SKILL.md")
    # extras land on model_extra (pydantic v2)
    assert fm.model_extra is not None
    assert "metadata" in fm.model_extra


def test_missing_opening_fence_rejected(tmp_role) -> None:
    path = tmp_role("name: pm\nscope: discovery\n")
    with pytest.raises(ValueError, match="must start with a YAML frontmatter fence"):
        parse_role_file(path)


def test_unclosed_fence_rejected(tmp_role) -> None:
    path = tmp_role(
        """---
name: pm
description: x
role: specialist
scope: discovery
caps:
  max_tokens: 100

(no closing fence)
"""
    )
    with pytest.raises(ValueError, match="not closed"):
        parse_role_file(path)


def test_unknown_scope_rejected(tmp_role) -> None:
    path = tmp_role(
        """---
name: pm
description: x
role: specialist
scope: nonsense
caps:
  max_tokens: 100
---
body
"""
    )
    with pytest.raises(ValueError, match="failed validation"):
        parse_role_file(path)


def test_zero_max_tokens_rejected(tmp_role) -> None:
    path = tmp_role(
        """---
name: pm
description: x
role: specialist
scope: discovery
caps:
  max_tokens: 0
---
body
"""
    )
    with pytest.raises(ValueError, match="failed validation"):
        parse_role_file(path)


def test_empty_body_rejected(tmp_role) -> None:
    path = tmp_role(
        """---
name: pm
description: x
role: specialist
scope: discovery
caps:
  max_tokens: 100
---

"""
    )
    with pytest.raises(ValueError, match="empty body"):
        parse_role_file(path)


def test_non_mapping_frontmatter_rejected(tmp_role) -> None:
    path = tmp_role(
        """---
- this
- is
- a list
---
body
"""
    )
    with pytest.raises(ValueError, match="must be a mapping"):
        parse_role_file(path)


def test_role_caps_default_max_iterations() -> None:
    caps = RoleCaps(max_tokens=100)
    assert caps.max_iterations == 1


def test_role_frontmatter_requires_caps() -> None:
    with pytest.raises(ValidationError):
        RoleFrontmatter(name="pm", description="x", role="specialist", scope=RoleScope.discovery)
