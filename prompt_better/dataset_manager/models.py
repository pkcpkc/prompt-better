from __future__ import annotations
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field


class HistoryMessageSpec(BaseModel):
    role: str
    content: Optional[str] = None
    prompt_name: Optional[str] = None
    inputs: Dict[str, str] = {}
    template_override: Optional[str] = None


class PromptExample(BaseModel):
    example_id: str = Field(alias="id")
    prompt_name: str
    inputs: Dict[str, str]
    reference_output: Dict[str, Any]
    rubric: List[str] = []
    history: List[HistoryMessageSpec] = []
