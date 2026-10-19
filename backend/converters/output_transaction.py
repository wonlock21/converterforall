"""Helpers for publishing converter outputs without leaving partial files."""

from __future__ import annotations

import os
import tempfile
from collections.abc import Mapping
from pathlib import Path

from backend.errors import ConversionError


def temporary_path_for(output_path: Path) -> Path:
    """Reserve a temporary sibling path with the output's real extension."""

    descriptor, name = tempfile.mkstemp(
        dir=output_path.parent,
        prefix=f".{output_path.stem}-",
        suffix=output_path.suffix,
    )
    os.close(descriptor)
    path = Path(name)
    path.unlink(missing_ok=True)
    return path


def publish_outputs(
    staged_outputs: Mapping[Path, Path], *, overwrite: bool
) -> tuple[Path, ...]:
    """Atomically publish staged siblings and restore existing files on failure."""

    backups: dict[Path, Path] = {}
    published: list[Path] = []
    try:
        if not overwrite:
            collision = next((path for path in staged_outputs.values() if path.exists()), None)
            if collision is not None:
                raise ConversionError(
                    "output_exists",
                    f"The output file already exists: {collision.name}",
                )

        for final_path in staged_outputs.values():
            if final_path.exists():
                backup = temporary_path_for(final_path)
                os.replace(final_path, backup)
                backups[final_path] = backup

        for staged_path, final_path in staged_outputs.items():
            os.replace(staged_path, final_path)
            published.append(final_path)

        for backup in backups.values():
            backup.unlink(missing_ok=True)
        return tuple(staged_outputs.values())
    except Exception:
        for final_path in reversed(published):
            final_path.unlink(missing_ok=True)
        for final_path, backup in backups.items():
            if backup.exists():
                os.replace(backup, final_path)
        raise
    finally:
        for staged_path in staged_outputs:
            staged_path.unlink(missing_ok=True)
        for backup in backups.values():
            backup.unlink(missing_ok=True)
