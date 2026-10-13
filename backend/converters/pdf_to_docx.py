"""PDF to DOCX conversion using pdf2docx."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

import fitz
from pdf2docx import Converter as Pdf2DocxConverter

from backend.converters.base import Converter
from backend.errors import ConversionError, ValidationError


class PdfToDocxConverter(Converter):
    source_format = "pdf"
    target_format = "docx"

    def validate_input(self, input_path: Path) -> None:
        try:
            with fitz.open(input_path) as document:
                if document.needs_pass:
                    raise ValidationError(
                        "password_protected_pdf",
                        "Password-protected PDF files are not supported.",
                    )
                if document.page_count < 1:
                    raise ValidationError("empty_pdf", "The PDF does not contain any pages.")
        except ValidationError:
            raise
        except (fitz.FileDataError, RuntimeError, ValueError) as error:
            raise ValidationError("invalid_pdf", "The input file is not a valid PDF.") from error

    def convert(self, input_path: Path, output_path: Path) -> None:
        temporary_path: Path | None = None
        converter: Pdf2DocxConverter | None = None

        try:
            with tempfile.NamedTemporaryFile(
                dir=output_path.parent,
                prefix=f".{output_path.stem}-",
                suffix=".docx",
                delete=False,
            ) as temporary_file:
                temporary_path = Path(temporary_file.name)

            converter = Pdf2DocxConverter(str(input_path))
            converter.convert(str(temporary_path))
            converter.close()
            converter = None

            if not temporary_path.is_file() or temporary_path.stat().st_size == 0:
                raise ConversionError(
                    "empty_output",
                    "The converter did not produce a valid DOCX file.",
                )

            os.replace(temporary_path, output_path)
            temporary_path = None
        except ConversionError:
            raise
        except Exception as error:
            raise ConversionError(
                "pdf_to_docx_failed",
                f"PDF to DOCX conversion failed: {error}",
            ) from error
        finally:
            if converter is not None:
                try:
                    converter.close()
                except Exception:
                    pass
            if temporary_path is not None:
                temporary_path.unlink(missing_ok=True)
