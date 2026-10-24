# SPDX-License-Identifier: 0BSD
"""Blender --background --factory-startup --python tools/encode_hammer_shovel_preview.py."""
import hashlib
import json
import struct
from pathlib import Path
import bpy

folder = Path(__file__).resolve().parents[1] / 'reports/hammer_shovel'
records = {}
for kind, expected in [('hammer', 189), ('shovel', 237)]:
    frames = sorted((folder / (kind+'_frames')).glob('*.png'))
    assert len(frames) == expected, f'Capture all {expected} {kind} samples first'
    scene = bpy.context.scene
    if scene.sequence_editor:
        scene.sequence_editor_clear()
    scene.render.resolution_x, scene.render.resolution_y = struct.unpack('>II', frames[0].read_bytes()[16:24])
    scene.render.resolution_percentage, scene.render.fps = 100, 30
    scene.frame_start, scene.frame_end = 1, len(frames)
    editor = scene.sequence_editor_create()
    strip = editor.strips.new_image(kind.capitalize()+' review', str(frames[0]), channel=1, frame_start=1)
    for frame in frames[1:]:
        strip.elements.append(frame.name)
    scene.view_settings.view_transform = 'Standard'
    scene.render.image_settings.media_type = 'VIDEO'
    scene.render.image_settings.file_format = 'FFMPEG'
    scene.render.ffmpeg.format, scene.render.ffmpeg.codec = 'MPEG4', 'H264'
    scene.render.ffmpeg.constant_rate_factor, scene.render.ffmpeg.ffmpeg_preset = 'MEDIUM', 'GOOD'
    video = folder / f'Human.{kind}.mp4'
    scene.render.filepath = str(video)
    bpy.ops.render.render(animation=True)
    records[kind] = {'fps': 30, 'frames': len(frames), 'sha256': hashlib.sha256(video.read_bytes()).hexdigest()}
(folder/'video.json').write_text(json.dumps(records, indent=2)+'\n')
print('HAMMER_SHOVEL_VIDEOS', json.dumps(records))
