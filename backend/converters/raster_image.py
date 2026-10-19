"""Loss-aware JPG/JPEG and PNG conversion using Pillow."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, UnidentifiedImageError

from backend.converters.base import Converter
from backend.converters.image_common import (
    flatten_to_rgb,
    oriented_copy,
    pillow_format,
    source_dpi,
    validate_image,
)
from backend.converters.output_transaction import publish_outputs, temporary_path_for
from backend.errors import ConversionError


class RasterImageConverter(Converter):
    def __init__(self, source_format: str, target_format: str) -> None:
        pillow_format(source_format)
        pillow_format(target_format)
        if source_format == target_format:
            raise ValueError("Source and target image formats must be different.")
        self.source_format = source_format
        self.target_format = target_format

    def validate_input(self, input_path: Path) -> None:
        validate_image(input_path, self.source_format)

    def convert(
        self, input_path: Path, output_path: Path, *, overwrite: bool = False
    ) -> tuple[Path, ...]:
        temporary_path = temporary_path_for(output_path)
        try:
            with Image.open(input_path) as source:
                oriented = oriented_copy(source)
                dpi = source_dpi(source)
                try:
                    if self.target_format == "png":
                        save_image = (
                            oriented.convert("RGB")
                            if oriented.mode == "CMYK"
                            else oriented
                        )
                        parameters: dict[str, object] = {"format": "PNG"}
                    else:
                        save_image = flatten_to_rgb(oriented)
                        parameters = {
                            "format": "JPEG",
                            "quality": 95,
                            "subsampling": 0,
                        }
                    if dpi is not None:
                        parameters["dpi"] = dpi
                    try:
                        save_image.save(temporary_path, **parameters)
                    finally:
                        if save_image is not oriented:
                            save_image.close()
                finally:
                    oriented.close()
            if not temporary_path.is_file() or temporary_path.stat().st_size == 0:
                raise ConversionError(
                    "empty_output", "The converter did not produce a valid image."
                )
            return publish_outputs(
                {temporary_path: output_path}, overwrite=overwrite
            )
        except ConversionError:
            raise
        except (UnidentifiedImageError, OSError, ValueError) as error:
            raise ConversionError(
                "image_conversion_failed", f"Image conversion failed: {error}"
            ) from error
        finally:
            temporary_path.unlink(missing_ok=True)
