from __future__ import annotations

import io
import json
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from prompt_better.dspy_manager.reporter import print_report_summary as _print_report_summary
from prompt_better.dspy_manager.optimizer import _get_baseline_eval_results
from prompt_better.dspy_manager.models import OptimizationConfig, EndpointConfig


class ReportingTests(unittest.TestCase):
    def test_print_report_summary_evaluate(self) -> None:
        baseline_report = {
            "prompt_name": "TestPrompt",
            "count": 2,
            "average_structural_score": 1.0,
            "average_similarity_score": 0.8,
            "average_aggregate_score": 0.9,
            "average_teacher_score": 0.95,
            "evaluations": [
                {
                    "example_id": "case1",
                    "structural_score": 1.0,
                    "similarity_score": 0.9,
                    "aggregate_score": 0.95,
                    "teacher_score": 1.0,
                    "teacher_rationale": "Perfect structure and content alignment.",
                },
                {
                    "example_id": "case2",
                    "structural_score": 1.0,
                    "similarity_score": 0.7,
                    "aggregate_score": 0.85,
                    "teacher_score": 0.9,
                    "teacher_rationale": "Minor differences.",
                }
            ]
        }

        f = io.StringIO()
        with patch("sys.stdout", f):
            _print_report_summary(
                prompt_name="TestPrompt",
                is_optimize=False,
                baseline_report=baseline_report,
            )
        output = f.getvalue()

        self.assertIn("Evaluation result: TestPrompt", output)
        self.assertIn("Examples count        : 2", output)
        self.assertIn("Average optimization:", output)
        self.assertIn("|                 |   aggregate score   |   structural score   |   similarity score   |   teacher score   |", output)
        self.assertIn("| :-------------- | :-----------------: | :------------------: | :------------------: | :---------------: |", output)
        self.assertIn("| baseline        |       0.9000        |        1.0000        |        0.8000        |      0.9500       |", output)
        self.assertIn("| case1           |       0.9500        |        1.0000        |        0.9000        |      1.0000       |", output)
        self.assertIn("| case2           |       0.8500        |        1.0000        |        0.7000        |      0.9000       |", output)
        self.assertIn("Perfect structure and content alignment.", output)
        self.assertIn("Minor differences.", output)

    def test_print_report_summary_optimize(self) -> None:
        baseline_report = {
            "average_structural_score": 0.5,
            "average_similarity_score": 0.4,
            "average_aggregate_score": 0.45,
            "average_teacher_score": 0.6,
            "evaluations": [
                {
                    "example_id": "case1",
                    "structural_score": 0.5,
                    "similarity_score": 0.4,
                    "aggregate_score": 0.45,
                    "teacher_score": 0.6,
                },
                {
                    "example_id": "case2",
                    "structural_score": 0.5,
                    "similarity_score": 0.4,
                    "aggregate_score": 0.45,
                    "teacher_score": 0.6,
                }
            ]
        }
        optimized_report = {
            "average_structural_score": 1.0,
            "average_similarity_score": 0.9,
            "average_aggregate_score": 0.95,
            "average_teacher_score": 0.8,
            "results": [
                {
                    "example_id": "case1",
                    "structural_score": 1.0,
                    "similarity_score": 0.9,
                    "aggregate_score": 0.95,
                    "teacher_score": 0.8,
                    "teacher_rationale": "Improved significantly.",
                },
                {
                    "example_id": "case2",
                    "structural_score": 1.0,
                    "similarity_score": 0.9,
                    "aggregate_score": 0.95,
                    "teacher_score": 0.8,
                    "teacher_rationale": "Improved significantly too.",
                }
            ]
        }

        f = io.StringIO()
        with patch("sys.stdout", f):
            _print_report_summary(
                prompt_name="TestPrompt",
                is_optimize=True,
                baseline_report=baseline_report,
                optimized_report=optimized_report,
                train_size=8,
                evalset_ids={"case1"},
            )
        output = f.getvalue()

        self.assertIn("Optimization result: TestPrompt", output)
        self.assertIn("Train / eval examples : 8 / 2", output)
        self.assertIn("Average optimization:", output)
        self.assertIn("|                 |   aggregate score   |   structural score   |   similarity score   |   teacher score   |", output)
        self.assertIn("| :-------------- | :-----------------: | :------------------: | :------------------: | :---------------: |", output)
        self.assertIn("| baseline        |       0.4500        |        0.5000        |        0.4000        |      0.6000       |", output)
        self.assertIn("| optimization    |       0.9500        |        1.0000        |        0.9000        |      0.8000       |", output)
        # Difference checks: (1.0 - 0.5 = 0.5), (0.9 - 0.4 = 0.5), (0.95 - 0.45 = 0.5), (0.8 - 0.6 = 0.2)
        self.assertIn("| case1 (eval)    |       +0.5000       |       +0.5000        |       +0.5000        |      +0.2000      |", output)
        self.assertIn("| case2 (train)   |       +0.5000       |       +0.5000        |       +0.5000        |      +0.2000      |", output)
        self.assertIn("Improved significantly.", output)
        self.assertIn("Improved significantly too.", output)


if __name__ == "__main__":
    unittest.main()
