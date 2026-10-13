# SPDX-License-Identifier: 0BSD
"""Check shared surface-cell extraction against the frozen terrain calculation."""
from pathlib import Path
import subprocess
from bootstrap_native import bootstrap, ROOT
info=bootstrap()
folder=ROOT/'.build/surface_cell_reuse';folder.mkdir(parents=True,exist_ok=True)
exe=folder/'probe.exe'
compiled=subprocess.run([info['zig'],'c++','-std=c++17','-O2','-Wno-nullability-completeness','-ffp-contract=off',str(ROOT/'tests/native/surface_cell_reuse_probe.cpp'),'-o',str(exe)],capture_output=True,text=True)
(folder/'compile.log').write_text(compiled.stdout+compiled.stderr)
if compiled.returncode:
 print((compiled.stdout+compiled.stderr)[-6000:]);raise SystemExit(compiled.returncode)
result=subprocess.run([str(exe)],capture_output=True,text=True)
(ROOT/'reports').mkdir(exist_ok=True)
(ROOT/'reports/surface_cell_reuse.log').write_text(result.stdout+result.stderr)
print(result.stdout+result.stderr)
if result.returncode:raise SystemExit(result.returncode)
# Compare complete encoded terrain patches with the pre-refactor source.
native=ROOT/'addons/volumetric_terrain/native'
baseline=folder/'baseline.cpp'
baseline.write_bytes(subprocess.run(['git','show','54cdc87:TerraForest/addons/volumetric_terrain/native/core.cpp'],cwd=ROOT.parent,capture_output=True,check=True).stdout)
outputs=[]
for name,source in [('before',baseline),('after',native/'core.cpp')]:
 target=folder/(name+'.exe')
 command=[info['zig'],'c++','-std=c++17','-O2','-Wno-nullability-completeness','-ffp-contract=off','-I',str(native),str(ROOT/'tests/native/surface_cell_world_probe.cpp'),str(source),'-o',str(target)]
 build=subprocess.run(command,capture_output=True,text=True)
 (folder/(name+'_compile.log')).write_text(build.stdout+build.stderr)
 if build.returncode:print((build.stdout+build.stderr)[-6000:]);raise SystemExit(build.returncode)
 run=subprocess.run([str(target)],capture_output=True,text=True,timeout=30)
 if run.returncode:print(run.stderr);raise SystemExit(run.returncode)
 outputs.append(run.stdout)
if outputs[0]!=outputs[1]:print('FAIL complete terrain patch mismatch');raise SystemExit(1)
with (ROOT/'reports/surface_cell_reuse.log').open('a') as report:
 report.write('PASS 72 generated, edited, cached and restored terrain packets match pre-refactor source\n'+outputs[1])
print('PASS 72 generated, edited, cached and restored terrain packets match pre-refactor source')
