import importlib
import importlib.util
import inspect
import sys
from pathlib import Path
from typing import Any

from .models import OptimizationConfig


class BaseOptimizer:
    """Base class for prompt optimization.

    Users can subclass this to customize how DSPy modules (or other prompts) are optimized.
    """

    def compile(
        self,
        config: OptimizationConfig,
        spec: Any,
        specs: dict[str, Any],
        student_lm: Any,
        teacher_lm: Any,
        trainset: list[Any],
        evalset: list[Any],
        metric: Any,
        module: Any,
    ) -> Any:
        """Optimize/compile the given DSPy module and return the compiled/optimized module."""
        raise NotImplementedError


class DefaultOptimizer(BaseOptimizer):
    """Default optimizer using DSPy's MIPROv2 compiler."""

    def compile(
        self,
        config: OptimizationConfig,
        spec: Any,
        specs: dict[str, Any],
        student_lm: Any,
        teacher_lm: Any,
        trainset: list[Any],
        evalset: list[Any],
        metric: Any,
        module: Any,
    ) -> Any:
        import dspy

        from prompt_better.prompt_json import to_dspy_examples

        optimizer_kwargs: dict[str, Any] = {
            "metric": metric,
            "auto": config.auto_mode,
            "num_threads": config.num_threads,
        }
        if config.num_candidates is not None:
            optimizer_kwargs["num_candidates"] = config.num_candidates

        optimizer_signature = inspect.signature(dspy.MIPROv2)
        if teacher_lm is not None and "prompt_model" in optimizer_signature.parameters:
            optimizer_kwargs["prompt_model"] = teacher_lm
        if "task_model" in optimizer_signature.parameters:
            optimizer_kwargs["task_model"] = student_lm

        optimizer = dspy.MIPROv2(**optimizer_kwargs)

        compile_kwargs: dict[str, Any] = {
            "trainset": to_dspy_examples(dspy, trainset, spec, specs),
            "valset": to_dspy_examples(dspy, evalset, spec, specs),
            "requires_permission_to_run": config.requires_permission_to_run,
        }
        if config.num_trials is not None:
            compile_kwargs["num_trials"] = config.num_trials
        if config.minibatch is not None:
            compile_kwargs["minibatch"] = config.minibatch

        return optimizer.compile(module, **compile_kwargs)


class GepaOptimizer(BaseOptimizer):
    """Reflective prompt optimizer using DSPy's GEPA compiler."""

    def compile(
        self,
        config: OptimizationConfig,
        spec: Any,
        specs: dict[str, Any],
        student_lm: Any,
        teacher_lm: Any,
        trainset: list[Any],
        evalset: list[Any],
        metric: Any,
        module: Any,
    ) -> Any:
        import dspy

        from prompt_better.prompt_json import to_dspy_examples

        optimizer_kwargs: dict[str, Any] = {
            "metric": metric,
            "auto": config.auto_mode,
            "num_threads": config.num_threads,
        }
        if teacher_lm is not None:
            optimizer_kwargs["reflection_lm"] = teacher_lm
        if config.num_trials is not None:
            optimizer_kwargs["max_metric_calls"] = config.num_trials

        optimizer = dspy.GEPA(**optimizer_kwargs)

        compile_kwargs: dict[str, Any] = {
            "trainset": to_dspy_examples(dspy, trainset, spec, specs),
            "valset": to_dspy_examples(dspy, evalset, spec, specs),
        }

        return optimizer.compile(module, **compile_kwargs)


def load_optimizer(optimizer_path: str | None) -> BaseOptimizer:
    """Dynamically load an Optimizer instance from a class path or file path."""
    if not optimizer_path or optimizer_path.lower() in (
        "predict",
        "chain-of-thought",
        "mipro",
        "miprov2",
        "default",
    ):
        return DefaultOptimizer()

    if optimizer_path.lower() == "gepa":
        return GepaOptimizer()



    try:
        # Check if it has a colon separating file/module and class name
        if ":" in optimizer_path:
            module_part, class_name = optimizer_path.rsplit(":", 1)
        else:
            # If no colon, assume class name is last component of a dotted path,
            # or look for subclasses of BaseOptimizer in the module/file.
            if optimizer_path.endswith(".py") or "/" in optimizer_path or "\\" in optimizer_path:
                module_part = optimizer_path
                class_name = None
            else:
                module_part, class_name = optimizer_path.rsplit(".", 1)

        path = Path(module_part)
        if path.exists() and path.is_file():
            # Load as a file
            module_name = path.stem
            spec = importlib.util.spec_from_file_location(module_name, str(path.resolve()))
            if spec is None or spec.loader is None:
                raise ImportError(f"Could not load spec for file {module_part}")
            module = importlib.util.module_from_spec(spec)
            sys.modules[module_name] = module
            spec.loader.exec_module(module)
        else:
            # Load as a module
            module = importlib.import_module(module_part)

        if class_name:
            cls = getattr(module, class_name)
        else:
            # Find the first subclass of BaseOptimizer in the module
            cls = None
            for attr_name in dir(module):
                attr = getattr(module, attr_name)
                if (
                    isinstance(attr, type)
                    and issubclass(attr, BaseOptimizer)
                    and attr is not BaseOptimizer
                    and attr is not DefaultOptimizer
                ):
                    cls = attr
                    break
            if cls is None:
                raise AttributeError(f"No BaseOptimizer subclass found in module {module_part}")

        return cls()
    except Exception as e:
        raise RuntimeError(f"Failed to load custom optimizer from '{optimizer_path}': {e}") from e
