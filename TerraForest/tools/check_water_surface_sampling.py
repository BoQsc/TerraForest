# SPDX-License-Identifier: 0BSD
"""Reject direct uniform sampling if it loses finite bucket-sized layers."""
import subprocess
from bootstrap_native import ROOT, bootstrap
info=bootstrap();folder=ROOT/'.build/water_surface_sampling';folder.mkdir(parents=True,exist_ok=True)
exe=folder/'probe.exe'
command=[info['zig'],'c++','-std=c++17','-O2','-Wno-nullability-completeness','-ffp-contract=off',str(ROOT/'tests/native/water_surface_sampling_probe.cpp'),'-o',str(exe)]
build=subprocess.run(command,capture_output=True,text=True)
(folder/'compile.log').write_text(build.stdout+build.stderr)
if build.returncode:print((build.stdout+build.stderr)[-6000:]);raise SystemExit(build.returncode)
run=subprocess.run([str(exe)],capture_output=True,text=True,timeout=10)
(ROOT/'reports').mkdir(exist_ok=True)
(ROOT/'reports/water_surface_sampling.log').write_text(run.stdout+run.stderr)
print(run.stdout+run.stderr)
raise SystemExit(run.returncode)
