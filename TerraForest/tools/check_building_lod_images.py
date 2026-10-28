"""Compare full-detail and automatic-LOD renders from the fixed-camera fixture."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops


def compare(folder):
    rows = []
    for original in sorted(folder.glob('*_full.png')):
        reduced = original.with_name(original.name.replace('_full', '_lod'))
        with Image.open(original) as full, Image.open(reduced) as lod:
            if full.size != (1920, 1080) or lod.size != full.size:
                raise ValueError('Expected equal native 1080p images')
            difference = ImageChops.difference(full.convert('RGB'), lod.convert('RGB'))
            red, green, blue = difference.split()
            maximum = ImageChops.lighter(ImageChops.lighter(red, green), blue)
            histogram = maximum.histogram()
            changed = sum(histogram[1:])
            rows.append(dict(view=original.stem.removesuffix('_full'),
                             changed_pixels=changed,
                             maximum_channel_difference=max(index for index, count in enumerate(histogram) if count),
                             full_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),
                             lod_sha256=hashlib.sha256(reduced.read_bytes()).hexdigest()))
    expected = {'view_0', 'view_1', 'view_2', 'shapes_30', 'shapes_180'} | {f'sweep_{frame:03}' for frame in range(0, 180, 15)}
    passed = {row['view'] for row in rows} == expected and all(row['changed_pixels'] <= 200 for row in rows)
    result = dict(passed=passed, pairs=rows, scope='Matched cameras/materials at 1080p; <=200 changed pixels per frame. Sparse samples complement the 180-frame travel test, not universal visual acceptance.')
    (folder / 'comparison.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    result = compare(parser.parse_args().folder)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['passed'] else 1)
