"""Default converter registry used by the internal JSON worker."""

from backend.converters.image_to_pdf import ImageToPdfConverter
from backend.converters.pdf_to_image import PdfToImageConverter
from backend.converters.pdf_to_docx import PdfToDocxConverter
from backend.converters.pdf_to_text import PdfToTextConverter
from backend.converters.raster_image import RasterImageConverter
from backend.engine import ConversionEngine


def create_default_engine() -> ConversionEngine:
    return ConversionEngine(
        [
            PdfToDocxConverter(),
            PdfToTextConverter(),
            PdfToImageConverter("jpg"),
            PdfToImageConverter("jpeg"),
            PdfToImageConverter("png"),
            ImageToPdfConverter("jpg"),
            ImageToPdfConverter("jpeg"),
            ImageToPdfConverter("png"),
            RasterImageConverter("jpg", "png"),
            RasterImageConverter("jpeg", "png"),
            RasterImageConverter("png", "jpg"),
            RasterImageConverter("png", "jpeg"),
        ]
    )
