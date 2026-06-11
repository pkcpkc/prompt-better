from __future__ import annotations
import unittest
import tempfile
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from prompt_better.dspy_manager import BaseEvaluator, DefaultEvaluator, load_evaluator
from prompt_better.prompt_json.models import PromptSpec, PromptFieldSpec, InstructionsSpec


class DummyCustomEvaluator(BaseEvaluator):
    def structural_score(self, spec: Any, candidate: Dict[str, Any]) -> float:
        return 0.99

    def similarity_score(self, spec: Any, reference: Dict[str, Any], candidate: Dict[str, Any]) -> float:
        return 0.88


class EvaluatorTests(unittest.TestCase):
    def test_load_evaluator_none(self) -> None:
        evaluator = load_evaluator(None)
        self.assertIsInstance(evaluator, DefaultEvaluator)

    def test_load_evaluator_dotted_path(self) -> None:
        evaluator = load_evaluator("prompt_better.dspy_manager.tests.test_evaluator.DummyCustomEvaluator")
        self.assertIsInstance(evaluator, DummyCustomEvaluator)
        self.assertEqual(evaluator.structural_score(None, {}), 0.99)

    def test_load_evaluator_file_path_with_class(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "custom.py"
            file_path.write_text(
                "from prompt_better.dspy_manager import BaseEvaluator\n"
                "class FileEvaluator(BaseEvaluator):\n"
                "    def structural_score(self, spec, candidate):\n"
                "        return 0.77\n",
                encoding="utf-8"
            )
            evaluator = load_evaluator(f"{file_path.resolve()}:FileEvaluator")
            self.assertEqual(evaluator.structural_score(None, {}), 0.77)

    def test_load_evaluator_file_path_auto_detect(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "custom_auto.py"
            file_path.write_text(
                "from prompt_better.dspy_manager import BaseEvaluator\n"
                "class AutoFileEvaluator(BaseEvaluator):\n"
                "    def structural_score(self, spec, candidate):\n"
                "        return 0.66\n",
                encoding="utf-8"
            )
            evaluator = load_evaluator(str(file_path.resolve()))
            self.assertEqual(evaluator.structural_score(None, {}), 0.66)

    def test_default_evaluator_structural_score(self) -> None:
        spec = PromptSpec(
            name="TestPrompt",
            instructions=InstructionsSpec(
                prompt="Template",
                context=[]
            ),
            outputs=[
                PromptFieldSpec(name="field1", type="string", desc="f1"),
                PromptFieldSpec(name="field2", type="array", desc="f2", items="string", min_count=2, max_count=2)
            ]
        )
        evaluator = DefaultEvaluator()

        # Valid candidate
        candidate_ok = {"field1": "hello", "field2": ["item1", "item2"]}
        self.assertEqual(evaluator.structural_score(spec, candidate_ok), 1.0)

        # Invalid candidate: wrong count for array, empty string
        candidate_bad = {"field1": "", "field2": ["item1"]}
        # field1: empty string -> 0.0
        # field2: not exact count -> 0.0, but all items are non-empty -> 1.0 (so average for field2 checks is 0.5)
        # checks list: field1 is 0.0; field2 has count check (0.0), type checks (all items non-empty -> 1.0).
        # Total checks: [0.0, 0.0, 1.0] -> average 0.3333
        self.assertAlmostEqual(evaluator.structural_score(spec, candidate_bad), 0.3333, places=4)

    def test_default_evaluator_similarity_score(self) -> None:
        spec = PromptSpec(
            name="TestPrompt",
            instructions=InstructionsSpec(
                prompt="Template",
                context=[]
            ),
            outputs=[
                PromptFieldSpec(name="field1", type="string", desc="f1")
            ]
        )
        evaluator = DefaultEvaluator()
        ref = {"field1": "hello world"}
        cand = {"field1": "hello there"}
        # token f1 check
        score = evaluator.similarity_score(spec, ref, cand)
        self.assertTrue(0.0 < score < 1.0)

    def test_teacher_score_temperature_resolution(self) -> None:
        from unittest.mock import patch
        from prompt_better.dspy_manager import OptimizationConfig, EndpointConfig

        spec = PromptSpec(
            name="TestPrompt",
            instructions=InstructionsSpec(
                prompt="Template",
                context=[]
            ),
            outputs=[PromptFieldSpec(name="field1", type="string", desc="f1")]
        )

        class DummyExample:
            id = "case1"
            inputs = {}
            reference_output = {}
            rubric = []
            history = []

        config_with_override = OptimizationConfig(
            student=EndpointConfig(base_url="http://localhost", model="m", api_key="k"),
            teacher=EndpointConfig(base_url="http://localhost", model="m2", api_key="k", eval_temperature=0.3),
            prompts_dir=Path("."),
            dataset_file=Path("."),
            prompt_name="ALL",
            teacher_eval_temp_override=0.5
        )

        config_global_fallback = OptimizationConfig(
            student=EndpointConfig(base_url="http://localhost", model="m", api_key="k"),
            teacher=EndpointConfig(base_url="http://localhost", model="m2", api_key="k", eval_temperature=0.3),
            prompts_dir=Path("."),
            dataset_file=Path("."),
            prompt_name="ALL",
            teacher_eval_temp_override=None
        )

        evaluator = DefaultEvaluator()
        
        # 1. Override is used
        with patch("prompt_better.dspy_manager.evaluator.call_json_schema") as mock_call:
            mock_call.return_value = {"score": 0.8, "rationale": "OK"}
            evaluator.teacher_score(spec, DummyExample(), {}, {}, config_with_override)
            mock_call.assert_called_once()
            self.assertEqual(mock_call.call_args[1]["temperature"], 0.5)

        # 2. Global config is used when no override
        with patch("prompt_better.dspy_manager.evaluator.call_json_schema") as mock_call:
            mock_call.return_value = {"score": 0.8, "rationale": "OK"}
            evaluator.teacher_score(spec, DummyExample(), {}, {}, config_global_fallback)
            mock_call.assert_called_once()
            self.assertEqual(mock_call.call_args[1]["temperature"], 0.3)

    def test_aggregate_and_dspy_scores(self) -> None:
        spec = PromptSpec(
            name="TestPrompt",
            instructions=InstructionsSpec(
                prompt="Template",
                context=[]
            ),
            outputs=[PromptFieldSpec(name="field1", type="string", desc="f1")]
        )
        evaluator = DefaultEvaluator()

        # aggregate_score: ((0.55 * struct + 0.45 * similarity) + teacher_score) / 2
        # similarity = 0.0 -> aggregate score is ((0.0) + 0.8) / 2 = 0.4
        score_zero_sim = evaluator.aggregate_score(spec, 1.0, 0.0, 0.8)
        self.assertEqual(score_zero_sim, 0.4)

        # similarity = 1.0, struct = 1.0, teacher_score = 0.8 -> ((0.55 * 1.0 + 0.45 * 1.0) + 0.8) / 2 = (1.0 + 0.8) / 2 = 0.9
        score_ok = evaluator.aggregate_score(spec, 1.0, 1.0, 0.8)
        self.assertEqual(score_ok, 0.9)

        # dspy_score: (0.55 * struct) + (0.45 * similarity) without teacher
        # similarity = 0.0 -> 0.0
        dspy_score_zero_sim = evaluator.dspy_score(spec, {"field1": "hello"}, {"field1": ""})
        self.assertEqual(dspy_score_zero_sim, 0.0)

        # similarity = 1.0 (both same), struct = 1.0 (valid string) -> 0.55 * 1.0 + 0.45 * 1.0 = 1.0
        dspy_score_ok = evaluator.dspy_score(spec, {"field1": "hello"}, {"field1": "hello"})
        self.assertEqual(dspy_score_ok, 1.0)


if __name__ == "__main__":
    unittest.main()
