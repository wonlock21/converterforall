"""Converter contract shared by every conversion module."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path


class Converter(ABC):
    source_format: str
    target_format: str

    @abstractmethod
    def validate_input(self, input_path: Path) -> None:
        """Validate format-specific input without modifying it."""

    def planned_output_paths(
        self, input_path: Path, output_path: Path
    ) -> tuple[Path, ...]:
        """Return every final output path before conversion begins."""

        return (output_path,)

    @abstractmethod
    def convert(
        self, input_path: Path, output_path: Path, *, overwrite: bool = False
    ) -> tuple[Path, ...]:
        """Convert input_path and return all produced paths."""
