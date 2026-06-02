from __future__ import annotations

import inspect
import json
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

from pydantic import create_model, Field, conlist

from .dataset import (
    examples_for_prompt,
    flatten_history,
    load_examples,
    resolve_history_messages,
    split_examples,
    token_f1,
)
from .models import OptimizationConfig, PromptExample, PromptSpec, ValidationResult
from .openai_structured import StructuredOutputError, call_json_schema
from .json_prompts import load_prompt_specs


class PromptOptimizationError(RuntimeError):
    """Raised when prompt optimization cannot continue."""


def list_prompts(prompts_dir: Path) -> List[PromptSpec]:
    specs = load_prompt_specs(prompts_dir)
    return list(specs.values())


def preview_schema(prompts_dir: Path, prompt_name: str) -> Dict[str, Any]:
    specs = load_prompt_specs(prompts_dir)
    if prompt_name == "ALL":
        return {name: spec.to_json_schema() for name, spec in specs.items()}
    return specs[prompt_name].to_json_schema()


def validate_prompt(config: OptimizationConfig) -> Dict[str, Any]:
    specs = load_prompt_specs(config.prompts_dir)
    examples = load_examples(config.dataset_file)
    prompt_names = _resolve_prompt_names(config.prompt_name, specs)
    report: Dict[str, Any] = {}

    for prompt_name in prompt_names:
        spec = specs[prompt_name]
        prompt_examples = examples_for_prompt(examples, prompt_name)
        validations = [
            _validate_single_example(spec, example, specs, config)
            for example in prompt_examples
        ]
        report[prompt_name] = {
            "count": len(validations),
            "average_structural_score": _average(validation.structural_score for validation in validations),
            "average_similarity_score": _average(validation.similarity_score for validation in validations),
            "average_aggregate_score": _average(validation.aggregate_score for validation in validations),
            "average_teacher_score": _average(
                validation.teacher_score
                for validation in validations
                if validation.teacher_score is not None
            ),
            "validations": [validation.model_dump() for validation in validations],
        }

    return report


def optimize_prompt(config: OptimizationConfig) -> Dict[str, Any]:
    try:
        import dspy
    except ModuleNotFoundError as exc:
        raise PromptOptimizationError(
            "DSPy is not installed. Run `./gradlew promptOptimizationInstall` first."
        ) from exc

    specs = load_prompt_specs(config.prompts_dir)
    examples = load_examples(config.dataset_file)
    prompt_names = _resolve_prompt_names(config.prompt_name, specs)

    student_lm = _build_lm(dspy, config.student)
    teacher_lm = _build_lm(dspy, config.teacher) if config.teacher else None
    dspy.configure(lm=student_lm)

    output: Dict[str, Any] = {}
    for prompt_name in prompt_names:
        spec = specs[prompt_name]
        prompt_examples = examples_for_prompt(examples, prompt_name)
        if len(prompt_examples) < 2:
            raise PromptOptimizationError(
                f"{prompt_name} needs at least 2 dataset examples for training and evaluation."
            )

        # Results live next to the prompt definition: <prompt_dir>/results/
        if spec.source_path is None:
            raise PromptOptimizationError(
                f"No source_path for prompt '{prompt_name}' — cannot determine where to write results."
            )
        prompt_output_dir: Path = spec.source_path.parent / "results"
        prompt_output_dir.mkdir(parents=True, exist_ok=True)

        if len(prompt_examples) <= 3:
            trainset = list(prompt_examples)
            evalset = list(prompt_examples)
            print(f"Small dataset detected ({len(prompt_examples)} cases). Using all cases for both training and evaluation.")
        else:
            trainset, evalset = split_examples(prompt_examples, config.train_ratio)
        module = _build_module(dspy, spec, prompt_examples)
        if hasattr(module, "set_lm"):
            module.set_lm(student_lm)
        elif hasattr(module, "predict") and hasattr(module.predict, "set_lm"):
            module.predict.set_lm(student_lm)

        metric = _build_metric(spec)
        baseline_score = _score_module_on_examples(module, evalset, specs, metric)

        # Setup progress tracker with baseline score reference
        tracker = ProgressTracker(prompt_name, baseline_score=baseline_score)
        compile_metric = _build_metric(spec, tracker=tracker)

        optimizer_kwargs: Dict[str, Any] = {
            "metric": compile_metric,
            "auto": config.auto_mode,
            "num_threads": config.num_threads,
        }
        optimizer_signature = inspect.signature(dspy.MIPROv2)
        if teacher_lm is not None and "prompt_model" in optimizer_signature.parameters:
            optimizer_kwargs["prompt_model"] = teacher_lm
        if "task_model" in optimizer_signature.parameters:
            optimizer_kwargs["task_model"] = student_lm

        optimizer = dspy.MIPROv2(**optimizer_kwargs)
        compiled = optimizer.compile(module, trainset=_to_dspy_examples(dspy, trainset, spec, specs))
        tracker.complete()
        optimized_score = _score_module_on_examples(compiled, evalset, specs, metric)

        teacher_validation = _score_with_teacher_on_eval(
            compiled=compiled,
            evalset=evalset,
            spec=spec,
            specs=specs,
            config=config,
        )

        serialized_path = _write_serialized_artifact(compiled, prompt_output_dir / f"{prompt_name}.dspy.json")
        extracted_instruction = _extract_instruction_text(compiled)

        if config.apply and extracted_instruction:
            print(f"Applying optimized prompt back to source JSON: {spec.source_path}")
            spec.instructions.prompt = extracted_instruction
            spec.save_to_source()

        result = {
            "prompt_name": prompt_name,
            "train_size": len(trainset),
            "eval_size": len(evalset),
            "baseline_dspy_score": baseline_score,
            "optimized_dspy_score": optimized_score,
            "teacher_validation": teacher_validation,
            "json_schema": spec.to_json_schema(),
            "extracted_instruction": extracted_instruction,
            "serialized_artifact": str(serialized_path) if serialized_path else None,
        }
        output[prompt_name] = result

        report_file = prompt_output_dir / f"{prompt_name}.report.json"
        report_file.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"  Report written → {report_file}")
        _print_prompt_summary(result)

    return output


