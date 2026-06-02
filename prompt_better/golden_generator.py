from __future__ import annotations
import json
from pathlib import Path
from typing import Any, Dict, Optional

from .models import EndpointConfig, PromptSpec
from .json_prompts import load_prompt_specs
from .openai_structured import call_json_schema

def generate_golden_truth(
    case_file: Path,
    prompts_dir: Path,
    dataset_dir: Path,
    prompt_name: str,
    teacher_config: Optional[EndpointConfig] = None
) -> None:
    """Loads a test case, loads prompt specification, generates golden output, and saves to golden-truth."""
    if not case_file.exists():
        raise FileNotFoundError(f"Test case file not found at {case_file}")
        
    print(f"Loading test case inputs from {case_file}...")
    case_data = json.loads(case_file.read_text(encoding="utf-8"))
    case_id = case_data.get("id", case_file.stem)
    inputs = case_data.get("inputs", {})
    
    # 1. Load Prompts & find the targeted prompt spec
    specs = load_prompt_specs(prompts_dir)
    if prompt_name not in specs:
        raise ValueError(f"Unknown prompt '{prompt_name}'. Available: {', '.join(sorted(specs.keys()))}")
    spec = specs[prompt_name]
    
    # 2. Generate Golden Output using Teacher model if available
    reference_output: Dict[str, Any] = {}
    rubrics = []
    
    if teacher_config is not None:
        print(f"Generating golden reference output via teacher model ({teacher_config.model})...")
        try:
            rendered_prompt = spec.build_instructions(inputs)
            messages = [
                {"role": "system", "content": "Du bist ein professioneller KI-Assistent."},
                {"role": "user", "content": rendered_prompt}
            ]
            
            reference_output = call_json_schema(teacher_config, messages, spec.to_json_schema())
            print("Golden reference output successfully generated and validated.")
            
            rubrics = [
                "Der Inhalt muss vollkommen im Kontext des Testartikels stehen.",
                "Keine Halluzinationen oder externen Fakten hinzudichten."
            ]
            for field in spec.outputs:
                rubrics.append(f"Das Feld '{field.name}' muss korrekt befüllt sein und dem Typ '{field.type}' entsprechen.")
                
        except Exception as exc:
            print(f"Warning: Teacher golden generation failed: {exc}. Creating empty skeleton.")
            reference_output = {field.name: [] if field.is_array else "" for field in spec.outputs}
            rubrics = ["Bitte manuelle Qualitätskriterien eintragen."]
    else:
        print("No teacher model configured. Creating empty baseline skeleton for manual entry.")
        reference_output = {field.name: [] if field.is_array else "" for field in spec.outputs}
        rubrics = [
            "Bitte manuelle Qualitätskriterien hier eintragen.",
            "Die Ausgabe muss der Wahrheit entsprechen."
        ]
        
    golden_payload = {
        "id": case_id,
        "reference_output": reference_output,
        "rubric": rubrics
    }
    
    # 3. Save to golden-truth folder
    prompt_base = prompt_name
    if prompt_base.endswith("Prompt"):
        prompt_base = prompt_base[:-6]
    golden_case_dir = dataset_dir / prompt_base / "golden-truth"
    golden_case_dir.mkdir(parents=True, exist_ok=True)
    
    golden_file = golden_case_dir / case_file.name
    golden_file.write_text(json.dumps(golden_payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Successfully saved golden truth case to: {golden_file}")
