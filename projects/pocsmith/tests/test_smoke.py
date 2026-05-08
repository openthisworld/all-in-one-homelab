"""Smoke tests — confirm the package imports and the CLI is wired up.

These will run before any role logic exists, so they intentionally check
only the things the v0 scaffold guarantees.
"""

from typer.testing import CliRunner

from pocsmith import __version__
from pocsmith.cli import app


def test_version_string_present() -> None:
    assert __version__ == "0.0.0"


def test_cli_version_command() -> None:
    runner = CliRunner()
    result = runner.invoke(app, ["version"])
    assert result.exit_code == 0
    assert __version__ in result.stdout


def test_cli_run_is_stub_and_exits_nonzero() -> None:
    """The `run` command is intentionally a stub in v0. It must not silently
    succeed — exit code 2 documents the not-implemented state.
    """
    runner = CliRunner()
    result = runner.invoke(app, ["run", "do something"])
    assert result.exit_code == 2
    assert "Not implemented yet" in result.stdout
