# SPDX-License-Identifier: 0BSD
"""Run with Blender --background --factory-startup after the Godot preview."""
import hashlib
import json
from pathlib import Path
import bpy
root=Path(__file__).resolve().parents[1]
folder=root/'reports/zombie_drag_walk'
frames=sorted((folder/'preview_frames').glob('*.png'))
assert len(frames)==240,'Capture all four gait cycles first'
scene=bpy.context.scene
scene.render.resolution_x,scene.render.resolution_y=1920,1080
scene.render.resolution_percentage=100;scene.render.fps=30
scene.frame_start,scene.frame_end=1,len(frames)
editor=scene.sequence_editor_create()
strip=editor.strips.new_image('Runtime zombie drag walk',str(frames[0]),channel=1,frame_start=1)
for frame in frames[1:]:strip.elements.append(frame.name)
scene.view_settings.view_transform='Standard'
scene.render.image_settings.media_type='VIDEO';scene.render.image_settings.file_format='FFMPEG'
scene.render.ffmpeg.format='MPEG4';scene.render.ffmpeg.codec='H264';scene.render.ffmpeg.constant_rate_factor='MEDIUM';scene.render.ffmpeg.ffmpeg_preset='GOOD'
video=folder/'Zombie.drag_walk.mp4';scene.render.filepath=str(video)
bpy.ops.render.render(animation=True)
(folder/'video.json').write_text(json.dumps({'encoder':'Blender '+bpy.app.version_string,'fps':30,'frames':240,
 'sha256':hashlib.sha256(video.read_bytes()).hexdigest(),
 'scope':'Four deterministic cycles on the unchanged runtime rig, with studio-only translation at 0.45 m/s; visual gait review, not live physics or FPS evidence.'},indent=2))
print('ZOMBIE_DRAG_VIDEO',video)
