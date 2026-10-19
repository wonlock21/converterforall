"""PDF to DOCX conversion using pdf2docx."""

from __future__ import annotations

from pathlib import Path

from pdf2docx import Converter as Pdf2DocxConverter

from backend.converters.base import Converter
from backend.converters.output_transaction import publish_outputs, temporary_path_for
from backend.converters.pdf_common import validate_pdf
from backend.errors import ConversionError


class PdfToDocxConverter(Converter):
    source_format = "pdf"
    target_format = "docx"

    def validate_input(self, input_path: Path) -> None:
        validate_pdf(input_path)

    def convert(
        self, input_path: Path, output_path: Path, *, overwrite: bool = False
    ) -> tuple[Path, ...]:
        temporary_path: Path | None = None
        converter: Pdf2DocxConverter | None = None

        try:
            temporary_path = temporary_path_for(output_path)

            converter = Pdf2DocxConverter(str(input_path))
            converter.convert(str(temporary_path))
            converter.close()
            converter = None

            if not temporary_path.is_file() or temporary_path.stat().st_size == 0:
                raise ConversionError(
                    "empty_output",
                    "The converter did not produce a valid DOCX file.",
                )

            outputs = publish_outputs(
                {temporary_path: output_path}, overwrite=overwrite
            )
            temporary_path = None
            return outputs
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
