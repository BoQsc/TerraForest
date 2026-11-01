# SPDX-License-Identifier: 0BSD
"""Check terrain patch bindings against isolated debug/release native libraries."""
from datetime import datetime, timezone
import hashlib
import json
import shutil

from run import ROOT, parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata


def main():
    config, _ = parse_args([])
    folder = ROOT / "reports/terrain_field_patch_binding" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    results = []
    for variant in ("debug", "release"):
        project = folder / variant
        addon = project / "addons/volumetric_terrain"
        (addon / "bin").mkdir(parents=True)
        (project / "tests").mkdir()
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Field Patch Check"\n', encoding="utf-8")
        library = "terrain_core.windows.x86_64.dll" if variant == "debug" else "terrain_core.windows.template_release.x86_64.dll"
        original = ROOT / "addons/volumetric_terrain/bin" / library
        shutil.copy2(original, addon / "bin" / library)
        extension = (ROOT / "addons/volumetric_terrain/terrain_core.gdextension").read_text()
        if variant == "release":
            extension = extension.replace("terrain_core.windows.x86_64.dll", library)
        (addon / "terrain_core.gdextension").write_text(extension, encoding="utf-8")
        shutil.copy2(ROOT / "addons/volumetric_terrain/mesh_codec.gd", addon / "mesh_codec.gd")
        shutil.copy2(ROOT / "addons/volumetric_terrain/mesh_codec.gd.uid", addon / "mesh_codec.gd.uid")
        shutil.copy2(ROOT / "tests/terrain_field_patch.gd", project / "tests/terrain_field_patch.gd")
        identity = ROOT / "tests/terrain_field_patch.gd.uid"
        shutil.copy2(identity, project / "tests/terrain_field_patch.gd.uid")
        command = [config.godot, "--headless", "--path", str(project), "--script", "res://tests/terrain_field_patch.gd", "--log-file", str(project / "engine.log")]
        result = execute(command, project, 90, "TERRAIN_FIELD_PATCH checks=")
        results.append({"variant": variant, "result": result, "command": command,
                        "library_sha256": hashlib.sha256((addon / "bin" / library).read_bytes()).hexdigest()})
    passed = all(row["result"]["passed"] for row in results)
    record = dict(passed=passed, variants=results, scope="Headless native adapter and deferred storage; not playable multi-owner quest reset.", **revision_metadata())
    (folder / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if passed else "FAIL ") + str(folder), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
