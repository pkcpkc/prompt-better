from __future__ import annotations
import sys
import unittest
from pathlib import Path
import dspy

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from prompt_better.prompt_json.dspy_converter import (
    _to_python_type_hint,
    build_dspy_signature,
    to_dspy_examples,
    prediction_to_dict,
)
from prompt_better.prompt_json.models import PromptSpec, InstructionsSpec, PromptFieldSpec
from prompt_better.dataset_manager.models import PromptExample


class DSPyConverterTests(unittest.TestCase):
    def test_to_python_type_hint_mappings(self) -> None:
        self.assertEqual(_to_python_type_hint("integer"), int)
        self.assertEqual(_to_python_type_hint("number"), float)
        self.assertEqual(_to_python_type_hint("float"), float)
        self.assertEqual(_to_python_type_hint("double"), float)
        self.assertEqual(_to_python_type_hint("boolean"), bool)
        self.assertEqual(_to_python_type_hint("string"), str)
        self.assertEqual(_to_python_type_hint("invalid_fallback"), str)

    def test_build_dspy_signature_flat_outputs(self) -> None:
        spec = PromptSpec(
            name="TestPrompt",
            instructions=InstructionsSpec(
                prompt="Classify: {{text}}",
                context=[
                    PromptFieldSpec(name="text", type="string", desc="Input text", role="input"),
                ],
            ),
            outputs=[
                PromptFieldSpec(name="topic", type="string", desc="Topic output", role="output"),
                PromptFieldSpec(name="score", type="number", desc="Confidence score", role="output"),
            ],
        )
        sig = build_dspy_signature(dspy, spec, [])
        
        # Verify inputs and outputs are flat fields on signature
        self.assertIn("text", sig.input_fields)
        self.assertIn("topic", sig.output_fields)
        self.assertIn("score", sig.output_fields)
        
        self.assertNotIn("output", sig.output_fields)
        self.assertEqual(sig.input_fields["text"].json_schema_extra["desc"], "Input text")
        self.assertEqual(sig.output_fields["topic"].json_schema_extra["desc"], "Topic output")

    def test_to_dspy_examples_flat_mapping(self) -> None:
        spec = PromptSpec(
            name="TestPrompt",
            instructions=InstructionsSpec(
                prompt="Classify: {{text}}",
                context=[
                    PromptFieldSpec(name="text", type="string", desc="Input text", role="input"),
                ],
            ),
            outputs=[
                PromptFieldSpec(name="topic", type="string", desc="Topic output", role="output"),
            ],
        )
        ex = PromptExample(
            id="1",
            prompt_name="TestPrompt",
            inputs={"text": "hello"},
            reference_output={"topic": "greeting"},
        )
        
        dspy_examples = to_dspy_examples(dspy, [ex], spec, {})
        self.assertEqual(len(dspy_examples), 1)
        dspy_ex = dspy_examples[0]
        
        # Verify fields are unpacked flatly
        self.assertEqual(dspy_ex.text, "hello")
        self.assertEqual(dspy_ex.topic, "greeting")
        self.assertFalse(hasattr(dspy_ex, "output"))

    def test_prediction_to_dict_flat_and_legacy(self) -> None:
        spec = PromptSpec(
            name="TestPrompt",
            instructions=InstructionsSpec(
                prompt="Classify: {{text}}",
                context=[
                    PromptFieldSpec(name="text", type="string", desc="Input text", role="input"),
                ],
            ),
            outputs=[
                PromptFieldSpec(name="topic", type="string", desc="Topic output", role="output"),
                PromptFieldSpec(name="score", type="number", desc="Score output", role="output"),
            ],
        )
        
        # Test Flat prediction object
        flat_pred = dspy.Prediction(topic="tech", score=0.9)
        d = prediction_to_dict(flat_pred, spec)
        self.assertEqual(d, {"topic": "tech", "score": 0.9})
        
        # Test Legacy nested prediction object (e.g. dict output)
        legacy_pred_dict = dspy.Prediction(output={"topic": "sports", "score": 0.5})
        d2 = prediction_to_dict(legacy_pred_dict, spec)
        self.assertEqual(d2, {"topic": "sports", "score": 0.5})
        
        # Test Legacy nested prediction object (Pydantic output)
        from pydantic import BaseModel
        class MockLegacyOutput(BaseModel):
            topic: str
            score: float
        
        legacy_pred_pydantic = dspy.Prediction(output=MockLegacyOutput(topic="news", score=0.8))
        d3 = prediction_to_dict(legacy_pred_pydantic, spec)
        self.assertEqual(d3, {"topic": "news", "score": 0.8})


if __name__ == "__main__":
    unittest.main()
