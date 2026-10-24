# SPDX-License-Identifier: 0BSD
"""Exercise real rig geometry/physics in a clean project with release DLLs only."""
from pathlib import Path
import datetime
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(root / "tools"))
from run import parse_args
from run_godot_check import execute
from play_checkpoint import revision_metadata

config, _ = parse_args([])
engine = Path(config.godot).resolve()
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
folder = root / "reports/checks" / (stamp + "_zombie_regions_release")
folder.mkdir(parents=True)
build = root / ".build"
build.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="zombie_release_", dir=build) as temporary:
    project = Path(temporary).resolve()
    assert project.parent == build.resolve()
    copied = []
    for addon in ("world_runtime", "player_runtime"):
        destination = project / "addons" / addon
        (destination / "bin").mkdir(parents=True)
        source = root / "addons" / addon
        library = source / "bin" / (addon + ".windows.template_release.x86_64.dll")
        shutil.copy2(library, destination / "bin" / library.name)
        descriptor = (source / (addon + ".gdextension")).read_text().replace("template_debug", "template_release")
        (destination / (addon + ".gdextension")).write_text(descriptor)
        copied.append(library)
    for relative in ("addons/characters/runtime/zombie.gd", "addons/characters/runtime/zombie_world.gd",
                     "addons/characters/runtime/assets/Zombie.r4.glb", "addons/characters/runtime/assets/Zombie.r4.behavior.json",
                     "addons/characters/runtime/assets/Zombie.drag_walk.res", "tests/zombie_combat_regions.gd"):
        source = root / relative
        destination = project / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        copied.append(source)
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Zombie Release Fixture"\n')
    imported = subprocess.run([str(engine), "--headless", "--editor", "--path", str(project), "--import"],
                              capture_output=True, text=True, timeout=90)
    import_log = imported.stdout + "\n" + imported.stderr
    (folder / "import.log").write_text(import_log, encoding="utf-8")
    if imported.returncode or "ERROR:" in import_log:
        print(import_log[-5000:])
        raise SystemExit(1)
    command = [str(engine), "--headless", "--path", str(project), "--log-file", str(folder / "engine.log"),
               "--max-fps", "60", "--script", "res://tests/zombie_combat_regions.gd", "--", "--zombie-combat-dir=" + str(folder / "result")]
    details = dict(command=command, utc=stamp, scope="Clean imported rig project, release world/player DLLs only; real geometry, anatomy and physical corpse/fragment checks.",
                   engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),
                   inputs={str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in copied}, **revision_metadata())
    manifest = folder / "run.json"
    manifest.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
    details["result"] = execute(command, folder, 90, "ZOMBIE_COMBAT_REGIONS checks=39 failures=0")
    manifest.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
print(("PASS " if details["result"]["passed"] else "FAIL ") + str(folder))
raise SystemExit(0 if details["result"]["passed"] else 1)
