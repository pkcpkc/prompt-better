from __future__ import annotations

import inspect
import json
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

from prompt_better.prompt_json import (
    load_prompt_specs,
    build_dspy_signature,
    to_dspy_examples,
    prediction_to_dict,
)
from prompt_better.dataset_manager import (
    load_examples,
    examples_for_prompt,
    split_examples,
    resolve_history_messages,
    flatten_history,
    token_f1,
)
from .models import EndpointConfig, OptimizationConfig, ValidationResult
from .openai_structured import StructuredOutputError, call_json_schema
from .evaluator import load_evaluator
from .optimizers import load_optimizer


class PromptOptimizationError(RuntimeError):
    """Raised when prompt optimization cannot continue."""


def validate_prompt(config: OptimizationConfig) -> Dict[str, Any]:
    specs = load_prompt_specs(config.prompts_dir)
    examples = load_examples(config.dataset_file)
    prompt_names = _resolve_prompt_names(config.prompt_name, specs)
    report: Dict[str, Any] = {}
    for prompt_name in prompt_names:
        spec = specs[prompt_name]
        evaluator = load_evaluator(config.evaluator)
        prompt_examples = examples_for_prompt(examples, prompt_name)
        validations = [
            _validate_single_example(spec, example, specs, config, evaluator)
            for example in prompt_examples
        ]
        
        if spec.source_path is None:
            raise PromptOptimizationError(
                f"No source_path for prompt '{prompt_name}' — cannot determine where to write results."
            )
        prompt_output_dir: Path = spec.source_path.parent / "results"
        prompt_output_dir.mkdir(parents=True, exist_ok=True)
        report_file = prompt_output_dir / "baseline-report.json"

        prompt_report = {
            "prompt_name": prompt_name,
            "count": len(validations),
            "average_structural_score": _average(validation.structural_score for validation in validations),
            "average_similarity_score": _average(validation.similarity_score for validation in validations),
            "average_aggregate_score": _average(validation.aggregate_score for validation in validations),
            "average_teacher_score": _average(validation.teacher_score for validation in validations),
            "validations": [validation.model_dump() for validation in validations],
        }
        report_file.write_text(json.dumps(prompt_report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"  Validation report written → {report_file}")

        report[prompt_name] = prompt_report

    return report


def validate_endpoint_connection(config: EndpointConfig, name: str = "Teacher") -> None:
    """Verifies that we can successfully connect to the endpoint."""
    try:
        from prompt_better.dspy_manager.openai_structured import create_openai_client
        client = create_openai_client(config)
        client.chat.completions.create(
            model=config.model,
            messages=[{"role": "user", "content": "ping"}],
            max_tokens=1,
        )
    except Exception as exc:
        raise PromptOptimizationError(
            f"Connection validation failed for {name} model endpoint ({config.model} at {config.base_url}). "
            f"Details: {exc}"
        )


def optimize_prompt(config: OptimizationConfig) -> Dict[str, Any]:
    try:
        import dspy
    except ModuleNotFoundError as exc:
        raise PromptOptimizationError(
            "DSPy is not installed. Install the package dependencies (e.g., `uv pip install -e .` or `pip install -e .`)."
        ) from exc

    if config.teacher is None:
        raise PromptOptimizationError(
            "Teacher model configuration is missing or incomplete, but is required for optimization. "
            "Please configure the teacher base URL and model via prompt-better.json or "
            "environment variables (PROMPT_BETTER_TEACHER_BASE_URL, PROMPT_BETTER_TEACHER_MODEL)."
        )

    # Validate remote API key if required
    teacher_conf = config.teacher
    if not teacher_conf.api_key and not (teacher_conf.base_url.startswith("http://localhost") or teacher_conf.base_url.startswith("http://127.0.0.1")):
        raise PromptOptimizationError("Teacher API Key is required for remote endpoints.")

    # Validate teacher connection
    print(f"Validating connection to teacher model ({teacher_conf.model} at {teacher_conf.base_url})...")
    validate_endpoint_connection(teacher_conf, name="Teacher")
    print("Teacher model connection validated successfully.")

    specs = load_prompt_specs(config.prompts_dir)
    examples = load_examples(config.dataset_file)
    prompt_names = _resolve_prompt_names(config.prompt_name, specs)

    student_lm = _build_lm(dspy, config.student)
    dspy.configure(lm=student_lm)

    output: Dict[str, Any] = {}
    for prompt_name in prompt_names:
        spec = specs[prompt_name]
        
        # Resolve teacher temperature for MIPRO
        teacher_temp = config.teacher_temp_override
        if teacher_temp is None:
            teacher_temp = config.teacher.temperature

        prompt_teacher_lm = _build_lm(dspy, config.teacher, temperature=teacher_temp)

        evaluator = load_evaluator(config.evaluator)
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

        # Get baseline validation metrics for the evaluation target examples
        eval_target = evalset if config.eval_cases_only else prompt_examples
        baseline_validation = _get_baseline_eval_results(
            config=config,
            spec=spec,
            evalset=eval_target,
            specs=specs,
            evaluator=evaluator,
            prompt_output_dir=prompt_output_dir,
        )

        chain_of_thought = (config.optimizer != "predict")
        module = _build_module(dspy, spec, prompt_examples, chain_of_thought=chain_of_thought)

        module = _wrap_module_to_handle_errors(module)
        if hasattr(module, "set_lm"):
            module.set_lm(student_lm)
        elif hasattr(module, "predict") and hasattr(module.predict, "set_lm"):
            module.predict.set_lm(student_lm)

        metric = _build_metric(spec, evaluator)
        baseline_score = _score_module_on_examples(module, evalset, specs, metric)

        optimizer_backend = load_optimizer(config.optimizer)
        compiled = optimizer_backend.compile(
            config=config,
            spec=spec,
            specs=specs,
            student_lm=student_lm,
            teacher_lm=prompt_teacher_lm,
            trainset=trainset,
            evalset=evalset,
            metric=metric,
            module=module,
        )
        compiled = _wrap_module_to_handle_errors(compiled)
        optimized_score = _score_module_on_examples(compiled, evalset, specs, metric)


        teacher_validation = _score_with_teacher_on_eval(
            compiled=compiled,
            evalset=eval_target,
            spec=spec,
            specs=specs,
            config=config,
            evaluator=evaluator,
        )

        serialized_path = _write_serialized_artifact(compiled, prompt_output_dir / "dspy.json")
        extracted_instruction = _extract_instruction_text(compiled)

        if config.apply and extracted_instruction:
            print(f"Applying optimized prompt back to source JSON: {spec.source_path}")
            spec.instructions.prompt = extracted_instruction
            spec.save_to_source()

        # Write the optimized prompt specification to optimized-prompt.json
        optimized_prompt_path = None
        if extracted_instruction:
            optimized_spec = spec.model_copy(deep=True)
            optimized_spec.instructions.prompt = extracted_instruction
            optimized_prompt_file = prompt_output_dir / "optimized-prompt.json"
            data = optimized_spec.model_dump(
                exclude={"source_path", "placeholders", "template_symbol"},
                by_alias=True,
            )
            if "instructions" in data and "context" in data["instructions"] and not data["instructions"]["context"]:
                data["instructions"].pop("context")
            optimized_prompt_file.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            optimized_prompt_path = str(optimized_prompt_file)
            print(f"  Optimized prompt specification written → {optimized_prompt_file}")

        result = {
            "prompt_name": prompt_name,
            "train_size": len(trainset),
            "eval_size": len(evalset),
            "evalset_ids": [example.example_id for example in evalset],
            "baseline_dspy_score": baseline_score,
            "optimized_dspy_score": optimized_score,
            "baseline_validation": baseline_validation,
            "teacher_validation": teacher_validation,
            "json_schema": spec.to_json_schema(),
            "extracted_instruction": extracted_instruction,
            "serialized_artifact": str(serialized_path) if serialized_path else None,
            "optimized_prompt_file": optimized_prompt_path,
        }
        output[prompt_name] = result

        report_file = prompt_output_dir / "optimize-report.json"
        report_file.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"  Optimization report written → {report_file}")

    return output


