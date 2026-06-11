from __future__ import annotations
import re
from typing import Any, Dict, Optional

# Pluggable Fallback Extractors Registry
FALLBACK_EXTRACTORS = {}

def register_fallback_extractor(name: str):
    def decorator(func):
        FALLBACK_EXTRACTORS[name] = func
        return func
    return decorator

# Register existing specific parsers:
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


def try_parse_fallback(content: str, properties: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    prop_keys = list(properties.keys())
    
    if set(prop_keys) == {"summary", "questions"}:
        return FALLBACK_EXTRACTORS["article_insight"](content, properties)
        
    if set(prop_keys) == {"answer", "followUpQuestion"}:
        return FALLBACK_EXTRACTORS["follow_up"](content, properties)

    if set(prop_keys) == {"score", "rationale"}:
        return FALLBACK_EXTRACTORS["teacher_grade"](content, properties)

    if len(prop_keys) == 1 and properties[prop_keys[0]].get("type") == "array":
        return FALLBACK_EXTRACTORS["single_array"](content, properties)

    return None
