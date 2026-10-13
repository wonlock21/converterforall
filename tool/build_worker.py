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

    with tempfile.TemporaryDirectory(prefix="uc-worker-smoke-") as temp_directory:
        temp_path = Path(temp_directory)
        source = temp_path / "source.pdf"
        output = temp_path / "result.docx"
        with pymupdf.open() as document:
            page = document.new_page()
            page.insert_text((72, 72), "Universal Converter worker smoke test")
            document.save(source)

        request = {
            "id": "pyinstaller-smoke-test",
            "action": "convert",
            "source_format": "pdf",
            "target_format": "docx",
            "input_path": str(source),
            "output_path": str(output),
            "overwrite": False,
        }
        completed = subprocess.run(
            [str(worker_path)],
            input=json.dumps(request) + "\n",
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=90,
            check=False,
        )
        protocol_lines = completed.stdout.splitlines()
        if completed.returncode != 0 or len(protocol_lines) != 1:
            raise SystemExit(
                "Frozen worker smoke test failed.\n"
                f"exit={completed.returncode}\n"
                f"stdout={completed.stdout}\n"
                f"stderr={completed.stderr}"
            )
        response = json.loads(protocol_lines[0])
        if response.get("id") != request["id"] or response.get("success") is not True:
            raise SystemExit(f"Unexpected frozen worker response: {response}")
        if not output.is_file():
            raise SystemExit("Frozen worker did not create the requested DOCX file.")
        with ZipFile(output) as archive:
            if "word/document.xml" not in archive.namelist():
                raise SystemExit("Frozen worker output is not a valid DOCX archive.")


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
