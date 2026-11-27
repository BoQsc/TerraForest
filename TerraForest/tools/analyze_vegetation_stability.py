# SPDX-License-Identifier: 0BSD
"""Create bounded, lossless before/after motion previews from an owned check."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def frames(path):
    data = path.read_bytes()
    if len(data) > 5 * 2**20 or len(data) < 4:
        raise ValueError('Invalid bounded motion packet')
    count, = struct.unpack_from('<I', data)
    if not 1 <= count <= 30:
        raise ValueError('Invalid frame count')
    offset, result = 4, []
    for _ in range(count):
        size, = struct.unpack_from('<I', data, offset)
        offset += 4
        if not 0 < size <= len(data) - offset:
            raise ValueError('Invalid frame payload')
        with Image.open(io.BytesIO(data[offset:offset+size])) as frame:
            if frame.size != (320, 96):
                raise ValueError('Unexpected crop dimensions')
            result.append(frame.convert('RGB'))
        offset += size
    if offset != len(data):
        raise ValueError('Trailing motion payload')
    return result


def analyze(folder):
    folder = Path(folder).resolve()
    if not folder.is_relative_to((ROOT/'reports/checks').resolve()):
        raise ValueError('Expected an owned repository check directory')
    run = json.loads((folder/'run.json').read_text(encoding='utf-8'))
    command = run.get('command', [])
    if ('res://tests/vegetation_stability.gd' not in command
            or '--check-evidence-dir='+str(folder) not in command
            or run.get('result', {}).get('exit_code') is None
            or run['result'].get('development_storage', {}).get('planned_report_bytes') != 16*2**20):
        raise ValueError('Expected a completed, admitted vegetation-stability receipt')
    report_path = folder/'vegetation_stability.json'
    report = json.loads(report_path.read_text(encoding='utf-8'))
    encoded_bytes = 0
    previews = {}
    for family in ('synthetic', 'world'):
        before, after = folder/(family+'_before.frames'), folder/(family+'_after.frames')
        if not before.is_file() and not after.is_file():
            continue
        old_frames, new_frames = frames(before), frames(after)
        if len(old_frames) != len(new_frames):
            raise ValueError('Unmatched motion frames')
        comparisons = []
        for old, new in zip(old_frames, new_frames):
            comparison = Image.new('RGB', (644, 96))
            comparison.paste(old, (0, 0))
            comparison.paste(new, (324, 0))
            comparisons.append(comparison)
        buffer = io.BytesIO()
        comparisons[0].save(buffer, format='WEBP', save_all=True, append_images=comparisons[1:],
                            duration=67, loop=0, lossless=True, method=4)
        encoded = buffer.getvalue()
        encoded_bytes += len(encoded)
        if encoded_bytes > 6*2**20:
            raise ValueError('Previews exceed the admitted 6 MiB ceiling')
        output = folder/(family+'_motion.webp')
        output.write_bytes(encoded)
        previews[family] = dict(file=output.name, frames=len(comparisons), duration_ms=67,
                                sha256=hashlib.sha256(encoded).hexdigest(), bytes=len(encoded),
                                source_sha256=[hashlib.sha256(p.read_bytes()).hexdigest() for p in (before, after)],
                                caption='Left: pre-trial shader. Right: stability trial. Matched camera/time; 1:1 lossless 320x96 distant-band crops at 15 fps. No interpolation or rescaling.')
    report['previews'] = previews
    report_path.write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    summary = {family: {key: report[family][key] for key in (
        'far_residual_ratio', 'worst_gpu_p95_increment_ms', 'noise_pass', 'cost_pass')}
        for family in ('synthetic', 'world') if family in report}
    print(json.dumps(dict(checks=report['checks'], failures=report['failures'], comparisons=summary,
                          preview_bytes=encoded_bytes, folder=str(folder)), indent=2))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    analyze(parser.parse_args().folder)
