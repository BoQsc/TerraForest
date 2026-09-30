"""Reject false tangent hits and skipped close roots against independent higher-precision oracles."""
import hashlib,json,os,subprocess
from decimal import Decimal,localcontext
from pathlib import Path
from bootstrap_native import ROOT,CACHE,bootstrap
toolchain=bootstrap();folder=ROOT/'.build/ray_numerics';folder.mkdir(exist_ok=True)
source=ROOT/'tests/native/terrain_ray_numerics_probe.cpp';header=ROOT/'addons/volumetric_terrain/native/experimental/density_ray.hpp';exe=folder/'probe.exe'
command=[toolchain['zig'],'c++','-target','x86_64-windows-gnu','-std=c++17','-O2','-fno-exceptions','-ffp-contract=off','-I',str(header.parent.parent),str(source),'-o',str(exe)]
env=os.environ.copy();env['ZIG_GLOBAL_CACHE_DIR']=str(CACHE/'zig-global-cache');env['ZIG_LOCAL_CACHE_DIR']=str(ROOT/'.build/zig-local-cache')
subprocess.run(command,check=True,env=env,timeout=120)
run=subprocess.run([str(exe)],check=True,capture_output=True,text=True,timeout=30)
rows=[json.loads(line) for line in run.stdout.splitlines()];assert len(rows)==67
def reference_root(values):
    with localcontext() as context:
        context.prec=80
        c=[Decimal.from_float(float(v)) for v in values]
        def evaluate(t):return ((c[3]*t+c[2])*t+c[1])*t+c[0]
        a,b,d=3*c[3],2*c[2],c[1];disc=b*b-4*a*d
        cuts=[Decimal(0),Decimal(1)]
        if disc>=0:
            cuts.extend(t for t in [(-b-disc.sqrt())/(2*a),(-b+disc.sqrt())/(2*a)] if 0<t<1)
        cuts.sort()
        # Reference tolerance is far below the smallest perturbation in this suite.
        tolerance=max(abs(v) for v in c)*Decimal('1e-65')
        for i,lo in enumerate(cuts):
            fl=evaluate(lo)
            if abs(fl)<tolerance:return float(lo)
            if i+1==len(cuts):break
            hi=cuts[i+1];fh=evaluate(hi)
            if (fl<0)==(fh<0):continue
            for _ in range(230):
                mid=(lo+hi)/2;fm=evaluate(mid)
                if fm==0:lo=hi=mid;break
                if (fm<0)==(fl<0):lo=mid;fl=fm
                else:hi=mid
            return float((lo+hi)/2)
        return None
for row in rows:
    if row.get('kind')!='cubic':continue
    root=reference_root(row['coefficients'])
    row.update(expected_hit=root is not None,expected_fraction=root,passed=row['hit']==(root is not None) and (root is None or abs(row['fraction']-root)<1e-9))
report=dict(cases=rows,failures=sum(not r['passed'] for r in rows),source_hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,header,Path(__file__).resolve()]},toolchain_lock_sha256=toolchain['lock_sha256'],adoption_qualified=False,scope='33 quadratic and 34 cubic restrictions over three coefficient scales; cubic oracle uses 80-digit Decimal arithmetic on actual input coefficients. No runtime performance qualification.')
(ROOT/'reports/terrain_ray_numerics.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps([r for r in rows if not r['passed']],indent=2));print('Failures:',report['failures'])
raise SystemExit(bool(report['failures']))
