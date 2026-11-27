# SPDX-License-Identifier: 0BSD
"""Bounded, receipt-owned motion evidence; metrics do not imply visual acceptance."""
import argparse
import hashlib
import io
import json
import statistics
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

ROOT = Path(__file__).resolve().parents[1]


def frames(path):
    data = path.read_bytes()
    if not 4 <= len(data) <= 16 * 2**20:
        raise ValueError('Invalid bounded frame packet')
    count, = struct.unpack_from('<I', data)
    if count != 32:
        raise ValueError('Expected 32 matched frames')
    offset, result = 4, []
    for _ in range(count):
        size, = struct.unpack_from('<I', data, offset)
        offset += 4
        if not 0 < size <= len(data) - offset:
            raise ValueError('Invalid frame payload')
        with Image.open(io.BytesIO(data[offset:offset+size])) as frame:
            if frame.size != (640, 160):
                raise ValueError('Unexpected motion crop')
            result.append(frame.convert('RGB'))
        offset += size
    if offset != len(data):
        raise ValueError('Trailing frame bytes')
    return result


def luminance(image):
    return [(r*.2126+g*.7152+b*.0722)/255 for r, g, b in image.convert('RGB').get_flattened_data()]


def analyze(folder):
    folder = folder.resolve()
    if not folder.is_relative_to(ROOT/'reports/checks'):
        raise ValueError('Expected repository check directory')
    receipt = json.loads((folder/'run.json').read_text())
    command = receipt.get('command', [])
    result = receipt.get('result', {})
    if ('res://tests/vegetation_reconstruction.gd' not in command
            or '--check-evidence-dir='+str(folder) not in command
            or result.get('exit_code') is None
            or result.get('development_storage', {}).get('planned_report_bytes') != 20*2**20):
        raise ValueError('Expected completed admitted reconstruction receipt')
    report = json.loads((folder/'vegetation_reconstruction.json').read_text())
    analysis = dict(run_passed=result['passed'], checks=report['checks'], failures=report['failures'],
                    resource_checks=result['resources']['checks'], timing_groups=[],
                    scope='Descriptive local-contrast and frame-difference metrics. They include real motion, occlusion, stones and lighting; not pure aliasing or visual acceptance. Global brightness averages cannot qualify isolated artifacts.')
    for row in report['world']['timings']:
        analysis['timing_groups'].append(dict(group=row['group'], mode=row['mode'],
            gpu_median_ms=statistics.median(row['gpu_ms']), gpu_p95_ms=sorted(row['gpu_ms'])[60],
            cpu_median_ms=statistics.median(row['cpu_ms']),
            draw_calls=statistics.median(row['draw_calls']), engine_video_bytes=statistics.median(row['video_memory'])))
    baseline = Image.open(folder/'attribution_baseline.png').convert('RGB')
    luma = luminance(baseline)
    median = luminance(baseline.filter(ImageFilter.MedianFilter(5)))
    # Inspected hillside tile excludes sky, buildings, large boulders and reticle.
    candidates = [y*960+x for y in range(240, 380) for x in range(590, 950)
                  if luma[y*960+x]-median[y*960+x] > .10 and luma[y*960+x] > .48]
    attribution = dict(local_region=[590, 240, 360, 140], candidate_count=len(candidates),
                       rule='Display luma >0.48 and >0.10 above 5x5 median; removed means one-at-a-time luma reduction >0.05. Counts can overlap.', variants={})
    for path in sorted(folder.glob('attribution_no_*.png')):
        values = luminance(Image.open(path))
        attribution['variants'][path.stem] = dict(removed=sum(luma[i]-values[i] > .05 for i in candidates),
            mean_luma_delta=statistics.mean(luma[i]-values[i] for i in candidates) if candidates else None)
    analysis['bright_point_attribution'] = attribution
    modes = [m for m in ['baseline', 'taa_msaa', 'taa_only', 'early_opaque', 'filtered'] if (folder/(m+'.frames')).exists()]
    if modes:
        decoded = {mode: frames(folder/(mode+'.frames')) for mode in modes}
        motion = {}
        for mode, sequence in decoded.items():
            rows = []
            previous = None
            for frame in sequence:
                lum = luminance(frame); local = luminance(frame.filter(ImageFilter.MedianFilter(3)))
                row = dict(mean_luma=statistics.mean(lum), bright_points=sum(a-b > .10 for a,b in zip(lum,local)),
                           dark_points=sum(b-a > .10 for a,b in zip(lum,local)))
                gray = frame.convert('L')
                if previous is not None:
                    row['screen_difference'] = ImageStat.Stat(ImageChops.difference(gray,previous)).mean[0]/255
                    # Translation compensation only, not ground-truth scene flow.
                    residuals = []
                    for offset in [-1, -.75, -.5, -.25, 0, .25, .5, .75, 1]:
                        moved = previous.transform(previous.size, Image.Transform.AFFINE, (1,0,offset,0,1,0), Image.Resampling.BILINEAR)
                        residuals.append(ImageStat.Stat(ImageChops.difference(gray,moved).crop((2,2,638,158))).mean[0]/255)
                    row['best_horizontal_residual'] = min(residuals)
                previous = gray
                rows.append(row)
            motion[mode] = {key: statistics.mean(row[key] for row in rows if key in row) for key in rows[-1]}
        analysis['motion'] = motion
        route = (folder/'baseline_route.frames').is_file() and (folder/'filtered_route.frames').is_file()
        total_preview_bytes = 0
        configurations = [('preview', 'motion.webp', ['baseline','filtered'] if route else modes, decoded, 33)]
        if route:
            route_frames = {mode:frames(folder/(mode+'_route.frames')) for mode in ['baseline','filtered']}
            configurations.append(('route_preview','route.webp',['baseline','filtered'],route_frames,133))
        for key, name, preview_modes, preview_frames, duration in configurations:
            panels = []
            for i in range(32):
                panel = Image.new('RGB', (256,120*len(preview_modes)))
                for row,mode in enumerate(preview_modes):
                    panel.paste(preview_frames[mode][i].crop((192,32,448,128)),(0,row*120+24))
                    ImageDraw.Draw(panel).text((8,row*120+5),mode,fill='white')
                panels.append(panel)
            buffer = io.BytesIO()
            panels[0].save(buffer,format='WEBP',save_all=True,append_images=panels[1:],duration=duration,loop=0,lossless=True,method=4)
            data = buffer.getvalue()
            total_preview_bytes += len(data)
            if total_preview_bytes > 3*2**20:
                raise ValueError('Previews exceed admitted 3 MiB budget')
            (folder/name).write_bytes(data)
            analysis[key] = dict(file=name,sha256=hashlib.sha256(data).hexdigest(),bytes=len(data),
                caption='Top-to-bottom: '+', '.join(preview_modes)+'. Central 256x96 portion of matched 640x160 crops; 1:1 lossless, no rescaling. '+('25.5m forward and 11.5-degree turn, captured every eighth rendered frame at 60Hz; actors/streaming paused.' if duration==133 else '1.6m sideways, 30fps.')+' Full frames retained in packets.')
    (folder/'analysis.json').write_text(json.dumps(analysis,indent=2)+'\n')
    print(json.dumps({key:analysis[key] for key in ['run_passed','bright_point_attribution','motion'] if key in analysis},indent=2))
    return analysis


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder',type=Path)
    analyze(parser.parse_args().folder)
