from __future__ import annotations
from typing import Any, Dict, Iterable, List, Optional
from pydantic import create_model, Field, conlist

from .models import PromptSpec


def _to_python_type_hint(t: str) -> Any:
    t_low = t.lower() if t else ""
    if t_low == "integer":
        return int
    if t_low in ("number", "float", "double"):
        return float
    if t_low == "boolean":
        return bool
    return str


def _signature_instruction(spec: PromptSpec, examples: Iterable[Any]) -> str:
    instruction = spec.instructions.prompt
    if any(example.history for example in examples):
        instruction += (
            "\n\nNutze `conversation_history` als bereits vorhandenen Gesprächskontext, "
            "falls dieses Feld befüllt ist."
        )
    return instruction


def build_dspy_signature(dspy: Any, spec: PromptSpec, examples: Iterable[Any]) -> Any:
    """Builds a dynamic DSPy signature with flat output fields for a PromptSpec."""
    # Distinguish input and output fields
    input_specs = [f for f in spec.fields if f.role == "input"]
    output_specs = [f for f in spec.fields if f.role == "output"]

    # Create the DSPy Signature attributes
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

    # Add flat Output Fields
    for f in output_specs:
        if f.is_array:
            item_hint = _to_python_type_hint(f.items or "string")
            if f.exact_count is not None:
                type_hint = conlist(item_hint, min_length=f.exact_count, max_length=f.exact_count)
            else:
                type_hint = List[item_hint]
        else:
            type_hint = _to_python_type_hint(f.type)
        
        attrs["__annotations__"][f.name] = type_hint
        attrs[f.name] = dspy.OutputField(desc=f.desc)

    return type(f"{spec.name}Signature", (dspy.Signature,), attrs)


def to_dspy_examples(dspy: Any, examples: Iterable[Any], spec: PromptSpec, specs: Dict[str, PromptSpec]) -> List[Any]:
    """Converts a collection of PromptExample objects into DSPy Examples."""
    from prompt_better.dataset_manager import flatten_history, resolve_history_messages

    converted = []
    
    input_keys = [f.name for f in spec.fields if f.role == "input"]
    include_history = any(example.history for example in examples)
    if include_history:
        input_keys.append("conversation_history")

    for example in examples:
        payload = dict(example.inputs)
        if include_history:
            payload["conversation_history"] = flatten_history(resolve_history_messages(example, specs))
        
        # Unpack reference output properties directly into the payload (flat structure)
        for k, v in example.reference_output.items():
            payload[k] = v
        
        converted.append(dspy.Example(**payload).with_inputs(*input_keys))
    return converted


def prediction_to_dict(prediction: Any, spec: PromptSpec) -> Dict[str, Any]:
    """Unwraps prediction outputs from DSPy Typed Signature structure into a standard dictionary."""
    # Check for flat output fields directly on prediction
    result = {}
    has_flat = False
    for f in spec.fields:
        if f.role == "output":
            if hasattr(prediction, f.name):
                result[f.name] = getattr(prediction, f.name)
                has_flat = True
    
    if has_flat:
        return result

    # Fallback to the legacy single 'output' field if it was used
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
