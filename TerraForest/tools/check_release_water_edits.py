# SPDX-License-Identifier: 0BSD
"""Exercise the real Windows release executable and adjacent candidate PCK on an isolated desktop."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

from development_storage import ROOT, admit
from run_godot_check import command_for, execute


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save(path, record):
    path.write_text(json.dumps(record, indent=2), encoding="utf-8")


def run_route(engine, pack_hash, label, flags, index, frozen_driver):
    folder = ROOT / "reports/checks" / stamp()
    folder.mkdir()
    driver = folder / "water_player_world.gd"
    shutil.copyfile(frozen_driver, driver)
    options = [
        "--water-source-slot=Cedar_Vale",
        "--water-source-sha256=988048ed6ae59676c66d8692e51cf5eb7636a94a686f4787bf42fa1fe269ba44",
        "--two-frame-edits", "--packed-terrain-upload", "--isolated-render", *flags,
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


def main():
    template = ROOT / "dist/TerraForest.exe"
    native = sorted((ROOT / "addons").glob("*/bin/*.windows.template_release.x86_64.dll"))
    pack_limit = (ROOT / "dist/TerraForest.pck").stat().st_size + 16 * 2**20
    admission = admit(ROOT, report_bytes=50 * 2**20, scratch_bytes=pack_limit + template.stat().st_size
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
        cut = ["--water-load-only", "--authoring-brush", "--authoring-lake-cut"]
        shores = ["--water-immediate-contact", "--water-edit-response", "--blast-only-timing"]
        passed = True
        for label, flags in [("cut", cut), ("shores", shores + ["--water-no-captures"]),
                             ("cut_angles", cut + ["--authoring-cut-angles"]), ("shore_angles", shores)]:
            folder, result = run_route(engine, record["pack_sha256"], label, flags, index, frozen_driver)
            record["runs"][label] = str(folder)
            save(index, record)
            passed &= result["passed"]
            log = folder / "console.log"
            if result.get("launch_error") or not log.exists() or "WATER_GAMEPLAY_INPUT " not in log.read_text(errors="replace"):
                break
        return 0 if passed and len(record["runs"]) == 4 else 1
    finally:
        for path in [pack, *(target for _, target in copies)]:
            if not path.resolve().is_relative_to(stage.resolve()):
                raise ValueError("Unexpected stage path")
            path.unlink(missing_ok=True)
        for directory in sorted((d for d in stage.rglob("*") if d.is_dir()), key=lambda d: -len(d.parts)):
            if not any(directory.iterdir()):
                directory.rmdir()
        if not any(stage.iterdir()):
            stage.rmdir()
        record["released"] = not stage.exists()
        save(index, record)
        print(index, flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
