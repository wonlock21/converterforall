"""Create portable desktop artifacts from a release Flutter bundle."""

from __future__ import annotations

import json
import os
import platform
import shutil
import stat
import subprocess
import tarfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PACKAGES_DIR = PROJECT_ROOT / "dist" / "packages"
APP_NAME = "UniversalConverter"
FLUTTER_BINARY = "convertforall_flutter"
WORKER_NAME = "universal_converter_worker"


def normalized_platform() -> str:
    return {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}.get(
        platform.system(), platform.system().lower()
    )


def normalized_architecture() -> str:
    machine = platform.machine().lower()
    if machine in {"amd64", "x86_64"}:
        return "x64"
    if machine in {"arm64", "aarch64"}:
        return "arm64"
    return machine


def smoke_test(worker: Path) -> None:
    if not worker.is_file():
        raise SystemExit(f"Packaged worker is missing: {worker}")
    if normalized_platform() != "windows" and not os.access(worker, os.X_OK):
        raise SystemExit(f"Packaged worker is not executable: {worker}")

    request = {
        "id": "packaged-worker-smoke-test",
        "action": "convert",
        "source_format": "pdf",
        "target_format": "docx",
        "input_path": str(PROJECT_ROOT / "missing-packaged-test.pdf"),
        "output_path": str(PROJECT_ROOT / "missing-packaged-test.docx"),
        "overwrite": False,
    }
    completed = subprocess.run(
        [str(worker)],
        input=json.dumps(request) + "\n",
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=90,
        check=False,
    )
    lines = completed.stdout.splitlines()
    if completed.returncode != 0 or len(lines) != 1:
        raise SystemExit(
            f"Packaged worker failed: exit={completed.returncode}\n"
            f"stdout={completed.stdout}\nstderr={completed.stderr}"
        )
    response = json.loads(lines[0])
    error = response.get("error")
    if (
        response.get("id") != request["id"]
        or response.get("success") is not False
        or not isinstance(error, dict)
        or error.get("code") != "input_not_found"
    ):
        raise SystemExit(f"Packaged worker protocol mismatch: {response}")


def package_windows(architecture: str) -> list[Path]:
    bundle = PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Release"
    worker = bundle / "worker" / f"{WORKER_NAME}.exe"
    smoke_test(worker)
    archive_base = PACKAGES_DIR / f"{APP_NAME}-windows-{architecture}"
    archive = Path(
        shutil.make_archive(str(archive_base), "zip", root_dir=bundle)
    )
    return [archive]


def package_macos(architecture: str) -> list[Path]:
    app = (
        PROJECT_ROOT
        / "build"
        / "macos"
        / "Build"
        / "Products"
        / "Release"
        / f"{FLUTTER_BINARY}.app"
    )
    worker = app / "Contents" / "Resources" / "worker" / WORKER_NAME
    smoke_test(worker)
    zip_path = PACKAGES_DIR / f"{APP_NAME}-macos-{architecture}.zip"
    subprocess.run(
        [
            "ditto",
            "-c",
            "-k",
            "--sequesterRsrc",
            "--keepParent",
            str(app),
            str(zip_path),
        ],
        check=True,
    )
    dmg_path = PACKAGES_DIR / f"{APP_NAME}-macos-{architecture}.dmg"
    subprocess.run(
        [
            "hdiutil",
            "create",
            "-volname",
            "Universal Converter",
            "-srcfolder",
            str(app),
            "-ov",
            "-format",
            "UDZO",
            str(dmg_path),
        ],
        check=True,
    )
    return [zip_path, dmg_path]


def create_appimage(bundle: Path, architecture: str) -> Path | None:
    appimage_tool = os.environ.get("APPIMAGETOOL")
    if not appimage_tool:
        print("APPIMAGETOOL is not set; skipping optional AppImage output.")
        return None

    app_dir = PROJECT_ROOT / "dist" / "appimage" / f"{APP_NAME}.AppDir"
    if app_dir.exists():
        shutil.rmtree(app_dir)
    application_dir = app_dir / "usr" / "lib" / "universal-converter"
    shutil.copytree(bundle, application_dir, symlinks=True)

    app_run = app_dir / "AppRun"
    app_run.write_text(
        '#!/bin/sh\nexec "$APPDIR/usr/lib/universal-converter/'
        f'{FLUTTER_BINARY}" "$@"\n',
        encoding="utf-8",
    )
    app_run.chmod(app_run.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    (app_dir / "universal-converter.desktop").write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=Universal Converter\n"
        f"Exec={FLUTTER_BINARY}\n"
        "Icon=universal-converter\n"
        "Terminal=false\n"
        "Categories=Utility;\n",
        encoding="utf-8",
    )
    shutil.copy2(
        PROJECT_ROOT / "web" / "icons" / "Icon-512.png",
        app_dir / "universal-converter.png",
    )
    appimage_path = PACKAGES_DIR / f"{APP_NAME}-linux-{architecture}.AppImage"
    environment = os.environ.copy()
    environment["ARCH"] = "x86_64" if architecture == "x64" else "aarch64"
    subprocess.run(
        [appimage_tool, "--appimage-extract-and-run", str(app_dir), str(appimage_path)],
        env=environment,
        check=True,
    )
    return appimage_path


def package_linux(architecture: str) -> list[Path]:
    flutter_arch = "x64" if architecture == "x64" else "arm64"
    bundle = PROJECT_ROOT / "build" / "linux" / flutter_arch / "release" / "bundle"
    worker = bundle / "worker" / WORKER_NAME
    smoke_test(worker)
    archive = PACKAGES_DIR / f"{APP_NAME}-linux-{architecture}.tar.gz"
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(bundle, arcname=APP_NAME)
    outputs = [archive]
    appimage = create_appimage(bundle, architecture)
    if appimage is not None:
        outputs.append(appimage)
    return outputs


def main() -> int:
    PACKAGES_DIR.mkdir(parents=True, exist_ok=True)
    target_platform = normalized_platform()
    architecture = normalized_architecture()
    if target_platform == "windows":
        outputs = package_windows(architecture)
    elif target_platform == "macos":
        outputs = package_macos(architecture)
    elif target_platform == "linux":
        outputs = package_linux(architecture)
    else:
        raise SystemExit(f"Unsupported packaging platform: {target_platform}")
    for output in outputs:
        print(f"Created: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
