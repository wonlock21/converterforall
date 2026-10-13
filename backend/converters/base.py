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

    @abstractmethod
    def convert(self, input_path: Path, output_path: Path) -> None:
        """Convert input_path and produce output_path or raise ConversionError."""

