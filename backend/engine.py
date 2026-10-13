"""Converter registry, common validation, and conversion orchestration."""

from __future__ import annotations

import os
from pathlib import Path
from time import perf_counter
from typing import Iterable

from backend.converters.base import Converter
from backend.errors import ConversionError, ValidationError
from backend.models import ConversionRequest, ConversionResult


class ConversionEngine:
    def __init__(self, converters: Iterable[Converter]) -> None:
        self._converters = {
            (converter.source_format.lower(), converter.target_format.lower()): converter
            for converter in converters
        }

    def supported_conversions(self) -> tuple[tuple[str, str], ...]:
        return tuple(sorted(self._converters))

    def convert(self, request: ConversionRequest) -> ConversionResult:
        started_at = perf_counter()
        source_format = request.source_format.lower().lstrip(".")
        target_format = request.target_format.lower().lstrip(".")

        try:
            input_path, output_path = self._validate_request(
                request, source_format, target_format
            )
            converter = self._converters.get((source_format, target_format))
            if converter is None:
                raise ValidationError(
                    "unsupported_conversion",
                    f"Conversion from {source_format.upper()} to "
                    f"{target_format.upper()} is not supported.",
                )

            converter.validate_input(input_path)
            converter.convert(input_path, output_path)
            return ConversionResult(
                success=True,
                input_path=str(input_path),
                output_path=str(output_path),
                source_format=source_format,
                target_format=target_format,
                duration_ms=self._duration_ms(started_at),
                message="Conversion completed successfully.",
            )
        except ConversionError as error:
            return ConversionResult(
                success=False,
                input_path=str(request.input_path),
                output_path=str(request.output_path),
                source_format=source_format,
                target_format=target_format,
                duration_ms=self._duration_ms(started_at),
                message=error.message,
                error_code=error.code,
            )
        except Exception:
            return ConversionResult(
                success=False,
                input_path=str(request.input_path),
                output_path=str(request.output_path),
                source_format=source_format,
                target_format=target_format,
                duration_ms=self._duration_ms(started_at),
                message="An unexpected conversion error occurred.",
                error_code="internal_error",
            )

    def _validate_request(
        self,
        request: ConversionRequest,
        source_format: str,
        target_format: str,
    ) -> tuple[Path, Path]:
        input_path = request.input_path.expanduser().resolve(strict=False)
        output_path = request.output_path.expanduser().resolve(strict=False)

        if not input_path.exists():
            raise ValidationError("input_not_found", "The input file does not exist.")
        if not input_path.is_file():
            raise ValidationError("input_not_file", "The input path is not a file.")
        if input_path.suffix.lower() != f".{source_format}":
            raise ValidationError(
                "invalid_input_extension",
                f"The input file must have a .{source_format} extension.",
            )
        if output_path.suffix.lower() != f".{target_format}":
            raise ValidationError(
                "invalid_output_extension",
                f"The output file must have a .{target_format} extension.",
            )
        if input_path == output_path:
            raise ValidationError(
                "same_input_output", "Input and output paths must be different."
            )
        if not output_path.parent.exists() or not output_path.parent.is_dir():
            raise ValidationError(
                "output_directory_not_found", "The output directory does not exist."
            )
        if not os.access(output_path.parent, os.W_OK):
            raise ValidationError(
                "output_directory_not_writable", "The output directory is not writable."
            )
        if output_path.exists() and not output_path.is_file():
            raise ValidationError("output_not_file", "The output path is not a file.")
        if output_path.exists() and not request.overwrite:
            raise ValidationError(
                "output_exists",
                "The output file already exists. Choose another location or allow overwrite.",
            )

        return input_path, output_path

    @staticmethod
    def _duration_ms(started_at: float) -> int:
        return round((perf_counter() - started_at) * 1000)
