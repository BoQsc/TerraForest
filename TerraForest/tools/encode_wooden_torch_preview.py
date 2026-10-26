# SPDX-License-Identifier: 0BSD
"""Encode the Godot torch presentation capture at its sampled timing."""
from pathlib import Path
import bpy

root=Path(__file__).resolve().parents[1]
frames=sorted((root/'reports/wooden_torch/frames').glob('*.png'))
assert len(frames)==240
newest=max((root/path).stat().st_mtime for path in ['addons/characters/runtime/assets/Human.torch.res','addons/characters/runtime/assets/Torch.glb','addons/characters/runtime/torch_flame.gdshader','addons/characters/runtime/torch_effects.gd'])
assert all(frame.stat().st_mtime>=newest for frame in frames)
out=root/'docs/evidence/wooden_torch';out.mkdir(parents=True,exist_ok=True)
scene=bpy.context.scene;scene.sequence_editor_clear()
scene.render.resolution_x,scene.render.resolution_y=1920,820
scene.render.resolution_percentage,scene.render.fps=100,30
scene.frame_start,scene.frame_end=1,len(frames)
editor=scene.sequence_editor_create();strip=editor.strips.new_image('Wooden torch',str(frames[0]),channel=1,frame_start=1)
for frame in frames[1:]:strip.elements.append(frame.name)
scene.view_settings.view_transform='Standard'
scene.render.image_settings.media_type='VIDEO';scene.render.image_settings.file_format='FFMPEG'
scene.render.ffmpeg.format,scene.render.ffmpeg.codec='MPEG4','H264'
scene.render.ffmpeg.constant_rate_factor,scene.render.ffmpeg.ffmpeg_preset='HIGH','GOOD'
scene.render.filepath=str(out/'Wooden-torch.preview.mp4');bpy.ops.render.render(animation=True)
print('WOODEN_TORCH_VIDEO',scene.render.filepath)
