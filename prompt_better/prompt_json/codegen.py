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


def swift_title_case_filter(name: str) -> str:
    import re
    words = re.findall(r'[A-Z]?[a-z]+|[A-Z]+(?=[A-Z][a-z]|\b)|[0-9]+', name)
    if not words:
        return name.capitalize()
    return " ".join(word.capitalize() for word in words)
