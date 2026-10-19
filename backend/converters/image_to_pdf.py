"""JPG and PNG to PDF conversion using Pillow."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, UnidentifiedImageError

from backend.converters.base import Converter
from backend.converters.image_common import (
    flatten_to_rgb,
    oriented_copy,
    source_dpi,
    validate_image,
)
from backend.converters.output_transaction import publish_outputs, temporary_path_for
from backend.errors import ConversionError


class ImageToPdfConverter(Converter):
    target_format = "pdf"

    def __init__(self, source_format: str) -> None:
        if source_format not in {"jpg", "jpeg", "png"}:
            raise ValueError(f"Unsupported image source format: {source_format}")
        self.source_format = source_format

    def validate_input(self, input_path: Path) -> None:
        validate_image(input_path, self.source_format)

    def convert(
        self, input_path: Path, output_path: Path, *, overwrite: bool = False
    ) -> tuple[Path, ...]:
        temporary_path = temporary_path_for(output_path)
        try:
            with Image.open(input_path) as source:
                oriented = oriented_copy(source)
                converted = flatten_to_rgb(oriented)
                try:
                    dpi = source_dpi(source)
                    resolution = dpi[0] if dpi is not None else 72.0
                    converted.save(temporary_path, "PDF", resolution=resolution)
                finally:
                    converted.close()
                    oriented.close()
            if not temporary_path.is_file() or temporary_path.stat().st_size == 0:
                raise ConversionError(
                    "empty_output", "The converter did not produce a valid PDF file."
                )
            return publish_outputs(
                {temporary_path: output_path}, overwrite=overwrite
            )
        except ConversionError:
            raise
        except (UnidentifiedImageError, OSError, ValueError) as error:
            raise ConversionError(
                "image_to_pdf_failed", f"Image to PDF conversion failed: {error}"
            ) from error
        finally:
            temporary_path.unlink(missing_ok=True)
