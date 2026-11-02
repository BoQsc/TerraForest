# SPDX-License-Identifier: 0BSD
"""Read-only startup/storage audit. Never opens a game or modifies a save/cache."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import struct
import time
import zlib

ROOT = Path(__file__).resolve().parents[1]


def sections(data: bytes) -> dict[str, bytes]:
    """Validate the outer TFWORLD1 container; component schemas remain native-owned."""
    if not 48 <= len(data) <= 256 * 1024 * 1024 or data[:8] != b"TFWORLD1":
        raise ValueError("Unsupported world container")
    version, count = struct.unpack_from("<II", data, 8)
    if version != 1 or not 1 <= count <= 128:
        raise ValueError("Unsupported archive version/section count")
    digest = hashlib.sha256(data[8:16])
    digest.update(memoryview(data)[48:])
    if digest.digest() != data[16:48]:
        raise ValueError("Archive digest mismatch")
    result = {}
    cursor = 48
    previous = ""
    for _ in range(count):
        if cursor + 8 > len(data):
            raise ValueError("Truncated section header")
        name_size, size = struct.unpack_from("<II", data, cursor)
        cursor += 8
        if not 1 <= name_size <= 48 or cursor + name_size + size > len(data):
            raise ValueError("Invalid section bounds")
        name = data[cursor:cursor + name_size].decode("ascii")
        cursor += name_size
        if not re.fullmatch(r"[a-z0-9_]+", name) or name <= previous:
            raise ValueError("Noncanonical section name/order")
        if name != "terrain" and size > 64 * 1024 * 1024:
            raise ValueError("Oversized addon section")
        result[name] = data[cursor:cursor + size]
        previous = name
        cursor += size
    if cursor != len(data) or "terrain" not in result:
        raise ValueError("Trailing bytes or missing terrain")
    return result


def generation(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    phases = []
    for phase in data.get("phases", []):
        profile = phase.get("profile", {})
        elapsed = profile.get("elapsed_microseconds", 0)
        recorded = sum(row["microseconds"] for row in profile.get("timings", []))
        current = profile.get("stage_microseconds", 0)
        dropped = profile.get("timings_dropped_microseconds", 0)
        phases.append({"stage": phase.get("stage"), "exit_code": phase.get("exit_code"),
                       "wall_seconds": phase.get("elapsed_usec", 0) / 1e6,
                       "profile_seconds": elapsed / 1e6,
                       "named_completed_seconds": recorded / 1e6,
                       "current_stage_seconds": current / 1e6,
                       "explicit_dropped_seconds": dropped / 1e6,
                       "unaccounted_seconds": (elapsed - recorded - current - dropped) / 1e6,
                       "timing_schema": profile.get("timing_schema", 1),
                       "timing_rows": len(profile.get("timings", [])),
                       "stage_timings": profile.get("timings", [])})
    result = {"report_id": path.parent.name, "destination": data.get("destination"),
              "seed": data.get("seed"), "generator": data.get("generator"),
              "published": data.get("publication", {}).get("ok", False),
              "phases": phases, "verification_ms": data.get("validation", {}).get("milliseconds"),
              "publication": {k: data.get("publication", {}).get(k) for k in
                              ("bytes", "files", "source_retired")},
              "run_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    for filename, key in (("earthworks_bake.json", "earthworks"),
                          ("generated_lakes_bake.json", "water_bake"),
                          ("photograph_timings.json", "photographs")):
        source = path.parent / filename
        if source.is_file():
            result[key] = json.loads(source.read_text(encoding="utf-8"))
    result["photograph_seconds"] = sum(sum(row.get(k, 0) for k in
        ("loading_ms", "vegetation_ms", "capture_ms")) for row in result.get("photographs", [])) / 1000
    return result


def file_inventory(path: Path) -> dict:
    groups = defaultdict(list)
    if path.is_file():
        groups[path.suffix].append(path.stat().st_size)
    elif path.is_dir():
        for directory, dirs, files in os.walk(path, followlinks=False):
            dirs[:] = [name for name in dirs if not (Path(directory) / name).is_symlink()]
            for name in files:
                item = Path(directory) / name
                if not item.is_symlink():
                    groups[item.suffix].append(item.stat().st_size)
    return {"files": sum(len(v) for v in groups.values()),
            "bytes": sum(sum(v) for v in groups.values()),
            "by_extension": {k: {"files": len(v), "bytes": sum(v),
                                  "median_bytes": statistics.median(v)} for k, v in sorted(groups.items())}}


def world(path: Path, compression: bool = False) -> dict:
    with path.open("rb") as handle:
        data = handle.read(256 * 1024 * 1024 + 1)
    parts = sections(data)
    result = {"slot": path.stem, "root_bytes": len(data), "root_sha256": hashlib.sha256(data).hexdigest(),
              "outer_digest_valid": True, "component_schema_validation": "not performed",
              "sections": {k: {"bytes": len(v), "prefix_hex": v[:8].hex()} for k, v in parts.items()}}
    result["storage"] = {suffix: file_inventory(Path(str(path) + suffix)) for suffix in
                         ("", ".bak", ".terrain", ".regions", ".models", ".water", ".baselines")}
    result["previews"] = file_inventory(path.with_suffix(".preview"))
    if compression and "volumetric_water" in parts:
        result["compression_experiment"] = []
        for level in (1, 6):
            source = parts["volumetric_water"]
            began = time.perf_counter()
            packed = zlib.compress(source, level)
            encode_ms = (time.perf_counter() - began) * 1000
            began = time.perf_counter()
            restored = zlib.decompress(packed)
            decode_ms = (time.perf_counter() - began) * 1000
            result["compression_experiment"].append({"codec": "Python zlib " + zlib.ZLIB_RUNTIME_VERSION,
                "level": level, "raw_bytes": len(source), "compressed_bytes": len(packed),
                "encode_ms": encode_ms, "decode_ms": decode_ms, "byte_exact": restored == source})
    result["root_unchanged"] = hashlib.sha256(path.read_bytes()).hexdigest() == result["root_sha256"]
    return result


def loading(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    durations = Counter()
    for row in data["samples"]:
        durations[row["phase"]] += row["ms"]
    return {"source": path.relative_to(ROOT).as_posix(), "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "sampled_phase_seconds": {k: v / 1000 for k, v in durations.items()},
            "stages": data.get("stages"), "startup": data.get("startup"),
            "max_frame_ms": data.get("max_frame_ms"),
            "scope": "Retained harness observations; phase-boundary frames and yielding included. Not cold-cache or CPU-exclusive times."}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user-data", type=Path, default=Path(os.environ.get("APPDATA", ".")) / "Godot/app_userdata/TerraForest")
    parser.add_argument("--slot", required=True)
    parser.add_argument("--report-id", action="append", default=[])
    parser.add_argument("--loading-report", type=Path)
    parser.add_argument("--compression-experiment", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,47}", args.slot):
        parser.error("Invalid slot identifier")
    if any(not re.fullmatch(r"[0-9a-f]{32}", value) for value in args.report_id):
        parser.error("Report IDs must be 32 lowercase hex digits")
    result = {"schema": 1, "observed_at_utc": datetime.now(timezone.utc).isoformat(),
              "scope": "Read-only saved evidence and storage inspection; no fresh world benchmark, no cold-cache claim. Publication byte counts exclude the root archive.",
              "generation": [generation(args.user_data / "generation_reports" / value / "run.json") for value in args.report_id],
              "world": world(args.user_data / "worlds" / (args.slot + ".trw"), args.compression_experiment)}
    if args.loading_report:
        result["loading"] = loading(args.loading_report.resolve())
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
