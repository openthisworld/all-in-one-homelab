"""Tests for `pocsmith.roles.base.Role`.

Covers loading from disk, the filename-vs-name invariant, and the v0
expectation that `run` raises `NotImplementedError` so any premature
wiring fails loudly.

The shipped `roles/pm.md` file is loaded as part of the fixture set —
that protects the role-mining pipeline from a regression that would
silently break every PM-driven run.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from pocsmith.roles import Role, RoleScope

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ROLES_DIR = PROJECT_ROOT / "roles"


def test_pm_role_file_loads() -> None:
    """The shipped `roles/pm.md` must load and have the pocsmith schema."""

    role = Role.from_path(ROLES_DIR / "pm.md")
    assert role.name == "pm"
    assert role.frontmatter.scope is RoleScope.discovery
    assert role.frontmatter.caps.max_tokens > 0
    # Mined role — must declare its source for ATTRIBUTIONS.md alignment.
    assert role.frontmatter.upstream_source is not None
    assert "feature-forge" in role.frontmatter.upstream_source
    # The body is the system prompt and must contain real guidance.
    assert "EARS" in role.system_prompt
    assert "acceptance" in role.system_prompt.lower()


def test_filename_must_match_frontmatter_name(tmp_path: Path) -> None:
    """If someone renames `pm.md` to `project-manager.md` without
    updating `name:`, loading must fail — silent divergence between
    filename and identity is the kind of bug that is impossible to
    debug six months later."""

    src = tmp_path / "totally-different-name.md"
    src.write_text(
        """---
name: pm
description: x
role: specialist
scope: discovery
caps:
  max_tokens: 100
---
body
""",
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="filename stem"):
        Role.from_path(src)


@pytest.mark.asyncio
async def test_run_is_not_implemented_in_v0() -> None:
    """v0 scaffold: `run` must raise so premature wiring fails fast.

    When the Claude Agent SDK transport lands, this test gets replaced
    by a transport-mocked happy path test in the same file.
    """

    role = Role.from_path(ROLES_DIR / "pm.md")
    with pytest.raises(NotImplementedError, match="not implemented in v0"):
        await role.run({"brief": "anything"})


def test_role_repr_includes_name_and_scope() -> None:
    role = Role.from_path(ROLES_DIR / "pm.md")
    rep = repr(role)
    assert "pm" in rep
    assert "discovery" in rep


def test_role_source_path_round_trips() -> None:
    path = ROLES_DIR / "pm.md"
    role = Role.from_path(path)
    assert role.source_path == path
