# SPDX-License-Identifier: 0BSD
"""Run the short populated main-world paging route and retain scoped evidence."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT = r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT_EXE", DEFAULT))
    args = parser.parse_args()
    engine = Path(args.godot)
    if not engine.is_file():
        parser.error("Supply an existing engine executable with --godot")
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    source = ROOT / "reports/model_world_route"
    output = source / stamp
    output.mkdir(parents=True)
    slot = "model_route_" + str(time.time_ns())
    command = [str(engine), "--path", str(ROOT), "--rendering-method", "forward_plus",
               "--fullscreen", "--resolution", "1920x1080", "--max-fps", "60",
               "--script", "res://tests/model_world_route.gd", "--",
               "--world-slot=" + slot, "--model-region-paging", "--max-fps=60"]
    paths = ["tests/model_world_route.gd", "demo/world.gd",
             "addons/structures/model_paging_coordinator.gd",
             "addons/structures/bin/structures.windows.template_debug.x86_64.dll",
             "addons/volumetric_terrain/bin/terrain_core.windows.x86_64.dll"]
    provenance = {"utc": stamp, "slot": slot, "command": command,
                  "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                  "sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    started = time.time_ns()
    with (output / "godot.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180)
    report = source / "result.json"
    if not report.exists() or report.stat().st_mtime_ns < started:
        raise RuntimeError(f"No fresh report; inspect {output / 'godot.log'}")
    data = json.loads(report.read_text())
    if data["slot"] != slot:
        raise RuntimeError("Report does not belong to this isolated test slot")
    shutil.copy2(report, output / report.name)
    for phase in data["route"]:
        image = source / (phase["phase"] + ".png")
        if not image.exists() or image.stat().st_mtime_ns < started:
            raise RuntimeError("Missing fresh screenshot: " + str(image))
        shutil.copy2(image, output / image.name)
    errors = re.search(r"(?m)^(?:SCRIPT ERROR|ERROR:|WARNING: ObjectDB instances leaked)",
                       (output / "godot.log").read_text(encoding="utf-8"))
    print(output)
    return 1 if result.returncode or data["failures"] or errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
