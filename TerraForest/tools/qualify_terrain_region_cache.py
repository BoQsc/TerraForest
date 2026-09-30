"""Reject unsafe adoption of the experimental cache using retained matched samples.

This is a necessary native component gate, never a substitute for the integrated
1920x1080 workload. Exit 1 means the experiment must remain disabled by default.
"""
from pathlib import Path
import argparse
import json
import statistics

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--report', type=Path, default=ROOT/'reports/terrain_region_cache_release.json')
args = parser.parse_args()
report = json.loads(args.report.read_text())
samples = report['samples']
checks = []


def gate(name, passed, observed, requirement):
    checks.append(dict(name=name, passed=bool(passed), observed=observed, requirement=requirement))


gate('correctness workload', report['failures'] == 0 and report['checks'] >= 293,
     dict(checks=report['checks'], failures=report['failures']), 'at least 293 checks, zero failures')
gate('replay changes real terrain', report['replayed'] == 2176 and report['replay_changed'] >= 0.9*2176,
     report['replay_changed'], 'at least 90% of 2176 commands change terrain')
cached = [r['total_ms'] for r in samples if r['op'] == 20]
# Native work alone exceeding the entire edit budget cannot pass end-to-end.
worst = max(cached, default=float('inf'))
gate('native component fits whole edit budget', worst <= 150, worst, 'every observed cached build <=150 ms')
for state, required in [('cold', 1), ('thrashing_64KiB', 3)]:
    by_op = {op: {r['iteration']: r['total_ms'] for r in samples
                  if r['state'] == state and r['op'] == op} for op in (1, 20)}
    complete = len(by_op[1]) >= required and by_op[1].keys() == by_op[20].keys()
    ratio = statistics.mean(by_op[20].values())/statistics.mean(by_op[1].values()) if complete else None
    gate(state+' regression', complete and ratio <= 1.05, ratio,
         f'>={required} matched pairs; cached mean <=1.05x uncached mean (provisional adoption gate)')
result = dict(qualified=all(c['passed'] for c in checks), checks=checks,
              source_report=str(args.report.resolve()),
              scope='Necessary experimental adoption gates only. Passing does not qualify integrated performance or endurance.')
destination = ROOT/'reports/terrain_region_qualification.json'
destination.write_text(json.dumps(result, indent=2)+'\n')
for check in checks:
    print(('PASS ' if check['passed'] else 'REJECT ')+check['name']+': '+str(check['observed']))
print('QUALIFIED' if result['qualified'] else 'REJECTED: keep reconstruction cache experimental')
raise SystemExit(0 if result['qualified'] else 1)
