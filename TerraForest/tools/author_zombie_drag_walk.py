# SPDX-License-Identifier: 0BSD
"""Blender authoring: a slow, looping left-led walk with right toe drag."""
import hashlib
import json
import math
from pathlib import Path
import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT=Path(__file__).resolve().parents[1]
OUTPUT=ROOT/'addons/characters/authoring'
PREVIEW=ROOT/'reports/zombie_drag_walk/blender'
OUTPUT.mkdir(parents=True,exist_ok=True);PREVIEW.mkdir(parents=True,exist_ok=True)
SOURCE=Path(bpy.data.filepath)
rig=bpy.data.objects['Zombie_Rig'];scene=bpy.context.scene
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
length={b.name:b.length for b in rig.data.bones}
for track in rig.animation_data.nla_tracks:track.mute=True
rig.animation_data.action=bpy.data.actions['Zombie_Idle']
rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(0);bpy.context.view_layer.update()
base={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
base_global={b.name:b.matrix.copy() for b in rig.pose.bones}
feet={}
for prefix,side in [('Left','L'),('Right','R')]:
    mesh=bpy.data.objects['Z_Foot_'+side]
    vertices=[mesh.matrix_world@v.co for v in mesh.data.vertices]
    low=min(v.z for v in vertices);sole=[v for v in vertices if v.z<low+.025]
    feet[prefix]={'sole':sole,'pivot':Vector((sum(v.x for v in sole)/len(sole),min(v.y for v in sole)+.025,low))}
for obj in bpy.data.objects:
    obj.animation_data_clear()
    if obj.type=='MESH' and obj.data.shape_keys:
        obj.data.shape_keys.animation_data_clear()
        for key in obj.data.shape_keys.key_blocks:key.value=0
for action in list(bpy.data.actions):bpy.data.actions.remove(action)

def frame(direction,normal):
    y=direction.normalized();z=normal.normalized();x=y.cross(z).normalized();z=x.cross(y).normalized()
    return Matrix((x,y,z)).transposed()
joint_frames={}
for prefix in ['Left','Right']:
    a=rest[prefix+'UpLeg'].to_3x3().col[1];b=rest[prefix+'Leg'].to_3x3().col[1]
    normal=a.cross(b).normalized()
    joint_frames[prefix]={name:frame(rest[name].to_3x3().col[1],normal).transposed()@rest[name].to_3x3() for name in [prefix+'UpLeg',prefix+'Leg']}

def solve_leg(prefix,target):
    upper,lower=prefix+'UpLeg',prefix+'Leg'
    start=rig.pose.bones[upper].head.copy();l1,l2=length[upper],length[lower]
    ray=target-start;distance=min(ray.length,l1+l2-.005);direction=ray.normalized()
    target=start+direction*distance
    side=1 if prefix=='Left' else -1
    pole=Vector((side*.23,-.8,.45))-start
    perpendicular=(pole-direction*pole.dot(direction)).normalized()
    along=(l1*l1-l2*l2+distance*distance)/(2*distance)
    knee=start+direction*along+perpendicular*math.sqrt(max(1e-8,l1*l1-along*along))
    normal=(knee-start).cross(target-knee).normalized()
    for name,a,b in [(upper,start,knee),(lower,knee,target)]:
        mat=(frame(b-a,normal)@joint_frames[prefix][name]).to_4x4();mat.translation=a
        rig.pose.bones[name].matrix=mat;bpy.context.view_layer.update()
    return target,(target-(start+ray)).length

def foot(prefix,y,pitch,lift):
    data=feet[prefix];rotation=Quaternion((1,0,0),math.radians(pitch));pivot=data['pivot']
    points=[rotation@(p-pivot)+pivot for p in data['sole']]
    z=.003+lift-min(p.z for p in points)
    ankle=rotation@(rest[prefix+'Foot'].translation-pivot)+pivot+Vector((0,y,z))
    target,error=solve_leg(prefix,ankle)
    mat=(rotation.to_matrix()@rest[prefix+'Foot'].to_3x3()).to_4x4();mat.translation=target
    rig.pose.bones[prefix+'Foot'].matrix=mat;bpy.context.view_layer.update()
    return error

def smooth(t):return t*t*(3-2*t)
def sample(t,keys):
    for (a,x),(b,y) in zip(keys,keys[1:]):
        if a<=t<=b:return x+(y-x)*smooth((t-a)/(b-a))
    return keys[-1][1]

NAME='Zombie_Walk_Drag_Right'
action=bpy.data.actions.new(NAME);rig.animation_data_create();rig.animation_data.action=action
scene.render.fps=60;scene.frame_start=0;scene.frame_end=120
records=[]
for n in range(121):
    scene.frame_set(n)
    t=(n%120)/120.0
    for b in rig.pose.bones:
        b.rotation_mode='QUATERNION';b.matrix_basis=base[b.name]
    # Left foot supports 62% of the loop; right toe stays low throughout its
    # delayed catch-up. Their cycles are intentionally not half-phase mirrors.
    if t<=.62:left_y=-.28+(.56/.62)*t
    else:left_y=.28-.56*smooth((t-.62)/.38)
    left_lift=0 if t<=.62 else .115*math.sin(math.pi*(t-.62)/.38)**1.3
    left_pitch=sample(t,[(0,-6),(.1,0),(.48,0),(.62,14),(.79,-9),(1,-6)])
    right_y=sample(t,[(0,.16),(.16,.23),(.26,.22),(.73,-.13),(1,.16)])
    right_pitch=sample(t,[(0,12),(.22,21),(.70,18),(.84,7),(1,12)])
    weight=math.sin(math.pi*min(t/.62,1)) if t<.62 else 0
    hip=base_global['Hips'].copy()
    hip.translation+=Vector((.018+.017*weight,0,-.022-.025*weight))
    hip=Matrix.Translation(hip.translation)@Quaternion((0,1,0),math.radians(-2.0-1.4*weight)).to_matrix().to_4x4()@Matrix.Translation(-hip.translation)@hip
    rig.pose.bones['Hips'].matrix=hip;bpy.context.view_layer.update()
    for name,amplitude,offset in [('LeftArm',3,0),('RightArm',7,.5),('Spine2',2,.15),('Head',1.5,.3)]:
        b=rig.pose.bones[name]
        b.rotation_quaternion=b.rotation_quaternion@Quaternion((1,0,0),math.radians(amplitude*math.sin(math.tau*(t+offset))))
    bpy.context.view_layer.update()
    errors=[foot('Left',left_y,left_pitch,left_lift),foot('Right',right_y,right_pitch,.0015*(.5-.5*math.cos(math.tau*t)))]
    for b in rig.pose.bones:
        b.keyframe_insert('location',frame=n,group=b.name)
        b.keyframe_insert('rotation_quaternion',frame=n,group=b.name)
        b.keyframe_insert('scale',frame=n,group=b.name)
    records.append({'frame':n,'left_lift':left_lift,'right_lift':.0015*(.5-.5*math.cos(math.tau*t)),
                    'left_ankle':list(rig.pose.bones['LeftFoot'].head),'right_ankle':list(rig.pose.bones['RightFoot'].head),
                    'max_target_error':max(errors)})
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:key.interpolation='LINEAR'
action.use_fake_user=True
rig['drag_walk_description']='Slow two-second asymmetric walk: left weight-bearing stride, right leg trails and toe scrapes forward. In place; native controller owns translation.'
for obj in bpy.data.objects:
    if obj.name.startswith('Z_Cap_'):obj.hide_render=True
    if obj.type=='LIGHT' or obj.type=='CAMERA' or obj.name.startswith('Preview.'):bpy.data.objects.remove(obj,do_unlink=True)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
bpy.data.objects['Z_Torso'].select_set(True);bpy.context.view_layer.objects.active=rig
scene.frame_set(0)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT/'Zombie.drag_walk.glb'),export_format='GLB',use_selection=True,
    export_materials='NONE',export_animations=True,export_animation_mode='ACTIONS',export_frame_range=True,
    export_force_sampling=True,export_skins=True,export_morph=False,export_yup=True)