def _get_baseline_eval_results(
    config: OptimizationConfig,
    spec: Any,
    evalset: List[Any],
    specs: Dict[str, Any],
    evaluator: Any,
    prompt_output_dir: Path,
) -> Dict[str, Any]:
    import sys
    baseline_report_file = prompt_output_dir / "baseline-report.json"
    
    # 1. Try to load existing baseline-report.json
    existing_validations: Dict[str, Any] = {}
    if baseline_report_file.exists():
        try:
            data = json.loads(baseline_report_file.read_text(encoding="utf-8"))
            if isinstance(data, dict) and "validations" in data:
                for v in data["validations"]:
                    if isinstance(v, dict) and "example_id" in v:
                        existing_validations[v["example_id"]] = v
        except Exception as e:
            print(f"Warning: Could not parse baseline-report.json: {e}", file=sys.stderr)

    # 2. Check which evalset examples are missing or need baseline validation
    baseline_list: List[Dict[str, Any]] = []
    missing_examples = []
    
    for example in evalset:
        eid = example.example_id
        if eid in existing_validations:
            baseline_list.append(existing_validations[eid])
        else:
            missing_examples.append(example)

    # 3. Dynamically run baseline validation for missing examples
    if missing_examples:
        print(f"Running baseline validation on-the-fly for {len(missing_examples)} missing cases...")
        for example in missing_examples:
            val_res = _validate_single_example(spec, example, specs, config, evaluator)
            baseline_list.append(val_res.model_dump())
            # Add to existing_validations so we can write/cache it
            existing_validations[example.example_id] = val_res.model_dump()

    # 4. Write back the updated/merged baseline-report.json
    # We construct a full report containing all validations we've run so far
    merged_validations = list(existing_validations.values())
    prompt_report = {
        "prompt_name": spec.name,
        "count": len(merged_validations),
        "average_structural_score": _average(v.get("structural_score") for v in merged_validations),
        "average_similarity_score": _average(v.get("similarity_score") for v in merged_validations),
        "average_aggregate_score": _average(v.get("aggregate_score") for v in merged_validations),
        "average_teacher_score": _average(v.get("teacher_score") for v in merged_validations),
        "validations": merged_validations,
    }
    baseline_report_file.write_text(json.dumps(prompt_report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"  Baseline report updated/written → {baseline_report_file}")

    # 5. Extract only the validations corresponding to evalset to return
    evalset_ids = {example.example_id for example in evalset}
    evalset_validations = [v for v in merged_validations if v["example_id"] in evalset_ids]
    
    return {
        "average_structural_score": _average(v.get("structural_score") for v in evalset_validations),
        "average_similarity_score": _average(v.get("similarity_score") for v in evalset_validations),
        "average_aggregate_score": _average(v.get("aggregate_score") for v in evalset_validations),
        "average_teacher_score": _average(v.get("teacher_score") for v in evalset_validations),
        "validations": evalset_validations,
    }


def _resolve_prompt_names(prompt_name: str, specs: Dict[str, Any]) -> List[str]:
    if prompt_name == "ALL":
        return sorted(specs.keys())
    if prompt_name not in specs:
        raise PromptOptimizationError(f"Unknown prompt '{prompt_name}'. Available: {', '.join(sorted(specs))}")
    return [prompt_name]


def _build_lm(dspy, endpoint_config, temperature: Optional[float] = None):
    if endpoint_config is None:
        return None
    api_key = endpoint_config.api_key
    if not api_key:
        api_key = "local"
    temp_val = temperature if temperature is not None else endpoint_config.temperature
    return dspy.LM(
        f"openai/{endpoint_config.model}",
        api_key=api_key,
        api_base=endpoint_config.base_url,
        model_type="chat",
        temperature=temp_val,
    )


def _build_module(dspy, spec: Any, examples: Iterable[Any], chain_of_thought: bool = True):
    signature = build_dspy_signature(dspy, spec, examples)
    if chain_of_thought:
        return dspy.ChainOfThought(signature)
    return dspy.Predict(signature)


def _wrap_module_to_handle_errors(module: Any) -> Any:
    if module is None:
        return None

    class WrappedModule(module.__class__):
        def forward(self, *args, **kwargs):
            try:
                return super().forward(*args, **kwargs)
            except Exception as e:
                import dspy
                print(f"  Warning: Module execution/parsing failed: {e}")
                # Determine output fields from the signature to return an appropriate empty prediction
                sig = None
                if hasattr(self, "signature"):
                    sig = self.signature
                elif hasattr(self, "predict") and hasattr(self.predict, "signature"):
                    sig = self.predict.signature
                
                output_fields = {}
                if sig is not None and hasattr(sig, "output_fields"):
                    output_fields = {k: None for k in sig.output_fields.keys()}
                else:
                    output_fields = {"output": None}
                return dspy.Prediction(**output_fields)

    module.__class__ = WrappedModule
    return module



def _build_metric(spec: Any, evaluator):
    def metric(example, prediction, trace=None):
        del trace
        
        # Extract reference from example. First try to read the flat attributes if present,
        # otherwise fall back to getattr(example, "output", {}).
        reference = {}
        has_flat = False
        for f in spec.fields:
            if f.role == "output":
                if hasattr(example, f.name):
                    reference[f.name] = getattr(example, f.name)
                    has_flat = True
        
        if not has_flat:
            raw_ref = getattr(example, "output", {})
            if isinstance(raw_ref, dict):
                reference = raw_ref
            elif hasattr(raw_ref, "model_dump"):
                reference = raw_ref.model_dump()
            elif hasattr(raw_ref, "dict"):
                reference = raw_ref.dict()
            else:
                reference = {}
                
        candidate = prediction_to_dict(prediction, spec)
        return round(evaluator.dspy_score(spec, reference, candidate), 4)

    return metric


def _score_module_on_examples(module, examples: Iterable[Any], specs: Dict[str, Any], metric) -> float:
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
    spec: Any,
    example: Any,
    specs: Dict[str, Any],
    config: OptimizationConfig,
    evaluator,
) -> ValidationResult:
    messages = resolve_history_messages(example, specs)
    messages.append({
        "role": "user",
        "content": spec.build_instructions(example.inputs),
    })

    candidate = call_json_schema(config.student, messages, spec.to_json_schema())
    structural = evaluator.structural_score(spec, candidate)
    similarity = evaluator.similarity_score(spec, example.reference_output, candidate)
    
    teacher_score, teacher_rationale = evaluator.teacher_score(spec, example, candidate, specs, config)
    aggregate = evaluator.aggregate_score(spec, structural, similarity, teacher_score)

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
    evalset: Iterable[Any],
    spec: Any,
    specs: Dict[str, Any],
    config: OptimizationConfig,
    evaluator,
) -> Dict[str, Any]:
    results: List[ValidationResult] = []
    for example in evalset:
        inputs = dict(example.inputs)
        if example.history:
            inputs["conversation_history"] = flatten_history(resolve_history_messages(example, specs))
        prediction = compiled(**inputs)
        candidate = prediction_to_dict(prediction, spec)
        
        structural = evaluator.structural_score(spec, candidate)
        similarity = evaluator.similarity_score(spec, example.reference_output, candidate)
        
        teacher_score, teacher_rationale = evaluator.teacher_score(spec, example, candidate, specs, config)
        aggregate = evaluator.aggregate_score(spec, structural, similarity, teacher_score)
        
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
        "average_teacher_score": _average(result.teacher_score for result in results),
        "results": [result.model_dump() for result in results],
    }


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
