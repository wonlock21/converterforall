from pathlib import Path

from backend.converters.base import Converter
from backend.engine import ConversionEngine
from backend.models import ConversionRequest


class RecordingConverter(Converter):
    source_format = "pdf"
    target_format = "docx"

    def __init__(self) -> None:
        self.validated = False

    def validate_input(self, input_path: Path) -> None:
        self.validated = True

    def convert(self, input_path: Path, output_path: Path) -> None:
        output_path.write_bytes(b"docx")


def request(input_path: Path, output_path: Path, *, overwrite: bool = False):
    return ConversionRequest(
        input_path=input_path,
        output_path=output_path,
        source_format="pdf",
        target_format="docx",
        overwrite=overwrite,
    )


def test_engine_runs_registered_converter(tmp_path: Path) -> None:
    source = tmp_path / "source.pdf"
    target = tmp_path / "result.docx"
    source.write_bytes(b"pdf")
    converter = RecordingConverter()

    result = ConversionEngine([converter]).convert(request(source, target))

    assert result.success is True
    assert result.error_code is None
    assert converter.validated is True
    assert target.read_bytes() == b"docx"


def test_engine_rejects_missing_input(tmp_path: Path) -> None:
    result = ConversionEngine([RecordingConverter()]).convert(
        request(tmp_path / "missing.pdf", tmp_path / "result.docx")
    )

    assert result.success is False
    assert result.error_code == "input_not_found"


def test_engine_rejects_wrong_extensions(tmp_path: Path) -> None:
    source = tmp_path / "source.txt"
    source.write_text("not a pdf")

    result = ConversionEngine([RecordingConverter()]).convert(
        request(source, tmp_path / "result.docx")
    )

    assert result.success is False
    assert result.error_code == "invalid_input_extension"


def test_engine_does_not_overwrite_by_default(tmp_path: Path) -> None:
    source = tmp_path / "source.pdf"
    target = tmp_path / "result.docx"
    source.write_bytes(b"pdf")
    target.write_bytes(b"existing")

    result = ConversionEngine([RecordingConverter()]).convert(request(source, target))

    assert result.success is False
    assert result.error_code == "output_exists"
    assert target.read_bytes() == b"existing"


def test_engine_can_explicitly_overwrite(tmp_path: Path) -> None:
    source = tmp_path / "source.pdf"
    target = tmp_path / "result.docx"
    source.write_bytes(b"pdf")
    target.write_bytes(b"existing")

    result = ConversionEngine([RecordingConverter()]).convert(
        request(source, target, overwrite=True)
    )

    assert result.success is True
    assert target.read_bytes() == b"docx"


def test_engine_reports_unsupported_conversion(tmp_path: Path) -> None:
    source = tmp_path / "source.pdf"
    source.write_bytes(b"pdf")
    conversion_request = ConversionRequest(
        input_path=source,
        output_path=tmp_path / "result.txt",
        source_format="pdf",
        target_format="txt",
    )

    result = ConversionEngine([RecordingConverter()]).convert(conversion_request)

    assert result.success is False
    assert result.error_code == "unsupported_conversion"

