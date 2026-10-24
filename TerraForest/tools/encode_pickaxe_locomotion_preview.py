# SPDX-License-Identifier: 0BSD
"""Encode the runtime locomotion preview at its sampled 30 FPS."""
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[1]
frames = sorted((root/'reports/pickaxe_locomotion/frames').glob('*.png'))
assert len(frames) == 180
asset_time = (root/'addons/characters/runtime/assets/Human.pickaxe_locomotion.res').stat().st_mtime
assert all(frame.stat().st_mtime >= asset_time for frame in frames)
out = root/'docs/evidence/pickaxe_locomotion'
out.mkdir(parents=True, exist_ok=True)
scene = bpy.context.scene
scene.sequence_editor_clear()
scene.render.resolution_x, scene.render.resolution_y = 1600, 510
scene.render.resolution_percentage, scene.render.fps = 100, 30
scene.frame_start, scene.frame_end = 1, len(frames)
editor = scene.sequence_editor_create()
strip = editor.strips.new_image('Pickaxe locomotion', str(frames[0]), channel=1, frame_start=1)
for frame in frames[1:]:
    strip.elements.append(frame.name)
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.media_type = 'VIDEO'
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format, scene.render.ffmpeg.codec = 'MPEG4', 'H264'
scene.render.ffmpeg.constant_rate_factor, scene.render.ffmpeg.ffmpeg_preset = 'HIGH', 'GOOD'
scene.render.filepath = str(out/'Pickaxe.locomotion.mp4')
bpy.ops.render.render(animation=True)
print('LOCOMOTION_VIDEO', scene.render.filepath)
