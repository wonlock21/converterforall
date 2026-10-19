"""Render every PDF page to JPG or PNG with PyMuPDF."""

from __future__ import annotations

from pathlib import Path

import pymupdf as fitz

from backend.converters.base import Converter
from backend.converters.output_transaction import publish_outputs, temporary_path_for
from backend.converters.pdf_common import validate_pdf
from backend.errors import ConversionError


def _render_page(page: fitz.Page, output_path: Path, target_format: str) -> None:
    """Render one page; kept separate so failure cleanup can be tested."""

    pixmap = page.get_pixmap(
        matrix=fitz.Matrix(2, 2),
        alpha=target_format == "png",
    )
    pixmap.save(output_path)


class PdfToImageConverter(Converter):
    source_format = "pdf"

    def __init__(self, target_format: str) -> None:
        if target_format not in {"jpg", "jpeg", "png"}:
            raise ValueError(f"Unsupported image target format: {target_format}")
        self.target_format = target_format

    def validate_input(self, input_path: Path) -> None:
        validate_pdf(input_path)

    def planned_output_paths(
        self, input_path: Path, output_path: Path
    ) -> tuple[Path, ...]:
        with fitz.open(input_path) as document:
            page_count = document.page_count
        if page_count == 1:
            return (output_path,)
        width = max(3, len(str(page_count)))
        return tuple(
            output_path.with_name(
                f"{output_path.stem}_page_{page_number:0{width}d}{output_path.suffix}"
            )
            for page_number in range(1, page_count + 1)
        )

    def convert(
        self, input_path: Path, output_path: Path, *, overwrite: bool = False
    ) -> tuple[Path, ...]:
        final_paths = self.planned_output_paths(input_path, output_path)
        staged: dict[Path, Path] = {}
        try:
            with fitz.open(input_path) as document:
                for page, final_path in zip(document, final_paths, strict=True):
                    temporary_path = temporary_path_for(final_path)
                    staged[temporary_path] = final_path
                    _render_page(page, temporary_path, self.target_format)
                    if temporary_path.stat().st_size == 0:
                        raise ConversionError(
                            "empty_output",
                            f"Page rendering produced an empty file: {final_path.name}",
                        )
            return publish_outputs(staged, overwrite=overwrite)
        except ConversionError:
            raise
        except Exception as error:
            raise ConversionError(
                "pdf_to_image_failed", f"PDF page rendering failed: {error}"
            ) from error
        finally:
            for temporary_path in staged:
                temporary_path.unlink(missing_ok=True)