def _fix_encoding(text: str) -> str:
    """Repair latin1-as-utf8 mojibake (e.g. prÃ¤zise -> präzise) commonly seen in local model outputs."""
    try:
        return text.encode("latin1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text


def _jinja_env():
    try:
        from jinja2 import Environment, FileSystemLoader, select_autoescape
    except ModuleNotFoundError as exc:
        raise PromptOptimizationError(
            "Jinja2 is not installed. Run `./gradlew promptOptimizationInstall` first."
        ) from exc

    templates_dir = Path(__file__).parent / "templates"
    env = Environment(
        loader=FileSystemLoader(str(templates_dir)),
        autoescape=select_autoescape([]),
        keep_trailing_newline=True,
    )
    env.filters["fix_encoding"] = _fix_encoding
    return env


def _print_prompt_summary(result: Dict[str, Any]) -> None:
    baseline = result["baseline_dspy_score"]
    optimized = result["optimized_dspy_score"]
    delta = optimized - baseline
    delta_str = f"+{delta:.4f}" if delta >= 0 else f"{delta:.4f}"

    env = _jinja_env()
    template = env.get_template("prompt_summary.j2")
    rendered = template.render(
        result=result,
        tv=result.get("teacher_validation") or {},
        delta_str=delta_str,
    )
    print(rendered)




def _resolve_prompt_names(prompt_name: str, specs: Dict[str, PromptSpec]) -> List[str]:
    if prompt_name == "ALL":
        return sorted(specs.keys())
    if prompt_name not in specs:
        raise PromptOptimizationError(f"Unknown prompt '{prompt_name}'. Available: {', '.join(sorted(specs))}")
    return [prompt_name]


def _build_lm(dspy, endpoint_config):
    if endpoint_config is None:
        return None
    return dspy.LM(
        f"openai/{endpoint_config.model}",
        api_key=endpoint_config.api_key,
        api_base=endpoint_config.base_url,
        model_type="chat",
    )


def _build_module(dspy, spec: PromptSpec, examples: Iterable[PromptExample]):
    signature = _build_signature(dspy, spec, examples)
    # Using ChainOfThought to enable automatic self-correction
    return dspy.ChainOfThought(signature)


def _to_python_type_hint(t: str) -> Any:
    t_low = t.lower() if t else ""
    if t_low == "integer":
        return int
    if t_low in ("number", "float", "double"):
        return float
    if t_low == "boolean":
        return bool
    return str


def _build_signature(dspy, spec: PromptSpec, examples: Iterable[PromptExample]):
    # Distinguish input and output fields
    input_specs = [f for f in spec.fields if f.role == "input"]
    output_specs = [f for f in spec.fields if f.role == "output"]

    # 1. Create the Pydantic model for outputs
    output_field_definitions = {}
    for f in output_specs:
        if f.is_array:
            item_hint = _to_python_type_hint(f.items or "string")
            if f.exact_count is not None:
                type_hint = conlist(item_hint, min_length=f.exact_count, max_length=f.exact_count)
            else:
                type_hint = List[item_hint]
        else:
            type_hint = _to_python_type_hint(f.type)
        output_field_definitions[f.name] = (type_hint, Field(description=f.desc))

    OutputModel = create_model(f"{spec.name}_output", **output_field_definitions)

    # 2. Create the DSPy Signature attributes
    attrs: Dict[str, Any] = {
        "__doc__": _signature_instruction(spec, examples),
        "__annotations__": {},
    }

    # Add Inputs
    for f in input_specs:
        attrs["__annotations__"][f.name] = _to_python_type_hint(f.type)
        attrs[f.name] = dspy.InputField(desc=f.desc)
    
    # Handle conversation history if present in examples
    if any(example.history for example in examples):
        attrs["__annotations__"]["conversation_history"] = str
        attrs["conversation_history"] = dspy.InputField(desc="Previous conversation turns.")

    # Add a single OutputModel Field as suggested
    attrs["__annotations__"]["output"] = OutputModel
    attrs["output"] = dspy.OutputField()

    return type(f"{spec.name}Signature", (dspy.Signature,), attrs)


def _signature_instruction(spec: PromptSpec, examples: Iterable[PromptExample]) -> str:
    instruction = spec.instructions.prompt
    if any(example.history for example in examples):
        instruction += (
            "\n\nNutze `conversation_history` als bereits vorhandenen Gesprächskontext, "
            "falls dieses Feld befüllt ist."
        )
    return instruction


def _to_dspy_examples(dspy, examples: Iterable[PromptExample], spec: PromptSpec, specs: Dict[str, PromptSpec]):
    converted = []
    
    input_keys = [f.name for f in spec.fields if f.role == "input"]
    include_history = any(example.history for example in examples)
    if include_history:
        input_keys.append("conversation_history")

    output_keys = ["output"] # We're using a single output field now

    for example in examples:
        payload = dict(example.inputs)
        if include_history:
            payload["conversation_history"] = flatten_history(resolve_history_messages(example, specs))
        
        # We need to wrap the reference output into the "output" key for the TypedSignature
        payload["output"] = example.reference_output
        
        converted.append(dspy.Example(**payload).with_inputs(*input_keys))
    return converted


def _prediction_to_dict(prediction: Any, spec: PromptSpec) -> Dict[str, Any]:
    # With TypedChainOfThought and OutputModel, the result is in prediction.output
    output_obj = getattr(prediction, "output", None)
    if output_obj is None:
        return {}
    
    if isinstance(output_obj, dict):
        return output_obj
    
    # It's a Pydantic model
    if hasattr(output_obj, "model_dump"):
        return output_obj.model_dump()
    if hasattr(output_obj, "dict"):
        return output_obj.dict()
        
    # Fallback
    result = {}
    for f in spec.fields:
        if f.role == "output":
            result[f.name] = getattr(output_obj, f.name, None)
    return result


class ProgressTracker:
    """A clean, lightweight progress tracker that updates metric evaluation stats dynamically in stdout."""
    def __init__(self, prompt_name: str, baseline_score: float = 0.0):
        self.prompt_name = prompt_name
        self.baseline_score = baseline_score
        self.eval_count = 0
        self.scores: List[float] = []

    def log_evaluation(self, score: float):
        import sys
        self.eval_count += 1
        self.scores.append(score)
        avg_score = sum(self.scores) / len(self.scores)
        best_score = max(self.scores) if self.scores else 0.0
        improvement = best_score - self.baseline_score
        imp_str = f"+{improvement:.4f}" if improvement >= 0 else f"{improvement:.4f}"
        
        sys.stdout.write(
            f"\r  [Optimizer Progress] Evaluated: {self.eval_count} candidates | "
            f"Current Avg: {avg_score:.4f} | Best: {best_score:.4f} ({imp_str} vs baseline)  "
        )
        sys.stdout.flush()

    def complete(self):
        import sys
        sys.stdout.write("\n  [Optimizer Progress] Optimization compile loops successfully completed.\n")
        sys.stdout.flush()


def _build_metric(spec: PromptSpec, tracker: Optional[ProgressTracker] = None):
    def metric(example, prediction, trace=None):
        del trace
        # reference is already in the example object, but we might need to unwrap it if it was wrapped in 'output'
        reference = getattr(example, "output", {})
        candidate = _prediction_to_dict(prediction, spec)
        structural = _structural_score(spec, candidate)
        similarity = _reference_similarity(spec, reference, candidate)
        score = round((0.55 * structural) + (0.45 * similarity), 4)
        
        if tracker is not None:
            tracker.log_evaluation(score)
            
        return score

    return metric


def _score_module_on_examples(module, examples: Iterable[PromptExample], specs: Dict[str, PromptSpec], metric) -> float:
    scores: List[float] = []
    for example in examples:
        inference_inputs = dict(example.inputs)
        if example.history:
            inference_inputs["conversation_history"] = flatten_history(resolve_history_messages(example, specs))
        prediction = module(**inference_inputs)
        
        # Wrap reference output for the metric
        class ReferenceWrapper:
            pass
        ref_obj = ReferenceWrapper()
        setattr(ref_obj, "output", example.reference_output)
        
        scores.append(metric(ref_obj, prediction))
    return _average(scores)


def _validate_single_example(
    spec: PromptSpec,
    example: PromptExample,
    specs: Dict[str, PromptSpec],
    config: OptimizationConfig,
) -> ValidationResult:
    messages = resolve_history_messages(example, specs)
    messages.append({
        "role": "user",
        "content": spec.build_instructions(example.inputs),
    })

    candidate = call_json_schema(config.student, messages, spec.to_json_schema())
    structural = _structural_score(spec, candidate)
    similarity = _reference_similarity(spec, example.reference_output, candidate)
    aggregate = (0.55 * structural) + (0.45 * similarity)

    teacher_score = None
    teacher_rationale = None
    if config.teacher is not None:
        teacher_score, teacher_rationale = _teacher_grade(spec, example, candidate, specs, config)
        aggregate = (aggregate + teacher_score) / 2

    return ValidationResult(
        example_id=example.example_id,
        prompt_name=spec.name,
        mode="manual_json_schema",
        candidate_output=candidate,
        structural_score=round(structural, 4),
        similarity_score=round(similarity, 4),
        aggregate_score=round(aggregate, 4),
        teacher_score=round(teacher_score, 4) if teacher_score is not None else None,
        teacher_rationale=teacher_rationale,
    )


def _score_with_teacher_on_eval(
    compiled,
    evalset: Iterable[PromptExample],
    spec: PromptSpec,
    specs: Dict[str, PromptSpec],
    config: OptimizationConfig,
) -> Dict[str, Any]:
    results: List[ValidationResult] = []
    for example in evalset:
        inputs = dict(example.inputs)
        if example.history:
            inputs["conversation_history"] = flatten_history(resolve_history_messages(example, specs))
        prediction = compiled(**inputs)
        candidate = _prediction_to_dict(prediction, spec)
        structural = _structural_score(spec, candidate)
        similarity = _reference_similarity(spec, example.reference_output, candidate)
        aggregate = (0.55 * structural) + (0.45 * similarity)
        teacher_score = None
        teacher_rationale = None
        if config.teacher is not None:
            teacher_score, teacher_rationale = _teacher_grade(spec, example, candidate, specs, config)
            aggregate = (aggregate + teacher_score) / 2
        results.append(
            ValidationResult(
                example_id=example.example_id,
                prompt_name=spec.name,
                mode="optimized_dspy",
                candidate_output=candidate,
                structural_score=round(structural, 4),
                similarity_score=round(similarity, 4),
                aggregate_score=round(aggregate, 4),
                teacher_score=round(teacher_score, 4) if teacher_score is not None else None,
                teacher_rationale=teacher_rationale,
            )
        )

    return {
        "average_structural_score": _average(result.structural_score for result in results),
        "average_similarity_score": _average(result.similarity_score for result in results),
        "average_aggregate_score": _average(result.aggregate_score for result in results),
        "average_teacher_score": _average(
            result.teacher_score
            for result in results
            if result.teacher_score is not None
        ),
        "results": [result.model_dump() for result in results],
    }


def _teacher_grade(
    spec: PromptSpec,
    example: PromptExample,
    candidate: Dict[str, Any],
    specs: Dict[str, PromptSpec],
    config: OptimizationConfig,
) -> Tuple[float, str]:
    assert config.teacher is not None
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
    judge_messages = [
        {
            "role": "system",
            "content": (
                "Du bewertest strukturierte Ausgaben fuer eine deutsche Nachrichten-App. "
                "Bewerte journalistische Relevanz, Genauigkeit, Format-Treue und Hilfsbereitschaft."
            ),
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
    try:
        grade = call_json_schema(config.teacher, judge_messages, judge_schema)
        score = float(grade["score"])
        score = max(0.0, min(1.0, score))
        rationale = str(grade["rationale"]).strip()
        return score, rationale
    except StructuredOutputError as exc:
        return 0.0, f"Teacher grading failed: {exc}"


def _reference_similarity(spec: PromptSpec, reference: Dict[str, Any], candidate: Dict[str, Any]) -> float:
    scores: List[float] = []
    output_fields = [f for f in spec.fields if f.role == "output"]
    for field in output_fields:
        scores.append(token_f1(reference.get(field.name), candidate.get(field.name)))
    return _average(scores)


def _structural_score(spec: PromptSpec, candidate: Dict[str, Any]) -> float:
    checks: List[float] = []
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
            if field.name in {"questions", "statements"} and value:
                checks.append(1.0 if all(_looks_like_sentence(item) for item in value) else 0.0)
        else:
            checks.append(1.0 if isinstance(value, str) and value.strip() else 0.0)
            if field.name == "followUpQuestion" and isinstance(value, str):
                checks.append(1.0 if _looks_like_question(value) else 0.0)
            if spec.name == "SearchQueryVariantsExtraction" and field.name == "conciseQuery" and isinstance(value, str):
                checks.append(1.0 if len(value.split()) <= 8 else 0.0)
            if spec.name == "FinalFollowUpAnswer" and field.name == "answer" and isinstance(value, str):
                checks.append(1.0 if not value.strip().startswith("{") else 0.0)
            if spec.name == "ResearchResult" and field.name == "answer" and isinstance(value, str):
                checks.append(1.0 if "[" in value and "]" in value else 0.0)
            if spec.name == "SearchSummary" and field.name == "answer" and isinstance(value, str):
                checks.append(1.0 if "?" not in value else 0.0)
    return _average(checks)


def _looks_like_sentence(value: str) -> bool:
    stripped = value.strip()
    return len(stripped.split()) >= 4 and stripped[-1] in ".?!"


def _looks_like_question(value: str) -> bool:
    stripped = value.strip()
    return len(stripped.split()) >= 3 and stripped.endswith("?")


def _average(values: Iterable[Optional[float]]) -> float:
    usable = [float(value) for value in values if value is not None]
    if not usable:
        return 0.0
    return round(sum(usable) / len(usable), 4)


def _extract_instruction_text(compiled) -> Optional[str]:
    candidates = [compiled]
    for attribute in ("predict", "respond", "module"):
        nested = getattr(compiled, attribute, None)
        if nested is not None:
            candidates.append(nested)
    for candidate in candidates:
        signature = getattr(candidate, "signature", None)
        if signature is None:
            continue
        instructions_val = getattr(signature, "instructions", None)
        if isinstance(instructions_val, str) and instructions_val.strip():
            return instructions_val.strip()
        doc = getattr(signature, "__doc__", None)
        if isinstance(doc, str) and doc.strip():
            return doc.strip()
    return None


def _write_serialized_artifact(compiled, destination: Path) -> Optional[Path]:
    save_method = getattr(compiled, "save", None)
    if not callable(save_method):
        return None
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        save_method(str(destination))
        return destination
    except Exception:
        return None
