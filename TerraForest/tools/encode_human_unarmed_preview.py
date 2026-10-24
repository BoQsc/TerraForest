# SPDX-License-Identifier: 0BSD
"""Encode the inspected Godot first-person sequence with Blender's video editor."""
from pathlib import Path
import sys
import bpy
ROOT = Path(__file__).resolve().parents[1]
world = '--world' in sys.argv
frames = ROOT/('reports/unarmed/world_frames' if world else 'reports/unarmed/frames')
frame_count = 180 if world else 240
fresh_after = max((ROOT/'addons/characters/runtime/assets'/name).stat().st_mtime for name in ['Human.unarmed.res','Human.unarmed_body.res'])
assert all((frames/f'{frame:03d}.png').stat().st_mtime > fresh_after for frame in range(frame_count)), 'Render all preview frames after importing the current animation and skin.'
out = ROOT/'docs/evidence/human_unarmed'
out.mkdir(parents=True,exist_ok=True); (out/'.gdignore').touch()
scene = bpy.context.scene
scene.render.resolution_x,scene.render.resolution_y = 1280,720
scene.render.resolution_percentage = 100; scene.render.fps = 30
scene.frame_start,scene.frame_end = 1,frame_count
editor = scene.sequence_editor_create()
strip = editor.strips.new_image('Neutral hands and straight punch',str(frames/'000.png'),channel=1,frame_start=1)
for frame in range(1,frame_count): strip.elements.append(f'{frame:03d}.png')
scene.view_settings.view_transform = 'Standard'
scene.render.image_settings.media_type = 'VIDEO'
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format = 'MPEG4'; scene.render.ffmpeg.codec = 'H264'
scene.render.ffmpeg.constant_rate_factor = 'HIGH'; scene.render.ffmpeg.ffmpeg_preset = 'GOOD'
scene.render.filepath = str(out/('Unarmed.world-contact-v3.mp4' if world else 'Unarmed.depth-stroke-v3.mp4'))
bpy.ops.render.render(animation=True)
print('UNARMED_VIDEO',scene.render.filepath)
