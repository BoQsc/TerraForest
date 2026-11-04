# SPDX-License-Identifier: 0BSD
"""Encode the reviewed generic-item fixture frames and retain provenance."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FRAMES = ROOT/'reports/item_use_v2/frames'
OUT = ROOT/'docs/evidence/item_use/revision02'
source = ROOT/'addons/characters/authoring'
frames = sorted(FRAMES.glob('*.png'))
assert [p.name for p in frames] == [f'{i:03}.png' for i in range(342)], 'Expected 342 frames at 30 fps'
dependencies = [source/'Human.item_use_v2.res', ROOT/'tools/preview_item_use_v2.gd']
assert min(p.stat().st_mtime for p in frames) >= max(p.stat().st_mtime for p in dependencies), 'Re-render stale frames'
checks_path = ROOT/'reports/item_use_v2/checks.json'
checks = json.loads(checks_path.read_text())
assert checks['failures'] == 0, 'Resolve candidate checks before retaining review evidence'
assert checks_path.stat().st_mtime >= max((source/'Human.item_use_v2.res').stat().st_mtime, (ROOT/'tests/item_use_v2_candidate.gd').stat().st_mtime), 'Re-run stale candidate checks'
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
for frame, name in [(25, 'book-hold'), (55, 'book-use'), (139, 'bread-hold'),
                    (169, 'bread-use'), (253, 'object-hold'), (283, 'object-use')]:
    shutil.copyfile(ROOT/f'reports/item_use_v2/pose_{frame:03}.png', OUT/(name+'.png'))
shutil.copyfile(checks_path, OUT/'checks.json')
shutil.copyfile(ROOT/'reports/item_use_v2/import.json', OUT/'import.json')
for name, output in [('item_use_v2_contact_failure', 'contact-failure'),
                     ('item_use_v2_expanded_contact_failure', 'expanded-contact-failure'),
                     ('item_use_v2_curl_failure', 'curl-failure'), ('item_use_v2_check', 'candidate-check')]:
    shutil.copyfile(ROOT/('reports/'+name+'.log'), OUT/(output+'.log'))
files = [ROOT/p for p in ['tools/author_item_use_v2.py', 'tools/import_item_use_v2.gd', 'tools/preview_item_use_v2.gd',
                         'tools/encode_item_use_v2_preview.py', 'tests/item_use_v2_candidate.gd',
                         'addons/player_runtime/art/consumables/214.res', 'addons/player_runtime/art/consumables/218.res',
                         'addons/player_runtime/art/consumables/provenance.json']]
files += [ROOT/'addons/characters/runtime/assets/Human.item_hold.res', source/'Human.item_use.res']
files += list(source.glob('Human.item_use_v2.*'))
files += [p for p in OUT.iterdir() if p.suffix in ['.png', '.mp4', '.gif', '.log'] or p.name in ['checks.json', 'import.json']]
manifest = {'status': 'Revision 02; player approval pending; integrated runtime retains candidate 01',
            'capture': 'Godot 4.7.2 Forward+ on RTX 4050; neutral controlled stage; no world or saved-player state',
            'cameras': '75-degree first-person FOV at 16:9; side/front body view and tracking underside grip camera',
            'timing': '342 frames at 30 fps / 11.4 seconds: book 0-3.8 s, bread 3.8-7.6 s, neutral object 7.6-11.4 s; each equips, holds, uses and returns at 1x speed',
            'mount': 'One RightHand attachment; actual authored underside fitted once per mesh against the articulated hand skin envelope; no per-frame IK or fitting',
            'scope': 'Original CC0 motion and neutral box; existing CC0 book/bread meshes with retained provenance; no new external assets',
            'limits': 'Closed book and whole loaf; generic lift/inspect gesture, no page turning, biting, object removal, rewards or inventory mutation',
            'sha256': {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}}
(OUT/'evidence.json').write_text(json.dumps(manifest, indent=2)+'\n')
print('ITEM_USE_V2_ENCODED', len(frames), 'frames; approval pending')
