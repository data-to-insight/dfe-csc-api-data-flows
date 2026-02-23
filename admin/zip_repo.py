#!/usr/bin/env python3
"""
zip_repo.py

Create zip of repo  (all files all subfolders) into ./ for download
Defaults to excluding only:
- .git/
- the output zip itself

Usage:
  python zip_repo.py
  python zip_repo.py --output my_repo.zip
  python zip_repo.py --exclude ".venv" "node_modules" "__pycache__"
"""

from __future__ import annotations

import argparse
import fnmatch
import os
from datetime import datetime
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


def _norm(p: str) -> str:
    return p.replace("\\", "/")


def should_exclude(rel_posix: str, exclude: list[str]) -> bool:
    rel_posix = _norm(rel_posix).lstrip("./")

    # Exclude if any path segment matches or whole relative path matches or glob matches
    parts = rel_posix.split("/") if rel_posix else []
    for pat in exclude:
        pat = _norm(pat).strip().strip("/")
        if not pat:
            continue

        if pat in parts:
            return True
        if rel_posix == pat:
            return True
        if fnmatch.fnmatch(rel_posix, pat) or fnmatch.fnmatch(Path(rel_posix).name, pat):
            return True

    return False


def zip_repo(root: Path, output_zip: Path, exclude: list[str]) -> tuple[int, int]:
    root = root.resolve()
    output_zip = output_zip.resolve()

    if output_zip.exists() and output_zip.is_dir():
        raise ValueError(f"Output path points to dir: {output_zip}")

    output_zip.parent.mkdir(parents=True, exist_ok=True)

    files_added = 0
    dirs_seen = 0

    with ZipFile(output_zip, "w", compression=ZIP_DEFLATED, compresslevel=9, allowZip64=True) as zf:
        for path in root.rglob("*"):
            rel = path.relative_to(root)
            rel_posix = _norm(str(rel))

            # Skip output zip if it sits inside root
            if path.resolve() == output_zip:
                continue

            if should_exclude(rel_posix, exclude):
                continue

            if path.is_dir():
                dirs_seen += 1
                continue

            # Only add regular files
            if not path.is_file():
                continue

            zf.write(path, arcname=rel_posix)
            files_added += 1

    return files_added, dirs_seen


def main() -> int:
    parser = argparse.ArgumentParser(description="Zip up the current repo folder into a zip in ./")
    parser.add_argument(
        "--root",
        default=".",
        help="Repo root to zip (default: current directory)",
    )
    parser.add_argument(
        "--output",
        default="",
        help="Output zip filename (default: <repo_name>_<timestamp>.zip in current folder)",
    )
    parser.add_argument(
        "--exclude",
        nargs="*",
        default=[],
        help='Extra exclude patterns or folder names, eg: --exclude ".venv" "node_modules" "*.parquet"',
    )

    args = parser.parse_args()

    root = Path(args.root).resolve()
    if not root.exists() or not root.is_dir():
        raise SystemExit(f"Root folder does not exist or is not directory: {root}")

    repo_name = root.name or "repo"
    default_name = f"{repo_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.zip"
    output_name = args.output.strip() or default_name

    # Always write into the current working directory, as requested
    output_zip = (Path.cwd() / output_name).resolve()

    exclude = [".git"]
    exclude.extend(args.exclude or [])

    files_added, _ = zip_repo(root, output_zip, exclude)

    size_mb = output_zip.stat().st_size / (1024 * 1024)
    print(f"Created: {output_zip.name}")
    print(f"Files added: {files_added}")
    print(f"Size: {size_mb:.2f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
