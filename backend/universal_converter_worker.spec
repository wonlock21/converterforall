# -*- mode: python ; coding: utf-8 -*-

import os
from pathlib import Path


project_root = Path(SPECPATH).resolve().parent
build_mode = os.environ.get("UC_WORKER_BUILD_MODE", "release")

analysis = Analysis(
    [str(project_root / "backend" / "worker.py")],
    pathex=[str(project_root)],
    binaries=[],
    datas=[],
    hiddenimports=[
        "backend.registry",
        "backend.converters.pdf_to_docx",
        "backend.converters.pdf_to_text",
        "backend.converters.pdf_to_image",
        "backend.converters.image_to_pdf",
        "backend.converters.raster_image",
        "cv2",
        "fitz",
        "PIL",
        "PIL.Image",
        "PIL.ImageOps",
        "pdf2docx",
        "pymupdf",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

python_archive = PYZ(analysis.pure)

worker = EXE(
    python_archive,
    analysis.scripts,
    analysis.binaries,
    analysis.datas,
    [],
    name="universal_converter_worker",
    debug=build_mode == "debug",
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
