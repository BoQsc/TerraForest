# SPDX-License-Identifier: 0BSD
"""Inspect fixed-population handoffs from bounded lossless lab packets."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from analyze_vegetation_transitions import frames, delta


def analyze(folder):
    folder = Path(folder)
    receipt = json.loads((folder / 'run.json').read_text())
    if not receipt['result']['passed']:
        raise ValueError('Incomplete/failed engine receipt')
    scenes = {}
    for meta, image in frames(folder / 'transition.frames'):
        scene = scenes.setdefault(meta['scenario'], {})
        sequence = scene.setdefault(meta['case'], [])
        if meta['frame'] != len(sequence):
            raise ValueError('Nonconsecutive frame')
        sequence.append((meta, image))
    report=json.loads((folder / "handoffs.json").read_text())
    shadow_suite=report.get("shadow_suite",False)
    result = {}
    review = []
    for name, scene in scenes.items():
        if scene['source'][0][1].tobytes() != scene['repeat'][0][1].tobytes():
            raise ValueError('Baseline repeat differs')
        count = len(scene['no_cover'])
        if any(len(seq) != (1 if case == 'repeat' else count) for case, seq in scene.items()):
            raise ValueError('Incomplete controls')
        measures = {}
        for case, sequence in scene.items():
            rows = []
            for index, (meta, image) in enumerate(sequence):
                contrast = sum(ImageStat.Stat(ImageChops.difference(image, scene['no_cover'][index][1])).sum)
                row = dict(frame=index, distance=meta['distance_m'], selection=meta['selection'], contrast=contrast)
                if index:
                    row['step'] = delta(image, sequence[index - 1][1])
                    row['contrast_step_percent'] = 100 * (contrast - rows[-1]['contrast']) / max(1, rows[-1]['contrast'])
                rows.append(row)
            measures[case] = rows
        switches = []
        for index, row in enumerate(measures['source'][1:], 1):
            if row['selection'] == measures['source'][index - 1]['selection']:
                continue
            event = dict(frame=index, distance=row['distance'], before=measures['source'][index - 1]['selection'], after=row['selection'])
            event['contrast_step_percent'] = {case: measures[case][index]['contrast_step_percent'] for case in measures if case not in ('repeat', 'no_cover')}
            switches.append(event)
        optimization_equal = all(a[1].tobytes() == b[1].tobytes() for a, b in zip(scene['source'], scene['no_optimization']))
        result[name] = dict(switches=switches, optimization_pixel_equal=optimization_equal, samples=measures)
        if shadow_suite:
            source_casters=[sum(p['casts_shadows'] for p in row[0]['pages']) for row in scene['source']]
            shadow_rows=[]
            for index in range(count):
                off=scene['held_after'][index][1]
                source_shadow=sum(ImageStat.Stat(ImageChops.difference(scene['source'][index][1],off)).sum)
                candidate_shadow=sum(ImageStat.Stat(ImageChops.difference(scene['candidate'][index][1],off)).sum)
                cutoff_difference=delta(scene['candidate'][index][1],scene['candidate_no_cut'][index][1])
                shadow_rows.append(dict(frame=index,source_casters=source_casters[index],source_shadow_contrast=source_shadow,candidate_shadow_contrast=candidate_shadow,cutoff_difference=cutoff_difference))
            exact=all(a[1].tobytes()==b[1].tobytes() for a,b in zip(scene['candidate'],scene['candidate_no_cut']))
            result[name]['shadow_control']=dict(native_cutoff_pixel_equal=exact,rows=shadow_rows,native_cutoff_frames=[i for i in range(1,count) if source_casters[i]!=source_casters[i-1]])
        if switches:
            index = max(switches, key=lambda s: abs(s['contrast_step_percent']['source']))['frame']
            for case in ('source', 'candidate', 'held_after'):
                review.extend([scene[case][index-1][1], scene[case][index][1]])
    encoded = (json.dumps(result, indent=2) + '\n').encode()
    if len(encoded) > 2**20:
        raise ValueError('Analysis cap')
    (folder / 'handoff_analysis.json').write_bytes(encoded)
    if review:
        canvas = Image.new('RGB', (2048, 128 * (len(review) // 2)))
        for index, image in enumerate(review):
            canvas.paste(image, ((index % 2) * 1024, (index // 2) * 128))
        canvas.save(folder / 'handoff_review.png')
    print(json.dumps({name: {k: v for k, v in data.items() if k != 'samples'} for name, data in result.items()}, indent=2))


if __name__ == '__main__':
    analyze(sys.argv[1])
