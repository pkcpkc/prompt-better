from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

from .models import PromptExample, PromptSpec


TOKEN_PATTERN = re.compile(r"\w+", re.UNICODE)


def load_examples(dataset_path: Path) -> List[PromptExample]:
    examples: List[PromptExample] = []
    
    if dataset_path.is_file():
        try:
            payload = json.loads(dataset_path.read_text(encoding="utf-8"))
            for prompt_name, items in payload.items():
                for item in items:
                    case_data = dict(item)
                    case_data["prompt_name"] = prompt_name
                    examples.append(PromptExample.model_validate(case_data))
        except Exception as e:
            print(f"Error loading legacy dataset file {dataset_path}: {e}")
        return examples

    # New nested layout: dataset_path contains prompt directories, each having dataset/ and golden-truth/
    # E.g. dataset_path/ArticleInsight/dataset/*.json
    # We also support dataset_path itself being a prompt directory
    prompt_dirs = []
    
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
                case_id = inputs_data.get("id", json_file.stem)
                inputs = inputs_data.get("inputs", {})
                history = inputs_data.get("history", [])
                
                golden_file = golden_dir / json_file.name
                if not golden_file.exists():
                    continue
                    
                golden_data = json.loads(golden_file.read_text(encoding="utf-8"))
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
    return [example for example in examples if example.prompt_name == prompt_name]


def split_examples(examples: List[PromptExample], train_ratio: float) -> Tuple[List[PromptExample], List[PromptExample]]:
    if not examples:
        return [], []
    sorted_examples = sorted(examples, key=lambda item: item.example_id)
    if len(sorted_examples) == 1:
        return sorted_examples, sorted_examples
    split_index = max(1, min(len(sorted_examples) - 1, int(round(len(sorted_examples) * train_ratio))))
    return sorted_examples[:split_index], sorted_examples[split_index:]


def resolve_history_messages(example: PromptExample, specs: Dict[str, PromptSpec]) -> List[Dict[str, str]]:
    messages: List[Dict[str, str]] = []
    for entry in example.history:
        if entry.content is not None:
            content = entry.content
        elif entry.prompt_name is not None:
            prompt_spec = specs[entry.prompt_name]
            # Use spec.build_instructions (renamed from build_prompt in refactor)
            content = prompt_spec.build_instructions(entry.inputs, template_override=entry.template_override)
        else:
            raise ValueError(f"History entry in {example.example_id} is missing content and prompt_name")
        messages.append({"role": entry.role, "content": content})
    return messages


def flatten_history(messages: List[Dict[str, str]]) -> str:
    if not messages:
        return ""
    return "\n\n".join(f"[{message['role'].upper()}]\n{message['content']}" for message in messages)


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return " ".join(normalize_text(item) for item in value)
    if isinstance(value, dict):
        return " ".join(normalize_text(item) for item in value.values())
    text = str(value).strip().lower()
    return " ".join(TOKEN_PATTERN.findall(text))


def token_f1(reference: Any, candidate: Any) -> float:
    reference_tokens = normalize_text(reference).split()
    candidate_tokens = normalize_text(candidate).split()
    if not reference_tokens and not candidate_tokens:
        return 1.0
    if not reference_tokens or not candidate_tokens:
        return 0.0
    reference_counts: Dict[str, int] = {}
    candidate_counts: Dict[str, int] = {}
    for token in reference_tokens:
        reference_counts[token] = reference_counts.get(token, 0) + 1
    for token in candidate_tokens:
        candidate_counts[token] = candidate_counts.get(token, 0) + 1
    overlap = 0
    for token, count in reference_counts.items():
        overlap += min(count, candidate_counts.get(token, 0))
    if overlap == 0:
        return 0.0
    precision = overlap / len(candidate_tokens)
    recall = overlap / len(reference_tokens)
    return 2 * precision * recall / (precision + recall)
