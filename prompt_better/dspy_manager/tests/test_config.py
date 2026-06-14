from __future__ import annotations
import unittest
import tempfile
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from prompt_better.config import build_runtime_config as _build_runtime_config
from prompt_better.dspy_manager import EndpointConfig

class MockArgs:
    def __init__(self, **kwargs):
        self.prompts_dir = ""
        self.prompt = "ALL"
        self.dataset = None
        self.auto = None
        self.num_threads = None
        self.train_ratio = None
        self.student_api_key = None
        self.teacher_api_key = None
        self.apply = False
        self.requires_permission_to_run = None
        self.num_trials = None
        self.minibatch = None
        self.num_candidates = None
        self.evaluator = None
        self.optimizer = None
        self.eval_cases_only = False

        for k, v in kwargs.items():
            setattr(self, k, v)



class ConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp_dir_obj = tempfile.TemporaryDirectory()
        self.tmp_dir = Path(self.tmp_dir_obj.name)
        self.prompts_dir = self.tmp_dir / "prompts"
        self.prompts_dir.mkdir()
        self.config_path = self.tmp_dir / "prompt-better.json"
        
        # Backup environment variables
        self.env_backup = dict(os.environ)

    def tearDown(self) -> None:
        self.tmp_dir_obj.cleanup()
        # Restore environment variables
        os.environ.clear()
        os.environ.update(self.env_backup)

    def write_config(self, data: dict) -> None:
        self.config_path.write_text(json.dumps(data), encoding="utf-8")

    def test_successful_load_no_keys(self) -> None:
        # Config has student and teacher details but no keys
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model"
            },
            "teacher": {
                "base_url": "http://localhost:8080/v1",
                "model": "teacher-model"
            }
        })
        
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        # No env keys set, but localhost base_url doesn't require a key
        config = _build_runtime_config(args)
        
        self.assertEqual(config.student.base_url, "http://localhost:8080/v1")
        self.assertEqual(config.student.model, "student-model")
        self.assertEqual(config.student.api_key, "")
        
        self.assertIsNotNone(config.teacher)
        self.assertEqual(config.teacher.base_url, "http://localhost:8080/v1")
        self.assertEqual(config.teacher.model, "teacher-model")
        self.assertEqual(config.teacher.api_key, "")

    def test_prohibits_student_api_key(self) -> None:
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model",
                "api_key": "some-secret-key"
            },
            "teacher": {
                "base_url": "http://localhost:8080/v1",
                "model": "teacher-model"
            }
        })
        
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        with self.assertRaises(SystemExit) as context:
            _build_runtime_config(args)
        self.assertIn("API keys cannot be specified in prompt-better.json", str(context.exception))

    def test_prohibits_teacher_api_key_dash(self) -> None:
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model"
            },
            "teacher": {
                "base_url": "http://localhost:8080/v1",
                "model": "teacher-model",
                "api-key": "another-key"
            }
        })
        
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        with self.assertRaises(SystemExit) as context:
            _build_runtime_config(args)
        self.assertIn("API keys cannot be specified in prompt-better.json", str(context.exception))

    def test_api_keys_from_env_variables(self) -> None:
        self.write_config({
            "student": {
                "base_url": "https://api.openai.com/v1",
                "model": "gpt-4o"
            },
            "teacher": {
                "base_url": "https://api.openai.com/v1",
                "model": "gpt-4o"
            }
        })
        
        os.environ["PROMPT_BETTER_STUDENT_API_KEY"] = "env-student-key"
        os.environ["PROMPT_BETTER_TEACHER_API_KEY"] = "env-teacher-key"
        
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        config = _build_runtime_config(args)
        
        self.assertEqual(config.student.api_key, "env-student-key")
        self.assertEqual(config.teacher.api_key, "env-teacher-key")

    def test_api_keys_from_cli_args_override_env(self) -> None:
        self.write_config({
            "student": {
                "base_url": "https://api.openai.com/v1",
                "model": "gpt-4o"
            },
            "teacher": {
                "base_url": "https://api.openai.com/v1",
                "model": "gpt-4o"
            }
        })
        
        os.environ["PROMPT_BETTER_STUDENT_API_KEY"] = "env-student-key"
        os.environ["PROMPT_BETTER_TEACHER_API_KEY"] = "env-teacher-key"
        
        args = MockArgs(
            prompts_dir=str(self.prompts_dir),
            student_api_key="cli-student-key",
            teacher_api_key="cli-teacher-key"
        )
        config = _build_runtime_config(args)
        
        self.assertEqual(config.student.api_key, "cli-student-key")
        self.assertEqual(config.teacher.api_key, "cli-teacher-key")

    def test_advanced_dspy_parameters(self) -> None:
        # 1. Config file values
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model"
            },
            "teacher": {
                "base_url": "http://localhost:8080/v1",
                "model": "teacher-model"
            },
            "requires_permission_to_run": False,
            "num_trials": 15,
            "minibatch": True,
            "num_candidates": 8
        })
        
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        config = _build_runtime_config(args)
        
        self.assertFalse(config.requires_permission_to_run)
        self.assertEqual(config.num_trials, 15)
        self.assertTrue(config.minibatch)
        self.assertEqual(config.num_candidates, 8)
        
        # 2. CLI overrides config file
        args_override = MockArgs(
            prompts_dir=str(self.prompts_dir),
            requires_permission_to_run=True,
            num_trials=20,
            minibatch=False,
            num_candidates=10
        )
        config_override = _build_runtime_config(args_override)
        
        self.assertTrue(config_override.requires_permission_to_run)
        self.assertEqual(config_override.num_trials, 20)
        self.assertFalse(config_override.minibatch)
        self.assertEqual(config_override.num_candidates, 10)
        
        # 3. Env overrides CLI & config file
        os.environ["PROMPT_BETTER_REQUIRES_PERMISSION_TO_RUN"] = "0"
        os.environ["PROMPT_BETTER_NUM_TRIALS"] = "30"
        os.environ["PROMPT_BETTER_MINIBATCH"] = "true"
        os.environ["PROMPT_BETTER_NUM_CANDIDATES"] = "25"
        
        config_env = _build_runtime_config(args_override)
        
        self.assertFalse(config_env.requires_permission_to_run)
        self.assertEqual(config_env.num_trials, 30)
        self.assertTrue(config_env.minibatch)
        self.assertEqual(config_env.num_candidates, 25)

    def test_evaluator_parameter(self) -> None:
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model"
            },
            "teacher": {
                "base_url": "http://localhost:8080/v1",
                "model": "teacher-model"
            },
            "evaluator": "config-module.ConfigEvaluator"
        })
        
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        config = _build_runtime_config(args)
        self.assertEqual(config.evaluator, "config-module.ConfigEvaluator")

        # CLI overrides config file
        args_override = MockArgs(
            prompts_dir=str(self.prompts_dir),
            evaluator="cli-module.CliEvaluator"
        )
        config_override = _build_runtime_config(args_override)
        self.assertEqual(config_override.evaluator, "cli-module.CliEvaluator")

        # Env overrides CLI
        os.environ["PROMPT_BETTER_EVALUATOR"] = "env-module.EnvEvaluator"
        config_env = _build_runtime_config(args_override)
        self.assertEqual(config_env.evaluator, "env-module.EnvEvaluator")

    def test_optimizer_parameter(self) -> None:
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model"
            },
            "teacher": {
                "base_url": "http://localhost:8080/v1",
                "model": "teacher-model"
            },
            "optimizer": "config-module.ConfigOptimizer"
        })
        
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        config = _build_runtime_config(args)
        self.assertEqual(config.optimizer, "config-module.ConfigOptimizer")

        # CLI overrides config file
        args_override = MockArgs(
            prompts_dir=str(self.prompts_dir),
            optimizer="cli-module.CliOptimizer"
        )
        config_override = _build_runtime_config(args_override)
        self.assertEqual(config_override.optimizer, "cli-module.CliOptimizer")

        # Env overrides CLI
        os.environ["PROMPT_BETTER_OPTIMIZER"] = "env-module.EnvOptimizer"
        config_env = _build_runtime_config(args_override)
        self.assertEqual(config_env.optimizer, "env-module.EnvOptimizer")

    def test_temperature_defaults(self) -> None:
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model"
            },
            "teacher": {
                "base_url": "http://localhost:8080/v1",
                "model": "teacher-model"
            }
        })
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        config = _build_runtime_config(args)
        # Check student defaults
        self.assertEqual(config.student.temperature, 0.2)
        self.assertEqual(config.student.eval_temperature, 0.0)
        # Check teacher defaults
        self.assertIsNotNone(config.teacher)
        self.assertEqual(config.teacher.temperature, 0.2)
        self.assertEqual(config.teacher.eval_temperature, 0.0)

    def test_temperature_hierarchical_resolution(self) -> None:
        # 1. Config file values
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model",
                "temperature": 0.4
            },
            "teacher": {
                "base_url": "http://localhost:8080/v1",
                "model": "teacher-model",
                "temperature": 0.5,
                "eval_temperature": 0.1
            }
        })
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        config = _build_runtime_config(args)
        self.assertEqual(config.student.temperature, 0.4)
        self.assertEqual(config.teacher.temperature, 0.5)
        self.assertEqual(config.teacher.eval_temperature, 0.1)

        # 2. CLI overrides config file
        args_override = MockArgs(
            prompts_dir=str(self.prompts_dir),
            student_temperature=0.6,
            teacher_temperature=0.7,
            teacher_eval_temperature=0.3
        )
        config_override = _build_runtime_config(args_override)
        self.assertEqual(config_override.student.temperature, 0.6)
        self.assertEqual(config_override.teacher.temperature, 0.7)
        self.assertEqual(config_override.teacher.eval_temperature, 0.3)

        # 3. Env overrides CLI & config file
        os.environ["PROMPT_BETTER_STUDENT_TEMPERATURE"] = "0.8"
        os.environ["PROMPT_BETTER_TEACHER_TEMPERATURE"] = "0.9"
        os.environ["PROMPT_BETTER_TEACHER_EVAL_TEMPERATURE"] = "0.4"
        
        config_env = _build_runtime_config(args_override)
        self.assertEqual(config_env.student.temperature, 0.8)
        self.assertEqual(config_env.teacher.temperature, 0.9)
        self.assertEqual(config_env.teacher.eval_temperature, 0.4)

    def test_build_lm_temperature_override(self) -> None:
        from unittest.mock import MagicMock
        from prompt_better.dspy_manager.optimizer import _build_lm
        from prompt_better.dspy_manager import EndpointConfig
        
        config = EndpointConfig(
            base_url="http://localhost:8080/v1",
            model="apple-intelligence",
            api_key="key",
            temperature=0.4
        )
        
        mock_dspy = MagicMock()
        
        # 1. Uses config temperature if no override passed
        _build_lm(mock_dspy, config)
        mock_dspy.LM.assert_called_with(
            "openai/apple-intelligence",
            api_key="key",
            api_base="http://localhost:8080/v1",
            model_type="chat",
            temperature=0.4
        )
        
        # 2. Uses override temperature if passed
        _build_lm(mock_dspy, config, temperature=0.7)
        mock_dspy.LM.assert_called_with(
            "openai/apple-intelligence",
            api_key="key",
            api_base="http://localhost:8080/v1",
            model_type="chat",
            temperature=0.7
        )

    def test_build_runtime_config_without_teacher(self) -> None:
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model"
            }
        })
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        config = _build_runtime_config(args)
        self.assertIsNone(config.teacher)

    def test_optimize_prompt_raises_when_no_teacher(self) -> None:
        from prompt_better.dspy_manager.optimizer import optimize_prompt, PromptOptimizationError
        self.write_config({
            "student": {
                "base_url": "http://localhost:8080/v1",
                "model": "student-model"
            }
        })
        args = MockArgs(prompts_dir=str(self.prompts_dir))
        config = _build_runtime_config(args)
        with self.assertRaises(PromptOptimizationError) as ctx:
            optimize_prompt(config)
        self.assertIn("Teacher model configuration is missing", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()

