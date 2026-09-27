#!/usr/bin/env python3
"""Windows delegates to pinned Zig; legacy Linux/tests require an existing C++ toolchain.
Runtime users need no compiler: Windows x86-64 DLL and Linux x86-64 SO are included.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def run(args: list[str]) -> None:
    print(subprocess.list2cmdline(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=["windows", "linux", "tests", "regression", "latency", "acceptance", "release", "bake"])
    parser.add_argument("--compiler", help="clang++ or g++ executable")
    args = parser.parse_args()
    if args.target == "windows":
        subprocess.run([sys.executable, str(ROOT.parents[1] / "tools/build_native.py"),
                        "--addon", "volumetric_terrain", "--target", "all"], check=True)
        return
    work = ROOT / ".build"
    work.mkdir(exist_ok=True)
    (ROOT / "bin").mkdir(exist_ok=True)
    compiler = args.compiler or shutil.which("clang++") or shutil.which("g++")
    if not compiler:
        raise RuntimeError("No C++ compiler found; no installation was attempted")
    core = str(ROOT / "native/core.cpp")
    bridge = str(ROOT / "native/godot_bridge.cpp")
    flags = ["-O2", "-std=c++17", "-fno-math-errno", "-ffp-contract=off"]
    if args.target == "linux":
        run([compiler, *flags, "-fno-exceptions", "-fno-rtti", "-fPIC", "-shared", core, bridge, "-o", str(ROOT / "bin/libterrain_core.linux.x86_64.so")])
    else:
        source = ROOT / {"tests": "tests/native_tests.cpp", "regression": "tests/regression_042.cpp", "latency": "tests/regression_043.cpp", "acceptance": "tests/regression_044.cpp", "release": "tests/regression_045.cpp", "bake": "tools/bake_cache.cpp"}[args.target]
        executable = work / (args.target + (".exe" if sys.platform == "win32" else ""))
        run([compiler, *flags, *(["-pthread"] if args.target == "latency" else []), str(source), core, "-o", str(executable)])
        run([str(executable)] + ([str(ROOT / "base_cache")] if args.target == "bake" else []))

if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print("BUILD FAILED:", error, file=sys.stderr)
        raise SystemExit(2)
