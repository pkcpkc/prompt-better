from __future__ import annotations
import jinja2
from pathlib import Path
from .models import PromptSpec


def generate_from_json(source: Path, target: Path, template_path: Path) -> None:
    """Generates a file from a prompt JSON definition and a Jinja template."""
    try:
        content = source.read_text(encoding="utf-8")
        spec = PromptSpec.model_validate_json(content)

        # Setup Jinja2 environment
        template_path = template_path.expanduser()
        if not template_path.is_absolute():
            template_path = Path.cwd() / template_path
        template_dir = template_path.parent
        from .codegen import swift_type_filter
        env = jinja2.Environment(
            loader=jinja2.FileSystemLoader(template_dir),
            trim_blocks=True,
            lstrip_blocks=True,
            keep_trailing_newline=True,
        )
        env.filters["swift_type"] = swift_type_filter
        template = env.get_template(template_path.name)

        # Render
        rendered = template.render(spec=spec)

        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rendered, encoding="utf-8")

    except Exception as e:
        raise ValueError(f"Failed to generate {target} from {source} with {template_path}: {e}")
