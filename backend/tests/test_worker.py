import io
import json
from pathlib import Path

from backend.models import ConversionResult
from backend.worker import ConversionWorker, serve


class FakeEngine:
    def supported_conversions(self):
        return (("pdf", "docx"), ("pdf", "txt"))

    def convert(self, request):
        print("third-party progress")
        return ConversionResult(
            success=True,
            input_path=str(request.input_path),
            output_path=str(request.output_path),
            output_paths=(str(request.output_path),),
            source_format=request.source_format,
            target_format=request.target_format,
            duration_ms=5,
            message="ok",
        )


def valid_message(tmp_path: Path) -> dict:
    return {
        "id": "request-1",
        "action": "convert",
        "input_path": str(tmp_path / "input.pdf"),
        "output_path": str(tmp_path / "output.docx"),
        "source_format": "pdf",
        "target_format": "docx",
        "overwrite": False,
    }


def test_worker_converts_protocol_message(tmp_path: Path) -> None:
    response = ConversionWorker(FakeEngine()).handle_message(valid_message(tmp_path))

    assert response["id"] == "request-1"
    assert response["type"] == "conversion_result"
    assert response["success"] is True
    assert response["error"] is None
    assert response["output_paths"] == [str(tmp_path / "output.docx")]


def test_worker_reports_engine_capabilities() -> None:
    response = ConversionWorker(FakeEngine()).handle_message(
        {"id": "capabilities-1", "action": "capabilities"}
    )

    assert response == {
        "id": "capabilities-1",
        "type": "capabilities_result",
        "success": True,
        "conversions": [
            {"source_format": "pdf", "target_format": "docx"},
            {"source_format": "pdf", "target_format": "txt"},
        ],
        "message": "Supported conversions retrieved successfully.",
        "error": None,
    }


def test_worker_rejects_invalid_json() -> None:
    response = ConversionWorker(FakeEngine()).handle_line("not-json")

    assert response["success"] is False
    assert response["error"]["code"] == "invalid_json"


def test_worker_rejects_invalid_request(tmp_path: Path) -> None:
    message = valid_message(tmp_path)
    message["overwrite"] = "yes"

    response = ConversionWorker(FakeEngine()).handle_message(message)

    assert response["id"] == "request-1"
    assert response["success"] is False
    assert response["error"]["code"] == "invalid_request"


def test_serve_keeps_stdout_protocol_only(tmp_path: Path) -> None:
    first_message = valid_message(tmp_path)
    second_message = {**first_message, "id": "request-2"}
    input_stream = io.StringIO(
        json.dumps(first_message) + "\n" + json.dumps(second_message) + "\n"
    )
    output_stream = io.StringIO()
    error_stream = io.StringIO()

    exit_code = serve(input_stream, output_stream, error_stream, FakeEngine())

    protocol_lines = output_stream.getvalue().splitlines()
    assert exit_code == 0
    assert len(protocol_lines) == 2
    assert json.loads(protocol_lines[0])["success"] is True
    assert json.loads(protocol_lines[1])["id"] == "request-2"
    assert "third-party progress" in error_stream.getvalue()
