from __future__ import annotations
import unittest
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

from prompt_better.dspy_manager import BaseOptimizer, DefaultOptimizer, load_optimizer


class DummyCustomOptimizer(BaseOptimizer):
    def compile(
        self,
        config: Any,
        spec: Any,
        specs: Dict[str, Any],
        student_lm: Any,
        teacher_lm: Any,
        trainset: List[Any],
        evalset: List[Any],
        metric: Any,
        module: Any,
    ) -> Any:
        return "customCompiledModule"


class OptimizerTests(unittest.TestCase):
    def test_load_optimizer_none(self) -> None:
        optimizer = load_optimizer(None)
        self.assertIsInstance(optimizer, DefaultOptimizer)

    def test_load_optimizer_builtin_modes(self) -> None:
        optimizer_predict = load_optimizer("predict")
        self.assertIsInstance(optimizer_predict, DefaultOptimizer)
        
        optimizer_cot = load_optimizer("chain-of-thought")
        self.assertIsInstance(optimizer_cot, DefaultOptimizer)


    def test_load_optimizer_dotted_path(self) -> None:
        optimizer = load_optimizer("prompt_better.dspy_manager.tests.test_optimizers.DummyCustomOptimizer")
        self.assertIsInstance(optimizer, DummyCustomOptimizer)
        self.assertEqual(
            optimizer.compile(None, None, {}, None, None, [], [], None, None),
            "customCompiledModule"
        )

    def test_load_optimizer_file_path_with_class(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "custom_opt.py"
            file_path.write_text(
                "from prompt_better.dspy_manager import BaseOptimizer\n"
                "class FileOptimizer(BaseOptimizer):\n"
                "    def compile(self, *args, **kwargs):\n"
                "        return 'fileOptCompiled'\n",
                encoding="utf-8"
            )
            optimizer = load_optimizer(f"{file_path.resolve()}:FileOptimizer")
            self.assertEqual(optimizer.compile(None, None, {}, None, None, [], [], None, None), "fileOptCompiled")

    def test_load_optimizer_file_path_auto_detect(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "custom_opt_auto.py"
            file_path.write_text(
                "from prompt_better.dspy_manager import BaseOptimizer\n"
                "class AutoFileOptimizer(BaseOptimizer):\n"
                "    def compile(self, *args, **kwargs):\n"
                "        return 'autoFileOptCompiled'\n",
                encoding="utf-8"
            )
            optimizer = load_optimizer(str(file_path.resolve()))
            self.assertEqual(optimizer.compile(None, None, {}, None, None, [], [], None, None), "autoFileOptCompiled")

    def test_wrap_module_deepcopy_compatibility(self) -> None:
        import dspy
        import copy
        from prompt_better.dspy_manager.optimizer import _wrap_module_to_handle_errors

        # Create a signature and Predict module
        sig = dspy.Signature("question -> answer", "Original Instructions")
        p = dspy.Predict(sig)

        # Wrap it
        wrapped = _wrap_module_to_handle_errors(p)

        # Make a deepcopy
        copied = copy.deepcopy(wrapped)

        # Update signature of the copy
        new_sig = sig.with_instructions("Updated Instructions")
        copied.signature = new_sig

        self.assertEqual(wrapped.signature.instructions, "Original Instructions")
        self.assertEqual(copied.signature.instructions, "Updated Instructions")

        # Mock a Dummy LM to inspect what instructions it receives when called
        class DummyLM(dspy.LM):
            def __init__(self) -> None:
                super().__init__("openai/gpt-4o-mini")
                self.calls: List[Any] = []

            def __call__(self, *args: Any, **kwargs: Any) -> List[str]:
                self.calls.append((args, kwargs))
                return ['{"answer": "mocked"}']

        dummy_lm = DummyLM()
        dspy.settings.configure(lm=dummy_lm)

        # Test original wrapped module uses Original Instructions
        wrapped(question="test original")
        self.assertTrue(len(dummy_lm.calls) > 0)
        system_content_orig = next(
            m["content"] for m in dummy_lm.calls[-1][1].get("messages", []) if m["role"] == "system"
        )
        self.assertIn("Original Instructions", system_content_orig)

        # Test copied module uses Updated Instructions
        dummy_lm.calls.clear()
        copied(question="test copied")
        self.assertTrue(len(dummy_lm.calls) > 0)
        system_content_copied = next(
            m["content"] for m in dummy_lm.calls[-1][1].get("messages", []) if m["role"] == "system"
        )
        self.assertIn("Updated Instructions", system_content_copied)


if __name__ == "__main__":
    unittest.main()
