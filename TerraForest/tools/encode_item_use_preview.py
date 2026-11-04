# SPDX-License-Identifier: 0BSD
"""Encode the reviewed generic-item fixture frames and retain provenance."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FRAMES = ROOT/'reports/item_use/frames'
OUT = ROOT/'docs/evidence/item_use'
source = ROOT/'addons/characters/authoring'
frames = sorted(FRAMES.glob('*.png'))
assert [p.name for p in frames] == [f'{i:03}.png' for i in range(288)], 'Expected 288 frames at 30 fps'
dependencies = [source/'Human.item_use.res', ROOT/'tools/preview_item_use.gd']
assert min(p.stat().st_mtime for p in frames) >= max(p.stat().st_mtime for p in dependencies), 'Re-render stale frames'
checks_path = ROOT/'reports/item_use/checks.json'
checks = json.loads(checks_path.read_text())
assert checks['failures'] == 0, 'Resolve candidate checks before retaining review evidence'
assert checks_path.stat().st_mtime >= max((source/'Human.item_use.res').stat().st_mtime, (ROOT/'tests/item_use_candidate.gd').stat().st_mtime), 'Re-run stale candidate checks'
OUT.mkdir(parents=True, exist_ok=True)
ffmpeg = shutil.which('ffmpeg')
assert ffmpeg, 'Use the existing external FFmpeg installation'
subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '30',
                '-i', str(FRAMES/'%03d.png'), '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p',
                '-movflags', '+faststart', str(OUT/'Generic-item.preview.mp4')], check=True)
subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '30',
                '-i', str(FRAMES/'%03d.png'), '-filter_complex',
                'fps=15,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3',
                '-loop', '0', str(OUT/'Generic-item.preview.gif')], check=True)
for frame, name in [(25, 'book-hold'), (55, 'book-use'), (121, 'bread-hold'),
                    (151, 'bread-use'), (217, 'object-hold'), (247, 'object-use')]:
    shutil.copyfile(ROOT/f'reports/item_use/pose_{frame:03}.png', OUT/(name+'.png'))
shutil.copyfile(checks_path, OUT/'checks.json')
shutil.copyfile(ROOT/'reports/item_use/import.json', OUT/'import.json')
files = [ROOT/p for p in ['tools/author_item_use.py', 'tools/import_item_use.gd', 'tools/preview_item_use.gd',
                         'tools/encode_item_use_preview.py', 'tests/item_use_candidate.gd',
                         'addons/player_runtime/art/consumables/214.res', 'addons/player_runtime/art/consumables/218.res',
                         'addons/player_runtime/art/consumables/provenance.json']]
files += list(source.glob('Human.item_use.*'))
files += [p for p in OUT.iterdir() if p.suffix in ['.png', '.mp4', '.gif'] or p.name in ['checks.json', 'import.json']]
manifest = {'status': 'Candidate 01; player approval pending; no gameplay integration',
            'capture': 'Godot 4.7.2 Forward+ on RTX 4050; neutral controlled stage; no world or saved-player state',
            'cameras': '75-degree first-person FOV at 16:9; side/front body view and tracking underside grip camera',
            'timing': '288 frames at 30 fps / 9.6 seconds: book 0-3.2 s, bread 3.2-6.4 s, neutral object 6.4-9.6 s; each equips, holds, uses and returns at 1x speed',
            'mount': 'One RightHand attachment; actual authored underside fitted once per mesh against the fixed cradle skin samples; no per-frame IK or fitting',
            'scope': 'Original CC0 motion and neutral box; existing CC0 book/bread meshes with retained provenance; no new external assets',
            'limits': 'Closed book and whole loaf; generic lift/inspect gesture, no page turning, biting, object removal, rewards or inventory mutation',
            'sha256': {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}}
(OUT/'evidence.json').write_text(json.dumps(manifest, indent=2)+'\n')
print('ITEM_USE_ENCODED', len(frames), 'frames; approval pending')
