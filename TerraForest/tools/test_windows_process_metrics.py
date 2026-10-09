"""Check CPU counter measurements against a child with known idle/busy phases."""
# SPDX-License-Identifier: 0BSD
import subprocess
import sys
from windows_process_metrics import ProcessMetrics

child = subprocess.Popen([sys.executable, '-u', '-c', '''
import sys,time
print('ready',flush=True)
for line in sys.stdin:
    if line.strip()=='busy':
        end=time.process_time()+.35
        while time.process_time()<end:pass
    else:time.sleep(.35)
    print('done',flush=True)
'''], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
reader = None
try:
    assert child.stdout.readline().strip() == 'ready'
    reader = ProcessMetrics(child.pid)
    reader.sample()
    child.stdin.write('idle\n'); child.stdin.flush(); assert child.stdout.readline().strip() == 'done'
    idle = reader.sample()
    child.stdin.write('busy\n'); child.stdin.flush(); assert child.stdout.readline().strip() == 'done'
    busy = reader.sample()
    assert busy['process_cpu_ms'] >= 250, busy
    assert idle['process_cpu_ms'] < busy['process_cpu_ms']/3, (idle, busy)
    assert 0 <= busy['system_busy_percent'] <= 100 and busy['logical_processors'] > 0
    assert abs(busy['process_machine_percent']*busy['logical_processors']-busy['process_one_core_percent']) < .001
    assert busy['working_set_bytes'] > 0 and busy['private_commit_bytes'] > 0
    print('PASS known CPU work, idle contrast, processor normalization and process memory')
    print({'idle_cpu_ms': idle['process_cpu_ms'], 'busy_cpu_ms': busy['process_cpu_ms'],
           'logical_processors': busy['logical_processors'], 'busy_one_core_percent': busy['process_one_core_percent']})
finally:
    if reader: reader.close()
    child.stdin.close()
    child.wait(timeout=5)
