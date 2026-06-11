from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from prompt_better.prompt_json import list_prompts, preview_schema, generate_from_json
from prompt_better.dspy_manager import EndpointConfig, OptimizationConfig, validate_prompt, optimize_prompt


TEMPLATES_DIR = Path(__file__).parent / "prompt_json" / "templates"


def main() -> None:
    try:
        parser = argparse.ArgumentParser(description="Prompt optimization CLI")
        subparsers = parser.add_subparsers(dest="command", required=True)

        list_parser = subparsers.add_parser("list-prompts", help="List prompts defined in JSON files.")
        _add_common_file_args(list_parser)

        schema_parser = subparsers.add_parser("preview-schema", help="Print JSON schema derived from @Guide metadata.")
        _add_common_file_args(schema_parser)
        schema_parser.add_argument("--prompt", required=True, help="Prompt name or ALL.")

        validate_parser = subparsers.add_parser("validate", help="Run baseline JSON-schema validation against the student endpoint.")
        _add_runtime_args(validate_parser)

        optimize_parser = subparsers.add_parser("optimize", help="Optimize one or more prompts with DSPy and write reports.")
        _add_runtime_args(optimize_parser)
        
        generate_parser = subparsers.add_parser("generate", help="Generate a file from a prompt JSON and Jinja template.")
        generate_parser.add_argument("--source", required=True, help="Path to your .json file.")
        generate_parser.add_argument("--target", required=True, help="Path to the output file.")
        template_group = generate_parser.add_mutually_exclusive_group(required=True)
        template_group.add_argument(
            "-language",
            "--language",
            help=_language_help(),
        )
        template_group.add_argument(
            "-template",
            "--template",
            help="Path to the Jinja template used for generation.",
        )

        golden_parser = subparsers.add_parser("generate-golden-truth", help="Generate golden truth references.")
        golden_parser.add_argument("--case-id", required=True, help="ID/Filename of target test case.")
        golden_parser.add_argument("--prompt", required=True, help="Target prompt name.")
        _add_common_file_args(golden_parser)
        golden_parser.add_argument("--dataset-dir", required=True, help="Path to the prompts root directory.")
        golden_parser.add_argument("--teacher-api-key", default=None, help="API key for the teacher endpoint.")
        golden_parser.add_argument("--teacher-temperature", type=float, default=None, help="MIPRO temperature for the teacher endpoint (default: 0.2).")

        validate_spec_parser = subparsers.add_parser("validate-spec", help="Validate prompt.json files recursively against prompt-schema.json.")
        _add_common_file_args(validate_spec_parser)

        args = parser.parse_args()

        if args.command == "generate":
            template_path = _resolve_generation_template(args)
            generate_from_json(Path(args.source), Path(args.target), template_path)
            print(f"Generated {args.target}")
            return

        if args.command == "generate-golden-truth":
            from prompt_better.dataset_manager import generate_golden_truth
            prompt_base = args.prompt
            if prompt_base.endswith("Prompt"):
                prompt_base = prompt_base[:-6]
            case_file = Path(args.dataset_dir) / prompt_base / "dataset" / f"{args.case_id}.json"
            
            # Setup teacher model configuration
            teacher_base_url = os.getenv("PROMPT_BETTER_TEACHER_BASE_URL", "").strip()
            teacher_model = os.getenv("PROMPT_BETTER_TEACHER_MODEL", "").strip()
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
                teacher_temperature = 0.2

            teacher = None
            if teacher_base_url and teacher_model and teacher_api_key:
                teacher = EndpointConfig(
                    base_url=teacher_base_url,
                    model=teacher_model,
                    api_key=teacher_api_key,
                    temperature=teacher_temperature,
                )
                
            generate_golden_truth(
                case_file=case_file,
                prompts_dir=Path(args.prompts_dir),
                dataset_dir=Path(args.dataset_dir),
                prompt_name=args.prompt,
                teacher_config=teacher,
            )
            return

        if args.command == "validate-spec":
            _validate_prompt_specifications(Path(args.prompts_dir))
            return

        prompts_dir = Path(args.prompts_dir)

        if args.command == "list-prompts":
            data = [
                {
                    "name": spec.name,
                    "template_symbol": spec.template_symbol,
                    "placeholders": spec.placeholders,
                    "fields": [field.name for field in spec.fields],
                }
                for spec in list_prompts(prompts_dir)
            ]
            print(json.dumps(data, ensure_ascii=False, indent=2))
            return

        if args.command == "preview-schema":
            data = preview_schema(prompts_dir, args.prompt)
            print(json.dumps(data, ensure_ascii=False, indent=2))
            return

        config = _build_runtime_config(args)
        if args.command == "validate":
            result = validate_prompt(config)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            from prompt_better.dspy_manager.optimizer import _print_report_summary
            for prompt_name, prompt_report in result.items():
                _print_report_summary(prompt_name, is_optimize=False, baseline_report=prompt_report)
        else:
            result = optimize_prompt(config)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            from prompt_better.dspy_manager.optimizer import _print_report_summary
            for prompt_name, prompt_result in result.items():
                _print_report_summary(
                    prompt_name=prompt_name,
                    is_optimize=True,
                    baseline_report=prompt_result["baseline_validation"],
                    optimized_report=prompt_result["teacher_validation"],
                    train_size=prompt_result["train_size"],
                    evalset_ids=set(prompt_result.get("evalset_ids", [])),
                )
    except Exception as exc:
        if os.getenv("PROMPT_BETTER_DEBUG") == "1":
            raise
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)


