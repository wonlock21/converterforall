from __future__ import annotations

from hashlib import sha256
from pathlib import Path

import pytest

fitz = pytest.importorskip("pymupdf")
Image = pytest.importorskip("PIL.Image")

from backend.converters import pdf_to_image as pdf_to_image_module
from backend.converters.pdf_common import validate_pdf
from backend.errors import ValidationError
from backend.models import ConversionRequest
from backend.registry import create_default_engine
from backend.worker import ConversionWorker


def convert(
    source: Path,
    target: Path,
    source_format: str,
    target_format: str,
    *,
    overwrite: bool = False,
):
    return create_default_engine().convert(
        ConversionRequest(
            input_path=source,
            output_path=target,
            source_format=source_format,
            target_format=target_format,
            overwrite=overwrite,
        )
    )


def create_pdf(path: Path, page_texts: list[str]) -> None:
    with fitz.open() as document:
        for text in page_texts:
            page = document.new_page(width=240, height=160)
            if text:
                page.insert_htmlbox((20, 20, 220, 140), text)
        document.save(path)


def test_pdf_to_text_preserves_turkish_and_page_breaks(tmp_path: Path) -> None:
    source = tmp_path / "türkçe.pdf"
    target = tmp_path / "türkçe.txt"
    create_pdf(source, ["İstanbul, çığ ve öğüt", "Şeker, ıhlamur, üzüm"])
    original_hash = sha256(source.read_bytes()).hexdigest()

    result = convert(source, target, "pdf", "txt")

    assert result.success, result.message
    text = target.read_text(encoding="utf-8")
    assert "İstanbul, çığ ve öğüt" in text
    assert "Şeker, ıhlamur, üzüm" in text
    assert "\f" in text
    assert sha256(source.read_bytes()).hexdigest() == original_hash


def test_pdf_without_selectable_text_returns_clear_error(tmp_path: Path) -> None:
    source = tmp_path / "blank.pdf"
    target = tmp_path / "blank.txt"
    create_pdf(source, [""])

    result = convert(source, target, "pdf", "txt")

    assert not result.success
    assert result.error_code == "no_extractable_text"
    assert not target.exists()


@pytest.mark.parametrize("target_format", ["jpg", "jpeg", "png"])
def test_pdf_to_image_renders_all_pages(
    tmp_path: Path, target_format: str
) -> None:
    source = tmp_path / "document.pdf"
    target = tmp_path / f"document.{target_format}"
    create_pdf(source, ["one", "two", "three"])

    result = convert(source, target, "pdf", target_format)

    assert result.success, result.message
    assert [Path(path).name for path in result.output_paths] == [
        f"document_page_001.{target_format}",
        f"document_page_002.{target_format}",
        f"document_page_003.{target_format}",
    ]
    for output in result.output_paths:
        with Image.open(output) as image:
            image.verify()


def test_single_page_pdf_uses_requested_image_name(tmp_path: Path) -> None:
    source = tmp_path / "single.pdf"
    target = tmp_path / "single.png"
    create_pdf(source, ["one"])

    result = convert(source, target, "pdf", "png")

    assert result.success, result.message
    assert result.output_paths == (str(target.resolve()),)
    assert target.is_file()


def test_multi_page_output_collision_requires_overwrite(tmp_path: Path) -> None:
    source = tmp_path / "document.pdf"
    target = tmp_path / "document.png"
    collision = tmp_path / "document_page_002.png"
    create_pdf(source, ["one", "two"])
    collision.write_bytes(b"existing")

    rejected = convert(source, target, "pdf", "png")
    accepted = convert(source, target, "pdf", "png", overwrite=True)

    assert not rejected.success
    assert rejected.error_code == "output_exists"
    assert accepted.success, accepted.message
    assert collision.read_bytes() != b"existing"


