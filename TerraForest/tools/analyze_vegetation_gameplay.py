# SPDX-License-Identifier: 0BSD
"""Bounded gameplay preview and timings, excluding image-readback phases."""
import argparse
import hashlib
import io
import json
import statistics
import struct
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def analyze(folder):
    folder = folder.resolve()
    receipt = json.loads((folder / 'run.json').read_text())
    result = receipt.get('result', {})
    if (not folder.is_relative_to(ROOT / 'reports/checks')
            or 'res://tests/vegetation_gameplay.gd' not in receipt.get('command', [])
            or '--check-evidence-dir=' + str(folder) not in receipt['command']
            or result.get('exit_code') is None
            or result.get('development_storage', {}).get('planned_report_bytes') != 20 * 2**20):
        raise ValueError('Expected completed admitted gameplay receipt')
    report = json.loads((folder / 'vegetation_gameplay.json').read_text())
    measured = [row for row in report['rows'] if row['phase'].startswith('measure_')]
    summary = dict(passed=result['passed'], failures=report['failures'], control=report['opaque_control'],
                   travelled_m=report['travelled_m'], save_sha256=report['save_sha256'], timings={})
    summary['mode']=report.get('mode','opaque' if report['opaque_control'] else 'candidate')
    summary['initial_forest']=report.get('initial_forest',{})
    summary['capture_method']=report.get('capture_method','Synchronous viewport readback')
    if report.get('capture_frame_ids'):
        ids=report['capture_frame_ids']
        summary['consecutive_frame_ids']=len(ids)==48 and all(b==a+1 for a,b in zip(ids,ids[1:]))
        summary['passed'] &= summary['consecutive_frame_ids'] and not report.get('capture_errors')
    witness_path=folder/'interference.json'
    witness=json.loads(witness_path.read_text()) if witness_path.is_file() else None
    # Preflight can wait without starting an engine. Keep that overlap in the
    # witness, but qualify only the actual gameplay interval plus the margin.
    start=result.get('engine_started_unix_s');end=result.get('engine_ended_unix_s')
    observations=witness.get('observations',[]) if witness else []
    gameplay_overlap=[o for o in observations if start and end and start-6<=witness['monitor_started_unix_s']+o['seconds']<=end+6]
    summary['gpu_environment_observation_valid']=bool(witness and start and end and not gameplay_overlap and witness['monitor_error'] is None)
    summary['gameplay_overlap_observed']=bool(gameplay_overlap)
    summary['gpu_environment']=witness
    for phase in sorted({row['phase'] for row in measured}):
        rows = [row for row in measured if row['phase'] == phase][30:]  # settling after a phase boundary
        summary['timings'][phase] = {}
        for key in ['gpu_ms', 'cpu_ms', 'frame_ms', 'draws', 'cover_us', 'batch_us','trees','forest_cells']:
            if not rows or key not in rows[0]:continue
            values = sorted(row[key] for row in rows)
            if values:
                summary['timings'][phase][key] = dict(median=statistics.median(values), p95=values[int((len(values)-1)*.95)])
    packet = folder / 'gameplay.frames'
    if packet.is_file():
        data = packet.read_bytes()
        if not 4 < len(data) <= 16 * 2**20 or struct.unpack_from('<I', data)[0] != 48:
            raise ValueError('Invalid gameplay packet')
        frames = []
        offset = 4
        faithful=len(report.get('capture_rgb_sha256',[]))==48
        for index in range(48):
            length, = struct.unpack_from('<I', data, offset)
            offset += 4
            if not 0 < length <= len(data) - offset:
                raise ValueError('Invalid gameplay frame')
            with Image.open(io.BytesIO(data[offset:offset+length])) as frame:
                if frame.size != (640, 240):
                    raise ValueError('Unexpected gameplay crop')
                if faithful and hashlib.sha256(frame.convert('RGB').tobytes()).hexdigest()!=report['capture_rgb_sha256'][index]:
                    raise ValueError('Gameplay capture pixels changed during encoding or decoding')
                frames.append(frame.convert('RGB').crop((160,8,480,136)))
            offset += length
        if offset != len(data):
            raise ValueError('Trailing gameplay bytes')
        buffer = io.BytesIO()
        times = report.get('capture_times_ms', [])
        durations = [b-a for a,b in zip(times,times[1:])] if len(times) == 48 else [100]*47
        durations.append(int(statistics.median(durations)))
        frames[0].save(buffer, format='WEBP', save_all=True, append_images=frames[1:],
                       duration=durations, loop=0, lossless=True, method=4)
        preview = buffer.getvalue()
        if len(preview) > 3 * 2**20:
            raise ValueError('Preview exceeds admitted 3 MiB')
        (folder / 'motion.webp').write_bytes(preview)
        summary['capture_stride']=report.get('capture_stride',6)
        summary['capture_pixels_verified']=faithful
        summary['capture_interval_ms']=dict(median=statistics.median(durations),p95=sorted(durations)[int((len(durations)-1)*.95)])
        summary['preview'] = f"Native 320x128 far-hillside crop, 48 frames, rendered-frame stride {summary['capture_stride']}; recorded capture intervals (legacy packets use nominal 10 fps). {summary['capture_method']} Physics/actors/streaming active. Full 640x240 frames remain in packet. Readback is excluded from GPU timing phases."
    (folder / 'analysis.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    analyze(parser.parse_args().folder)
