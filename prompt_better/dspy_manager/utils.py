from __future__ import annotations
from pathlib import Path
from typing import Any


def fix_encoding(text: str) -> str:
    """Repair latin1-as-utf8 mojibake (e.g. prÃ¤zise -> präzise) commonly seen in local model outputs."""
    try:
        return text.encode("latin1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text


def get_jinja_env() -> Any:
    try:
        from jinja2 import Environment, FileSystemLoader, select_autoescape
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "Jinja2 is not installed. Install the package dependencies (e.g., `uv pip install -e .` or `pip install -e .`)."
        ) from exc

    templates_dir = Path(__file__).parent / "templates"
    env = Environment(
        loader=FileSystemLoader(str(templates_dir)),
        autoescape=select_autoescape([]),
        keep_trailing_newline=True,
    )
    env.filters["fix_encoding"] = fix_encoding
    return env
