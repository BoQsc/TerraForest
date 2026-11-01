# SPDX-License-Identifier: 0BSD
"""Run bounded block-cell reset contracts against isolated debug/release DLLs."""
from datetime import datetime, timezone
import hashlib
import json
import re
import shutil

from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    config, _ = parse_args([])
    folder = ROOT / "reports/block_cell_patch" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    results = []
    for variant in ("debug", "release"):
        project = folder / variant
        addon = project / "addons/structures"
        (addon / "bin").mkdir(parents=True)
        (project / "tests").mkdir()
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Block Cell Patch Check"\n', encoding="utf-8")
        library = f"structures.windows.template_{variant}.x86_64.dll"
        shutil.copy2(ROOT / "addons/structures/bin" / library, addon / "bin" / library)
        extension = (ROOT / "addons/structures/structures.gdextension").read_text()
        if variant == "release":
            extension = extension.replace("template_debug", "template_release")
        (addon / "structures.gdextension").write_text(extension, encoding="utf-8")
        for suffix in (".gd", ".gd.uid"):
            shutil.copy2(ROOT / "tests" / ("block_regions" + suffix), project / "tests" / ("block_regions" + suffix))
        command = [config.godot, "--headless", "--path", str(project), "--script", "res://tests/block_regions.gd", "--log-file", str(project / "engine.log"), "--", "--cell-patch-only"]
        result = execute(command, project, 90, "BLOCK_CELL_PATCH checks=")
        log = (project / "console.log").read_text(encoding="utf-8", errors="replace")
        maximum = re.search(r"BLOCK_CELL_PATCH_MAX bytes=(\d+) capture_us=(\d+) restore_us=(\d+)", log)
        assertions = re.search(r"BLOCK_CELL_PATCH checks=(\d+) failures=(\d+)", log)
        results.append({"variant": variant, "result": result, "command": command,
                        "assertions": list(map(int, assertions.groups())) if assertions else None,
                        "maximum_patch": dict(zip(("bytes", "capture_us", "restore_us"), map(int, maximum.groups()))) if maximum else None,
                        "library_sha256": hashlib.sha256((addon / "bin" / library).read_bytes()).hexdigest()})
    passed = all(row["result"]["passed"] for row in results)
    record = dict(passed=passed, variants=results, scope="Bounded native block cells only; not complete multi-owner quest reset.", **revision_metadata())
    record["source_sha256"] = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
        "addons/structures/native/block_patch.cpp", "addons/structures/native/block_world.cpp",
        "addons/structures/native/block_world.hpp", "tests/block_regions.gd", "tools/check_block_cell_patch.py")}
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if passed else "FAIL ") + str(folder), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
