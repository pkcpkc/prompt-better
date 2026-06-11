from __future__ import annotations
import re
from pathlib import Path
from typing import Dict, Any

from .models import PromptSpec


def load_prompt_specs(prompts_dir: Path) -> Dict[str, PromptSpec]:
    """Loads prompt specifications from JSON files in the given directory."""
    specs: Dict[str, PromptSpec] = {}
    
    for json_file in prompts_dir.rglob("prompt.json"):
        if json_file.name in ["prompt-schema.json", "schema.json"]:
            continue
            
        try:
            content = json_file.read_text(encoding="utf-8")
            spec = PromptSpec.model_validate_json(content)
            spec.source_path = json_file
            
            # Find all {{placeholder}} tags in instructions for validation/metadata
            spec.placeholders = sorted(list(set(re.findall(r"\{\{([a-zA-Z][a-zA-Z0-9_]*)\}\}", spec.instructions.prompt))))
            
            specs[spec.name] = spec
        except Exception as e:
            print(f"Error loading {json_file}: {e}")
            
    return specs


def preview_schema(prompts_dir: Path, prompt_name: str) -> Dict[str, Any]:
    """Returns JSON schema for given prompt_name or all loaded prompts."""
    specs = load_prompt_specs(prompts_dir)
    if prompt_name == "ALL":
        return {name: spec.to_json_schema() for name, spec in specs.items()}
    return specs[prompt_name].to_json_schema()


def list_prompts(prompts_dir: Path) -> List[PromptSpec]:
    """Lists all loaded prompt specifications."""
    specs = load_prompt_specs(prompts_dir)
    return list(specs.values())

