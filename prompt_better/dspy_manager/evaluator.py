from __future__ import annotations
import importlib
import importlib.util
import json
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, Optional, Tuple

from prompt_better.dataset_manager import token_f1, resolve_history_messages
from .openai_structured import call_json_schema, StructuredOutputError
from .models import OptimizationConfig


class BaseEvaluator:
    """Base class for prompt evaluation and scoring.
    
    Users can subclass this to customize structural, similarity, teacher, or aggregate scoring.
    """
    structural_weight: float = 0.55
    similarity_weight: float = 0.45

    def structural_score(self, spec: Any, candidate: Dict[str, Any]) -> float:
        """Calculate structural adherence score (between 0.0 and 1.0)."""
        checks: list[float] = []
        output_fields = [f for f in spec.fields if f.role == "output"]
        for field in output_fields:
            value = candidate.get(field.name)
            if field.is_array:
                if not isinstance(value, list):
                    checks.append(0.0)
                    continue
                if field.exact_count is not None:
                    checks.append(1.0 if len(value) == field.exact_count else 0.0)
                else:
                    checks.append(1.0 if value else 0.0)
                checks.append(1.0 if all(isinstance(item, str) and item.strip() for item in value) else 0.0)
            else:
                checks.append(1.0 if isinstance(value, str) and value.strip() else 0.0)
        return self._average(checks)

    def similarity_score(self, spec: Any, reference: Dict[str, Any], candidate: Dict[str, Any]) -> float:
        """Calculate token-level similarity score between reference and candidate outputs (between 0.0 and 1.0)."""
        scores: list[float] = []
        output_fields = [f for f in spec.fields if f.role == "output"]
        for field in output_fields:
            scores.append(token_f1(reference.get(field.name), candidate.get(field.name)))
        return self._average(scores)

    def teacher_score(
        self,
        spec: Any,
        example: Any,
        candidate: Dict[str, Any],
        specs: Dict[str, Any],
        config: OptimizationConfig,
    ) -> Tuple[Optional[float], Optional[str]]:
        """Fetch a semantic grade from a high-capacity Teacher model."""
        if config.teacher is None:
            return None, "Teacher model not configured."
        judge_schema = {
            "name": "prompt_grade",
            "strict": True,
            "schema": {
                "type": "object",
                "properties": {
                    "score": {
                        "type": "number",
                        "description": "Overall quality score from 0.0 to 1.0.",
                        "minimum": 0.0,
                        "maximum": 1.0,
                    },
                    "rationale": {
                        "type": "string",
                        "description": "Short explanation with the most important quality signal.",
                    },
                },
                "required": ["score", "rationale"],
                "additionalProperties": False,
            },
        }
        history_messages = resolve_history_messages(example, specs)
        
        # Resolve dynamic evaluation system prompt from metadata or environment
        import os
        eval_system_prompt = None
        if hasattr(spec, "metadata") and spec.metadata is not None:
            eval_system_prompt = getattr(spec.metadata, "eval_system_prompt", None)
        if not eval_system_prompt:
            eval_system_prompt = os.getenv("PROMPT_BETTER_EVAL_SYSTEM_PROMPT")
        if not eval_system_prompt:
            eval_system_prompt = (
                "You are a helpful and precise assistant evaluating structured outputs from language models. "
                "Grade the output's accuracy, format adherence, and overall quality based on the input, description, and rubric."
            )
            
        judge_messages = [
            {
                "role": "system",
                "content": eval_system_prompt,
            },
            {
                "role": "user",
                "content": json.dumps(
                    {
                        "prompt_name": spec.name,
                        "instructions": spec.instructions.prompt,
                        "output_schema": spec.to_json_schema()["schema"],
                        "rubric": example.rubric,
                        "history": history_messages,
                        "inputs": example.inputs,
                        "reference_output": example.reference_output,
                        "candidate_output": candidate,
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
            },
        ]
        eval_temp = config.teacher_eval_temp_override
        if eval_temp is None:
            eval_temp = config.teacher.eval_temperature if config.teacher else 0.0

        try:
            grade = call_json_schema(
                config.teacher,
                judge_messages,
                judge_schema,
                temperature=eval_temp,
            )
            score = float(grade["score"])
            score = max(0.0, min(1.0, score))
            rationale = str(grade["rationale"]).strip()
            return score, rationale
        except StructuredOutputError as exc:
            return 0.0, f"Teacher grading failed: {exc}"
        except Exception as exc:
            print(f"Warning: Teacher connection/call failed: {exc}. Ignoring teacher score.", file=sys.stderr)
            return None, f"Teacher connection failed: {exc}"

    def aggregate_score(
        self,
        spec: Any,
        structural: float,
        similarity: float,
        teacher_score: Optional[float],
    ) -> float:
        """Combine structural, similarity, and teacher scores into a single aggregate score."""
        struct_w, sim_w = self._get_weights(spec)
        if similarity == 0.0:
            aggregate = 0.0
        else:
            aggregate = (struct_w * structural) + (sim_w * similarity)
        
        if teacher_score is None:
            return aggregate
        return (aggregate + teacher_score) / 2

    def dspy_score(self, spec: Any, reference: Dict[str, Any], candidate: Dict[str, Any]) -> float:
        """Calculate the scoring function used inside DSPy metric."""
        struct_w, sim_w = self._get_weights(spec)
        structural = self.structural_score(spec, candidate)
        similarity = self.similarity_score(spec, reference, candidate)
        if similarity == 0.0:
            return 0.0
        return (struct_w * structural) + (sim_w * similarity)

    def _get_weights(self, spec: Any) -> Tuple[float, float]:
        struct_w = getattr(self, "structural_weight", 0.55)
        sim_w = getattr(self, "similarity_weight", 0.45)
        if hasattr(spec, "metadata") and spec.metadata is not None:
            cfg_struct = getattr(spec.metadata, "structural_weight", None)
            cfg_sim = getattr(spec.metadata, "similarity_weight", None)
            if cfg_struct is not None:
                struct_w = float(cfg_struct)
            if cfg_sim is not None:
                sim_w = float(cfg_sim)
        return struct_w, sim_w

    def _average(self, values: Iterable[Optional[float]]) -> float:
        usable = [float(value) for value in values if value is not None]
        if not usable:
            return 0.0
        return round(sum(usable) / len(usable), 4)


class DefaultEvaluator(BaseEvaluator):
    """Default implementation of prompt evaluation."""
    pass


def load_evaluator(evaluator_path: Optional[str]) -> BaseEvaluator:
    """Dynamically load an Evaluator instance from a class path or file path."""
    if not evaluator_path:
        return DefaultEvaluator()

    try:
        # Check if it has a colon separating file/module and class name
        if ":" in evaluator_path:
            module_part, class_name = evaluator_path.rsplit(":", 1)
        else:
            # If no colon, assume class name is the last component of a dotted path,
            # or look for subclasses of BaseEvaluator in the module/file.
            if evaluator_path.endswith(".py") or "/" in evaluator_path or "\\" in evaluator_path:
                module_part = evaluator_path
                class_name = None
            else:
                module_part, class_name = evaluator_path.rsplit(".", 1)

        path = Path(module_part)
        if path.exists() and path.is_file():
            # Load as a file
            module_name = path.stem
            spec = importlib.util.spec_from_file_location(module_name, str(path.resolve()))
            if spec is None or spec.loader is None:
                raise ImportError(f"Could not load spec for file {module_part}")
            module = importlib.util.module_from_spec(spec)
            sys.modules[module_name] = module
            spec.loader.exec_module(module)
        else:
            # Load as a module
            module = importlib.import_module(module_part)

        if class_name:
            cls = getattr(module, class_name)
        else:
            # Find the first subclass of BaseEvaluator in the module
            cls = None
            for attr_name in dir(module):
                attr = getattr(module, attr_name)
                if (
                    isinstance(attr, type)
                    and issubclass(attr, BaseEvaluator)
                    and attr is not BaseEvaluator
                    and attr is not DefaultEvaluator
                ):
                    cls = attr
                    break
            if cls is None:
                raise AttributeError(f"No BaseEvaluator subclass found in module {module_part}")

        return cls()
    except Exception as e:
        raise RuntimeError(f"Failed to load custom evaluator from '{evaluator_path}': {e}") from e
