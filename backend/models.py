"""Shared input and output models for all converters."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True, slots=True)
class ConversionRequest:
    input_path: Path
    output_path: Path
    source_format: str
    target_format: str
    overwrite: bool = False


@dataclass(frozen=True, slots=True)
class ConversionResult:
    success: bool
    input_path: str | None
    output_path: str | None
    output_paths: tuple[str, ...] = ()
    source_format: str | None = None
    target_format: str | None = None
    duration_ms: int = 0
    message: str = ""
    error_code: str | None = None

    def to_dict(self) -> dict[str, Any]:
        error = None
        if not self.success:
            error = {"code": self.error_code or "conversion_failed", "message": self.message}

        return {
            "success": self.success,
            "input_path": self.input_path,
            "output_path": self.output_path,
            "output_paths": list(self.output_paths),
            "source_format": self.source_format,
            "target_format": self.target_format,
            "duration_ms": self.duration_ms,
            "message": self.message,
            "error": error,
        }


@dataclass(frozen=True, slots=True)
class ConversionPlanResult:
    success: bool
    input_path: str | None
    output_paths: tuple[str, ...] = ()
    conflicting_output_paths: tuple[str, ...] = ()
    source_format: str | None = None
    target_format: str | None = None
    duration_ms: int = 0
    message: str = ""
    error_code: str | None = None

    def to_dict(self) -> dict[str, Any]:
        error = None
        if not self.success:
            error = {"code": self.error_code or "planning_failed", "message": self.message}
        return {
            "success": self.success,
            "input_path": self.input_path,
            "output_paths": list(self.output_paths),
            "conflicting_output_paths": list(self.conflicting_output_paths),
            "source_format": self.source_format,
            "target_format": self.target_format,
            "duration_ms": self.duration_ms,
            "message": self.message,
            "error": error,
        }
