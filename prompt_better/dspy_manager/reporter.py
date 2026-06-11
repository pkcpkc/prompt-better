from __future__ import annotations
import re
from typing import Any, Dict, List, Optional
from .utils import get_jinja_env


def print_report_summary(
    prompt_name: str,
    is_optimize: bool,
    baseline_report: Dict[str, Any],
    optimized_report: Optional[Dict[str, Any]] = None,
    train_size: Optional[int] = None,
    evalset_ids: Optional[set[str]] = None,
) -> None:
    baseline = {
        "aggregate_score": baseline_report.get("average_aggregate_score", 0.0),
        "structural_score": baseline_report.get("average_structural_score", 0.0),
        "similarity_score": baseline_report.get("average_similarity_score", 0.0),
        "teacher_score": baseline_report.get("average_teacher_score", 0.0),
    }
    
    optimized = None
    if is_optimize and optimized_report is not None:
        optimized = {
            "aggregate_score": optimized_report.get("average_aggregate_score", 0.0),
            "structural_score": optimized_report.get("average_structural_score", 0.0),
            "similarity_score": optimized_report.get("average_similarity_score", 0.0),
            "teacher_score": optimized_report.get("average_teacher_score", 0.0),
        }

    # Build maps of example_id -> validation dict
    base_vals = {v["example_id"]: v for v in baseline_report.get("validations", [])}
    opt_vals = {}
    if optimized_report:
        opt_vals = {v["example_id"]: v for v in optimized_report.get("validations", optimized_report.get("results", []))}

    # All examples evaluated
    eval_ids = list(base_vals.keys())
    if is_optimize:
        # For optimize, we only compare examples that are in both or at least in optimized (evalset)
        eval_ids = list(opt_vals.keys())

    def natural_sort_key(s: str) -> list[Any]:
        return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', s)]

    eval_ids = sorted(eval_ids, key=natural_sort_key)

    cases = []
    has_teacher_rationales = False
    for eid in eval_ids:
        b_val = base_vals.get(eid, {})
        o_val = opt_vals.get(eid, {})

        b_scores = {
            "aggregate_score": b_val.get("aggregate_score", 0.0),
            "structural_score": b_val.get("structural_score", 0.0),
            "similarity_score": b_val.get("similarity_score", 0.0),
            "teacher_score": b_val.get("teacher_score", 0.0),
        }

        o_scores = None
        diff_scores = None
        teacher_rationale = b_val.get("teacher_rationale")

        if is_optimize:
            o_scores = {
                "aggregate_score": o_val.get("aggregate_score", 0.0),
                "structural_score": o_val.get("structural_score", 0.0),
                "similarity_score": o_val.get("similarity_score", 0.0),
                "teacher_score": o_val.get("teacher_score", 0.0),
            }
            
            def safe_diff(o_val_metric: Any, b_val_metric: Any) -> Optional[float]:
                if o_val_metric is None or b_val_metric is None:
                    return None
                return round(float(o_val_metric) - float(b_val_metric), 4)

            diff_scores = {
                "aggregate_score": safe_diff(o_val.get("aggregate_score"), b_val.get("aggregate_score")),
                "structural_score": safe_diff(o_val.get("structural_score"), b_val.get("structural_score")),
                "similarity_score": safe_diff(o_val.get("similarity_score"), b_val.get("similarity_score")),
                "teacher_score": safe_diff(o_val.get("teacher_score"), b_val.get("teacher_score")),
            }
            teacher_rationale = o_val.get("teacher_rationale")

        if teacher_rationale:
            has_teacher_rationales = True

        display_id = eid
        if evalset_ids:
            if eid in evalset_ids:
                display_id = f"{eid} (eval)"
            else:
                display_id = f"{eid} (train)"

        cases.append({
            "example_id": display_id,
            "baseline_scores": b_scores,
            "optimized_scores": o_scores,
            "diff_scores": diff_scores,
            "teacher_rationale": teacher_rationale,
        })

    env = get_jinja_env()
    env.filters["format_score"] = lambda v: f"{v:.4f}" if v is not None else "n/a"
    env.filters["format_diff"] = lambda v: (f"+{v:.4f}" if v >= 0 else f"{v:.4f}") if v is not None else "n/a"
    env.filters["align_left"] = lambda s, w: f"{s:<{w}}"
    env.filters["align_right"] = lambda s, w: f"{s:>{w}}"
    env.filters["align_center"] = lambda s, w: f"{s:^{w}}"

    template = env.get_template("prompt_summary.j2")
    rendered = template.render(
        prompt_name=prompt_name,
        is_optimize=is_optimize,
        train_size=train_size,
        eval_size=len(eval_ids),
        baseline=baseline,
        optimized=optimized,
        cases=cases,
        has_teacher_rationales=has_teacher_rationales,
    )
    print(rendered)
