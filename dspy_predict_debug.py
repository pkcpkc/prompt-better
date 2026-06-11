import sys
import os
import dspy
from pathlib import Path

# Setup paths
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from prompt_better.prompt_json import load_prompt_specs
from prompt_better.dspy_manager.optimizer import _build_lm, _build_module
from prompt_better.cli import _build_runtime_config

# Mock args to build runtime config
class MockArgs:
    def __init__(self):
        self.prompts_dir = "example/prompts"
        self.prompt = "TopicClassifierPrompt"
        self.dataset = "example/prompts"


        self.auto = None
        self.num_threads = 1
        self.train_ratio = 0.8
        self.student_api_key = os.getenv("PROMPT_BETTER_STUDENT_API_KEY", "")
        self.teacher_api_key = os.getenv("PROMPT_BETTER_TEACHER_API_KEY", "")
        self.student_temperature = 0.0
        self.teacher_temperature = 0.2
        self.teacher_eval_temperature = 0.0
        self.apply = False
        self.requires_permission_to_run = False
        self.num_trials = None
        self.minibatch = None
        self.num_candidates = None
        self.evaluator = None
        self.optimizer = "predict"
        self.eval_cases_only = False

config = _build_runtime_config(MockArgs())
student_lm = _build_lm(dspy, config.student)
dspy.configure(lm=student_lm)

specs = load_prompt_specs(config.prompts_dir)
spec = specs["TopicClassifierPrompt"]

from prompt_better.dataset_manager import load_examples, examples_for_prompt
examples = load_examples(config.dataset_file)
prompt_examples = examples_for_prompt(examples, "TopicClassifierPrompt")

module = _build_module(dspy, spec, prompt_examples, chain_of_thought=False)
module.set_lm(student_lm)

# Run one example
ex = prompt_examples[0]
print(f"Inputs: {ex.inputs}")
try:
    pred = module(text=ex.inputs["text"])
    print("Prediction succeeded!")
    print(pred)
except Exception as e:
    print("Prediction failed!")
    import traceback
    traceback.print_exc()

# Let's inspect the last prompt and response
if hasattr(student_lm, "history") and student_lm.history:
    print("\n--- Last LM Call ---")
    print(student_lm.history[-1])
