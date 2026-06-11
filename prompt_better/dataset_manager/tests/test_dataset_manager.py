from __future__ import annotations
import sys
import unittest
import tempfile
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from prompt_better.dataset_manager import (
    load_examples,
    examples_for_prompt,
    split_examples,
    resolve_history_messages,
    flatten_history,
    token_f1,
)
from prompt_better.prompt_json.models import PromptSpec


class DatasetManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp_dir_obj = tempfile.TemporaryDirectory()
        self.tmp_dir = Path(self.tmp_dir_obj.name)

    def tearDown(self) -> None:
        self.tmp_dir_obj.cleanup()

    def test_token_f1(self) -> None:
        self.assertAlmostEqual(token_f1("hello world", "hello world"), 1.0)
        self.assertAlmostEqual(token_f1("hello world", "hello"), 0.6666666, places=5)
        self.assertAlmostEqual(token_f1("hello", ""), 0.0)

    def test_load_examples_ignores_legacy_files(self) -> None:
        legacy_file = self.tmp_dir / "legacy_dataset.json"
        legacy_file.write_text(json.dumps({
            "ArticleInsightPrompt": [
                {
                    "id": "case1",
                    "inputs": {"input": "test"},
                    "reference_output": {"summary": "test summary"},
                }
            ]
        }), encoding="utf-8")
        
        examples = load_examples(legacy_file)
        self.assertEqual(len(examples), 0)

    def test_load_examples_nested_layout(self) -> None:
        prompt_dir = self.tmp_dir / "ArticleInsight"
        dataset_dir = prompt_dir / "dataset"
        golden_dir = prompt_dir / "golden-truth"
        dataset_dir.mkdir(parents=True)
        golden_dir.mkdir(parents=True)
        
        case_file = dataset_dir / "case1.json"
        case_file.write_text(json.dumps({
            "id": "case1",
            "inputs": {"input": "Hello test article."},
            "history": [
                {"role": "user", "content": "hello"}
            ]
        }), encoding="utf-8")
        
        golden_file = golden_dir / "case1.json"
        golden_file.write_text(json.dumps({
            "reference_output": {"summary": "test summary"},
            "rubric": ["must be accurate"]
        }), encoding="utf-8")
        
        examples = load_examples(self.tmp_dir)
        self.assertEqual(len(examples), 1)
        ex = examples[0]
        self.assertEqual(ex.example_id, "case1")
        self.assertEqual(ex.prompt_name, "ArticleInsightPrompt")
        self.assertEqual(ex.inputs["input"], "Hello test article.")
        self.assertEqual(ex.reference_output["summary"], "test summary")
        self.assertEqual(ex.rubric, ["must be accurate"])
        self.assertEqual(len(ex.history), 1)
        self.assertEqual(ex.history[0].role, "user")
        self.assertEqual(ex.history[0].content, "hello")

    def test_examples_for_prompt(self) -> None:
        prompt_dir = self.tmp_dir / "ArticleInsight"
        dataset_dir = prompt_dir / "dataset"
        golden_dir = prompt_dir / "golden-truth"
        dataset_dir.mkdir(parents=True)
        golden_dir.mkdir(parents=True)
        
        (dataset_dir / "case1.json").write_text(json.dumps({"id": "case1", "inputs": {"input": "one"}}), encoding="utf-8")
        (golden_dir / "case1.json").write_text(json.dumps({"reference_output": {"summary": "one"}}), encoding="utf-8")
        
        examples = load_examples(self.tmp_dir)
        filtered = examples_for_prompt(examples, "ArticleInsightPrompt")
        self.assertEqual(len(filtered), 1)
        
        filtered_empty = examples_for_prompt(examples, "NonexistentPrompt")
        self.assertEqual(len(filtered_empty), 0)

    def test_split_examples(self) -> None:
        prompt_dir = self.tmp_dir / "ArticleInsight"
        dataset_dir = prompt_dir / "dataset"
        golden_dir = prompt_dir / "golden-truth"
        dataset_dir.mkdir(parents=True)
        golden_dir.mkdir(parents=True)
        
        for i in range(5):
            (dataset_dir / f"case{i}.json").write_text(json.dumps({"id": f"case{i}", "inputs": {"input": str(i)}}), encoding="utf-8")
            (golden_dir / f"case{i}.json").write_text(json.dumps({"reference_output": {"summary": str(i)}}), encoding="utf-8")
            
        examples = load_examples(self.tmp_dir)
        train, val = split_examples(examples, 0.6)
        self.assertEqual(len(train), 3)
        self.assertEqual(len(val), 2)


    def test_load_examples_validation_warning(self) -> None:
        # Create invalid nested structures that fail schema constraints
        prompt_dir = self.tmp_dir / "ArticleInsight"
        dataset_dir = prompt_dir / "dataset"
        golden_dir = prompt_dir / "golden-truth"
        dataset_dir.mkdir(parents=True)
        golden_dir.mkdir(parents=True)
        
        # Missing required "inputs" key in dataset
        case_file = dataset_dir / "case1.json"
        case_file.write_text(json.dumps({
            "id": "case1"
        }), encoding="utf-8")
        
        # Missing required "reference_output" key in golden truth
        golden_file = golden_dir / "case1.json"
        golden_file.write_text(json.dumps({
            "rubric": ["must fail schema"]
        }), encoding="utf-8")
        
        # Capture warning messages printed to stdout during load
        import io
        from contextlib import redirect_stdout
        
        f = io.StringIO()
        with redirect_stdout(f):
            load_examples(self.tmp_dir)
            
        output = f.getvalue()
        self.assertIn("Warning: Dataset case file", output)
        self.assertIn("Warning: Golden truth case file", output)


if __name__ == "__main__":
    unittest.main()
