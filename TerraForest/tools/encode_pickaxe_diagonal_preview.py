# SPDX-License-Identifier: 0BSD
"""Blender factory-startup: encode the deterministic first-person review frames."""
import hashlib
import json
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[1]
folder = root/'reports/pickaxe_diagonal'
frames = sorted((folder/'preview_frames').glob('*.png'))
assert len(frames) == 240, 'Capture all 240 review samples first'
scene = bpy.context.scene
scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
scene.render.resolution_percentage, scene.render.fps = 100, 30
scene.frame_start, scene.frame_end = 1, len(frames)
editor = scene.sequence_editor_create()
strip = editor.strips.new_image('Diagonal pickaxe review', str(frames[0]), channel=1, frame_start=1)
for frame in frames[1:]:
    strip.elements.append(frame.name)
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.media_type = 'VIDEO'
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format, scene.render.ffmpeg.codec = 'MPEG4', 'H264'
scene.render.ffmpeg.constant_rate_factor, scene.render.ffmpeg.ffmpeg_preset = 'MEDIUM', 'GOOD'
video = folder/'Human.pickaxe_forward_reduced_twist_v4.mp4'
scene.render.filepath = str(video)
bpy.ops.render.render(animation=True)
(folder/'video.json').write_text(json.dumps({
    'approval': 'PENDING USER VISUAL REVIEW; do not commit',
    'encoder': 'Blender '+bpy.app.version_string, 'fps': 30, 'frames': len(frames),
    'sha256': hashlib.sha256(video.read_bytes()).hexdigest(),
    'revision': 'Reduced left twist: 6-8 degrees at contact, minimal torso turn, forward/right-side strike',
    'scope': 'Actual runtime rig/camera against a fixed studio target. Two normal-speed swings and a half-speed inspection pass; deterministic visual review, not live input, collision or performance evidence.'
}, indent=2))
print('PICKAXE_DIAGONAL_VIDEO', video)
