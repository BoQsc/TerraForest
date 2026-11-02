# SPDX-License-Identifier: 0BSD
"""Required terrain/block contract checks for source and exported builds."""
import argparse
import datetime
import hashlib
import json
import shutil
from pathlib import Path

from run import ROOT, parse_args
from run_godot_check import command_for, execute, revision_metadata
from native_test_retention import release_copies


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    options = parser.parse_args()
    engine = options.godot or parse_args([])[0].godot
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    report = ROOT / "reports/building_standards" / stamp
    report.mkdir(parents=True)
    results = []
    for test in ("terrain_block_contract", "terrain_block_catalog", "building_expansion", "building_materials", "building_expansion_pack", "production_building_catalog"):
        folder = report / test
        folder.mkdir()
        command, _ = command_for(engine, test, folder, [], headless=True)
        result = execute(command, folder, 180, test.upper() + " checks=")
        results.append({"test": test, "command": command, **result})
        print(("PASS " if result["passed"] else "FAIL ") + test, flush=True)

    # Isolated release-only project: the real checkout's descriptors/DLLs are
    # never rewritten, which also permits other chats to keep their own builds.
    project = ROOT / ".build" / ("building_contract_release_" + stamp)
    project.mkdir(parents=True)
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Building Contract Release Check"\n')
    extensions = []
    hashes = {}
    copied_libraries = {}
    for addon, descriptor, library in (
        ("structures", "structures.gdextension", "structures.windows.template_release.x86_64.dll"),
        ("volumetric_terrain", "terrain_core.gdextension", "terrain_core.windows.template_release.x86_64.dll"),
    ):
        source = ROOT / "addons" / addon
        target = project / "addons" / addon
        (target / "bin").mkdir(parents=True)
        shutil.copy2(source / "bin" / library, target / "bin" / library)
        hashes[library] = hashlib.sha256((source / "bin" / library).read_bytes()).hexdigest()
        copied_libraries[target / 'bin' / library] = hashes[library]
        text = (source / descriptor).read_text().replace("template_debug", "template_release").replace("terrain_core.windows.x86_64.dll", library)
        (target / descriptor).write_text(text)
        extensions.append("res://addons/" + addon + "/" + descriptor)
    for name in (
        "addons/structures/foundation_check.gd", "addons/structures/terrain_contact.gd",
        "addons/structures/site_plan.gd",
        "addons/volumetric_terrain/mesh_codec.gd", "addons/volumetric_terrain/surface_tokens.gd",
        "addons/world_runtime/generation_earthworks.gd", "tests/terrain_block_contract.gd",
        "tests/building_expansion.gd", "addons/structures/shape_catalog.gd",
    ):
        target = project / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    shutil.copytree(ROOT / "addons/structures/textures/expansion_v2", project / "addons/structures/textures/expansion_v2")
    (project / ".godot").mkdir()
    (project / ".godot/extension_list.cfg").write_text("\n".join(extensions) + "\n")
    folder = report / "release"
    folder.mkdir()
    command = [str(engine), "--headless", "--path", str(project), "--log-file", str(folder / "engine.log"), "--script", "res://tests/terrain_block_contract.gd"]
    result = execute(command, folder, 120, "TERRAIN_BLOCK_CONTRACT checks=")
    results.append({"test": "terrain_block_contract_release", "command": command, "native_sha256": hashes, **result})
    print(("PASS " if result["passed"] else "FAIL ") + "release contract", flush=True)
    folder = report / "expansion_release"
    folder.mkdir()
    command = [str(engine), "--headless", "--path", str(project), "--log-file", str(folder / "engine.log"), "--script", "res://tests/building_expansion.gd"]
    result = execute(command, folder, 120, "BUILDING_EXPANSION checks=")
    results.append({"test": "building_expansion_release", "command": command, "native_sha256": hashes, **result})
    print(("PASS " if result["passed"] else "FAIL ") + "expansion release", flush=True)
    passed = all(row["passed"] for row in results)
    retention = release_copies({project: copied_libraries}, passed)
    (report / "run.json").write_text(json.dumps({**revision_metadata(), "passed": passed, "results": results, "native_copy_retention": retention}, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if passed else "FAIL ") + str(report))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
