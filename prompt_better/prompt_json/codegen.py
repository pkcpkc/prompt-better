from __future__ import annotations
from typing import Any
from prompt_better.prompt_json.models import PromptFieldSpec


def to_swift_primitive(t: str) -> str:
    t_low = t.lower() if t else ""
    if t_low == "integer":
        return "Int"
    if t_low in ("number", "float", "double"):
        return "Double"
    if t_low == "boolean":
        return "Bool"
    return "String"


def swift_type_filter(field: PromptFieldSpec) -> str:
    if field.is_array:
        return f"[{to_swift_primitive(field.items or 'string')}]"
    return to_swift_primitive(field.type)
