"""Shared Pillow validation and orientation/transparency handling."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageOps, UnidentifiedImageError

from backend.errors import ValidationError

TRANSPARENCY_BACKGROUND = "white"


def pillow_format(source_format: str) -> str:
    if source_format in {"jpg", "jpeg"}:
        return "JPEG"
    if source_format == "png":
        return "PNG"
    raise ValueError(f"Unsupported image format: {source_format}")


def validate_image(input_path: Path, source_format: str) -> None:
    try:
        with Image.open(input_path) as image:
            expected_format = pillow_format(source_format)
            if image.format != expected_format:
                raise ValidationError(
                    "invalid_image_format",
                    f"The image content is not {expected_format} data.",
                )
            image.verify()
    except ValidationError:
        raise
    except (UnidentifiedImageError, OSError, ValueError) as error:
        raise ValidationError(
            "invalid_image", "The input file is not a valid supported image."
        ) from error


def oriented_copy(source: Image.Image) -> Image.Image:
    """Load pixels and return an independent, EXIF-oriented image."""

    source.load()
    oriented = ImageOps.exif_transpose(source)
    if oriented is source:
        return source.copy()
    return oriented


def flatten_to_rgb(image: Image.Image) -> Image.Image:
    """Convert to RGB, compositing transparency on the shared white background."""

    if image.mode in {"RGBA", "LA"} or (
        image.mode == "P" and "transparency" in image.info
    ):
        rgba = image.convert("RGBA")
        background = Image.new("RGB", rgba.size, TRANSPARENCY_BACKGROUND)
        background.paste(rgba, mask=rgba.getchannel("A"))
        rgba.close()
        return background
    if image.mode != "RGB":
        return image.convert("RGB")
    return image.copy()


def source_dpi(source: Image.Image) -> tuple[float, float] | None:
    dpi = source.info.get("dpi")
    if not isinstance(dpi, tuple) or len(dpi) < 2:
        return None
    try:
        horizontal, vertical = float(dpi[0]), float(dpi[1])
    except (TypeError, ValueError):
        return None
    if horizontal <= 0 or vertical <= 0:
        return None
    return horizontal, vertical
