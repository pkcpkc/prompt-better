from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from .models import EndpointConfig


class StructuredOutputError(RuntimeError):
    """Raised when a structured output response cannot be parsed."""


# MARK: - Type Coercion Engine

def coerce_types_to_schema(data: Any, json_schema: Dict[str, Any]) -> Dict[str, Any]:
    """Coerces values inside a parsed dictionary into matching types declared in the JSON schema."""
    if not isinstance(data, dict):
        return {}

    properties = json_schema.get("schema", {}).get("properties", {})
    if not properties:
        properties = json_schema.get("properties", {})
    if not properties:
        return data

    coerced = {}
    for key, prop_spec in properties.items():
        value = data.get(key)
        # Handle cases where array matches item array key
        if value is None and len(properties) == 1 and "items" in data:
            value = data.get("items")

        prop_type = prop_spec.get("type", "string")

        if value is None:
            if prop_type == "array":
                coerced[key] = []
            elif prop_type == "string":
                coerced[key] = ""
            elif prop_type == "integer":
                coerced[key] = 0
            elif prop_type == "number":
                coerced[key] = 0.0
            elif prop_type == "boolean":
                coerced[key] = False
            continue

        if prop_type == "string":
            coerced[key] = str(value)
        elif prop_type == "integer":
            try:
                coerced[key] = int(float(value))
            except (ValueError, TypeError):
                match = re.search(r'\b\d+\b', str(value))
                coerced[key] = int(match.group(0)) if match else 0
        elif prop_type == "number":
            try:
                coerced[key] = float(value)
            except (ValueError, TypeError):
                match = re.search(r'\b\d+(?:\.\d+)?\b', str(value))
                coerced[key] = float(match.group(0)) if match else 0.0
        elif prop_type == "boolean":
            if isinstance(value, bool):
                coerced[key] = value
            else:
                coerced[key] = str(value).lower() in ("true", "1", "yes")
        elif prop_type == "array":
            item_type = prop_spec.get("items", {}).get("type", "string")
            if not isinstance(value, list):
                value = [value]
            coerced_list = []
            for item in value:
                if item_type == "integer":
                    try:
                        coerced_list.append(int(float(item)))
                    except (ValueError, TypeError):
                        pass
                elif item_type == "number":
                    try:
                        coerced_list.append(float(item))
                    except (ValueError, TypeError):
                        pass
                elif item_type == "boolean":
                    if isinstance(item, bool):
                        coerced_list.append(item)
                    else:
                        coerced_list.append(str(item).lower() in ("true", "1", "yes"))
                else:
                    coerced_list.append(str(item))
            coerced[key] = coerced_list
        else:
            coerced[key] = value

    return coerced


def find_and_parse_json(content: str) -> Optional[Dict[str, Any]]:
    """Detects and parses JSON object or list enclosed in text, handling markdown blocks."""
    content_clean = content.strip()
    
    # 1. Clean markdown code blocks if present
    if "```" in content_clean:
        match = re.search(r'```(?:json)?\s*(.*?)\s*```', content_clean, re.DOTALL)
        if match:
            candidate = match.group(1).strip()
            try:
                obj = json.loads(candidate)
                if isinstance(obj, (dict, list)):
                    return obj if isinstance(obj, dict) else {"items": obj}
            except Exception:
                pass

    # 2. Match outer curly braces for objects
    start_idx = content_clean.find('{')
    end_idx = content_clean.rfind('}')
    if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
        candidate = content_clean[start_idx:end_idx+1]
        try:
            obj = json.loads(candidate)
            if isinstance(obj, dict):
                return obj
        except Exception:
            pass

    # 3. Match outer square brackets for arrays
    start_idx = content_clean.find('[')
    end_idx = content_clean.rfind(']')
    if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
        candidate = content_clean[start_idx:end_idx+1]
        try:
            obj = json.loads(candidate)
            if isinstance(obj, list):
                return {"items": obj}
        except Exception:
            pass

    return None


# MARK: - Fallback Entry Point

