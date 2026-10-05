"""Report bright text-pixel retention in fixed-layout diagnostic PNGs.

Requires Pillow and NumPy. This is evidence analysis, not a font correctness or
FPS test. Bright changing backgrounds can invalidate this mask-based comparison.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/evidence'
REFERENCE = EVIDENCE / 'transparent_text/before.png'
REGIONS = {
    'help': ((0, 995, 1920, 1080), 210),
    'title': ((40, 65, 270, 110), 230),
}


def mask(path, box, threshold):
    with Image.open(path) as image:
        pixels = np.asarray(image.convert('RGB').crop(box))
    return np.min(pixels, axis=2) > threshold


def main():
    paths = [EVIDENCE / 'natural_harvest/native_flush' / name for name in
             ['after_settled.png', 'after_redraw.png']]
    paths += [EVIDENCE / 'transparent_text/after_settled.png']
    results = []
    for path in paths:
        row = {'image': str(path.relative_to(EVIDENCE)), 'regions': {}}
        for name, (box, threshold) in REGIONS.items():
            reference = mask(REFERENCE, box, threshold)
            current = mask(path, box, threshold)
            row['regions'][name] = {
                'threshold': threshold,
                'reference_bright_pixels': int(reference.sum()),
                'missing_reference_pixels': int((reference & ~current).sum()),
                'additional_bright_pixels': int((~reference & current).sum()),
            }
        results.append(row)
    strips = sorted((EVIDENCE / 'transparent_text').glob('help_*.png'))
    if not strips:
        raise RuntimeError('Run natural_harvest_visual.gd --transparent-text-probe first')
    first = mask(strips[0], (0, 0, 1920, 85), 210)
    report = {
        'reference': str(REFERENCE.relative_to(EVIDENCE)),
        'comparison': results,
        'transparent_help_samples': len(strips),
        'changed_bright_masks_after_first_sample': sum(
            not np.array_equal(first, mask(path, (0, 0, 1920, 85), 210))
            for path in strips[1:]),
        'limitation': 'Masks measure bright pixel retention, not complete glyph correctness; no timing or FPS claim.',
    }
    output = EVIDENCE / 'transparent_text/pixel_comparison.json'
    output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
