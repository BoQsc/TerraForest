# SPDX-License-Identifier: 0BSD
"""Blender authoring: planted support, weak-side collapse and a delayed toe scrape."""
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
    feet[prefix]={'sole':sole,'toe':Vector((sum(v.x for v in sole)/len(sole),min(v.y for v in sole),low)),
                  'heel':Vector((sum(v.x for v in sole)/len(sole),max(v.y for v in sole),low))}
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

def foot(prefix,y,pitch,lift,x=0):
    data=feet[prefix]
    # Roll around the loaded edge of the boot, rather than its ankle. The
    # stance translation cancels 0.45 m/s of travel even while the heel rolls.
    yaw=4 if prefix=='Left' else -8
    rotation=Quaternion((0,0,1),math.radians(yaw))@Quaternion((1,0,0),math.radians(pitch))
    pivot=data['toe' if pitch>=0 else 'heel']
    points=[rotation@(p-pivot)+pivot for p in data['sole']]
    z=.002+lift-min(p.z for p in points)
    ankle=rotation@(rest[prefix+'Foot'].translation-pivot)+pivot+Vector((x,y,z))
    target,error=solve_leg(prefix,ankle)
    mat=(rotation.to_matrix()@rest[prefix+'Foot'].to_3x3()).to_4x4();mat.translation=target
    rig.pose.bones[prefix+'Foot'].matrix=mat;bpy.context.view_layer.update()
    return error

def smooth(t):return t*t*(3-2*t)
def sample(t,keys):
    for (a,x),(b,y) in zip(keys,keys[1:]):
        if a<=t<=b:return x+(y-x)*smooth((t-a)/(b-a))
    return keys[-1][1]

def recovery(t,start,end,a,b):
    """Hermite return with the same foot velocity as the adjacent stance."""
    u=(t-start)/(end-start);m=.9*(end-start)
    return (2*u**3-3*u*u+1)*a+(u**3-2*u*u+u)*m+(-2*u**3+3*u*u)*b+(u**3-u*u)*m

def rotate_local(name,x=0,y=0,z=0):
    bone=rig.pose.bones[name]
    for axis,angle in [((1,0,0),x),((0,1,0),y),((0,0,1),z)]:
        bone.rotation_quaternion=bone.rotation_quaternion@Quaternion(axis,math.radians(angle))

def aim(name,direction):
    bone=rig.pose.bones[name];matrix=bone.matrix.copy()
    rotation=matrix.to_3x3().col[1].normalized().rotation_difference(direction.normalized())
    oriented=(rotation.to_matrix()@matrix.to_3x3()).to_4x4();oriented.translation=matrix.translation
    bone.matrix=oriented;bpy.context.view_layer.update()

