from __future__ import annotations

import argparse
import re
from pathlib import Path
from zipfile import BadZipFile, ZipFile


WINDOWS_ABSOLUTE = re.compile(rb"(?i)(?:^|[^A-Za-z0-9])([A-Z]:[\\/])")
TEXT_SUFFIXES = {
    ".csv",
    ".json",
    ".lock",
    ".md",
    ".mjs",
    ".py",
    ".r",
    ".cs",
    ".csproj",
    ".tsv",
    ".txt",
}
ARCHIVE_SUFFIXES = {".docx", ".xlsx"}


def contains_absolute_path(data: bytes) -> bool:
    return bool(WINDOWS_ABSOLUTE.search(data))


def main() -> None:
    parser = argparse.ArgumentParser(description="Audit public-release directory hygiene.")
    parser.add_argument("release_root", type=Path)
    args = parser.parse_args()
    root = args.release_root.resolve()

    forbidden: list[str] = []
    path_leaks: list[str] = []
    for path in root.rglob("*"):
        relative = path.relative_to(root).as_posix()
        parts = set(path.relative_to(root).parts)
        if parts & {"figures", "tmp", "node_modules", "__pycache__", ".pytest_cache"}:
            forbidden.append(relative)
            continue
        if path.name.endswith(".inspect.ndjson") or "v1.3_20260710" in path.name:
            forbidden.append(relative)
            continue
        if not path.is_file():
            continue
        if path.suffix.lower() in TEXT_SUFFIXES:
            if contains_absolute_path(path.read_bytes()):
                path_leaks.append(relative)
        elif path.suffix.lower() in ARCHIVE_SUFFIXES:
            try:
                with ZipFile(path) as archive:
                    for member in archive.infolist():
                        if member.is_dir() or Path(member.filename).suffix.lower() not in {
                            ".xml",
                            ".rels",
                            ".txt",
                            ".json",
                        }:
                            continue
                        if contains_absolute_path(archive.read(member)):
                            path_leaks.append(f"{relative}!{member.filename}")
            except BadZipFile:
                path_leaks.append(f"{relative}!invalid-zip")

    print(f"Forbidden entries: {len(forbidden)}")
    print(f"Absolute-path leaks: {len(path_leaks)}")
    for item in forbidden + path_leaks:
        print(item)
    if forbidden or path_leaks:
        raise SystemExit("Release hygiene audit failed")


if __name__ == "__main__":
    main()
