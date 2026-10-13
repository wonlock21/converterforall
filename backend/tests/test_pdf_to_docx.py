import io
import json
import subprocess
import sys
from hashlib import sha256
from pathlib import Path
from zipfile import ZipFile

import pytest

fitz = pytest.importorskip("fitz")
pytest.importorskip("pdf2docx")
from backend.models import ConversionRequest
from backend.registry import create_default_engine
from backend.worker import serve


def test_real_pdf_to_docx_conversion_preserves_input(tmp_path: Path) -> None:
    source = tmp_path / "source.pdf"
    target = tmp_path / "result.docx"

    document = fitz.open()
    page = document.new_page()
    page.insert_text((72, 72), "Universal Converter")
    document.save(source)
    document.close()
    original_hash = sha256(source.read_bytes()).hexdigest()

    result = create_default_engine().convert(
        ConversionRequest(
            input_path=source,
            output_path=target,
            source_format="pdf",
            target_format="docx",
        )
    )

    assert result.success is True, result.message
    assert target.stat().st_size > 0
    assert sha256(source.read_bytes()).hexdigest() == original_hash
    with ZipFile(target) as docx_archive:
        assert "word/document.xml" in docx_archive.namelist()


def test_invalid_pdf_is_rejected_without_output(tmp_path: Path) -> None:
    source = tmp_path / "invalid.pdf"
    target = tmp_path / "result.docx"
    source.write_text("not a PDF")

    result = create_default_engine().convert(
        ConversionRequest(
            input_path=source,
            output_path=target,
            source_format="pdf",
            target_format="docx",
        )
    )

    assert result.success is False
    assert result.error_code == "invalid_pdf"
    assert not target.exists()


def test_worker_emits_one_json_result_for_real_conversion(tmp_path: Path) -> None:
    source = tmp_path / "worker-source.pdf"
    target = tmp_path / "worker-result.docx"
    document = fitz.open()
    document.new_page().insert_text((72, 72), "Worker conversion")
    document.save(source)
    document.close()

    request = {
        "id": "real-conversion",
        "action": "convert",
        "source_format": "pdf",
        "target_format": "docx",
        "input_path": str(source),
        "output_path": str(target),
        "overwrite": False,
    }
    input_stream = io.StringIO(json.dumps(request) + "\n")
    output_stream = io.StringIO()
    error_stream = io.StringIO()

    exit_code = serve(
        input_stream,
        output_stream,
        error_stream,
        create_default_engine(),
    )

    output = json.loads(output_stream.getvalue())
    assert exit_code == 0
    assert output["success"] is True
    assert output["error"] is None
    assert target.is_file()


def test_worker_subprocess_uses_stdin_stdout_protocol(tmp_path: Path) -> None:
    source = tmp_path / "process-source.pdf"
    target = tmp_path / "process-result.docx"
    document = fitz.open()
    document.new_page().insert_text((72, 72), "Process conversion")
    document.save(source)
    document.close()
    request = {
        "id": "process-conversion",
        "action": "convert",
        "source_format": "pdf",
        "target_format": "docx",
        "input_path": str(source),
        "output_path": str(target),
        "overwrite": False,
    }

    completed = subprocess.run(
        [sys.executable, "-m", "backend.worker"],
        input=json.dumps(request) + "\n",
        capture_output=True,
        text=True,
        encoding="utf-8",
        cwd=Path(__file__).resolve().parents[2],
        check=False,
    )

    protocol_lines = completed.stdout.splitlines()
    assert completed.returncode == 0, completed.stderr
    assert len(protocol_lines) == 1
    assert json.loads(protocol_lines[0])["success"] is True
    assert target.is_file()
