# SPDX-License-Identifier: 0BSD
"""Run with Blender --background --factory-startup after preview_human_placement.gd."""
import hashlib
import json
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[1]
folder = root / 'reports/human_placement'
frames = sorted((folder / 'preview_frames').glob('*.png'))
assert len(frames) == 57, 'Capture the complete first-person sequence first'
scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
scene.render.resolution_percentage = 100
scene.render.fps = 30
scene.frame_start, scene.frame_end = 1, len(frames)
editor = scene.sequence_editor_create()
strip = editor.strips.new_image('Runtime relaxed placement', str(frames[0]), channel=1, frame_start=1)
for frame in frames[1:]:
    strip.elements.append(frame.name)
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.media_type = 'VIDEO'
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format = 'MPEG4'
scene.render.ffmpeg.codec = 'H264'
scene.render.ffmpeg.constant_rate_factor = 'MEDIUM'
scene.render.ffmpeg.ffmpeg_preset = 'GOOD'
scene.render.filepath = str(folder / 'Human.placement.mp4')
bpy.ops.render.render(animation=True)
video = folder / 'Human.placement.mp4'
(folder / 'video.json').write_text(json.dumps({'encoder': 'Blender ' + bpy.app.version_string,
    'source': 'Unchanged runtime rig in a matching first-person studio camera; deterministic 30 Hz AnimationPlayer samples, no world UI',
    'frames': len(frames), 'fps': 30, 'sha256': hashlib.sha256(video.read_bytes()).hexdigest()}, indent=2))
print('PLACEMENT_PREVIEW_VIDEO', video)
