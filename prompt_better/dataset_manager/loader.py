from __future__ import annotations
import json
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

from .models import PromptExample
from prompt_better.prompt_json.models import PromptSpec


def load_examples(dataset_path: Path) -> List[PromptExample]:
    """Loads prompt examples from the nested prompts/dataset/ and prompts/golden-truth/ directories."""
    examples: List[PromptExample] = []
    prompt_dirs = []
    
    # Load validation schemas
    dataset_schema_path = Path(__file__).parent / "dataset-schema.json"
    golden_schema_path = Path(__file__).parent / "golden-schema.json"
    dataset_schema = None
    golden_schema = None
    try:
        import jsonschema
        if dataset_schema_path.exists():
            dataset_schema = json.loads(dataset_schema_path.read_text(encoding="utf-8"))
        if golden_schema_path.exists():
            golden_schema = json.loads(golden_schema_path.read_text(encoding="utf-8"))
    except ImportError:
        jsonschema = None

    # 1. Check if dataset_path itself contains a 'dataset' subfolder
    if (dataset_path / "dataset").exists():
        prompt_dirs.append(dataset_path)
    
    # 2. Check if subdirectories of dataset_path contain a 'dataset' subfolder
    if dataset_path.exists() and dataset_path.is_dir():
        for path in dataset_path.iterdir():
            if path.is_dir() and (path / "dataset").exists() and path not in prompt_dirs:
                prompt_dirs.append(path)
            
    for prompt_dir in prompt_dirs:
        dataset_dir = prompt_dir / "dataset"
        golden_dir = prompt_dir / "golden-truth"
        
        # Get base prompt name (e.g. "ArticleInsight" -> "ArticleInsightPrompt")
        prompt_folder_name = prompt_dir.name
        prompt_name = prompt_folder_name if prompt_folder_name.endswith("Prompt") else f"{prompt_folder_name}Prompt"
        
        for json_file in dataset_dir.glob("*.json"):
            try:
                inputs_data = json.loads(json_file.read_text(encoding="utf-8"))
                
                # Validate dataset file structure
                if jsonschema is not None and dataset_schema is not None:
                    try:
                        jsonschema.validate(instance=inputs_data, schema=dataset_schema)
                    except jsonschema.ValidationError as ve:
                        print(f"Warning: Dataset case file {json_file} failed schema validation: {ve.message}")
                
                case_id = inputs_data.get("id", json_file.stem)
                inputs = inputs_data.get("inputs", {})
                history = inputs_data.get("history", [])
                
                golden_file = golden_dir / json_file.name
                if not golden_file.exists():
                    continue
                    
                golden_data = json.loads(golden_file.read_text(encoding="utf-8"))
                
                # Validate golden truth file structure
                if jsonschema is not None and golden_schema is not None:
                    try:
                        jsonschema.validate(instance=golden_data, schema=golden_schema)
                    except jsonschema.ValidationError as ve:
                        print(f"Warning: Golden truth case file {golden_file} failed schema validation: {ve.message}")
                
                reference_output = golden_data.get("reference_output", {})
                rubric = golden_data.get("rubric", [])
                
                case_data = {
                    "id": case_id,
                    "prompt_name": prompt_name,
                    "inputs": inputs,
                    "reference_output": reference_output,
                    "rubric": rubric,
                    "history": history
                }
                
                examples.append(PromptExample.model_validate(case_data))
            except Exception as e:
                print(f"Error loading case from {json_file}: {e}")
                
    return examples


def examples_for_prompt(examples: Iterable[PromptExample], prompt_name: str) -> List[PromptExample]:
    """Filters examples by target prompt name."""
    return [example for example in examples if example.prompt_name == prompt_name]


def split_examples(examples: List[PromptExample], train_ratio: float) -> Tuple[List[PromptExample], List[PromptExample]]:
    """Splits examples into training and evaluation sets based on ratio."""
    if not examples:
        return [], []
    sorted_examples = sorted(examples, key=lambda item: item.example_id)
    if len(sorted_examples) == 1:
        return sorted_examples, sorted_examples
    split_index = max(1, min(len(sorted_examples) - 1, int(round(len(sorted_examples) * train_ratio))))
    return sorted_examples[:split_index], sorted_examples[split_index:]


def resolve_history_messages(example: PromptExample, specs: Dict[str, PromptSpec]) -> List[Dict[str, str]]:
    """Resolves chat history template specifications or raw contents into role/message pairs."""
    messages: List[Dict[str, str]] = []
    for entry in example.history:
        if entry.content is not None:
            content = entry.content
        elif entry.prompt_name is not None:
            prompt_spec = specs[entry.prompt_name]
            content = prompt_spec.build_instructions(entry.inputs, template_override=entry.template_override)
        else:
            raise ValueError(f"History entry in {example.example_id} is missing content and prompt_name")
        messages.append({"role": entry.role, "content": content})
    return messages


def flatten_history(messages: List[Dict[str, str]]) -> str:
    """Formats role/message lists into formatted instruction prompt texts."""
    if not messages:
        return ""
    return "\n\n".join(f"[{message['role'].upper()}]\n{message['content']}" for message in messages)
