"""Build and smoke-test the platform-native Python worker with PyInstaller."""

from __future__ import annotations

import json
import os
import platform
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
from zipfile import ZipFile


PROJECT_ROOT = Path(__file__).resolve().parents[1]
WORKER_NAME = "universal_converter_worker"


def normalized_platform() -> str:
    names = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}
    try:
        return names[platform.system()]
    except KeyError as error:
        raise SystemExit(f"Unsupported build platform: {platform.system()}") from error


def normalized_architecture() -> str:
    machine = platform.machine().lower()
    if machine in {"amd64", "x86_64"}:
        return "x64"
    if machine in {"arm64", "aarch64"}:
        return "arm64"
    return machine


def parse_mode() -> str:
    mode = sys.argv[1].lower() if len(sys.argv) > 1 else "release"
    if mode not in {"debug", "release"}:
        raise SystemExit("Usage: python tool/build_worker.py [debug|release]")
    return mode


def smoke_test(worker_path: Path) -> None:
    import pymupdf
    from PIL import Image

    with tempfile.TemporaryDirectory(prefix="uc-worker-smoke-") as temp_directory:
        temp_path = Path(temp_directory)
        source = temp_path / "source.pdf"
        output = temp_path / "result.docx"
        image_source = temp_path / "source.png"
        image_output = temp_path / "image.pdf"
        raster_output = temp_path / "image.jpeg"
        with pymupdf.open() as document:
            page = document.new_page()
            page.insert_text((72, 72), "Universal Converter worker smoke test")
            document.save(source)
        with Image.new("RGBA", (24, 12), (87, 88, 166, 128)) as image:
            image.save(image_source)

        capabilities_request = {
            "id": "pyinstaller-capabilities-test",
            "action": "capabilities",
        }
        docx_request = {
            "id": "pyinstaller-smoke-test",
            "action": "convert",
            "source_format": "pdf",
            "target_format": "docx",
            "input_path": str(source),
            "output_path": str(output),
            "overwrite": False,
        }
        image_request = {
            "id": "pyinstaller-image-test",
            "action": "convert",
            "source_format": "png",
            "target_format": "pdf",
            "input_path": str(image_source),
            "output_path": str(image_output),
            "overwrite": False,
        }
        raster_request = {
            "id": "pyinstaller-raster-test",
            "action": "convert",
            "source_format": "png",
            "target_format": "jpeg",
            "input_path": str(image_source),
            "output_path": str(raster_output),
            "overwrite": False,
        }
        completed = subprocess.run(
            [str(worker_path)],
            input="\n".join(
                json.dumps(request)
                for request in (
                    capabilities_request,
                    docx_request,
                    image_request,
                    raster_request,
                )
            )
            + "\n",
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=90,
            check=False,
        )
        protocol_lines = completed.stdout.splitlines()
        if completed.returncode != 0 or len(protocol_lines) != 4:
            raise SystemExit(
                "Frozen worker smoke test failed.\n"
                f"exit={completed.returncode}\n"
                f"stdout={completed.stdout}\n"
                f"stderr={completed.stderr}"
            )
        capabilities, docx_response, image_response, raster_response = map(
            json.loads, protocol_lines
        )
        conversions = {
            (item.get("source_format"), item.get("target_format"))
            for item in capabilities.get("conversions", [])
        }
        expected = {
            ("pdf", "docx"),
            ("pdf", "txt"),
            ("png", "pdf"),
            ("jpg", "png"),
            ("png", "jpeg"),
        }
        if capabilities.get("id") != capabilities_request["id"] or not expected.issubset(conversions):
            raise SystemExit(f"Unexpected capabilities response: {capabilities}")
        if docx_response.get("id") != docx_request["id"] or docx_response.get("success") is not True:
            raise SystemExit(f"Unexpected frozen worker response: {docx_response}")
        if image_response.get("id") != image_request["id"] or image_response.get("success") is not True:
            raise SystemExit(f"Unexpected image response: {image_response}")
        if raster_response.get("id") != raster_request["id"] or raster_response.get("success") is not True:
            raise SystemExit(f"Unexpected raster response: {raster_response}")
        if not output.is_file():
            raise SystemExit("Frozen worker did not create the requested DOCX file.")
        with ZipFile(output) as archive:
            if "word/document.xml" not in archive.namelist():
                raise SystemExit("Frozen worker output is not a valid DOCX archive.")
        with pymupdf.open(image_output) as document:
            if document.page_count != 1:
                raise SystemExit("Frozen worker image output is not a valid PDF.")
        with Image.open(raster_output) as image:
            if image.format != "JPEG" or image.size != (24, 12):
                raise SystemExit("Frozen worker raster output is not a valid JPEG.")


def main() -> int:
    mode = parse_mode()
    target_platform = normalized_platform()
    architecture = normalized_architecture()
    extension = ".exe" if target_platform == "windows" else ""
    dist_dir = PROJECT_ROOT / "backend" / "dist" / mode
    work_dir = (
        PROJECT_ROOT
        / "build"
        / "pyinstaller"
        / target_platform
        / architecture
        / mode
    )
    spec_file = PROJECT_ROOT / "backend" / "universal_converter_worker.spec"

    if dist_dir.exists():
        shutil.rmtree(dist_dir)
    dist_dir.mkdir(parents=True)
    work_dir.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    environment["UC_WORKER_BUILD_MODE"] = mode
    command = [
        sys.executable,
        "-m",
        "PyInstaller",
        "--noconfirm",
        "--clean",
        "--distpath",
        str(dist_dir),
        "--workpath",
        str(work_dir),
        str(spec_file),
    ]
    subprocess.run(command, cwd=PROJECT_ROOT, env=environment, check=True)

    worker_path = dist_dir / f"{WORKER_NAME}{extension}"
    if not worker_path.is_file():
        raise SystemExit(f"PyInstaller did not create {worker_path}")
    if target_platform != "windows":
        worker_path.chmod(worker_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    smoke_test(worker_path)
    manifest = {
        "platform": target_platform,
        "architecture": architecture,
        "mode": mode,
        "python": platform.python_version(),
        "worker": worker_path.name,
    }
    (dist_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Built and verified: {worker_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
