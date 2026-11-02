# SPDX-License-Identifier: 0BSD
import json
import sys
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[1]
folder = Path(sys.argv[sys.argv.index('--') + 1]).resolve()
if not folder.is_relative_to(root / 'reports/expedition_motion'):
    raise ValueError('Expected an owned motion review')
frames = sorted((folder / 'frames').glob('[0-9][0-9][0-9][0-9].png'))
if len(frames) != 150:
    raise ValueError('Expected 150 first-person frames')
scene = bpy.context.scene
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.render.resolution_percentage = 100
scene.render.fps = 30
scene.frame_start, scene.frame_end = 1, 150
editor = scene.sequence_editor_create()
strip = editor.strips.new_image('Godot first-person wake-up', str(frames[0]), channel=1, frame_start=1)
for frame in frames[1:]:
    strip.elements.append(frame.name)
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.media_type = 'VIDEO'
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format = 'MPEG4'
scene.render.ffmpeg.codec = 'H264'
scene.render.ffmpeg.constant_rate_factor = 'MEDIUM'
scene.render.filepath = str(folder / 'Wakeup.proposal.mp4')
bpy.ops.render.render(animation=True)
print('WAKEUP_VIDEO', scene.render.filepath)
