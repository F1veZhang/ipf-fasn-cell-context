from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import tarfile
import urllib.request
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Download, verify, and extract public IPF inputs.")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--raw-data-root", required=True, type=Path)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--no-extract", action="store_true")
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": "IPF-source-reanalysis/1.3"})
    with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as output:
        while True:
            block = response.read(8 * 1024 * 1024)
            if not block:
                break
            output.write(block)
    os.replace(partial, destination)


def safe_extract_tar(archive: Path, destination: Path) -> int:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with tarfile.open(archive) as handle:
        members = handle.getmembers()
        for member in members:
            target = (destination / member.name).resolve()
            if root != target and root not in target.parents:
                raise ValueError(f"Unsafe archive member: {member.name}")
        handle.extractall(destination, members=members, filter="data")
    return len(members)


def main() -> None:
    args = parse_args()
    manifest = args.manifest.resolve()
    raw_root = args.raw_data_root.resolve()
    raw_root.mkdir(parents=True, exist_ok=True)
    rows = list(csv.DictReader(manifest.open(encoding="utf-8-sig")))
    report = []

    for row in rows:
        relative = Path(row["relative_path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Manifest path is not repository-relative: {relative}")
        path = raw_root / relative
        expected_bytes = int(row["bytes"])
        expected_hash = row["sha256"].lower()
        if not path.exists():
            if args.verify_only:
                raise FileNotFoundError(path)
            print(f"Downloading {row['accession']}: {path.name}", flush=True)
            download(row["source_url"], path)
        actual_bytes = path.stat().st_size
        actual_hash = sha256(path)
        if actual_bytes != expected_bytes or actual_hash != expected_hash:
            raise ValueError(
                f"Verification failed for {path}: bytes {actual_bytes}/{expected_bytes}; "
                f"sha256 {actual_hash}/{expected_hash}"
            )
        report.append({"path": str(relative).replace("\\", "/"), "bytes": actual_bytes, "sha256": actual_hash})

        if path.name.endswith("_RAW.tar") and not args.no_extract:
            cel_dir = path.parent / "CEL"
            existing = list(cel_dir.rglob("*.CEL.gz")) + list(cel_dir.rglob("*.cel.gz"))
            if not existing:
                count = safe_extract_tar(path, cel_dir)
                print(f"Extracted {count} members to {cel_dir}", flush=True)

    report_path = raw_root / "input_verification_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Verified {len(report)} public inputs; report: {report_path}")


if __name__ == "__main__":
    main()
