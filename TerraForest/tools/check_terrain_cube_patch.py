# SPDX-License-Identifier: 0BSD
"""Check bounded exact terrain-cube capture and atomic restoration."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import subprocess

from bootstrap_native import ROOT, CACHE, bootstrap


def main():
    toolchain = bootstrap()
    native = ROOT / "addons/volumetric_terrain/native"
    source = ROOT / "tests/native/terrain_cube_patch_probe.cpp"
    folder = ROOT / "reports/terrain_cube_patch" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    environment = os.environ.copy()
    environment["ZIG_GLOBAL_CACHE_DIR"] = str(CACHE / "zig-global-cache")
    environment["ZIG_LOCAL_CACHE_DIR"] = str(ROOT / ".build/zig-local-cache")
    results = []
    for variant, optimization in (("debug", "-O2"), ("release", "-O3")):
        executable = folder / f"{variant}.exe"
        command = [toolchain["zig"], "c++", "-target", "x86_64-windows-gnu", "-std=c++17",
                   optimization, "-fno-exceptions", "-fno-sanitize=undefined", "-ffp-contract=off",
                   "-DTERRAFOREST_TYPED_BRIDGE", "-I", str(native),
                   str(source), str(native / "core.cpp"), "-o", str(executable)]
        compiled = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=180)
        (folder / f"{variant}-compile.log").write_text(compiled.stdout + compiled.stderr, encoding="utf-8")
        if compiled.returncode:
            raise RuntimeError(f"Native compile failed: {folder / (variant + '-compile.log')}")
        run = subprocess.run([str(executable)], capture_output=True, text=True, timeout=120)
        (folder / f"{variant}.log").write_text(run.stdout + run.stderr, encoding="utf-8")
        checks = [json.loads(line) for line in run.stdout.splitlines()]
        results.append({"variant": variant, "exit_code": run.returncode, "checks": checks,
                        "passed": run.returncode == 0 and len(checks) >= 30 and all(row["passed"] for row in checks)})
    files = [source, Path(__file__), native / "terrain_cube_patch.hpp", *sorted(native.glob("*.h")),
             *sorted(native.glob("*.hpp")), native / "core.cpp"]
    report = {"passed": all(row["passed"] for row in results), "variants": results,
              "scope": "Exact terrain cubes only; no Godot adapter, gameplay quest reset or foreground performance qualification.",
              "source_hashes": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}}
    (folder / "run.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "report": str(folder / "run.json")}), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
