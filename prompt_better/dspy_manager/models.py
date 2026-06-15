from __future__ import annotations
from pathlib import Path
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field


class EndpointConfig(BaseModel):
    base_url: str
    model: str
    api_key: str
    timeout_seconds: float = 120.0
    temperature: float = 0.2
    eval_temperature: float = 0.0


class OptimizationConfig(BaseModel):
    student: EndpointConfig
    teacher: Optional[EndpointConfig] = None
    prompts_dir: Path
    dataset_file: Path
    prompt_name: str
    auto_mode: str = "light"
    num_threads: int = 6
    train_ratio: float = 0.8
    apply: bool = False
    
    # Advanced optimization settings
    requires_permission_to_run: bool = True
    num_trials: Optional[int] = None
    minibatch: Optional[bool] = None
    num_candidates: Optional[int] = None
    evaluator: Optional[str] = None
    optimizer: Optional[str] = None
    teacher_temp_override: Optional[float] = None
    teacher_eval_temp_override: Optional[float] = None
    eval_cases_only: bool = False



class EvaluationResult(BaseModel):
    example_id: str
    prompt_name: str
    mode: str
    candidate_output: Dict[str, Any]
    structural_score: float
    similarity_score: float
    aggregate_score: float
    teacher_score: Optional[float] = None
    teacher_rationale: Optional[str] = None
