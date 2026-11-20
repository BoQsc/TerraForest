# SPDX-License-Identifier: 0BSD
"""Summarize a completed packaged route from the retained raw frame measurements."""
import argparse
from array import array
import json
import math
from pathlib import Path
import sys


def summarize(folder):
    description = json.loads((folder/"qualification_frames.json").read_text())
    run = json.loads((folder/"run.json").read_text())
    columns = description["columns"]
    count = description["frames"]
    path = folder/"qualification_frames.bin"
    if description["overflow"] or not 0 < count <= 36000 or path.stat().st_size != 8*len(columns)*count:
        raise ValueError("Incomplete frame record")
    samples = array("d")
    with path.open("rb") as source:
        samples.fromfile(source, count*len(columns))
    if sys.byteorder!="little":
        samples.byteswap()
    indices = [columns.index(k) for k in ("phase","interval_us","viewport_cpu_ms","viewport_gpu_ms","queued")]
    series = {}
    streaks = {}
    previous = None
    streak = 0
    for offset in range(0,len(samples),len(columns)):
        phase, interval, cpu, gpu, queue = (samples[offset+i] for i in indices)
        key = description["phases"][int(phase)]
        if key != previous:
            streak = 0
        streak = streak + 1 if interval > 1_000_000 / 60 else 0
        streaks[key] = max(streaks.get(key, 0), streak)
        previous = key
        series.setdefault(key,[]).append((interval/1000,cpu,gpu,queue))
    phases = {}
    for key,rows in series.items():
        interval,cpu,gpu,queues = zip(*rows)
        index = math.ceil(.99*len(rows))-1
        phases[key] = dict(frames=len(rows), p99_frame_ms=sorted(interval)[index],
                           max_frame_ms=max(interval), intervals_above_budget=sum(t>1000/60 for t in interval),
                           longest_above_budget=streaks[key], viewport_cpu_p99_ms=sorted(cpu)[index],
                           viewport_gpu_p99_ms=sorted(gpu)[index], max_terrain_queue=max(queues))
    return dict(source_sha256=description["source_sha256"], pack_sha256=run.get("pack_sha256"),
                completed_checks=run.get("result",{}).get("passed"), driver_sha256=run.get("test_sha256"),
                scope=description["scope"], refresh_hz=description["monitor_hz"], phases=phases)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run",type=Path)
    print(json.dumps(summarize(parser.parse_args().run),indent=2))
