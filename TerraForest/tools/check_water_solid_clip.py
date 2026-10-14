# SPDX-License-Identifier: 0BSD
"""Bounded native geometry check for building-water replacement."""
import subprocess
from bootstrap_native import ROOT, bootstrap
info=bootstrap(); folder=ROOT/'.build/water_solid_clip'; folder.mkdir(parents=True,exist_ok=True)
exe=folder/'probe.exe'
command=[info['zig'],'c++','-std=c++17','-O2','-ffp-contract=off',str(ROOT/'tests/native/water_solid_clip_probe.cpp'),'-o',str(exe)]
build=subprocess.run(command,capture_output=True,text=True)
(folder/'compile.log').write_text(build.stdout+build.stderr)
if build.returncode: print(build.stdout+build.stderr); raise SystemExit(build.returncode)
run=subprocess.run([str(exe)],capture_output=True,text=True,timeout=10)
(ROOT/'reports').mkdir(exist_ok=True)
(ROOT/'reports/water_solid_clip.log').write_text(run.stdout+run.stderr)
print(run.stdout+run.stderr)
raise SystemExit(run.returncode)
