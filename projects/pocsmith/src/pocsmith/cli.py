"""pocsmith CLI surface.

This is the v0 scaffold — only the version subcommand is wired up. The
`run` subcommand is registered as a stub so that anyone running
`pocsmith --help` immediately sees the intended shape, and so that
later commits can fill in the body without touching the entry point.

See ADR-0010 for the full design.
"""

from __future__ import annotations

import typer
from rich.console import Console

from pocsmith import __version__

app = typer.Typer(
    name="pocsmith",
    help="Agentic PoC factory — CEO-led role loop. See ADR-0010.",
    no_args_is_help=True,
    add_completion=False,
)

console = Console()


@app.command()
def version() -> None:
    """Print the pocsmith version."""
    console.print(f"pocsmith [bold]{__version__}[/bold]")


@app.command()
def run(prompt: str) -> None:
    """Kick off a PoC run from a free-text prompt.

    Stub for v0. Implemented in a follow-up commit.
    """
    console.print(
        "[yellow]Not implemented yet.[/yellow] "
        "This is a v0 scaffold — see projects/pocsmith/README.md "
        "and docs/adr/0010-pocsmith-agentic-poc-factory.md."
    )
    console.print(f"Would run with prompt: [italic]{prompt}[/italic]")
    raise typer.Exit(code=2)


if __name__ == "__main__":
    app()
