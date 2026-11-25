# SPDX-License-Identifier: 0BSD
"""Exercise the real Windows release executable and adjacent candidate PCK on an isolated desktop."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from development_storage import ROOT, admit
from maintain_water_captures import maintain
from run_godot_check import command_for, execute


EDITOR = ["--water-load-only", "--authoring-brush"]
CUT = EDITOR + ["--authoring-lake-cut"]
SHORES = ["--water-immediate-contact", "--water-edit-response", "--blast-only-timing"]
DEFAULT_ROUTES = ("cut", "shores", "cut_angles", "shore_angles", "bucket_interruption", "object_contact")
WORKLOADS = {
    "cut": CUT,
    "object_contact": SHORES + ["--water-no-captures", "--water-object-contact", "--lossless-shore-views"],
    "shores": SHORES + ["--water-no-captures"],
    "cut_angles": CUT + ["--authoring-cut-angles"],
    "shore_angles": SHORES + ["--lossless-shore-views"],
    "bucket_interruption": ["--water-immediate-contact", "--water-edit-response", "--water-no-captures"],
    "dry_cut": EDITOR + ["--authoring-dry-cut"],
    "dry_cut_profile": EDITOR + ["--authoring-dry-cut", "--authoring-native-profile"],
    "dry_cut_replay": EDITOR + ["--authoring-dry-cut", "--authoring-swap-bound"],
    "brush_dig": EDITOR,
    "brush_fill": EDITOR + ["--authoring-fill"],
    "brush_drag": EDITOR + ["--authoring-drag"],
    "brush_materials": EDITOR + ["--authoring-materials"],
    "brush_max": EDITOR + ["--authoring-fill", "--authoring-max-radius"],
    "overview_wet": EDITOR + ["--authoring-overview-wet"],
    "overview_brush": EDITOR + ["--authoring-overview"],
    "overview_review": EDITOR + ["--authoring-overview", "--editor-review"],
    "overview_remote": EDITOR + ["--authoring-overview", "--editor-remote"],
}


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save(path, record):
    path.write_text(json.dumps(record, indent=2), encoding="utf-8")


def release_stage(stage, files):
    root = stage.resolve(strict=True)
    for path in files:
        if not path.resolve().is_relative_to(root):
            raise ValueError("Unexpected stage path")
        # Windows can briefly retain the image mapping after reporting the
        # exit code. Only retry the files owned by this frozen candidate.
        deadline = time.monotonic() + 5
        while True:
            try:
                path.unlink(missing_ok=True)
                break
            except PermissionError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.1)
    for directory in sorted((d for d in stage.rglob("*") if d.is_dir()), key=lambda d: -len(d.parts)):
        if not any(directory.iterdir()):
            directory.rmdir()
    if not any(stage.iterdir()):
        stage.rmdir()


def run_route(engine, pack_hash, label, flags, index, frozen_driver):
    folder = ROOT / "reports/checks" / stamp()
    folder.mkdir()
    driver = folder / "water_player_world.gd"
    shutil.copyfile(frozen_driver, driver)
    options = [
        "--water-source-slot=Cedar_Vale",
        "--water-source-sha256=988048ed6ae59676c66d8692e51cf5eb7636a94a686f4787bf42fa1fe269ba44",
        "--two-frame-edits", "--isolated-render", *flags,
    ]
    command, cache = command_for(engine, driver.stem, folder, options, headless=False)
    # The production export discovers its adjacent pack. It rejects --path and --main-pack.
    pos = command.index("--path")
    del command[pos:pos + 2]
    command[command.index("--fullscreen")] = "--windowed"
    pos = command.index("--script")
    del command[pos:pos + 2]
    command.append("--water-qualification-driver=res://qualification/water_player_world.gd")
    record = dict(command=command, cache=cache, pack_sha256=pack_hash, driver_sha256=digest(driver),
                  release_receipt=str(index), isolated_render=True)
    path = folder / "run.json"
    save(path, record)
    record["result"] = execute(command, folder, 375, "WATER_PLAYER_WORLD failures=0", isolated_render=True)
    save(path, record)
    print(label, folder, record["result"]["passed"], flush=True)
    return folder, record["result"]


def main(timing_only=False, selected_routes=None):
    template = ROOT / "dist/TerraForest.exe"
    native = sorted((ROOT / "addons").glob("*/bin/*.windows.template_release.x86_64.dll"))
    pack_limit = (ROOT / "dist/TerraForest.pck").stat().st_size + 16 * 2**20
    # The export writes a receipt, driver and export log. Each subsequent
    # route admits its own logs and images in execute() before game launch.
    admission = admit(ROOT, report_bytes=2 * 2**20, scratch_bytes=pack_limit + template.stat().st_size
                      + sum(path.stat().st_size for path in native))
    tag = stamp()
    output = ROOT / "reports/checks" / tag
    stage = ROOT / ".build" / ("water_release_" + tag)
    output.mkdir()
    stage.mkdir()
    engine = stage / template.name
    pack = engine.with_suffix(".pck")
    copies = [(template, engine)] + [(source, stage / source.relative_to(ROOT)) for source in native]
    index = output / "candidate.json"
    record = dict(admission=admission, revision=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT,
                  text=True).strip(), stage=str(stage), inputs={}, runs={}, lifecycle="Release only this run's named staged files after process exit")
    frozen_driver = output / "water_player_world.gd"
    shutil.copyfile(ROOT / "tests" / frozen_driver.name, frozen_driver)
    record["driver_sha256"] = digest(frozen_driver)
    save(index, record)
    try:
        for source, target in copies:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            if digest(target) != digest(source):
                raise RuntimeError("Staging changed " + str(source))
            record["inputs"][target.relative_to(stage).as_posix()] = digest(target)
        with (output / "export.log").open("w", encoding="utf-8") as log:
            subprocess.run([str(ROOT / "TerraForest.exe"), "--headless", "--path", str(ROOT),
                            "--export-pack", "Windows Desktop", str(pack)], cwd=ROOT, stdout=log,
                           stderr=subprocess.STDOUT, timeout=240, check=True,
                           env={**os.environ, "TERRAFOREST_WATER_QUALIFICATION_PACK": str(pack),
                                "TERRAFOREST_WATER_QUALIFICATION_DRIVER": str(frozen_driver)})
        export_log = (output / "export.log").read_text(errors="replace")
        if pack.stat().st_size > pack_limit or "ERROR:" in export_log or "WATER_RELEASE_MAIN_SCENE" not in export_log:
            raise RuntimeError("Candidate export failed inspection")
        record["pack_sha256"] = digest(pack)
        save(index, record)
        passed = True
        routes = selected_routes or (("cut", "shores") if timing_only else DEFAULT_ROUTES)
        repetitions = {}
        for workload in routes:
            repetitions[workload] = repetitions.get(workload, 0) + 1
            label = workload if repetitions[workload] == 1 else f"{workload}.{repetitions[workload]}"
            folder, result = run_route(engine, record["pack_sha256"], label, WORKLOADS[workload], index, frozen_driver)
            record["runs"][label] = str(folder)
            if result.get("exit_code") is not None:
                record.setdefault("closed_runs", {})[str(folder)] = digest(folder / "run.json")
            save(index, record)
            passed &= result["passed"]
            log = folder / "console.log"
            if result.get("launch_error") or not log.exists() or "WATER_GAMEPLAY_INPUT " not in log.read_text(errors="replace"):
                break
            reviews = {"cut_angles": (4, "authoring_cut_angles"), "shore_angles": (10, "water_player_world"),
                       "overview_review": (2, "world_editor"), "object_contact": (3, "crater_object")}
            expected, family = reviews.get(workload, (0, None))
            if expected and result.get("exit_code") is not None:
                extension = "*.webp" if workload in {"shore_angles", "object_contact"} else "*.png"
                if len(list(folder.glob(extension))) != expected:
                    passed = False
                    continue
                try:
                    receipt = maintain(True, ROOT, 1, {family})
                    record.setdefault("capture_archives", {})[label] = receipt["manifests"]
                except OSError as error:
                    # An active game or build keeps its ownership. The following
                    # route still goes through its ordinary output admission.
                    record.setdefault("retention_wait", {})[label] = str(error)
                save(index, record)
        return 0 if passed and len(record["runs"]) == len(routes) else 1
    finally:
        try:
            release_stage(stage, [pack, *(target for _, target in copies)])
        finally:
            record["released"] = not stage.exists()
            save(index, record)
            print(index, flush=True)


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--timing-only",action="store_true",help="Run both deadline routes without allocating a camera-capture pass.")
    selection.add_argument("--route", choices=WORKLOADS, action="append",
                           help="Run named packaged routes in order. Repeating a route starts a fresh game process against the same frozen build.")
    args = parser.parse_args()
    raise SystemExit(main(args.timing_only, args.route))
