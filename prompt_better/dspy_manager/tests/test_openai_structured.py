from __future__ import annotations

import os
import sys
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from prompt_better.dspy_manager.openai_structured import (
    coerce_types_to_schema,
    find_and_parse_json,
)
from prompt_better.dspy_manager.fallbacks import (
    FALLBACK_EXTRACTORS,
    register_fallback_extractor,
)


class OpenAIStructuredTests(unittest.TestCase):
    def test_find_and_parse_json_markdown_blocks(self) -> None:
        raw_input = "Here is your JSON:\n```json\n{\n  \"status\": \"success\",\n  \"code\": 200\n}\n```\nHope it works!"
        parsed = find_and_parse_json(raw_input)
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.get("status"), "success")
        self.assertEqual(parsed.get("code"), 200)

    def test_find_and_parse_json_outer_braces(self) -> None:
        raw_input = "Sure, the result is {\"score\": 0.95, \"completed\": true} thank you."
        parsed = find_and_parse_json(raw_input)
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.get("score"), 0.95)
        self.assertEqual(parsed.get("completed"), True)

    def test_find_and_parse_json_square_brackets(self) -> None:
        raw_input = "Here are the queries: [\"swift ui\", \"ios core\"]"
        parsed = find_and_parse_json(raw_input)
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.get("items"), ["swift ui", "ios core"])

    def test_type_coercion_primitives(self) -> None:
        schema = {
            "properties": {
                "count": {"type": "integer"},
                "rate": {"type": "number"},
                "active": {"type": "boolean"},
                "name": {"type": "string"},
            }
        }
        raw_data = {
            "count": "42",
            "rate": "3.1415",
            "active": "yes",
            "name": 12345,
        }
        coerced = coerce_types_to_schema(raw_data, schema)
        self.assertEqual(coerced.get("count"), 42)
        self.assertEqual(coerced.get("rate"), 3.1415)
        self.assertEqual(coerced.get("active"), True)
        self.assertEqual(coerced.get("name"), "12345")

    def test_type_coercion_arrays(self) -> None:
        schema = {
            "properties": {
                "ids": {
                    "type": "array",
                    "items": {"type": "integer"}
                },
                "flags": {
                    "type": "array",
                    "items": {"type": "boolean"}
                }
            }
        }
        raw_data = {
            "ids": ["10", "20", 30],
            "flags": ["true", "no", True]
        }
        coerced = coerce_types_to_schema(raw_data, schema)
        self.assertEqual(coerced.get("ids"), [10, 20, 30])
        self.assertEqual(coerced.get("flags"), [True, False, True])

    def test_custom_fallback_extractor_registration(self) -> None:
        @register_fallback_extractor("test_custom_parser")
        def custom_parser(content: str, properties: dict) -> dict:
            return {"result": content.upper().strip()}

        self.assertIn("test_custom_parser", FALLBACK_EXTRACTORS)
        res = FALLBACK_EXTRACTORS["test_custom_parser"]("hello", {})
        self.assertEqual(res, {"result": "HELLO"})


if __name__ == "__main__":
    unittest.main()
