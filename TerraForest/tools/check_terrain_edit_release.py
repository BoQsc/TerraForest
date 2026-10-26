"""Exercise the volume/history fixture with only the release terrain DLL available."""
import datetime
import hashlib
import json
import shutil

from run import ROOT, parse_args
from run_godot_check import execute, revision_metadata


def main():
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    report = ROOT / "reports/terrain_edit_release" / stamp
    project = ROOT / ".build" / ("terrain_edit_release_" + stamp)
    report.mkdir(parents=True)
    addon = project / "addons/volumetric_terrain"
    (addon / "bin").mkdir(parents=True)
    source = ROOT / "addons/volumetric_terrain"
    library = source / "bin/terrain_core.windows.template_release.x86_64.dll"
    shutil.copy2(library, addon / "bin" / library.name)
    descriptor = (source / "terrain_core.gdextension").read_text().replace("terrain_core.windows.x86_64.dll", library.name)
    (addon / "terrain_core.gdextension").write_text(descriptor)
    shutil.copy2(source / "mesh_codec.gd", addon / "mesh_codec.gd")
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Terrain Edit Release Check"\n')
    (project / ".godot").mkdir()
    (project / ".godot/extension_list.cfg").write_text("res://addons/volumetric_terrain/terrain_core.gdextension\n")
    (project / "tests").mkdir()
    (project / "reports").mkdir()
    script = ROOT / "tests/terrain_edit_volumes.gd"
    shutil.copy2(script, project / "tests" / script.name)
    command = [str(config.godot), "--headless", "--path", str(project), "--log-file", str(report / "engine.log"),
               "--script", "res://tests/terrain_edit_volumes.gd"]
    result = execute(command, report, 180, "TERRAIN_EDIT_VOLUMES failures=0")
    measurements = project / "reports/terrain_edit_volumes.json"
    if measurements.is_file():
        shutil.copy2(measurements, report / "measurements.json")
    manifest = {**revision_metadata(), "command": command, "result": result,
                "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest(),
                "script_sha256": hashlib.sha256(script.read_bytes()).hexdigest(),
                "scope": "Isolated release-DLL native volumes, meshing and persistence; not exported-game frame performance."}
    (report / "run.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if result["passed"] else "FAIL ") + str(report))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