def _add_common_file_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--prompts-dir",
        required=True,
        help="Absolute or repo-relative path to the directory containing JSON prompt definitions.",
    )


def _add_runtime_args(parser: argparse.ArgumentParser) -> None:
    _add_common_file_args(parser)
    parser.add_argument("--dataset", required=False, default=None, help="Path to the optimization dataset JSON or directory.")
    parser.add_argument("--prompt", required=True, help="Prompt name or ALL.")
    parser.add_argument("--auto", default=None, help="DSPy auto mode for MIPROv2 (default: light).")
    parser.add_argument("--num-threads", type=int, default=None, help="DSPy optimization threads (default: 6).")
    parser.add_argument("--train-ratio", type=float, default=None, help="Train/eval split ratio (default: 0.8).")
    parser.add_argument("--apply", action="store_true", help="Apply optimized prompts back to their source JSON definitions.")
    parser.add_argument("--student-api-key", default=None, help="API key for the student endpoint.")
    parser.add_argument("--teacher-api-key", default=None, help="API key for the teacher endpoint.")
    parser.add_argument("--student-temperature", type=float, default=None, help="Temperature for the student endpoint (default: 0.2).")
    parser.add_argument("--teacher-temperature", type=float, default=None, help="MIPRO temperature for the teacher endpoint (default: 0.2).")
    parser.add_argument("--teacher-eval-temperature", type=float, default=None, help="Validation temperature for the teacher endpoint (default: 0.0).")
    
    # Advanced optimization settings
    parser.add_argument(
        "--requires-permission-to-run",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Ask for confirmation of estimated token costs before running DSPy optimization (default: True)."
    )
    parser.add_argument("--num-trials", type=int, default=None, help="Direct override for num_trials in MIPROv2 compile.")
    parser.add_argument(
        "--minibatch",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Controls the minibatch parameter in MIPROv2 compile."
    )
    parser.add_argument("--num-candidates", type=int, default=None, help="Controls the num_candidates configuration in MIPROv2 constructor.")
    parser.add_argument("--evaluator", default=None, help="Import path or file path to custom Evaluator class.")
    parser.add_argument("--optimizer", default=None, help="Import path or file path to custom Optimizer class.")
    parser.add_argument(
        "--eval-cases-only",
        action="store_true",
        help="Evaluate only the evalset slice of cases instead of all cases after optimization (default: False)."
    )


def _build_runtime_config(args: argparse.Namespace) -> OptimizationConfig:
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


def _resolve_generation_template(args: argparse.Namespace) -> Path:
    if args.template:
        return Path(args.template)
    if args.language:
        language = args.language.strip().lower()
        template = TEMPLATES_DIR / f"{language}.jinja2"
        if template.exists():
            return template
        available = ", ".join(_available_generation_languages()) or "none"
        raise SystemExit(
            f"Error: Built-in template for language '{args.language}' is not available. "
            f"Expected {template}. Available languages: {available}."
        )
    raise SystemExit("Error: Use either -language <language> or -template <template.jinja2>.")


def _available_generation_languages() -> list[str]:
    if not TEMPLATES_DIR.exists():
        return []
    languages = []
    for template in TEMPLATES_DIR.glob("*.jinja2"):
        languages.append(template.name.removesuffix(".jinja2"))
    return sorted(languages)


def _language_help() -> str:
    available = ", ".join(_available_generation_languages()) or "none"
    return f"Built-in generation language. Resolved from templates/<language>.jinja2. Available: {available}."


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def _validate_prompt_specifications(prompts_dir: Path) -> None:
    schema_path = Path(__file__).parent / "prompt_json" / "prompt-schema.json"
    if not schema_path.exists():
        raise FileNotFoundError(f"Schema file not found at {schema_path}")
        
    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except Exception as e:
        raise ValueError(f"Failed to parse prompt-schema.json: {e}")
        
    import jsonschema
    
    print(f"Scanning recursively for prompt specifications in: {prompts_dir.resolve()}")
    prompt_files = list(prompts_dir.rglob("prompt.json"))
    if not prompt_files:
        print("No prompt.json files found.")
        return
        
    all_valid = True
    for file in sorted(prompt_files):
        try:
            rel_path = file.relative_to(prompts_dir)
        except ValueError:
            rel_path = file
            
        print(f"Validating {rel_path}...")
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
            jsonschema.validate(instance=data, schema=schema)
            print(f"  OK: {rel_path}")
        except jsonschema.exceptions.ValidationError as ve:
            print(f"  FAILED: {rel_path} - Schema validation error: {ve.message}", file=sys.stderr)
            print(f"    At path: {' -> '.join(str(p) for p in ve.path)}", file=sys.stderr)
            all_valid = False
        except Exception as e:
            print(f"  FAILED: {rel_path} - {e}", file=sys.stderr)
            all_valid = False
            
    if not all_valid:
        raise SystemExit("Prompt schema validation failed.")
    print("All prompt specifications validated successfully.")


if __name__ == "__main__":
    main()
