# SPDX-License-Identifier: 0BSD
"""Exercise the release placement query in a clean, temporary project."""
from pathlib import Path
import datetime
import hashlib
import json
import shutil
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
folder = root / "reports/checks" / (stamp + "_placement_release")
folder.mkdir(parents=True)
build = root / ".build"
build.mkdir(exist_ok=True)
library = root / "addons/structures/bin/structures.windows.template_release.x86_64.dll"
test = root / "tests/placement_support.gd"
with tempfile.TemporaryDirectory(prefix="placement_release_", dir=build) as temporary:
    project = Path(temporary).resolve()
    assert project.parent == build.resolve(), "Temporary project must remain under the task build directory"
    addon = project / "addons/structures"
    (addon / "bin").mkdir(parents=True)
    shutil.copy2(library, addon / "bin" / library.name)
    descriptor = (root / "addons/structures/structures.gdextension").read_text()
    (addon / "structures.gdextension").write_text(descriptor.replace("template_debug", "template_release"))
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Placement Release Check"\n')
    shutil.copy2(test, project / test.name)
    command = [str(engine), "--headless", "--path", str(project), "--log-file", str(folder / "engine.log"), "--script", "res://" + test.name]
    details = dict(command=command, scope="Clean temporary project, release DLL only; fixed native support-query assertions.",
                   utc=stamp, engine_sha256=hashlib.sha256(engine.read_bytes()).hexdigest(),
                   library_sha256=hashlib.sha256(library.read_bytes()).hexdigest(),
                   test_sha256=hashlib.sha256(test.read_bytes()).hexdigest(), **revision_metadata())
    manifest = folder / "run.json"
    manifest.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
    details["result"] = execute(command, folder, 45, "PLACEMENT_SUPPORT failures=0")
    manifest.write_text(json.dumps(details, indent=2) + "\n", encoding="utf-8")
print(("PASS " if details["result"]["passed"] else "FAIL ") + str(folder))
raise SystemExit(0 if details["result"]["passed"] else 1)