NAME='Zombie_Walk_Drag_Right'
action=bpy.data.actions.new(NAME);rig.animation_data_create();rig.animation_data.action=action
scene.render.fps=60;scene.frame_start=0;scene.frame_end=120
records=[]
for n in range(121):
    scene.frame_set(n)
    t=(n%120)/120.0
    for b in rig.pose.bones:
        b.rotation_mode='QUATERNION';b.matrix_basis=base[b.name]
    # The strong leg supports 68% of a cycle. The weak foot supports the
    # recovery step across the loop seam, then scrapes forward late. Both
    # support trajectories cancel the full 0.9 m of travel per two-second loop.
    left_y=-.30+.9*t if t<=.68 else recovery(t,.68,1,.312,-.30)
    left_lift=0 if t<=.68 else .095*math.sin(math.pi*(t-.68)/.32)**2
    left_pitch=sample(t,[(0,-9),(.055,0),(.55,0),(.64,13),(.68,22),(.76,10),(.85,-6),(.95,-12),(1,-9)])
    right_y=-.16+.9*(t-.60 if t>=.60 else t+.40) if t<=.14 or t>=.60 else recovery(t,.14,.60,.326,-.16)
    right_pitch=sample(t,[(0,9),(.14,15),(.25,23),(.45,21),(.60,12),(.70,8),(.95,8),(1,9)])
    right_lift=.0015*math.sin(math.pi*(t-.14)/.46)**2 if .14<t<.60 else 0
    sway=sample(t,[(0,.010),(.10,.043),(.32,.060),(.52,.040),(.63,-.005),(.75,-.042),(.86,-.025),(1,.010)])
    drop=sample(t,[(0,-.012),(.055,-.038),(.31,-.002),(.54,-.012),(.71,-.065),(.81,-.043),(1,-.012)])
    surge=sample(t,[(0,-.025),(.10,-.047),(.34,.008),(.56,-.010),(.73,-.050),(.87,-.020),(1,-.025)])
    roll=sample(t,[(0,-1),(.20,-4),(.46,-3),(.72,5),(.84,3),(1,-1)])
    twist=sample(t,[(0,-3),(.30,4),(.56,2),(.78,-5),(1,-3)])
    hip=base_global['Hips'].copy()
    hip.translation+=Vector((sway,surge,drop))
    rotation=Quaternion((0,0,1),math.radians(twist))@Quaternion((0,1,0),math.radians(roll))@Quaternion((1,0,0),math.radians(3))
    hip=Matrix.Translation(hip.translation)@rotation.to_matrix().to_4x4()@Matrix.Translation(-hip.translation)@hip
    rig.pose.bones['Hips'].matrix=hip;bpy.context.view_layer.update()
    # Distribute the hunch through the spine. Loading shocks travel upward
    # with delays, instead of moving every body part as one rigid pendulum.
    loading=sample((t-.045)%1,[(0,0),(.07,3),(.30,-1),(.55,0),(.73,5),(.85,2),(1,0)])
    rotate_local('Spine',4+loading*.35,y=-twist*.35,z=roll*.25)
    rotate_local('Spine1',3+loading*.35,y=-twist*.30,z=roll*.30)
    rotate_local('Spine2',2+loading*.30,y=-twist*.25,z=roll*.20)
    rotate_local('Neck',-3+2*math.sin(math.tau*(t-.10)),z=2*math.sin(math.tau*(t-.16)))
    rotate_local('Head',-2+2.5*math.sin(math.tau*(t-.15)),y=1.5*math.sin(math.tau*(t-.23)))
    bpy.context.view_layer.update()
    for prefix,side in [('Left',1),('Right',-1)]:
        delay=.10 if prefix=='Left' else .22
        swing=math.sin(math.tau*(t-delay))
        shoulder=rig.pose.bones[prefix+'Shoulder']
        follow=shoulder.matrix.to_3x3()@base_global[prefix+'Shoulder'].to_3x3().inverted()
        # Uneven hanging arms, soft elbows and lagging wrists replace the
        # fixed, parallel forearms inherited from the original idle action.
        aim(prefix+'Arm',follow@Vector((side*.060,-.035+(.040 if side==1 else -.055)*swing,-.270)))
        aim(prefix+'ForeArm',follow@Vector((side*-.025,-(.190 if side==1 else .100)+.035*math.sin(math.tau*(t-delay-.07)),-(.145 if side==1 else .210))))
        rotate_local(prefix+'Hand',x=4*math.sin(math.tau*(t-delay-.13)),z=3*math.sin(math.tau*(t-delay-.18)))
    bpy.context.view_layer.update()
    errors=[foot('Left',left_y,left_pitch,left_lift),foot('Right',right_y,right_pitch,right_lift)]
    for b in rig.pose.bones:
        b.keyframe_insert('location',frame=n,group=b.name)
        b.keyframe_insert('rotation_quaternion',frame=n,group=b.name)
        b.keyframe_insert('scale',frame=n,group=b.name)
    records.append({'frame':n,'left_lift':left_lift,'right_lift':right_lift,
                    'hips':list(rig.pose.bones['Hips'].head),'left_stance':t<=.68,'right_stance':t<=.14 or t>=.60,
                    'left_ankle':list(rig.pose.bones['LeftFoot'].head),'right_ankle':list(rig.pose.bones['RightFoot'].head),
                    'max_target_error':max(errors)})
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for curve in bag.fcurves:
                for key in curve.keyframe_points:key.interpolation='LINEAR'
action.use_fake_user=True
rig['drag_walk_description']='Weighted two-second limp: planted left stance, delayed right toe scrape, weak-side collapse, spinal follow-through and uneven hanging arms. In place; native controller owns translation.'
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
 'reference_speed_mps':.45,'revision':'weighted_limp_v2','dragging_leg':'right','support_leg':'left','bones':len(rig.data.bones),
 'left_stance_phase':[0,.68],'right_stance_phase':[[0,.14],[.60,1]],'cycle_travel_m':.9,
 'maximum_solver_error_m':max(r['max_target_error'] for r in records),'samples':records,
 'scope':'Authored in-place bone motion. Flat-floor visual gait; no terrain foot IK, root translation, traversal permission or limb-loss rule.'}
(OUTPUT/'Zombie.drag_walk.json').write_text(json.dumps(metadata,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT/'Zombie.drag_walk.blend'),compress=True)
for name,cam in [('three_quarter',front),('side',side)]:
    scene.camera=cam;scene.render.filepath=str(PREVIEW/(name+'.png'));bpy.ops.render.render(write_still=True)
print('ZOMBIE_DRAG_WALK_AUTHORED',NAME,'solver_error',metadata['maximum_solver_error_m'])
