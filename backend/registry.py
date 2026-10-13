"""Default converter registry used by the internal JSON worker."""

from backend.converters.pdf_to_docx import PdfToDocxConverter
from backend.engine import ConversionEngine


def create_default_engine() -> ConversionEngine:
    return ConversionEngine([PdfToDocxConverter()])
