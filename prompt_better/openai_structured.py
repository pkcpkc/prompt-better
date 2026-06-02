from __future__ import annotations

import json
import os
import re
import sqlite3
import hashlib
from pathlib import Path
from typing import Any, Dict, List, Optional

from .models import EndpointConfig


class StructuredOutputError(RuntimeError):
    """Raised when a structured output response cannot be parsed."""


# MARK: - Pluggable Fallback Extractors Registry

FALLBACK_EXTRACTORS = {}

def register_fallback_extractor(name: str):
    def decorator(func):
        FALLBACK_EXTRACTORS[name] = func
        return func
    return decorator


# MARK: - Generic JSON Recoverer

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


# MARK: - Specific Legacy Fallback Parsers (Registered)

@register_fallback_extractor("article_insight")
def extract_article_insight(content: str, properties: Dict[str, Any]) -> Dict[str, Any]:
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    summary_parts = []
    questions = []
    for line in lines:
        if re.match(r'^(\d+[\.\)]|[\-\*\u2022])\s+', line) or (line and line[0].isdigit() and (line.startswith("1") or line.startswith("2") or line.startswith("3") or line.startswith("4")) and "." in line[:3]):
            clean_line = re.sub(r'^(\d+[\.\)]|[\-\*\u2022])\s+', '', line).strip()
            if clean_line == line:
                clean_line = re.sub(r'^\d+\.\s*', '', line).strip()
            questions.append(clean_line)
        else:
            summary_parts.append(line)
    return {
        "summary": "\n".join(summary_parts),
        "questions": questions
    }


@register_fallback_extractor("follow_up")
def extract_follow_up(content: str, properties: Dict[str, Any]) -> Dict[str, Any]:
    result = {}
    paragraphs = [p.strip() for p in content.split("\n\n") if p.strip()]
    if not paragraphs:
        paragraphs = [line.strip() for line in content.splitlines() if line.strip()]
    if len(paragraphs) >= 2:
        result["answer"] = "\n\n".join(paragraphs[:-1])
        result["followUpQuestion"] = paragraphs[-1]
    elif len(paragraphs) == 1:
        text = paragraphs[0]
        sentences = re.split(r'(?<=[.!?])\s+', text)
        if len(sentences) >= 2 and sentences[-1].endswith("?"):
            result["answer"] = " ".join(sentences[:-1])
            result["followUpQuestion"] = sentences[-1]
        else:
            result["answer"] = text
            result["followUpQuestion"] = ""
    else:
        result["answer"] = ""
        result["followUpQuestion"] = ""
    return result


@register_fallback_extractor("teacher_grade")
def extract_teacher_grade(content: str, properties: Dict[str, Any]) -> Dict[str, Any]:
    score_val = 0.0
    score_match = re.search(r'(?:score|Score|Bewertung|Note)\s*[:=]\s*("?0?\.\d+|"?1\.0|"?1|"?0)\b', content)
    if score_match:
        try:
            score_val = float(score_match.group(1).replace('"', ''))
        except ValueError:
            pass
    else:
        floats = re.findall(r'\b(0\.\d+|1\.0|0|1)\b', content)
        if floats:
            try:
                score_val = float(floats[0])
            except ValueError:
                pass
    
    lines = [line for line in content.splitlines() if not re.search(r'^\s*(?:score|Score|Bewertung|Note)\s*[:=]', line)]
    rationale_val = "\n".join(lines).strip()
    return {
        "score": score_val,
        "rationale": rationale_val
    }


@register_fallback_extractor("single_array")
def extract_single_array(content: str, properties: Dict[str, Any]) -> Dict[str, Any]:
    prop_keys = list(properties.keys())
    if not prop_keys:
        return {}
    key = prop_keys[0]
    lines = [line.strip() for line in content.splitlines() if line.strip()]
    items = []
    for line in lines:
        clean_line = re.sub(r'^(\d+[\.\)]|[\-\*\u2022])\s+', '', line).strip()
        if "," in clean_line and len(lines) == 1:
            items.extend([x.strip() for x in clean_line.split(",") if x.strip()])
        else:
            items.append(clean_line)
    return {key: items}


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
        
    prop_keys = list(properties.keys())
    
    # 3. Handle specific layouts with clean registries
    if set(prop_keys) == {"summary", "questions"}:
        extracted = FALLBACK_EXTRACTORS["article_insight"](content, properties)
        return coerce_types_to_schema(extracted, json_schema)
        
    if set(prop_keys) == {"answer", "followUpQuestion"}:
        extracted = FALLBACK_EXTRACTORS["follow_up"](content, properties)
        return coerce_types_to_schema(extracted, json_schema)

    if set(prop_keys) == {"score", "rationale"}:
        extracted = FALLBACK_EXTRACTORS["teacher_grade"](content, properties)
        return coerce_types_to_schema(extracted, json_schema)

    if len(prop_keys) == 1 and properties[prop_keys[0]].get("type") == "array":
        extracted = FALLBACK_EXTRACTORS["single_array"](content, properties)
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


