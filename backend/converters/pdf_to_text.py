"""Extract selectable PDF text to a UTF-8 text file."""

from __future__ import annotations

from pathlib import Path

import pymupdf as fitz

from backend.converters.base import Converter
from backend.converters.output_transaction import publish_outputs, temporary_path_for
from backend.converters.pdf_common import validate_pdf
from backend.errors import ConversionError


class PdfToTextConverter(Converter):
    source_format = "pdf"
    target_format = "txt"

    def validate_input(self, input_path: Path) -> None:
        validate_pdf(input_path)

    def convert(
        self, input_path: Path, output_path: Path, *, overwrite: bool = False
    ) -> tuple[Path, ...]:
        temporary_path = temporary_path_for(output_path)
        try:
            with fitz.open(input_path) as document:
                pages = [page.get_text("text").rstrip() for page in document]
            if not any(page.strip() for page in pages):
                raise ConversionError(
                    "no_extractable_text",
                    "The PDF has no selectable text. OCR is not supported yet.",
                )
            content = "\n\n\f\n\n".join(pages) + "\n"
            temporary_path.write_text(content, encoding="utf-8", newline="\n")
            return publish_outputs(
                {temporary_path: output_path}, overwrite=overwrite
            )
        except ConversionError:
            raise
        except Exception as error:
            raise ConversionError(
                "pdf_to_text_failed", f"PDF text extraction failed: {error}"
            ) from error
        finally:
            temporary_path.unlink(missing_ok=True)
