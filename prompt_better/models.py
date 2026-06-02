from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field, ConfigDict


class PromptFieldSpec(BaseModel):
    model_config = ConfigDict(populate_by_name=True)
    
    name: str
    type: str = "string"  # "string" or "array"
    desc: str
    items: Optional[str] = None
    min_count: Optional[int] = None
    max_count: Optional[int] = None
    
    # Internal usage/legacy compatibility
    role: str = "output"  # "input" or "output"

    @property
    def is_array(self) -> bool:
        return self.type == "array"

    @property
    def array_item_type(self) -> Optional[str]:
        return self.items

    @property
    def exact_count(self) -> Optional[int]:
        if self.min_count is not None and self.min_count == self.max_count:
            return self.min_count
        return None

    def _to_swift_primitive(self, t: str) -> str:
        t_low = t.lower() if t else ""
        if t_low == "integer":
            return "Int"
        if t_low in ("number", "float", "double"):
            return "Double"
        if t_low == "boolean":
            return "Bool"
        return "String"

    def _to_python_primitive(self, t: str) -> str:
        t_low = t.lower() if t else ""
        if t_low == "integer":
            return "int"
        if t_low in ("number", "float", "double"):
            return "float"
        if t_low == "boolean":
            return "bool"
        return "str"

    def _to_json_schema_type(self, t: str) -> str:
        t_low = t.lower() if t else ""
        if t_low == "integer":
            return "integer"
        if t_low in ("number", "float", "double"):
            return "number"
        if t_low == "boolean":
            return "boolean"
        return "string"

    @property
    def swift_type(self) -> str:
        if self.is_array:
            return f"[{self._to_swift_primitive(self.items or 'string')}]"
        return self._to_swift_primitive(self.type)

    @property
    def python_type_name(self) -> str:
        if self.is_array:
            return f"list[{self._to_python_primitive(self.items or 'string')}]"
        return self._to_python_primitive(self.type)

    def to_json_schema_property(self) -> Dict[str, Any]:
        if self.is_array:
            schema: Dict[str, Any] = {
                "type": "array",
                "description": self.desc,
                "items": {"type": self._to_json_schema_type(self.items or "string")},
            }
            if self.exact_count is not None:
                schema["minItems"] = self.exact_count
                schema["maxItems"] = self.exact_count
            return schema
        return {
            "type": self._to_json_schema_type(self.type),
            "description": self.desc,
        }


class PromptMetadata(BaseModel):
    version: str = "0.1.0"
    author: str = "Paul"


class PromptConfig(BaseModel):
    model_id: str = "base"
    temperature: float = 0.2
    top_p: float = 0.1
    top_k: int = 5
    max_tokens: int = 500
    stop_sequences: List[str] = ["###"]


class InstructionsSpec(BaseModel):
    prompt: str
    context: List[PromptFieldSpec] = []


class PromptSpec(BaseModel):
    name: str
    instructions: InstructionsSpec
    outputs: List[PromptFieldSpec]
    metadata: PromptMetadata = Field(default_factory=PromptMetadata)
    config: PromptConfig = Field(default_factory=PromptConfig)
    
    # Non-serialized fields for app logic
    source_path: Optional[Path] = None
    placeholders: List[str] = []
    template_symbol: str = "instructions"

    @property
    def fields(self) -> List[PromptFieldSpec]:
        """Legacy compatibility property to get all fields."""
        res = []
        for f in self.instructions.context:
            f.role = "input"
            res.append(f)
        for f in self.outputs:
            f.role = "output"
            res.append(f)
        return res

    def build_instructions(self, values: Dict[str, str], template_override: Optional[str] = None) -> str:
        rendered = template_override if template_override is not None else self.instructions.prompt
        for placeholder in self.placeholders:
            if placeholder not in values:
                raise KeyError(f"Missing placeholder '{placeholder}' for prompt {self.name}")
            rendered = rendered.replace(f"{{{{{placeholder}}}}}", values[placeholder])
        return rendered

    def to_json_schema(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "strict": True,
            "schema": {
                "type": "object",
                "properties": {
                    field.name: field.to_json_schema_property()
                    for field in self.outputs
                },
                "required": [field.name for field in self.outputs],
                "additionalProperties": False,
            },
        }

    def save_to_source(self) -> None:
        if not self.source_path:
            raise ValueError(f"No source_path set for prompt {self.name}")
        import json
        data = self.model_dump(
            exclude={"source_path", "placeholders", "template_symbol"},
            by_alias=True,
        )
        if "instructions" in data and "context" in data["instructions"] and not data["instructions"]["context"]:
            data["instructions"].pop("context")
        self.source_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class HistoryMessageSpec(BaseModel):
    role: str
    content: Optional[str] = None
    prompt_name: Optional[str] = None
    inputs: Dict[str, str] = {}
    template_override: Optional[str] = None


class PromptExample(BaseModel):
    example_id: str = Field(alias="id")
    prompt_name: str
    inputs: Dict[str, str]
    reference_output: Dict[str, Any]
    rubric: List[str] = []
    history: List[HistoryMessageSpec] = []


class EndpointConfig(BaseModel):
    base_url: str
    model: str
    api_key: str
    timeout_seconds: float = 120.0


class OptimizationConfig(BaseModel):
    student: EndpointConfig
    teacher: Optional[EndpointConfig]
    prompts_dir: Path
    dataset_file: Path
    prompt_name: str
    auto_mode: str = "light"
    num_threads: int = 6
    train_ratio: float = 0.8
    apply: bool = False


class ValidationResult(BaseModel):
    example_id: str
    prompt_name: str
    mode: str
    candidate_output: Dict[str, Any]
    structural_score: float
    similarity_score: float
    aggregate_score: float
    teacher_score: Optional[float] = None
    teacher_rationale: Optional[str] = None