# MARK: - Hashing-based SQLite Response Cache

class ResponseCache:
    """Manages an SQLite database that caches LLM JSON schema responses based on request properties."""
    def __init__(self, db_path: Optional[str] = None):
        if db_path is None:
            db_path = str(Path.cwd() / ".prompt_better_cache.db")
        self.db_path = db_path
        self._init_db()

    def _init_db(self):
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS cache (
                        key TEXT PRIMARY KEY,
                        response TEXT,
                        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
                    )
                    """
                )
        except Exception as e:
            print(f"Warning: Failed to initialize SQLite cache at {self.db_path}: {e}")

    def _compute_key(
        self,
        config_model: str,
        messages: List[Dict[str, str]],
        json_schema: Dict[str, Any],
        temperature: float
    ) -> str:
        payload = {
            "model": config_model,
            "messages": messages,
            "schema": json_schema,
            "temperature": temperature,
        }
        serialized = json.dumps(payload, sort_keys=True, ensure_ascii=False)
        return hashlib.sha256(serialized.encode("utf-8")).hexdigest()

    def get(
        self,
        config_model: str,
        messages: List[Dict[str, str]],
        json_schema: Dict[str, Any],
        temperature: float
    ) -> Optional[Dict[str, Any]]:
        key = self._compute_key(config_model, messages, json_schema, temperature)
        try:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT response FROM cache WHERE key = ?", (key,))
                row = cursor.fetchone()
                if row:
                    return json.loads(row[0])
        except Exception as e:
            print(f"Warning: Failed to read from SQLite cache: {e}")
        return None

    def set(
        self,
        config_model: str,
        messages: List[Dict[str, str]],
        json_schema: Dict[str, Any],
        temperature: float,
        response: Dict[str, Any]
    ):
        key = self._compute_key(config_model, messages, json_schema, temperature)
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute(
                    "INSERT OR REPLACE INTO cache (key, response) VALUES (?, ?)",
                    (key, json.dumps(response, ensure_ascii=False)),
                )
        except Exception as e:
            print(f"Warning: Failed to write to SQLite cache: {e}")


_cache_instance = None

def get_cache() -> Optional[ResponseCache]:
    global _cache_instance
    if os.getenv("PROMPT_BETTER_DISABLE_CACHE") == "1":
        return None
    if _cache_instance is None:
        _cache_instance = ResponseCache()
    return _cache_instance


# MARK: - OpenAI Client Completion Core

def create_openai_client(config: EndpointConfig):
    try:
        from openai import OpenAI
    except ModuleNotFoundError as exc:
        raise StructuredOutputError(
            "The `openai` Python package is not installed. Run `./gradlew promptOptimizationInstall` first."
        ) from exc

    return OpenAI(
        base_url=config.base_url,
        api_key=config.api_key,
        timeout=config.timeout_seconds,
    )


def call_json_schema(
    config: EndpointConfig,
    messages: List[Dict[str, str]],
    json_schema: Dict[str, Any],
    temperature: float = 0.0,
) -> Dict[str, Any]:
    # 1. Intercept with local SQLite response cache
    cache = get_cache()
    if cache is not None:
        cached = cache.get(config.model, messages, json_schema, temperature)
        if cached is not None:
            print(f"  [Cache Hit] Response resolved from SQLite cache ({config.model}).")
            return cached

    # 2. Invoke actual completion endpoint
    client = create_openai_client(config)
    response = client.chat.completions.create(
        model=config.model,
        messages=messages,
        temperature=temperature,
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

    # 3. Store result in cache if successful
    if cache is not None and result:
        cache.set(config.model, messages, json_schema, temperature, result)

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
