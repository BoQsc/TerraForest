# SPDX-License-Identifier: 0BSD
"""Encode the sampled Godot candidate review and retain exact artifact hashes."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FRAMES = ROOT / 'reports/torch_attack/frames'
OUT = ROOT / 'docs/evidence/torch_attack'
ASSET = ROOT / 'addons/characters/authoring/Human.torch_attack.res'
frames = sorted(FRAMES.glob('*.png'))
assert [p.name for p in frames] == [f'{i:03}.png' for i in range(234)], 'Expected 234 frames at 30 Hz'
newest = max(p.stat().st_mtime for p in [ASSET, ROOT / 'tools/preview_torch_attack.gd'])
assert min(p.stat().st_mtime for p in frames) >= newest, 'Re-render stale preview frames'
checks = json.loads((ROOT / 'reports/torch_attack/checks.json').read_text())
assert checks['failures'] == 0, 'Resolve the candidate checks before publishing review evidence'
OUT.mkdir(parents=True, exist_ok=True)
ffmpeg = shutil.which('ffmpeg')
assert ffmpeg, 'Use the existing external FFmpeg installation'
subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '30',
                '-i', str(FRAMES / '%03d.png'), '-c:v', 'libx264', '-crf', '18',
                '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(OUT / 'Torch-attack.preview.mp4')], check=True)
subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-framerate', '30',
                '-i', str(FRAMES / '%03d.png'), '-filter_complex',
                'fps=15,scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3',
                '-loop', '0', str(OUT / 'Torch-attack.preview.gif')], check=True)
for source, target in [('pose_000.png', 'ready.png'), ('pose_022.png', 'pullback.png'),
                       ('pose_028.png', 'strike.png'), ('pose_031.png', 'follow-through.png')]:
    shutil.copyfile(ROOT / 'reports/torch_attack' / source, OUT / target)
shutil.copyfile(ROOT / 'reports/torch_attack/checks.json', OUT / 'checks.json')
files = [ROOT / p for p in ['tools/author_torch_attack.py', 'tools/import_torch_attack.gd',
                           'tools/preview_torch_attack.gd', 'tests/torch_attack_candidate.gd']]
files += list((ROOT / 'addons/characters/authoring').glob('Human.torch_attack.*'))
files += [OUT / p for p in ['Torch-attack.preview.mp4', 'Torch-attack.preview.gif',
                           'ready.png', 'pullback.png', 'strike.png', 'follow-through.png', 'checks.json']]
manifest = {'approval': 'Player visual review pending; no gameplay integration',
            'capture': 'Godot 4.7.2 Forward+; NVIDIA RTX 4050; controlled review stage; no world/save',
            'timing': '234 deterministic frames at 30 fps: two 1x swings, then 0.5x swing',
            'first_person': '75 degree FOV, 16:9 viewport, existing runtime Human and torch attachment',
            'limits': 'No target response, damage, fire spread, audio or gameplay acceptance; inherited body/clothing retained',
            'sha256': {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}}
(OUT / 'evidence.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('TORCH_ATTACK_ENCODED', len(frames), 'frames; review remains pending')
