from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from .models import EndpointConfig, OptimizationConfig
from .optimizer import list_prompts, optimize_prompt, preview_schema, validate_prompt
from .swift_generator import generate_from_json


TEMPLATES_DIR = Path(__file__).parent / "templates"


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

        validate_spec_parser = subparsers.add_parser("validate-spec", help="Validate prompt.json files recursively against prompt-schema.json.")
        _add_common_file_args(validate_spec_parser)

        args = parser.parse_args()

        if args.command == "generate":
            template_path = _resolve_generation_template(args)
            generate_from_json(Path(args.source), Path(args.target), template_path)
            print(f"Generated {args.target}")
            return

        if args.command == "generate-golden-truth":
            from .golden_generator import generate_golden_truth
            prompt_base = args.prompt
            if prompt_base.endswith("Prompt"):
                prompt_base = prompt_base[:-6]
            case_file = Path(args.dataset_dir) / prompt_base / "dataset" / f"{args.case_id}.json"
            
            # Setup teacher model configuration
            teacher_base_url = os.getenv("PROMPT_BETTER_TEACHER_BASE_URL", "").strip()
            teacher_model = os.getenv("PROMPT_BETTER_TEACHER_MODEL", "").strip()
            teacher_api_key = os.getenv("PROMPT_BETTER_TEACHER_API_KEY", "").strip()
            teacher = None
            if teacher_base_url and teacher_model and teacher_api_key:
                teacher = EndpointConfig(
                    base_url=teacher_base_url,
                    model=teacher_model,
                    api_key=teacher_api_key,
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
        else:
            result = optimize_prompt(config)
        print(json.dumps(result, ensure_ascii=False, indent=2))
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
    parser.add_argument("--dataset", required=True, help="Path to the news optimization dataset JSON.")
    parser.add_argument("--prompt", required=True, help="Prompt name or ALL.")
    parser.add_argument("--auto", default="light", help="DSPy auto mode for MIPROv2.")
    parser.add_argument("--num-threads", type=int, default=6, help="DSPy optimization threads.")
    parser.add_argument("--train-ratio", type=float, default=0.8, help="Train/eval split ratio.")
    parser.add_argument("--apply", action="store_true", help="Apply optimized prompts back to their source JSON definitions.")


def _build_runtime_config(args: argparse.Namespace) -> OptimizationConfig:
    prompts_dir = Path(args.prompts_dir)
    config_file = prompts_dir.parent / "config.json"
    
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
            
    # Extract configurations with hierarchical fallbacks: Env > config.json > defaults
    student_json = file_config.get("student", {})
    student_base_url = os.getenv("PROMPT_BETTER_STUDENT_BASE_URL", student_json.get("base_url", "")).strip()
    student_model = os.getenv("PROMPT_BETTER_STUDENT_MODEL", student_json.get("model", "")).strip()
    student_api_key = os.getenv("PROMPT_BETTER_STUDENT_API_KEY", student_json.get("api_key", "")).strip()
    
    if not student_base_url:
        raise SystemExit("Error: Student base URL is not set. Set it via config.json or PROMPT_BETTER_STUDENT_BASE_URL.")
    if not student_model:
        raise SystemExit("Error: Student model is not set. Set it via config.json or PROMPT_BETTER_STUDENT_MODEL.")
    # Allow blank API key for local dev servers
    if not student_api_key and not (student_base_url.startswith("http://localhost") or student_base_url.startswith("http://127.0.0.1")):
        raise SystemExit("Error: Student API Key is required for remote endpoints.")
        
    student = EndpointConfig(
        base_url=student_base_url,
        model=student_model,
        api_key=student_api_key,
    )
    
    teacher_json = file_config.get("teacher", {})
    teacher_base_url = os.getenv("PROMPT_BETTER_TEACHER_BASE_URL", teacher_json.get("base_url", "")).strip()
    teacher_model = os.getenv("PROMPT_BETTER_TEACHER_MODEL", teacher_json.get("model", "")).strip()
    teacher_api_key = os.getenv("PROMPT_BETTER_TEACHER_API_KEY", teacher_json.get("api_key", "")).strip()
    
    teacher = None
    if teacher_base_url and teacher_model:
        teacher = EndpointConfig(
            base_url=teacher_base_url,
            model=teacher_model,
            api_key=teacher_api_key,
        )
        
    # Standard settings
    auto_mode = os.getenv("PROMPT_BETTER_AUTO_MODE", getattr(args, "auto", file_config.get("auto_mode", "light")))
    num_threads = int(os.getenv("PROMPT_BETTER_NUM_THREADS", str(getattr(args, "num_threads", file_config.get("num_threads", 6)))))
    train_ratio = float(os.getenv("PROMPT_BETTER_TRAIN_RATIO", str(getattr(args, "train_ratio", file_config.get("train_ratio", 0.8)))))
    
    return OptimizationConfig(
        student=student,
        teacher=teacher,
        prompts_dir=prompts_dir,
        dataset_file=Path(args.dataset),
        prompt_name=args.prompt,
        auto_mode=auto_mode,
        num_threads=num_threads,
        train_ratio=train_ratio,
        apply=getattr(args, "apply", False),
    )


def _resolve_generation_template(args: argparse.Namespace) -> Path:
    if args.template:
        return Path(args.template)
    if args.language:
        language = args.language.strip().lower()
        template = TEMPLATES_DIR / f"{language}_gen.jinja2"
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
    for template in TEMPLATES_DIR.glob("*_gen.jinja2"):
        languages.append(template.name.removesuffix("_gen.jinja2"))
    return sorted(languages)


def _language_help() -> str:
    available = ", ".join(_available_generation_languages()) or "none"
    return f"Built-in generation language. Resolved from templates/<language>_gen.jinja2. Available: {available}."


def _required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise SystemExit(f"Missing required environment variable: {name}")
    return value


def _validate_prompt_specifications(prompts_dir: Path) -> None:
    schema_path = Path(__file__).parent / "prompt-schema.json"
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
