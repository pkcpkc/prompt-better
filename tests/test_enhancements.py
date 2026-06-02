from __future__ import annotations

import os
import sys
import json
import unittest
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from prompt_better.openai_structured import (
    ResponseCache,
    coerce_types_to_schema,
    find_and_parse_json,
    FALLBACK_EXTRACTORS,
    register_fallback_extractor,
)
from prompt_better.optimizer import _to_python_type_hint


class EnhancementsTests(unittest.TestCase):
    def test_to_python_type_hint_mappings(self) -> None:
        self.assertEqual(_to_python_type_hint("integer"), int)
        self.assertEqual(_to_python_type_hint("number"), float)
        self.assertEqual(_to_python_type_hint("float"), float)
        self.assertEqual(_to_python_type_hint("double"), float)
        self.assertEqual(_to_python_type_hint("boolean"), bool)
        self.assertEqual(_to_python_type_hint("string"), str)
        self.assertEqual(_to_python_type_hint("invalid_fallback"), str)

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

    def test_sqlite_response_cache_flow(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            db_file = Path(tmpdir) / "test_cache.db"
            cache = ResponseCache(str(db_file))

            model = "gpt-4o"
            messages = [{"role": "user", "content": "hello"}]
            schema = {"properties": {"score": {"type": "number"}}}
            temp = 0.2
            response = {"score": 0.99, "rationale": "perfect"}

            # Get should be miss initially
            self.assertIsNone(cache.get(model, messages, schema, temp))

            # Set the response
            cache.set(model, messages, schema, temp, response)

            # Get should hit now
            cached = cache.get(model, messages, schema, temp)
            self.assertIsNotNone(cached)
            assert cached is not None
            self.assertEqual(cached.get("score"), 0.99)
            self.assertEqual(cached.get("rationale"), "perfect")

    def test_sqlite_response_cache_bypass_env(self) -> None:
        from prompt_better.openai_structured import get_cache
        
        # Test default is enabled (None = default file)
        os.environ["PROMPT_BETTER_DISABLE_CACHE"] = "0"
        cache = get_cache()
        self.assertIsNotNone(cache)

        # Test disable flag works
        os.environ["PROMPT_BETTER_DISABLE_CACHE"] = "1"
        self.assertIsNone(get_cache())

        # Clean up
        os.environ.pop("PROMPT_BETTER_DISABLE_CACHE", None)


if __name__ == "__main__":
    unittest.main()
