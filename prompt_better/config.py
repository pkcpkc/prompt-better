from __future__ import annotations
import argparse
import json
import os
import sys
from pathlib import Path

from prompt_better.dspy_manager import EndpointConfig, OptimizationConfig


def build_runtime_config(args: argparse.Namespace) -> OptimizationConfig:
    prompts_dir = Path(args.prompts_dir)
    config_file = prompts_dir.parent / "prompt-better.json"
    
    file_config = {}
    if config_file.exists():
        try:
            file_config = json.loads(config_file.read_text(encoding="utf-8"))
            try:
                rel_path = config_file.resolve().relative_to(Path(os.getcwd()).resolve())
            except ValueError:
                rel_path = config_file.resolve()
            print(f"Loaded default settings from configuration file: {rel_path}")
        except Exception as e:
            print(f"Warning: Could not parse config file {config_file}: {e}", file=sys.stderr)
            
    # Prohibit API keys in prompt-better.json
    def check_for_keys(data):
        if isinstance(data, dict):
            for k, v in data.items():
                if "api_key" in k.lower() or "api-key" in k.lower():
                    raise SystemExit(
                        "Error: API keys cannot be specified in prompt-better.json. "
                        f"Found prohibited key '{k}' in configuration file. "
                        "Provide keys either via command line arguments (--student-api-key / --teacher-api-key) "
                        "or environment variables (PROMPT_BETTER_STUDENT_API_KEY / PROMPT_BETTER_TEACHER_API_KEY)."
                    )
                check_for_keys(v)
        elif isinstance(data, list):
            for item in data:
                check_for_keys(item)

    check_for_keys(file_config)

    # Extract configurations with hierarchical fallbacks: Env > prompt-better.json > defaults
    student_json = file_config.get("student", {})
    student_base_url = os.getenv("PROMPT_BETTER_STUDENT_BASE_URL", student_json.get("base_url", "")).strip()
    student_model = os.getenv("PROMPT_BETTER_STUDENT_MODEL", student_json.get("model", "")).strip()
    
    # Precedence: CLI args > Env vars. Config file cannot have keys.
    student_api_key = ""
    if getattr(args, "student_api_key", None) is not None:
        student_api_key = args.student_api_key.strip()
    else:
        student_api_key = os.getenv("PROMPT_BETTER_STUDENT_API_KEY", "").strip()
    
    if not student_base_url:
        raise SystemExit("Error: Student base URL is not set. Set it via prompt-better.json or PROMPT_BETTER_STUDENT_BASE_URL.")
    if not student_model:
        raise SystemExit("Error: Student model is not set. Set it via prompt-better.json or PROMPT_BETTER_STUDENT_MODEL.")
    # Allow blank API key for local dev servers
    if not student_api_key and not (student_base_url.startswith("http://localhost") or student_base_url.startswith("http://127.0.0.1")):
        raise SystemExit("Error: Student API Key is required for remote endpoints.")
        
    env_student_temp = os.getenv("PROMPT_BETTER_STUDENT_TEMPERATURE")
    cli_student_temp = getattr(args, "student_temperature", None)
    if env_student_temp is not None:
        student_temperature = float(env_student_temp)
    elif cli_student_temp is not None:
        student_temperature = cli_student_temp
    else:
        cfg_temp = student_json.get("temperature")
        student_temperature = float(cfg_temp) if cfg_temp is not None else 0.2

    student = EndpointConfig(
        base_url=student_base_url,
        model=student_model,
        api_key=student_api_key,
        temperature=student_temperature,
    )
    
    teacher_json = file_config.get("teacher", {})
    teacher_base_url = os.getenv("PROMPT_BETTER_TEACHER_BASE_URL", teacher_json.get("base_url", "")).strip()
    teacher_model = os.getenv("PROMPT_BETTER_TEACHER_MODEL", teacher_json.get("model", "")).strip()
    
    # Precedence: CLI args > Env vars. Config file cannot have keys.
    teacher_api_key = ""
    if getattr(args, "teacher_api_key", None) is not None:
        teacher_api_key = args.teacher_api_key.strip()
    else:
        teacher_api_key = os.getenv("PROMPT_BETTER_TEACHER_API_KEY", "").strip()
    
    env_teacher_temp = os.getenv("PROMPT_BETTER_TEACHER_TEMPERATURE")
    cli_teacher_temp = getattr(args, "teacher_temperature", None)
    if env_teacher_temp is not None:
        teacher_temperature = float(env_teacher_temp)
    elif cli_teacher_temp is not None:
        teacher_temperature = cli_teacher_temp
    else:
        cfg_temp = teacher_json.get("temperature")
        teacher_temperature = float(cfg_temp) if cfg_temp is not None else 0.2

    env_teacher_eval_temp = os.getenv("PROMPT_BETTER_TEACHER_EVAL_TEMPERATURE")
    cli_teacher_eval_temp = getattr(args, "teacher_eval_temperature", None)
    if env_teacher_eval_temp is not None:
        teacher_eval_temperature = float(env_teacher_eval_temp)
    elif cli_teacher_eval_temp is not None:
        teacher_eval_temperature = cli_teacher_eval_temp
    else:
        cfg_eval_temp = teacher_json.get("eval_temperature")
        teacher_eval_temperature = float(cfg_eval_temp) if cfg_eval_temp is not None else 0.0

    if not teacher_base_url:
        raise SystemExit("Error: Teacher base URL is not set. Set it via prompt-better.json or PROMPT_BETTER_TEACHER_BASE_URL.")
    if not teacher_model:
        raise SystemExit("Error: Teacher model is not set. Set it via prompt-better.json or PROMPT_BETTER_TEACHER_MODEL.")
    # Allow blank API key for local dev servers
    if not teacher_api_key and not (teacher_base_url.startswith("http://localhost") or teacher_base_url.startswith("http://127.0.0.1")):
        raise SystemExit("Error: Teacher API Key is required for remote endpoints.")

    teacher = EndpointConfig(
        base_url=teacher_base_url,
        model=teacher_model,
        api_key=teacher_api_key,
        temperature=teacher_temperature,
        eval_temperature=teacher_eval_temperature,
    )

    # Standard settings resolution (Precedence: Env > CLI > prompt-better.json > default)
    env_auto = os.getenv("PROMPT_BETTER_AUTO_MODE")
    cli_auto = getattr(args, "auto", None)
    if env_auto is not None:
        auto_mode = env_auto.strip()
    elif cli_auto is not None:
        auto_mode = cli_auto
    else:
        auto_mode = file_config.get("auto_mode", "light")

    env_num_threads = os.getenv("PROMPT_BETTER_NUM_THREADS")
    cli_num_threads = getattr(args, "num_threads", None)
    if env_num_threads is not None:
        num_threads = int(env_num_threads)
    elif cli_num_threads is not None:
        num_threads = cli_num_threads
    else:
        num_threads = int(file_config.get("num_threads", 6))

    env_train_ratio = os.getenv("PROMPT_BETTER_TRAIN_RATIO")
    cli_train_ratio = getattr(args, "train_ratio", None)
    if env_train_ratio is not None:
        train_ratio = float(env_train_ratio)
    elif cli_train_ratio is not None:
        train_ratio = cli_train_ratio
    else:
        train_ratio = float(file_config.get("train_ratio", 0.8))
        
    # Infer dataset directory if not provided
    dataset_val = getattr(args, "dataset", None)
    if not dataset_val:
        prompt_base = args.prompt
        if prompt_base and prompt_base != "ALL":
            if prompt_base.endswith("Prompt"):
                prompt_base = prompt_base[:-6]
            inferred = prompts_dir / prompt_base
            if inferred.exists():
                dataset_val = str(inferred)
        if not dataset_val:
            dataset_val = str(prompts_dir)
            
    dataset_file = Path(dataset_val)
    
    # Advanced settings (Precedence: Env > CLI > prompt-better.json > default)
    env_perm = os.getenv("PROMPT_BETTER_REQUIRES_PERMISSION_TO_RUN")
    cli_perm = getattr(args, "requires_permission_to_run", None)
    if env_perm is not None:
        requires_permission_to_run = env_perm.strip().lower() in ("1", "true", "yes")
    elif cli_perm is not None:
        requires_permission_to_run = cli_perm
    else:
        config_val = file_config.get("requires_permission_to_run", True)
        if isinstance(config_val, str):
            requires_permission_to_run = config_val.lower() in ("true", "yes", "1")
        else:
            requires_permission_to_run = bool(config_val)

    env_num_trials = os.getenv("PROMPT_BETTER_NUM_TRIALS")
    cli_num_trials = getattr(args, "num_trials", None)
    if env_num_trials is not None:
        num_trials = int(env_num_trials)
    elif cli_num_trials is not None:
        num_trials = cli_num_trials
    else:
        config_val = file_config.get("num_trials", None)
        num_trials = int(config_val) if config_val is not None else None

    env_minibatch = os.getenv("PROMPT_BETTER_MINIBATCH")
    cli_minibatch = getattr(args, "minibatch", None)
    if env_minibatch is not None:
        minibatch = env_minibatch.strip().lower() in ("1", "true", "yes")
    elif cli_minibatch is not None:
        minibatch = cli_minibatch
    else:
        config_val = file_config.get("minibatch", None)
        if config_val is not None:
            if isinstance(config_val, str):
                minibatch = config_val.lower() in ("true", "yes", "1")
            else:
                minibatch = bool(config_val)
        else:
            minibatch = None

    env_num_candidates = os.getenv("PROMPT_BETTER_NUM_CANDIDATES")
    cli_num_candidates = getattr(args, "num_candidates", None)
    if env_num_candidates is not None:
        num_candidates = int(env_num_candidates)
    elif cli_num_candidates is not None:
        num_candidates = cli_num_candidates
    else:
        config_val = file_config.get("num_candidates", None)
        num_candidates = int(config_val) if config_val is not None else None
    env_evaluator = os.getenv("PROMPT_BETTER_EVALUATOR")
    cli_evaluator = getattr(args, "evaluator", None)
    if env_evaluator is not None:
        evaluator = env_evaluator.strip()
    elif cli_evaluator is not None:
        evaluator = cli_evaluator
    else:
        evaluator = file_config.get("evaluator", None)

    env_optimizer = os.getenv("PROMPT_BETTER_OPTIMIZER")
    cli_optimizer = getattr(args, "optimizer", None)
    if env_optimizer is not None:
        optimizer = env_optimizer.strip()
    elif cli_optimizer is not None:
        optimizer = cli_optimizer
    else:
        optimizer = file_config.get("optimizer", None)
    
    teacher_temp_override = None
    if env_teacher_temp is not None:
        teacher_temp_override = float(env_teacher_temp)
    elif cli_teacher_temp is not None:
        teacher_temp_override = cli_teacher_temp

    teacher_eval_temp_override = None
    if env_teacher_eval_temp is not None:
        teacher_eval_temp_override = float(env_teacher_eval_temp)
    elif cli_teacher_eval_temp is not None:
        teacher_eval_temp_override = cli_teacher_eval_temp

    return OptimizationConfig(
        student=student,
        teacher=teacher,
        prompts_dir=prompts_dir,
        dataset_file=dataset_file,
        prompt_name=args.prompt,
        auto_mode=auto_mode,
        num_threads=num_threads,
        train_ratio=train_ratio,
        apply=getattr(args, "apply", False),
        requires_permission_to_run=requires_permission_to_run,
        num_trials=num_trials,
        minibatch=minibatch,
        num_candidates=num_candidates,
        evaluator=evaluator,
        optimizer=optimizer,
        teacher_temp_override=teacher_temp_override,
        teacher_eval_temp_override=teacher_eval_temp_override,
        eval_cases_only=getattr(args, "eval_cases_only", False),
    )
