"""Internal JSON-lines worker used by the Flutter desktop application."""

from __future__ import annotations

import json
import logging
import sys
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any, TextIO

from backend.engine import ConversionEngine
from backend.models import ConversionRequest, ConversionResult

LOGGER = logging.getLogger("universal_converter.worker")


class ConversionWorker:
    """Translate protocol messages to domain requests without UI or transport code."""

    def __init__(self, engine: ConversionEngine) -> None:
        self._engine = engine

    def handle_line(self, line: str) -> dict[str, Any]:
        try:
            message = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            return self._error_response(
                None, "invalid_json", "The request is not valid JSON."
            )
        return self.handle_message(message)

    def handle_message(self, message: object) -> dict[str, Any]:
        if not isinstance(message, dict):
            return self._error_response(
                None, "invalid_request", "The request must be a JSON object."
            )

        request_id = message.get("id")
        if not isinstance(request_id, str) or not request_id:
            return self._error_response(
                None, "missing_request_id", "A non-empty request id is required."
            )
        action = message.get("action")
        if action == "capabilities":
            return {
                "id": request_id,
                "type": "capabilities_result",
                "success": True,
                "conversions": [
                    {"source_format": source, "target_format": target}
                    for source, target in self._engine.supported_conversions()
                ],
                "message": "Supported conversions retrieved successfully.",
                "error": None,
            }
        if action != "convert":
            return self._error_response(
                request_id,
                "unsupported_action",
                "The requested worker action is not supported.",
            )

        try:
            input_path = self._required_text(message, "input_path")
            output_path = self._required_text(message, "output_path")
            source_format = self._required_text(message, "source_format")
            target_format = self._required_text(message, "target_format")
            overwrite = message.get("overwrite", False)
            if not isinstance(overwrite, bool):
                raise ValueError("overwrite must be a boolean")
        except ValueError as error:
            return self._error_response(
                request_id, "invalid_request", f"Invalid conversion request: {error}."
            )

        try:
            result = self._engine.convert(
                ConversionRequest(
                    input_path=Path(input_path),
                    output_path=Path(output_path),
                    source_format=source_format,
                    target_format=target_format,
                    overwrite=overwrite,
                )
            )
        except Exception:
            LOGGER.exception("Unhandled conversion engine error")
            return self._error_response(
                request_id,
                "internal_error",
                "An unexpected conversion error occurred.",
            )
        return {
            "id": request_id,
            "type": "conversion_result",
            **result.to_dict(),
        }

    @staticmethod
    def _required_text(message: dict[str, Any], field: str) -> str:
        value = message.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"{field} must be a non-empty string")
        return value

    @staticmethod
    def _error_response(
        request_id: str | None, code: str, message: str
    ) -> dict[str, Any]:
        result = ConversionResult(
            success=False,
            input_path=None,
            output_path=None,
            source_format=None,
            target_format=None,
            duration_ms=0,
            message=message,
            error_code=code,
        )
        return {
            "id": request_id,
            "type": "protocol_error",
            **result.to_dict(),
        }


def serve(
    input_stream: TextIO,
    output_stream: TextIO,
    error_stream: TextIO,
    engine: ConversionEngine,
) -> int:
    """Serve JSON-lines requests until Flutter closes stdin."""

    worker = ConversionWorker(engine)
    for raw_line in input_stream:
        line = raw_line.strip()
        if not line:
            continue
        try:
            # pdf2docx prints progress to stdout. It is diagnostic output, not
            # protocol data, so route it to the worker's stderr channel.
            with redirect_stdout(error_stream):
                response = worker.handle_line(line)
        except Exception:
            LOGGER.exception("Unhandled error while processing a worker request")
            response = ConversionWorker._error_response(
                None,
                "internal_error",
                "An unexpected worker error occurred.",
            )

        output_stream.write(json.dumps(response, ensure_ascii=False) + "\n")
        output_stream.flush()
    return 0


def _configure_standard_streams() -> None:
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            reconfigure(encoding="utf-8")


def main() -> int:
    _configure_standard_streams()
    logging.basicConfig(stream=sys.stderr, level=logging.INFO)
    try:
        with redirect_stdout(sys.stderr):
            from backend.registry import create_default_engine

            engine = create_default_engine()
    except Exception:
        LOGGER.exception("The conversion engine could not be initialized")
        response = ConversionWorker._error_response(
            None,
            "engine_start_failed",
            "The conversion engine could not be started.",
        )
        response["type"] = "fatal_error"
        sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
        sys.stdout.flush()
        return 1

    return serve(sys.stdin, sys.stdout, sys.stderr, engine)


if __name__ == "__main__":
    raise SystemExit(main())
