#!/usr/bin/env python3
"""Optional native rebuild. Python standard library only. Requires an existing C++ toolchain.
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
    work = ROOT / ".build"
    work.mkdir(exist_ok=True)
    (ROOT / "bin").mkdir(exist_ok=True)
    compiler = args.compiler or shutil.which("clang++") or shutil.which("g++")
    if not compiler:
        raise RuntimeError("No C++ compiler found; no installation was attempted")
    core = str(ROOT / "native/core.cpp")
    bridge = str(ROOT / "native/godot_bridge.cpp")
    flags = ["-O2", "-std=c++17", "-fno-math-errno", "-ffp-contract=off"]
    if args.target == "windows":
        linker = shutil.which("lld-link")
        if not linker or "clang" not in Path(compiler).name.lower():
            raise RuntimeError("The standalone Windows target requires clang++ and lld-link in PATH")
        flags += ["--target=x86_64-pc-windows-msvc", "-fno-exceptions", "-fno-rtti", "-fno-stack-protector", "-fno-builtin"]
        objects = []
        for source in (core, bridge):
            obj = str(work / (Path(source).stem + ".win.obj"))
            run([compiler, *flags, "-c", source, "-o", obj])
            objects.append(obj)
        run([linker, "/dll", "/noentry", "/nodefaultlib", "/machine:x64", "/opt:ref", "/opt:icf", "/out:" + str(ROOT / "bin/terrain_core.windows.x86_64.dll"), *objects])
    elif args.target == "linux":
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
