from __future__ import annotations
import re
from typing import Any, Dict

TOKEN_PATTERN = re.compile(r"\w+", re.UNICODE)


def normalize_text(value: Any) -> str:
    """Normalizes string or sequence values into clean, lowercase token structures."""
    if value is None:
        return ""
    if isinstance(value, list):
        return " ".join(normalize_text(item) for item in value)
    if isinstance(value, dict):
        return " ".join(normalize_text(item) for item in value.values())
    text = str(value).strip().lower()
    return " ".join(TOKEN_PATTERN.findall(text))


def token_f1(reference: Any, candidate: Any) -> float:
    """Computes F1-score token overlap between candidate output and reference output."""
    reference_tokens = normalize_text(reference).split()
    candidate_tokens = normalize_text(candidate).split()
    if not reference_tokens and not candidate_tokens:
        return 1.0
    if not reference_tokens or not candidate_tokens:
        return 0.0
    reference_counts: Dict[str, int] = {}
    candidate_counts: Dict[str, int] = {}
    for token in reference_tokens:
        reference_counts[token] = reference_counts.get(token, 0) + 1
    for token in candidate_tokens:
        candidate_counts[token] = candidate_counts.get(token, 0) + 1
    overlap = 0
    for token, count in reference_counts.items():
        overlap += min(count, candidate_counts.get(token, 0))
    if overlap == 0:
        return 0.0
    precision = overlap / len(candidate_tokens)
    recall = overlap / len(reference_tokens)
    return 2 * precision * recall / (precision + recall)
