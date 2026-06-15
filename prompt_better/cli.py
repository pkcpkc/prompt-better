from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from prompt_better.prompt_json import list_prompts, preview_schema, generate_from_json
from prompt_better.dspy_manager import EndpointConfig, OptimizationConfig, evaluate_prompt, optimize_prompt
from prompt_better.config import build_runtime_config


TEMPLATES_DIR = Path(__file__).parent / "prompt_json" / "templates"


def main() -> None:
    try:
        parser = argparse.ArgumentParser(
            description=(
                "Prompt optimization CLI. Configure via command-line arguments, "
                "prompt-better.json, or PROMPT_BETTER_* environment variables."
            )
        )
        subparsers = parser.add_subparsers(dest="command", required=True)

        list_parser = subparsers.add_parser("list-prompts", help="List prompts defined in JSON files.")
        _add_common_file_args(list_parser)

        schema_parser = subparsers.add_parser("preview-schema", help="Print JSON schema derived from @Guide metadata.")
        _add_common_file_args(schema_parser)
        schema_parser.add_argument("--prompt", required=True, help="Prompt name or ALL.")

        evaluate_parser = subparsers.add_parser("evaluate", help="Run baseline evaluation/scoring against the student endpoint.")
        _add_runtime_args(evaluate_parser)

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

        evaluate_spec_parser = subparsers.add_parser("evaluate-spec", help="Validate prompt.json files recursively against prompt-schema.json.")
        _add_common_file_args(evaluate_spec_parser)

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

            if not teacher_base_url:
                raise SystemExit("Error: Teacher base URL is not set. Set it via prompt-better.json or PROMPT_BETTER_TEACHER_BASE_URL.")
            if not teacher_model:
                raise SystemExit("Error: Teacher model is not set. Set it via prompt-better.json or PROMPT_BETTER_TEACHER_MODEL.")
            # Allow blank API key for local dev servers
            if not teacher_api_key and not (teacher_base_url.startswith("http://localhost") or teacher_base_url.startswith("http://127.0.0.1")):
                raise SystemExit("Error: Teacher API Key is required for remote endpoints.")
            
            env_teacher_temp = os.getenv("PROMPT_BETTER_TEACHER_TEMPERATURE")
            cli_teacher_temp = getattr(args, "teacher_temperature", None)
            if env_teacher_temp is not None:
                teacher_temperature = float(env_teacher_temp)
            elif cli_teacher_temp is not None:
                teacher_temperature = cli_teacher_temp
            else:
                teacher_temperature = 0.2

            teacher = EndpointConfig(
                base_url=teacher_base_url,
                model=teacher_model,
                api_key=teacher_api_key,
                temperature=teacher_temperature,
            )

            # Validate connection
            print(f"Validating connection to teacher model ({teacher.model} at {teacher.base_url})...")
            try:
                from prompt_better.dspy_manager.optimizer import validate_endpoint_connection
                validate_endpoint_connection(teacher, name="Teacher")
                print("Teacher model connection validated successfully.")
            except Exception as exc:
                raise SystemExit(f"Error: {exc}")
                
            generate_golden_truth(
                case_file=case_file,
                prompts_dir=Path(args.prompts_dir),
                dataset_dir=Path(args.dataset_dir),
                prompt_name=args.prompt,
                teacher_config=teacher,
            )
            return

        if args.command == "evaluate-spec":
            _evaluate_prompt_specifications(Path(args.prompts_dir))
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

        config = build_runtime_config(args)
        if args.command == "evaluate":
            result = evaluate_prompt(config)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            from prompt_better.dspy_manager.reporter import print_report_summary
            for prompt_name, prompt_report in result.items():
                print_report_summary(prompt_name, is_optimize=False, baseline_report=prompt_report)
        else:
            result = optimize_prompt(config)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            from prompt_better.dspy_manager.reporter import print_report_summary
            for prompt_name, prompt_result in result.items():
                print_report_summary(
                    prompt_name=prompt_name,
                    is_optimize=True,
                    baseline_report=prompt_result["baseline_evaluation"],
                    optimized_report=prompt_result["teacher_evaluation"],
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
    parser.add_argument(
        "--auto",
        default=None,
        help="DSPy auto mode for MIPROv2 (default: light). Env: PROMPT_BETTER_AUTO_MODE"
    )
    parser.add_argument(
        "--num-threads",
        type=int,
        default=None,
        help="DSPy optimization threads (default: 6). Env: PROMPT_BETTER_NUM_THREADS"
    )
    parser.add_argument(
        "--train-ratio",
        type=float,
        default=None,
        help="Train/eval split ratio (default: 0.8). Env: PROMPT_BETTER_TRAIN_RATIO"
    )
    parser.add_argument("--apply", action="store_true", help="Apply optimized prompts back to their source JSON definitions.")
    parser.add_argument(
        "--student-api-key",
        default=None,
        help="API key for the student endpoint. Env: PROMPT_BETTER_STUDENT_API_KEY"
    )
    parser.add_argument(
        "--teacher-api-key",
        default=None,
        help="API key for the teacher endpoint. Env: PROMPT_BETTER_TEACHER_API_KEY"
    )
    parser.add_argument(
        "--student-temperature",
        type=float,
        default=None,
        help="Temperature for the student endpoint (default: 0.2). Env: PROMPT_BETTER_STUDENT_TEMPERATURE"
    )
    parser.add_argument(
        "--teacher-temperature",
        type=float,
        default=None,
        help="MIPRO temperature for the teacher endpoint (default: 0.2). Env: PROMPT_BETTER_TEACHER_TEMPERATURE"
    )
    parser.add_argument(
        "--teacher-eval-temperature",
        type=float,
        default=None,
        help="Evaluation temperature for the teacher endpoint (default: 0.0). Env: PROMPT_BETTER_TEACHER_EVAL_TEMPERATURE"
    )
    
    # Advanced optimization settings
    parser.add_argument(
        "--requires-permission-to-run",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Ask for confirmation of estimated token costs before running DSPy optimization (default: True). Env: PROMPT_BETTER_REQUIRES_PERMISSION_TO_RUN"
    )
    parser.add_argument(
        "--num-trials",
        type=int,
        default=None,
        help="Direct override for num_trials in MIPROv2 compile. Env: PROMPT_BETTER_NUM_TRIALS"
    )
    parser.add_argument(
        "--minibatch",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Controls the minibatch parameter in MIPROv2 compile. Env: PROMPT_BETTER_MINIBATCH"
    )
    parser.add_argument(
        "--num-candidates",
        type=int,
        default=None,
        help="Controls the num_candidates configuration in MIPROv2 constructor. Env: PROMPT_BETTER_NUM_CANDIDATES"
    )
    parser.add_argument(
        "--evaluator",
        default=None,
        help="Import path or file path to custom Evaluator class. Env: PROMPT_BETTER_EVALUATOR"
    )
    parser.add_argument(
        "--optimizer",
        default=None,
        help="Import path or file path to custom Optimizer class. Env: PROMPT_BETTER_OPTIMIZER"
    )
    parser.add_argument(
        "--eval-cases-only",
        action="store_true",
        help="Evaluate only the evalset slice of cases instead of all cases after optimization (default: False)."
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


def _evaluate_prompt_specifications(prompts_dir: Path) -> None:
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
        raise SystemExit("Prompt schema evaluation failed.")
    print("All prompt specifications evaluated successfully.")


if __name__ == "__main__":
    main()