def test_pdf_image_failure_removes_all_partial_outputs(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = tmp_path / "document.pdf"
    target = tmp_path / "document.png"
    create_pdf(source, ["one", "two"])
    real_render = pdf_to_image_module._render_page
    call_count = 0

    def fail_on_second_page(page, output_path, target_format):
        nonlocal call_count
        call_count += 1
        if call_count == 2:
            raise RuntimeError("simulated render failure")
        real_render(page, output_path, target_format)

    monkeypatch.setattr(pdf_to_image_module, "_render_page", fail_on_second_page)

    result = convert(source, target, "pdf", "png")

    assert not result.success
    assert result.error_code == "pdf_to_image_failed"
    assert not list(tmp_path.glob("document_page_*.png"))
    assert not list(tmp_path.glob(".document_page_*.png"))


@pytest.mark.parametrize(
    ("source_format", "image_format"),
    [("jpg", "JPEG"), ("jpeg", "JPEG"), ("png", "PNG")],
)
def test_image_to_pdf_real_conversion(
    tmp_path: Path, source_format: str, image_format: str
) -> None:
    source = tmp_path / f"source.{source_format}"
    target = tmp_path / "result.pdf"
    with Image.new("RGB", (120, 60), "navy") as image:
        image.save(source, image_format)

    result = convert(source, target, source_format, "pdf")

    assert result.success, result.message
    with fitz.open(target) as document:
        assert document.page_count == 1
        assert document[0].rect.width > document[0].rect.height


def test_transparent_png_is_flattened_on_white(tmp_path: Path) -> None:
    source = tmp_path / "transparent.png"
    target = tmp_path / "transparent.pdf"
    with Image.new("RGBA", (20, 20), (0, 0, 0, 0)) as image:
        for x in range(5, 15):
            for y in range(5, 15):
                image.putpixel((x, y), (255, 0, 0, 255))
        image.save(source)

    result = convert(source, target, "png", "pdf")

    assert result.success, result.message
    with fitz.open(target) as document:
        pixmap = document[0].get_pixmap(alpha=False)
        assert all(channel > 240 for channel in pixmap.pixel(1, 1))


def test_exif_orientation_is_applied(tmp_path: Path) -> None:
    source = tmp_path / "oriented.jpg"
    target = tmp_path / "oriented.pdf"
    with Image.new("RGB", (80, 40), "green") as image:
        exif = Image.Exif()
        exif[274] = 6
        image.save(source, "JPEG", exif=exif)

    result = convert(source, target, "jpg", "pdf")

    assert result.success, result.message
    with fitz.open(target) as document:
        assert document[0].rect.height > document[0].rect.width


def test_corrupt_image_is_rejected_without_output(tmp_path: Path) -> None:
    source = tmp_path / "broken.png"
    target = tmp_path / "broken.pdf"
    source.write_bytes(b"not an image")

    result = convert(source, target, "png", "pdf")

    assert not result.success
    assert result.error_code == "invalid_image"
    assert not target.exists()


def test_empty_pdf_validation(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    class EmptyDocument:
        needs_pass = False
        page_count = 0

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

    monkeypatch.setattr("backend.converters.pdf_common.fitz.open", lambda _: EmptyDocument())

    with pytest.raises(ValidationError) as error:
        validate_pdf(tmp_path / "empty.pdf")

    assert error.value.code == "empty_pdf"


@pytest.mark.parametrize("source_format", ["jpg", "jpeg"])
def test_jpeg_family_to_png_preserves_pixel_dimensions(
    tmp_path: Path, source_format: str
) -> None:
    source = tmp_path / f"source.{source_format}"
    target = tmp_path / "result.png"
    with Image.new("RGB", (137, 83), (40, 80, 120)) as image:
        image.save(source, "JPEG", quality=95)

    result = convert(source, target, source_format, "png")

    assert result.success, result.message
    with Image.open(target) as output:
        assert output.format == "PNG"
        assert output.size == (137, 83)


@pytest.mark.parametrize("target_format", ["jpg", "jpeg"])
def test_png_to_jpeg_family_preserves_dimensions_and_flattens_transparency(
    tmp_path: Path, target_format: str
) -> None:
    source = tmp_path / "transparent.png"
    target = tmp_path / f"result.{target_format}"
    with Image.new("RGBA", (96, 64), (0, 0, 0, 0)) as image:
        for x in range(24, 72):
            for y in range(16, 48):
                image.putpixel((x, y), (255, 0, 0, 255))
        image.save(source)

    result = convert(source, target, "png", target_format)

    assert result.success, result.message
    with Image.open(target) as output:
        assert output.format == "JPEG"
        assert output.size == (96, 64)
        assert all(channel > 240 for channel in output.convert("RGB").getpixel((2, 2)))


def test_jpeg_to_png_applies_exif_orientation(tmp_path: Path) -> None:
    source = tmp_path / "oriented.jpeg"
    target = tmp_path / "oriented.png"
    with Image.new("RGB", (80, 40), "green") as image:
        exif = Image.Exif()
        exif[274] = 6
        image.save(source, "JPEG", exif=exif)

    result = convert(source, target, "jpeg", "png")

    assert result.success, result.message
    with Image.open(target) as output:
        assert output.size == (40, 80)


def test_raster_conversion_respects_overwrite_flag(tmp_path: Path) -> None:
    source = tmp_path / "source.jpg"
    target = tmp_path / "result.png"
    with Image.new("RGB", (20, 10), "blue") as image:
        image.save(source, "JPEG")
    target.write_bytes(b"existing")

    rejected = convert(source, target, "jpg", "png")
    accepted = convert(source, target, "jpg", "png", overwrite=True)

    assert not rejected.success
    assert rejected.error_code == "output_exists"
    assert accepted.success, accepted.message
    with Image.open(target) as output:
        assert output.size == (20, 10)


def test_default_worker_capabilities_include_raster_conversions() -> None:
    response = ConversionWorker(create_default_engine()).handle_message(
        {"id": "raster-capabilities", "action": "capabilities"}
    )
    conversions = {
        (item["source_format"], item["target_format"])
        for item in response["conversions"]
    }

    assert response["success"] is True
    assert {
        ("jpg", "png"),
        ("jpeg", "png"),
        ("png", "jpg"),
        ("png", "jpeg"),
    }.issubset(conversions)
