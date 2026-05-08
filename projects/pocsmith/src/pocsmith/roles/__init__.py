"""Role definitions for the pocsmith CEO loop.

Each role is a markdown file under `projects/pocsmith/roles/` with YAML
frontmatter that declares the role's name, scope, caps, and (when mined
from upstream) the source it was derived from. The frontmatter is
parsed by `pocsmith.roles.frontmatter.RoleFrontmatter`; the body is the
system prompt.

The `Role` base class wraps a parsed role file and exposes:

- `frontmatter`        — typed metadata
- `system_prompt`      — the markdown body, ready to send as a prompt
- `run(input)`         — async entry point; the v0 scaffold raises
                         `NotImplementedError`. Concrete reasoning lands
                         in a follow-up commit once the Claude Agent SDK
                         transport is wired up.

See `projects/pocsmith/roles/README.md` for the file format and
`docs/adr/0010-pocsmith-agentic-poc-factory.md` for the architecture.
"""

from pocsmith.roles.base import Role
from pocsmith.roles.frontmatter import RoleCaps, RoleFrontmatter, RoleScope

__all__ = ["Role", "RoleCaps", "RoleFrontmatter", "RoleScope"]
