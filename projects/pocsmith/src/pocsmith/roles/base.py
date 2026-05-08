"""Role base class.

A `Role` wraps a parsed role file. It exposes typed metadata
(`frontmatter`), the system prompt (`system_prompt`), and a `run`
coroutine that the LangGraph state machine awaits.

The v0 `run` raises `NotImplementedError` deliberately. The Claude
Agent SDK transport, the structured-output validation, and the per-call
budget bookkeeping are landing in follow-up commits — keeping them out
of the scaffold makes the role-loading mechanism reviewable on its own.

Subclasses customise `run` to attach:
- a Claude Agent SDK client with role-specific allowed tools
- a pydantic output schema validated against the role's expected shape
- token bookkeeping that decrements the run budget

The base class is intentionally not a subclass-required pattern:
generic roles can use `Role` directly with `run` returning a string,
and only roles that need extra structure subclass.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from pocsmith.roles.frontmatter import RoleFrontmatter, parse_role_file


class Role:
    """A loaded role. Created via `Role.from_path(...)` or with explicit
    `frontmatter` and `body` arguments — the latter is mainly for tests.
    """

    def __init__(self, frontmatter: RoleFrontmatter, body: str, source_path: Path | None = None):
        self.frontmatter = frontmatter
        self._body = body
        self._source_path = source_path

    @classmethod
    def from_path(cls, path: Path | str) -> Role:
        """Load a role from a markdown file with YAML frontmatter.

        Validation is strict — see `parse_role_file`. Filename stem must
        equal `frontmatter.name` so a file rename can't silently
        diverge from the role's declared identity.
        """

        path = Path(path)
        frontmatter, body = parse_role_file(path)
        if path.stem != frontmatter.name:
            msg = (
                f"Role file {path} has filename stem '{path.stem}' but "
                f"frontmatter name '{frontmatter.name}'. Rename one or the other."
            )
            raise ValueError(msg)
        return cls(frontmatter=frontmatter, body=body, source_path=path)

    @property
    def name(self) -> str:
        return self.frontmatter.name

    @property
    def system_prompt(self) -> str:
        """The markdown body of the role file. Pass this verbatim as the
        Claude system prompt for any call this role makes.
        """

        return self._body

    @property
    def source_path(self) -> Path | None:
        """Path the role was loaded from, if any. Used in postmortems."""

        return self._source_path

    async def run(self, role_input: Any) -> Any:  # noqa: ARG002 — see docstring
        """Async entry point invoked by the LangGraph state machine.

        Not implemented in v0. Concrete reasoning subclasses or a
        single generic implementation backed by Claude Agent SDK lands
        in a follow-up commit. Raising `NotImplementedError` here makes
        any premature wiring fail loudly.
        """

        msg = (
            f"Role.run is not implemented in v0 (role={self.name!r}). "
            "See projects/pocsmith/README.md and ADR-0010."
        )
        raise NotImplementedError(msg)

    def __repr__(self) -> str:
        return f"Role(name={self.name!r}, scope={self.frontmatter.scope.value!r})"
