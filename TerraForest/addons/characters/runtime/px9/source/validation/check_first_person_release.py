#!/usr/bin/env python3
# SPDX-License-Identifier: CC0-1.0
"""Run the three independent PX9 release checks without changing asset inputs.

Usage:
    python3 check_first_person_release.py /path/to/PX9_Eclipse_FirstPerson_CC0

Keep this file, the three validate_*.py files, hand_weight_eligibility.py and original_*_contract.json
snapshots together. Only the Python standard library and native Blender APIs
are used. Native Godot playback/serialization validation remains a separate
report; this command does not substitute for it.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


HERE = Path(__file__).resolve().parent
ORIGINAL_HUMAN_SHA256 = "0dc8fdbcfac451f61b6eee5c914b1e79f5ec450f5e98e4c896e8b46370bf35c8"


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def file_record(path: Path) -> dict:
    return {"file": str(path), "bytes": path.stat().st_size, "sha256": digest(path)}


def json_write(path: Path, value: dict) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def entry_path(value: str, definition: Path, project: Path) -> Path:
    if value.startswith("res://"):
        return (project / value[6:]).resolve()
    path = Path(value)
    return (path if path.is_absolute() else definition.parent / path).resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("package", type=Path, help="Final package directory")
    parser.add_argument("--blender", default="blender", help="Native Blender executable")
    parser.add_argument("--definition", type=Path, help="Override item_px9.json path")
    parser.add_argument("--source", type=Path, help="Override combined Blender source path")
    parser.add_argument("--frames", type=Path, help="Override AUTHORED_FRAMES.json path")
    parser.add_argument("--hand-patch", type=Path, help="Override portable hand-weight JSON path")
    parser.add_argument("--project-root", type=Path, help="Godot project root used to resolve res:// entries")
    parser.add_argument("--report-dir", type=Path, help="Output directory; defaults to PACKAGE/validation")
    parser.add_argument("--stage-timeout", type=float, default=1800.0, help="Maximum seconds per stage")
    args = parser.parse_args()
    package = args.package.expanduser().resolve()
    if not package.is_dir():
        parser.error("Package directory does not exist: " + str(package))
    report_dir = (args.report_dir or package / "validation").expanduser().resolve()
    report_dir.mkdir(parents=True, exist_ok=True)
    definition = (args.definition or package / "item_px9.json").expanduser().resolve()
    project = (args.project_root or package).expanduser().resolve()
    source = (args.source or package / "source" / "Human.px9_eclipse.blend").expanduser().resolve()
    frames = (args.frames or package / "validation" / "AUTHORED_FRAMES.json").expanduser().resolve()
    preflight_errors = []
    data = {}
    if not definition.is_file():
        preflight_errors.append("Missing item definition: " + str(definition))
    else:
        try:
            data = json.loads(definition.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            preflight_errors.append("Cannot read item definition: " + str(error))

    inputs = {"definition": definition, "blender_source": source, "authored_frames": frames}
    for role, key in (("human_animation", "human_animation_source"),
                      ("weapon_animation", "item_scene"),
                      ("human_reference", "human_reference")):
        value = data.get("files", {}).get(key)
        if isinstance(value, str) and value:
            inputs[role] = entry_path(value, definition, project)
        else:
            preflight_errors.append("Missing definition.files." + key)
    patch_value = data.get("human", {}).get("hand_weight_patch")
    if args.hand_patch:
        inputs["hand_patch"] = args.hand_patch.expanduser().resolve()
    elif isinstance(patch_value, str) and patch_value:
        inputs["hand_patch"] = entry_path(patch_value, definition, project)
    else:
        # Older authoring manifests omit the runtime adapter's optional field.
        candidates = [package / "hand_weight_patch.json",
                      package / "Human.px9_eclipse.hand_weights.json",
                      package / "source" / "hand_weight_patch.json"]
        existing = [path for path in candidates if path.is_file()]
        if len(existing) == 1:
            inputs["hand_patch"] = existing[0]
        else:
            preflight_errors.append("Hand-weight patch cannot be resolved; pass --hand-patch explicitly")

    support_names = ["check_first_person_release.py", "validate_first_person_blender.py", "validate_first_person_exports.py",
                     "validate_exported_contacts.py", "hand_weight_eligibility.py", "original_r11_contract.json",
                     "original_px9_contract.json", "original_human_body_variant_contract.json"]
    support = {name: HERE / name for name in support_names}
    for role, path in {**inputs, **support}.items():
        if not path.is_file():
            preflight_errors.append("Missing " + role + ": " + str(path))
    blender = shutil.which(args.blender)
    if not blender:
        preflight_errors.append("Blender executable not found: " + args.blender)
    if args.stage_timeout <= 0:
        preflight_errors.append("stage-timeout must be positive")

    before = {role: file_record(path) for role, path in inputs.items() if path.is_file()}
    reference_hash = before.get("human_reference", {}).get("sha256")
    if reference_hash and reference_hash != ORIGINAL_HUMAN_SHA256:
        preflight_errors.append("Included Human.r11.glb is not the exact original runtime reference")
    manifest_reference_hash = data.get("human", {}).get("reference_sha256")
    if manifest_reference_hash != ORIGINAL_HUMAN_SHA256:
        preflight_errors.append("Manifest human.reference_sha256 does not name the original runtime file")

    summary = {
        "schema": "px9-first-person-release-validation-1",
        "passed": False,
        "checked_at_utc": datetime.now(timezone.utc).isoformat(),
        "package": str(package),
        "inputs_before": before,
        "validator_files": {name: file_record(path) for name, path in support.items() if path.is_file()},
        "preflight_errors": preflight_errors,
        "stages": [],
        "scope": "Read-only combined Blender source preservation, paired GLB contracts, and raw exported every-frame rigid contacts. Native Godot import, skin serialization, runtime events, switching and rendering are validated separately.",
    }
    summary_path = report_dir / "RELEASE_VALIDATION.json"
    if preflight_errors:
        json_write(summary_path, summary)
        print(json.dumps({"passed": False, "preflight_errors": preflight_errors,
                          "report": str(summary_path)}, indent=2), flush=True)
        return 1

    common = [str(blender), "--background", "--disable-autoexec"]
    stages = [
        ("blender_source", "BLENDER_VALIDATION.json",
         common + [str(source), "--python-exit-code", "1", "--python", str(support["validate_first_person_blender.py"]), "--",
                   "--manifest", str(definition), "--hand-patch", str(inputs["hand_patch"])]),
        ("paired_glb", "GLB_VALIDATION.json",
         [sys.executable, str(support["validate_first_person_exports.py"]),
          "--definition", str(definition), "--human", str(inputs["human_animation"]),
          "--weapon", str(inputs["weapon_animation"])]),
        ("exported_contacts", "CONTACT_VALIDATION.json",
         common + ["--factory-startup", "--python-exit-code", "1", "--python", str(support["validate_exported_contacts.py"]), "--",
                   "--definition", str(definition), "--frames", str(frames),
                   "--human", str(inputs["human_animation"]), "--weapon", str(inputs["weapon_animation"])]),
    ]
    # Fresh temporary report paths prevent a crashed child from reusing a stale
    # PASS. Final report names are updated only with this run's result.
    with tempfile.TemporaryDirectory(prefix=".release_check_", dir=report_dir) as temporary:
        for name, report_name, command in stages:
            stage_report = Path(temporary) / report_name
            command = command + ["--report", str(stage_report)]
            log_path = report_dir / (name + ".log")
            print("Checking " + name + " …", flush=True)
            started = time.monotonic()
            failure = None
            returncode = None
            with log_path.open("w", encoding="utf-8") as log:
                try:
                    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                            timeout=args.stage_timeout, check=False)
                    returncode = result.returncode
                except (OSError, subprocess.TimeoutExpired) as error:
                    failure = str(error)
                    log.write("\nRELEASE WRAPPER ERROR: " + failure + "\n")
            detail = None
            if stage_report.is_file():
                try:
                    detail = json.loads(stage_report.read_text(encoding="utf-8"))
                except (OSError, ValueError) as error:
                    failure = "Child report could not be read: " + str(error)
            else:
                failure = failure or "Child did not create a report"
            passed = returncode == 0 and isinstance(detail, dict) and detail.get("passed") is True and not failure
            output = report_dir / report_name
            if isinstance(detail, dict):
                if not passed:
                    detail["passed"] = False
                    detail["release_wrapper_failure"] = {"returncode": returncode, "message": failure}
                json_write(output, detail)
            else:
                json_write(output, {"passed": False, "stage": name, "returncode": returncode,
                                    "failure": failure, "log": log_path.name})
            summary["stages"].append({
                "name": name, "passed": passed, "returncode": returncode,
                "elapsed_seconds": round(time.monotonic() - started, 3),
                "report": output.name, "report_sha256": digest(output),
                "log": log_path.name, "failure": failure,
            })
            print(name + ": " + ("PASS" if passed else "FAIL") + " (" + output.name + ")", flush=True)

    after = {role: file_record(path) for role, path in inputs.items() if path.is_file()}
    modified = [role for role in before if before[role] != after.get(role)]
    summary["inputs_after"] = after
    summary["input_files_modified_during_validation"] = modified
    summary["exact_original_runtime_reference_preserved"] = after.get("human_reference", {}).get("sha256") == ORIGINAL_HUMAN_SHA256
    summary["passed"] = (all(row["passed"] for row in summary["stages"])
                         and len(summary["stages"]) == 3 and not modified
                         and summary["exact_original_runtime_reference_preserved"])
    json_write(summary_path, summary)
    print(json.dumps({"passed": summary["passed"], "input_files_modified": modified,
                      "stages": [{"name": row["name"], "passed": row["passed"]} for row in summary["stages"]],
                      "report": str(summary_path)}, indent=2), flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