def try_parse_raw_text_to_schema(content: str, json_schema: Dict[str, Any]) -> Dict[str, Any]:
    content = content.strip()
    
    # 1. Attempt generic outer-braces JSON parsing
    parsed_json = find_and_parse_json(content)
    if parsed_json is not None:
        return coerce_types_to_schema(parsed_json, json_schema)

    # 2. Get properties from schema
    properties = json_schema.get("schema", {}).get("properties", {})
    if not properties:
        properties = json_schema.get("properties", {})
    if not properties:
        raise ValueError("No properties found in schema")
        
    # 3. Handle specific layouts with clean registries
    from .fallbacks import try_parse_fallback
    extracted = try_parse_fallback(content, properties)
    if extracted is not None:
        return coerce_types_to_schema(extracted, json_schema)

    # 4. Standard light primitive fallback loop
    result: Dict[str, Any] = {}
    for key, spec in properties.items():
        prop_type = spec.get("type", "string")
        if prop_type == "string":
            result[key] = content
            content = ""
        elif prop_type == "array":
            lines = [line.strip() for line in content.splitlines() if line.strip()]
            items = []
            for line in lines:
                clean_line = re.sub(r'^(\d+[\.\)]|[\-\*\u2022])\s+', '', line).strip()
                items.append(clean_line)
            result[key] = items
            content = ""
        elif prop_type in ("integer", "number"):
            result[key] = 0
        elif prop_type == "boolean":
            result[key] = False
            
    return coerce_types_to_schema(result, json_schema)


# MARK: - OpenAI Client Completion Core

def create_openai_client(config: EndpointConfig):
    try:
        from openai import OpenAI
    except ModuleNotFoundError as exc:
        raise StructuredOutputError(
            "The `openai` Python package is not installed. Install it via pip or uv (e.g., `uv pip install openai` or `pip install openai`)."
        ) from exc

    api_key = config.api_key
    if not api_key:
        api_key = "local"
    return OpenAI(
        base_url=config.base_url,
        api_key=api_key,
        timeout=config.timeout_seconds,
    )


def call_json_schema(
    config: EndpointConfig,
    messages: List[Dict[str, str]],
    json_schema: Dict[str, Any],
    temperature: Optional[float] = None,
) -> Dict[str, Any]:
    # 1. Invoke actual completion endpoint
    client = create_openai_client(config)
    temp_to_use = temperature if temperature is not None else config.temperature
    response = client.chat.completions.create(
        model=config.model,
        messages=messages,
        temperature=temp_to_use,
        response_format={
            "type": "json_schema",
            "json_schema": json_schema,
        },
    )

    choice = response.choices[0].message
    refusal = getattr(choice, "refusal", None)
    if refusal:
        raise StructuredOutputError(f"Model refusal: {refusal}")

    parsed = getattr(choice, "parsed", None)
    result = None
    if parsed is not None:
        if hasattr(parsed, "model_dump"):
            result = parsed.model_dump()
        elif isinstance(parsed, dict):
            result = parsed

    if result is None:
        content = _extract_content(choice.content)
        try:
            result = json.loads(content)
        except json.JSONDecodeError as exc:
            try:
                result = try_parse_raw_text_to_schema(content, json_schema)
            except Exception as fallback_exc:
                raise StructuredOutputError(
                    f"Invalid JSON output: {content}. Fallback parser failed: {fallback_exc}"
                ) from exc

    return result


def _extract_content(content: Any) -> str:
    if isinstance(content, str):
        cleaned = content.replace("Ċ", "\n").replace("Ġ", " ")
        return cleaned
    if isinstance(content, list):
        parts: List[str] = []
        for item in content:
            if isinstance(item, dict):
                text = item.get("text")
                if text:
                    parts.append(text)
                continue
            text_value = getattr(item, "text", None)
            if text_value:
                parts.append(text_value)
        if parts:
            return "".join(parts).replace("Ċ", "\n").replace("Ġ", " ")
    raise StructuredOutputError("Unable to extract response content from chat completion")
