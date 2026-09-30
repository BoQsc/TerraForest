"""Test exact-zero lattice merging without replacing the displaced-zero baseline."""
from pathlib import Path
from collections import Counter
import contextlib,hashlib,io,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
# Reuse the independent topology decoder and verify unchanged default behavior.
with contextlib.redirect_stdout(io.StringIO()):
    baseline={"__file__":str(ROOT/'tools/probe_terrain_tetra.py')}
    code=(ROOT/'tools/probe_terrain_tetra.py').read_text().replace('raise SystemExit(bool(result[\'failures\']))','assert not result[\'failures\']')
    exec(compile(code,baseline['__file__'],'exec'),baseline)
folder=ROOT/'.build/exact_zero_probe';folder.mkdir(exist_ok=True)
source=ROOT/'tests/native/terrain_exact_zero_probe.cpp';exe=folder/'probe.exe'
command=baseline['command'].copy()
command[command.index(str(baseline['source']))]=str(source);command[-1]=str(exe)
subprocess.run(command,check=True,env=baseline['env'],timeout=120)
run=subprocess.run([str(exe),str(folder)],capture_output=True,text=True,check=True,timeout=60)
native=[json.loads(line) for line in run.stdout.splitlines()];checks=[];meshes={}
for row in native:
    triangles,stats=baseline['decode'](folder/(row['name']+'.bin'));meshes[row['name']]=triangles
    checks.append(dict(name=row['name'],passed=not any(stats[k] for k in ['zero_area','duplicate_faces','overused_edges','inconsistent_orientation','bad_vertex_links','interior_open_edges']),**stats,collapsed_triangles=row['collapsed_triangles']))
for site,base in [(0,960),(1,1280),(2,1280)]:
    merged=Counter()
    for dz in [0,16]:
        for dx in [0,16]:merged.update(meshes[f'{site}_{base+dx}_{base+dz}_16'])
    whole=meshes[f'{site}_{base}_{base}_32']
    checks.append(dict(name=f'{site} exact partition',passed=whole==merged,missing=sum((whole-merged).values()),extra=sum((merged-whole).values())))
report=dict(checks=checks,failures=sum(not c['passed'] for c in checks),adoption_qualified=False,source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,Path(__file__).resolve(),ROOT/'addons/volumetric_terrain/native/experimental/region_mesher.hpp']},scope='Exact-zero indexed merging experiment; defaults preserved. No normal, material, collider or runtime qualification.')
(ROOT/'reports/terrain_exact_zero.json').write_text(json.dumps(report,indent=2)+'\n')
for check in checks:print(('PASS' if check['passed'] else 'FAIL'),check)
raise SystemExit(bool(report['failures']))
