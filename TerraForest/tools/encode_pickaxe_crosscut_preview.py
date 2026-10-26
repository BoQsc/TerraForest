# SPDX-License-Identifier: 0BSD
"""Encode separate comparison/body previews; never replace accepted evidence."""
from pathlib import Path
import hashlib
import json
import bpy

root=Path(__file__).resolve().parents[1]
output=root/'issues/pickaxe-crosscut';output.mkdir(parents=True,exist_ok=True)
asset=root/'addons/characters/runtime/assets/Human.pickaxe_crosscut.res'
records=[]
for name in ['comparison','body']:
    frames=sorted((root/f'reports/pickaxe_crosscut/{name}_frames').glob('*.png'))
    assert len(frames)==300 and all(p.stat().st_mtime>=asset.stat().st_mtime for p in frames)
    scene=bpy.context.scene;scene.sequence_editor_clear()
    scene.render.resolution_x,scene.render.resolution_y=1920,820
    scene.render.resolution_percentage,scene.render.fps=100,30
    scene.frame_start,scene.frame_end=1,300
    editor=scene.sequence_editor_create();strip=editor.strips.new_image(name,str(frames[0]),channel=1,frame_start=1)
    for frame in frames[1:]:strip.elements.append(frame.name)
    scene.view_settings.view_transform='Standard'
    scene.render.image_settings.media_type='VIDEO';scene.render.image_settings.file_format='FFMPEG'
    scene.render.ffmpeg.format,scene.render.ffmpeg.codec='MPEG4','H264'
    scene.render.ffmpeg.constant_rate_factor,scene.render.ffmpeg.ffmpeg_preset='HIGH','GOOD'
    path=output/f'Pickaxe.upper-right-to-lower-left.{name}.mp4';scene.render.filepath=str(path)
    bpy.ops.render.render(animation=True)
    records.append({'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'frames':300,'fps':30,'size':[1920,820]})
(output/'video.json').write_text(json.dumps({'status':'Revised candidate; not approved or selected as default','videos':records,'timeline':'Two normal-speed swings, one half-speed swing, then walking. Original 1.7 s and candidate 1.6 s durations are preserved.'},indent=2)+'\n')
print('PICKAXE_CROSSCUT_VIDEOS',json.dumps(records))