def camera(name,location,target):
    data=bpy.data.cameras.new(name);obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj)
    obj.location=location;obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler();data.lens=55
    return obj
def light(name,location,power,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    obj=bpy.data.objects.new(name,data);scene.collection.objects.link(obj);obj.location=location
    obj.rotation_euler=(Vector((0,0,.9))-obj.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.005))
ground=bpy.context.object;ground.name='Drag Walk Review Floor'
material=bpy.data.materials.new('Drag Walk Review Slate');material.diffuse_color=(.12,.17,.20,1);ground.data.materials.append(material)
light('Drag Key',(2,-3,4),450,3);light('Drag Fill',(-3,-1,2.5),300,3);light('Drag Rim',(0,3,3),500,2)
scene.world=bpy.data.worlds.new('Drag Walk Studio');scene.world.color=(.15,.15,.15)
front=camera('Drag Walk Three Quarter',(3,-4,2.0),(0,0,.92))
side=camera('Drag Walk Side',(4,0,1.2),(0,0,.9))
scene.camera=front;scene.render.engine='CYCLES';scene.cycles.samples=24
scene.render.resolution_x=1280;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.frame_set(42)
metadata={'action':NAME,'blender':bpy.app.version_string,'source':str(SOURCE.relative_to(ROOT)),
 'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'frames':[0,120],'fps':60,'seconds':2,
 'reference_speed_mps':.45,'dragging_leg':'right','support_leg':'left','bones':len(rig.data.bones),
 'maximum_solver_error_m':max(r['max_target_error'] for r in records),'samples':records,
 'scope':'Authored in-place bone motion. Flat-floor visual gait; no terrain foot IK, root translation, traversal permission or limb-loss rule.'}
(OUTPUT/'Zombie.drag_walk.json').write_text(json.dumps(metadata,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT/'Zombie.drag_walk.blend'),compress=True)
for name,cam in [('three_quarter',front),('side',side)]:
    scene.camera=cam;scene.render.filepath=str(PREVIEW/(name+'.png'));bpy.ops.render.render(write_still=True)
print('ZOMBIE_DRAG_WALK_AUTHORED',NAME,'solver_error',metadata['maximum_solver_error_m'])
