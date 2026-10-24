# SPDX-License-Identifier: 0BSD
"""Encode the rough motion study, comparison and unobstructed first-person view."""
import hashlib
import json
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/'reports/pickaxe_fresh'
OUT=ROOT/'docs/evidence/pickaxe_fresh'
records=[]
animation_time=(ROOT/'addons/characters/runtime/assets/Human.pickaxe_fresh.res').stat().st_mtime
for name,size,filename in [('blockout',(2560,860),'Pickaxe.firm-grip-blockout.mp4'),
                           ('comparison',(2560,860),'Pickaxe.current-vs-firm-grip.mp4'),
                           ('first_person',(1280,720),'Pickaxe.firm-grip-first-person.mp4')]:
    frames=sorted((FOLDER/(name+'_frames')).glob('*.png'))
    assert len(frames)==300,'Capture all 300 samples first'
    assert all(frame.stat().st_mtime>=animation_time for frame in frames),'Finish a fresh capture of every frame after the latest animation import'
    scene=bpy.context.scene;scene.sequence_editor_clear()
    scene.render.resolution_x,scene.render.resolution_y=size
    scene.render.resolution_percentage,scene.render.fps=100,30
    scene.frame_start,scene.frame_end=1,len(frames)
    editor=scene.sequence_editor_create()
    strip=editor.strips.new_image('Pickaxe '+name,str(frames[0]),channel=1,frame_start=1)
    for frame in frames[1:]:strip.elements.append(frame.name)
    scene.view_settings.view_transform='Standard'
    scene.render.image_settings.media_type='VIDEO';scene.render.image_settings.file_format='FFMPEG'
    scene.render.ffmpeg.format,scene.render.ffmpeg.codec='MPEG4','H264'
    scene.render.ffmpeg.constant_rate_factor,scene.render.ffmpeg.ffmpeg_preset='HIGH','GOOD'
    video=OUT/filename;scene.render.filepath=str(video)
    bpy.ops.render.render(animation=True)
    records.append({'video':filename,'size':list(size),'fps':30,'frames':300,'sha256':hashlib.sha256(video.read_bytes()).hexdigest()})
(OUT/'video.json').write_text(json.dumps({'status':'USER ACCEPTED fixed-grip default, 2026-10-24; comparison uses the previous pullback',
    'videos':records,'timeline':'Two normal-speed swings, one half-speed swing. Comparison preserves each action duration without retiming.',
    'scope':'Actual runtime rig in an isolated studio; new motion on neutral R11, not a derivative of earlier swing actions. No live gameplay or visual-acceptance claim.'},indent=2))
print('PICKAXE_FRESH_VIDEO',json.dumps(records))
