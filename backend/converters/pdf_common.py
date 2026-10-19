"""Shared PDF validation used by PDF source converters."""

from __future__ import annotations

from pathlib import Path

import pymupdf as fitz

from backend.errors import ValidationError


def validate_pdf(input_path: Path) -> None:
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
