"""R4 behavior expansion. Blender bundled API and Python standard library only; CC0.

Preserves the input rig, bind pose, four base clips, materials, and skin weights.
Adds deterministic 60 Hz actions and a synchronized BiteOpen shape key.
Run: blender -b --python source/author_behaviors.py -- --project /path/to/project
The immutable previous R4 source is archive/r4.previous/Zombie.r4.blend.
"""
import bpy
import bmesh
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
parser=argparse.ArgumentParser()
parser.add_argument('--project',type=Path,default=Path(__file__).resolve().parent.parent)
parser.add_argument('--draft',action='store_true')
parser.add_argument('--arm-clearance',type=float,default=.180)
parser.add_argument('--right-wrist-clearance',type=float,default=0.0)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
ROOT=args.project.resolve()
SOURCE=ROOT/'archive/r4.previous/Zombie.r4.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene=bpy.context.scene
rig=bpy.data.objects['Zombie_Rig']
rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
length={b.name:b.length for b in rig.data.bones}
for t in rig.animation_data.nla_tracks:t.mute=True
rig.animation_data.action=bpy.data.actions['Zombie_Idle']
rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(0)
BASE_POSE={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
rig.animation_data.action=None
scene.render.fps=60
scene.render.fps_base=1.0

def fcurve_digest(action):
    rows=[]
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag=strip.channelbag(slot)
                if bag:
                    rows.extend((fc.data_path,fc.array_index,[(tuple(k.co),k.interpolation) for k in fc.keyframe_points]) for fc in bag.fcurves)
    return hashlib.sha256(repr(rows).encode()).hexdigest()
BASE_DIGESTS={n:fcurve_digest(bpy.data.actions[n]) for n in ('Zombie_Idle','Zombie_Walk','Zombie_Attack','Zombie_Hit')}

def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smooth(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def curve(frame, keys):
    """Shape-preserving cubic interpolation; no overshoot past authored poses."""
    if frame <= keys[0][0]:
        return keys[0][1]
    if frame >= keys[-1][0]:
        return keys[-1][1]
    slopes = [(keys[i+1][1]-keys[i][1])/(keys[i+1][0]-keys[i][0])
              for i in range(len(keys)-1)]
    tangents = [0.0]
    for i in range(1, len(keys)-1):
        a, b = slopes[i-1], slopes[i]
        if a*b <= 0.0:
            tangents.append(0.0)
        else:
            h0 = keys[i][0]-keys[i-1][0]
            h1 = keys[i+1][0]-keys[i][0]
            w1, w2 = 2*h1+h0, h1+2*h0
            tangents.append((w1+w2)/(w1/a+w2/b))
    tangents.append(0.0)
    for i in range(len(keys)-1):
        if keys[i][0] <= frame <= keys[i+1][0]:
            h = keys[i+1][0]-keys[i][0]
            u = (frame-keys[i][0])/h
            return ((2*u**3-3*u**2+1)*keys[i][1]
                    +(u**3-2*u**2+u)*h*tangents[i]
                    +(-2*u**3+3*u**2)*keys[i+1][1]
                    +(u**3-u**2)*h*tangents[i+1])


def vector_curve(frame, keys):
    return Vector([curve(frame, [(f, v[axis]) for f, v in keys]) for axis in range(3)])


def rotate_world(name, axis, degrees):
    bone = rig.pose.bones[name]
    mat = bone.matrix.copy()
    mat = (Matrix.Translation(mat.translation)
           @ Quaternion(Vector(axis), math.radians(degrees)).to_matrix().to_4x4()
           @ Matrix.Translation(-mat.translation) @ mat)
    bone.matrix = mat
    bpy.context.view_layer.update()


def point_bone(name, start, end, transport=False):
    direction = (end-start).normalized()
    reference=rest[name]
    parent=rig.data.bones[name].parent
    if transport and parent:
        reference=rig.pose.bones[parent.name].matrix @ rest[parent.name].inverted() @ rest[name]
    rotation = reference.to_3x3().col[1].normalized().rotation_difference(direction)
    matrix = (rotation.to_matrix() @ reference.to_3x3()).to_4x4()
    matrix.translation = start
    rig.pose.bones[name].matrix = matrix
    bpy.context.view_layer.update()


def solve_limb(upper_name, lower_name, target, pole, margin=0.009, transport=False):
    start = rig.pose.bones[upper_name].head.copy()
    l1, l2 = length[upper_name], length[lower_name]
    delta = target-start
    distance = clamp(delta.length, abs(l1-l2)+0.055, l1+l2-margin)
    direction = delta.normalized()
    target = start+direction*distance
    perpendicular = pole-start-direction*(pole-start).dot(direction)
    if perpendicular.length < 1e-6:
        perpendicular = Vector((0, -1, 0))
    perpendicular.normalize()
    projection = (l1*l1-l2*l2+distance*distance)/(2*distance)
    height = math.sqrt(max(0.000001, l1*l1-projection*projection))
    middle = start+direction*projection+perpendicular*height
    point_bone(upper_name, start, middle, transport)
    point_bone(lower_name, middle, target, transport)
    return target


foot_geometry = {}
for side, prefix in ((1, 'Left'), (-1, 'Right')):
    obj = bpy.data.objects['Z_Foot_'+('L' if side == 1 else 'R')]
    vertices = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    low = min(v.z for v in vertices)
    sole = [v for v in vertices if v.z < low+0.025]
    x = sum(v.x for v in sole)/len(sole)
    foot_geometry[prefix] = {
        'sole': sole,
        'heel': Vector((x, max(v.y for v in sole)-0.01, low)),
        'toe': Vector((x, min(v.y for v in sole)+0.025, low)),
    }


def place_foot(prefix, shift, pitch=0.0, lift=0.0):
    """Roll around a grounded heel/toe while retaining the authored stance travel."""
    data = foot_geometry[prefix]
    pivot = data['heel'] if pitch < 0 else data['toe']
    rotation = Quaternion((1, 0, 0), math.radians(pitch))
    points = [rotation @ (v-pivot)+pivot for v in data['sole']]
    correction = 0.004-min(v.z for v in points)+lift
    displacement = Vector(shift)+Vector((0, 0, correction))
    ankle = rotation @ (rest[prefix+'Foot'].translation-pivot)+pivot+displacement
    side = 1 if prefix == 'Left' else -1
    pole = Vector((side*0.18, -0.64, 0.43))
    solved = solve_knee(prefix, ankle, pole, 0.004)
    matrix = (rotation.to_matrix() @ rest[prefix+'Foot'].to_3x3()).to_4x4()
    matrix.translation = solved
    rig.pose.bones[prefix+'Foot'].matrix = matrix
    bpy.context.view_layer.update()


def limb_frame(direction, normal):
    """A single elbow plane gives the two segments one actual hinge."""
    y = direction.normalized()
    x = (normal-y*normal.dot(y)).normalized()
    z = x.cross(y).normalized()
    return Matrix((x, y, z)).transposed()


arm_rest_frames = {}
for prefix in ('Left', 'Right'):
    upper, lower = prefix+'Arm', prefix+'ForeArm'
    a = rest[upper].to_3x3().col[1].normalized()
    b = rest[lower].to_3x3().col[1].normalized()
    normal = a.cross(b).normalized()
    arm_rest_frames[prefix] = {
        upper: limb_frame(a, normal).transposed() @ rest[upper].to_3x3(),
        lower: limb_frame(b, normal).transposed() @ rest[lower].to_3x3(),
    }


def place_arm(prefix, target, hand_direction, tension=0.0, pole_offset=0.0,
              pole_direction=None, wrist_roll=0.0, wrist_bend=0.0,
              hand_correction=14.0, finger_curl=None):
    side = 1 if prefix == 'Left' else -1
    if prefix == 'Right':
        target = Vector(target)+Vector((-args.right_wrist_clearance,0,0))
    shoulder = rig.pose.bones[prefix+'Arm'].head.copy()
    pole_ray = Vector(pole_direction or (side*(0.065+pole_offset), 0.085, -0.43))
    # Restored cylindrical arm volume needs humerus clearance from the ribs.
    # Move the elbow plane, keeping the controlled hand target in place.
    pole_ray.x += side*args.arm_clearance
    pole = shoulder+pole_ray
    upper, lower = prefix+'Arm', prefix+'ForeArm'
    l1, l2 = length[upper], length[lower]
    delta = target-shoulder
    # Always retain a readable elbow. No full extension, hyperflexion or stretch.
    min_distance = math.sqrt(l1*l1+l2*l2+2*l1*l2*math.cos(math.radians(100)))
    max_distance = math.sqrt(l1*l1+l2*l2+2*l1*l2*math.cos(math.radians(24)))
    distance = clamp(delta.length, min_distance, max_distance)
    direction = delta.normalized()
    wrist = shoulder+direction*distance
    pole_ray = pole-shoulder
    perpendicular = (pole_ray-direction*pole_ray.dot(direction)).normalized()
    along = (l1*l1-l2*l2+distance*distance)/(2*distance)
    height = math.sqrt(max(1e-8,l1*l1-along*along))
    elbow = shoulder+direction*along+perpendicular*height
    normal = (elbow-shoulder).cross(wrist-elbow).normalized()
    for name, start, end in ((upper,shoulder,elbow),(lower,elbow,wrist)):
        matrix = (limb_frame(end-start, normal) @ arm_rest_frames[prefix][name]).to_4x4()
        matrix.translation = start
        rig.pose.bones[name].matrix = matrix
        bpy.context.view_layer.update()
    forearm = rig.pose.bones[prefix+'ForeArm'].matrix
    matrix = forearm @ rest[prefix+'ForeArm'].inverted() @ rest[prefix+'Hand']
    direction = matrix.to_3x3().col[1].normalized()
    turn = direction.rotation_difference(hand_direction.normalized())
    if turn.angle > math.radians(hand_correction):
        turn = Quaternion(turn.axis, math.radians(hand_correction))
    matrix = (turn.to_matrix() @ matrix.to_3x3()).to_4x4()
    matrix = (Quaternion(matrix.to_3x3().col[1].normalized(), math.radians(wrist_roll)).to_matrix()
              @ matrix.to_3x3()).to_4x4()
    matrix = (Quaternion(matrix.to_3x3().col[0].normalized(), math.radians(wrist_bend)).to_matrix()
              @ matrix.to_3x3()).to_4x4()
    matrix.translation = wrist
    rig.pose.bones[prefix+'Hand'].matrix = matrix
    bpy.context.view_layer.update()
    for finger in ('Index', 'Middle', 'Ring', 'Pinky'):
        for joint in (1, 2, 3):
            bone = rig.pose.bones.get(prefix+'Hand'+finger+str(joint))
            if bone:
                # Keep the corrected narrow right-middle web inside its safe curl.
                if joint > 1 and prefix == 'Right' and finger == 'Middle':
                    curl = -0.16
                else:
                    # Adjacent finger webs are shared skinned surfaces. Retain
                    # the validated curl envelope while the hand pose changes.
                    curl = (-0.18 if joint == 1 else -0.34)-0.025*clamp(tension)
                bone.rotation_mode = 'QUATERNION'
                if finger_curl is not None: curl = finger_curl * (0.60 if joint == 1 else 1.0)
                bone.rotation_quaternion = Quaternion((1, 0, 0), curl)
    for joint in (1, 2, 3):
        bone = rig.pose.bones.get(prefix+'HandThumb'+str(joint))
        if bone:
            bone.rotation_mode = 'QUATERNION'
            bone.rotation_quaternion = Quaternion((1, 0, 0), -0.20)


def body(offset, hip_yaw, hip_roll, lean, chest_turn, head_turn=0, head_tilt=4,
         shoulder_right=0.0, shoulder_left=0.0):
    hips = rig.pose.bones['Hips']
    matrix = rest['Hips'].copy()
    matrix.translation += Vector(offset)
    hips.matrix = matrix
    bpy.context.view_layer.update()
    rotate_world('Hips', (0, 0, 1), hip_yaw)
    rotate_world('Hips', (0, 1, 0), hip_roll)
    for name, share in (('Spine', .25), ('Spine1', .35), ('Spine2', .40)):
        rotate_world(name, (1, 0, 0), lean*share)
        rotate_world(name, (0, 0, 1), chest_turn*share)
    rotate_world('Neck', (0, 1, 0), head_tilt)
    rotate_world('Head', (1, 0, 0), -5.0)
    rotate_world('Head', (0, 0, 1), head_turn)
    # Scapulae lead arm gestures rather than keeping both shoulders frozen.
    rotate_world('RightShoulder', (0, 1, 0), shoulder_right)
    rotate_world('LeftShoulder', (0, 1, 0), -shoulder_left)


RIGHT_READY=Vector((-.280,-.345,1.265))
LEFT_READY=Vector((.245,-.255,1.105))
NEW_CLIPS=[
    ('Zombie_Attack_Bite',81,'bite'),
    ('Zombie_Attack_Left',78,'left'),
    ('Zombie_Attack_Right',84,'right'),
    ('Zombie_Attack_Both',96,'both'),
    ('Zombie_Crawl',96,'crawl'),
    ('Zombie_Crawl_Idle',120,'crawl_idle'),
    ('Zombie_Crawl_Bite',72,'crawl_bite'),
    ('Zombie_To_Crawl',48,'to_crawl'),
    ('Zombie_Crawl_Hit',30,'crawl_hit'),
    ('Zombie_Jump',72,'jump'),
    ('Zombie_Climb_Ladder',120,'ladder'),
]

leg_rest_frames={}
for prefix in ('Left','Right'):
    upper,lower=prefix+'UpLeg',prefix+'Leg'
    a=rest[upper].to_3x3().col[1].normalized();b=rest[lower].to_3x3().col[1].normalized()
    normal=a.cross(b).normalized()
    leg_rest_frames[prefix]={upper:limb_frame(a,normal).transposed()@rest[upper].to_3x3(),lower:limb_frame(b,normal).transposed()@rest[lower].to_3x3()}


def solve_knee(prefix,target,pole,margin=.004):
    upper,lower=prefix+'UpLeg',prefix+'Leg'
    start=rig.pose.bones[upper].head.copy();l1,l2=length[upper],length[lower]
    ray=Vector(target)-start
    minimum=math.sqrt(l1*l1+l2*l2+2*l1*l2*math.cos(math.radians(98)))
    distance=clamp(ray.length,minimum,l1+l2-margin);direction=ray.normalized()
    ankle=start+direction*distance
    ray=Vector(pole)-start;perp=(ray-direction*ray.dot(direction)).normalized()
    projection=(l1*l1-l2*l2+distance*distance)/(2*distance)
    bend=math.sqrt(max(1e-8,l1*l1-projection*projection))
    knee=start+direction*projection+perp*bend
    normal=(knee-start).cross(ankle-knee).normalized()
    for name,a,b in ((upper,start,knee),(lower,knee,ankle)):
        matrix=(limb_frame(b-a,normal)@leg_rest_frames[prefix][name]).to_4x4();matrix.translation=a
        rig.pose.bones[name].matrix=matrix;bpy.context.view_layer.update()
    return ankle


def reset_pose():
    for bone in rig.pose.bones:
        bone.matrix_basis.identity()
    bpy.context.view_layer.update()


def ready_pose():
    for b in rig.pose.bones:b.matrix_basis=BASE_POSE[b.name]
    bpy.context.view_layer.update()


def standing_feet(frame,end,contact,side=1,step=.15):
    settle=contact+18
    move=curve(frame,[(0,0),(7,0),(contact-3,step),(settle,step),(end-7,0),(end,0)])
    lift=.065*math.sin(math.pi*clamp((frame-7)/(contact-10))) if frame<contact-3 else .045*math.sin(math.pi*clamp((frame-settle)/max(1,end-7-settle)))
    for s,p in ((1,'Left'),(-1,'Right')):
        pitch=curve(frame,[(0,0),(contact-8,0),(contact+8,9),(end-13,0),(end,0)]) if s!=side else 0
        place_foot(p,(s*.005,(-.06 if s==1 else .07)-(move if s==side else 0),0),pitch,lift if s==side else 0)


def standing_attack(kind,frame,end):
    contact={'bite':36,'left':32,'right':36,'both':42}[kind]
    side=1 if kind in ('left','bite','both') else -1
    preparation=curve(frame,[(0,0),(8,.25),(contact-13,1),(contact-7,1),(contact,0),(end,0)])
    thrust=curve(frame,[(0,0),(contact-8,0),(contact,1),(contact+5,1.04),(contact+15,.65),(end-14,.03),(end,0)])
    recovery=curve(frame,[(0,0),(contact+10,0),(contact+23,1),(end-8,.15),(end,0)])
    if kind=='bite':
        body((-.008*preparation,-.165*thrust,-.060-.045*preparation-.045*thrust),
             -3-3*preparation+2*thrust,-1.0*preparation,15-7*preparation+23*thrust,
             -3*preparation+2*thrust,1.8*preparation,4-1.5*thrust,2+5*preparation,-2+5*preparation)
        rotate_world('Neck',(1,0,0),-6*preparation-6*thrust)
        rotate_world('Head',(1,0,0),-8*preparation-15*thrust)
        targets={
          'Right':vector_curve(frame,[(0,RIGHT_READY),(17,(-.255,-.295,1.315)),(27,(-.250,-.420,1.415)),(36,(-.250,-.425,1.305)),(44,(-.245,-.415,1.245)),(60,(-.265,-.340,1.200)),(81,RIGHT_READY)]),
          'Left':vector_curve(frame,[(0,LEFT_READY),(17,(.245,-.290,1.180)),(27,(.240,-.440,1.320)),(36,(.250,-.445,1.225)),(44,(.255,-.430,1.185)),(60,(.245,-.290,1.095)),(81,LEFT_READY)])}
        standing_feet(frame,end,contact,1,.11)
    else:
        both=kind=='both'
        attack_sign=1 if kind=='right' else -1
        turn=(-20*preparation+18*thrust)*attack_sign if not both else 3*preparation-3*thrust
        body((.015*attack_sign*preparation,-.130*thrust,-.060-.048*preparation-.070*thrust-.012*recovery),
             -3+(-10*preparation+11*thrust)*attack_sign if not both else -3+2*thrust,
             2*attack_sign*(thrust-preparation) if not both else 0,
             15-8*preparation+18*thrust,turn,-.25*turn,4,
             2+(8*preparation if kind in ('right','both') else 2*preparation),
             -2+(8*preparation if kind in ('left','both') else 2*preparation)+(16*thrust if kind=='left' else 0))
        standing_feet(frame,end,contact,side,.18 if not both else .14)
        if kind=='right':
            targets={
             'Right':vector_curve(frame,[(0,RIGHT_READY),(10,(-.285,-.245,1.290)),(22,(-.355,-.090,1.555)),(28,(-.360,-.085,1.590)),(32,(-.340,-.290,1.525)),(36,(-.145,-.715,1.325)),(42,(.060,-.615,1.060)),(48,(.040,-.565,1.065)),(62,(-.255,-.340,1.120)),(73,(-.285,-.350,1.275)),(84,RIGHT_READY)]),
             'Left':LEFT_READY+Vector((.01,-.13,.075))*thrust+Vector((.01,-.035,.075))*preparation}
        elif kind=='left':
            targets={
             'Left':vector_curve(frame,[(0,LEFT_READY),(9,(.270,-.230,1.180)),(19,(.365,-.060,1.390)),(25,(.365,-.060,1.435)),(28,(.325,-.265,1.440)),(32,(.105,-.720,1.365)),(38,(-.045,-.635,1.200)),(44,(-.025,-.545,1.115)),(55,(.260,-.335,1.140)),(66,(.250,-.245,1.095)),(78,LEFT_READY)]),
             'Right':RIGHT_READY+Vector((-.02,-.07,-.09))*thrust+Vector((-.025,-.06,.12))*preparation}
        else:
            targets={
             'Right':vector_curve(frame,[(0,RIGHT_READY),(12,(-.280,-.275,1.280)),(26,(-.300,-.160,1.570)),(33,(-.300,-.160,1.600)),(37,(-.270,-.360,1.550)),(42,(-.230,-.690,1.325)),(49,(-.205,-.605,1.105)),(57,(-.215,-.550,1.105)),(73,(-.285,-.345,1.170)),(96,RIGHT_READY)]),
             'Left':vector_curve(frame,[(0,LEFT_READY),(12,(.260,-.255,1.180)),(26,(.285,-.160,1.525)),(33,(.290,-.160,1.570)),(37,(.265,-.360,1.510)),(42,(.225,-.680,1.285)),(49,(.210,-.600,1.065)),(57,(.225,-.545,1.055)),(73,(.260,-.295,1.110)),(96,LEFT_READY)])}
    for s,p in ((1,'Left'),(-1,'Right')):
        higher=preparation if (kind=='both' or kind==p.lower()) else .3*preparation
        pole=Vector((s*(.06+.12*higher),.09,-.43+.09*higher))
        if kind=='both' and p=='Left':pole.x+=.035*preparation
        if kind=='both':
            if p=='Right':
                targets[p].y-=.03*preparation
                pole.x-=.12*thrust
            else:pole.x-=.08*thrust
        if kind=='right' and p=='Right':
            targets[p].y-=.04*thrust
            targets[p].x-=.08*thrust
        direction=Vector((0,-1,.14+.32*higher-.30*thrust))
        place_arm(p,targets[p],direction,1.0,pole_direction=pole,wrist_roll=s*4)


def grounded_trailing_foot(prefix,xy,pitch,pole,transported=False):
    foot=bpy.data.objects['Z_Foot_'+('L' if prefix=='Left' else 'R')]
    rotation=Quaternion((1,0,0),math.radians(pitch))
    rest_ankle=rest[prefix+'Foot'].translation
    low=min((rotation@(foot.matrix_world@v.co-rest_ankle)).z for v in foot.data.vertices)
    ankle=Vector((xy[0],xy[1],.006-low))
    solved=(solve_limb(prefix+'UpLeg',prefix+'Leg',ankle,Vector(pole),.012,transport=True)
            if transported else solve_knee(prefix,ankle,Vector(pole),.012))
    fm=(rotation.to_matrix()@rest[prefix+'Foot'].to_3x3()).to_4x4();fm.translation=solved
    rig.pose.bones[prefix+'Foot'].matrix=fm
    bpy.context.view_layer.update()


def crawl_body(frame,end,kind='crawl',transition=1.0):
    phase=math.tau*frame/end
    moving=kind=='crawl'
    pulse=curve(frame,[(0,0),(18,.0),(30,1),(36,.95),(48,.30),(62,0),(72,0)]) if kind=='crawl_bite' else 0.0
    hit=curve(frame,[(0,0),(4,1),(9,.85),(17,.22),(25,0),(30,0)]) if kind=='crawl_hit' else 0.0
    sway=.013*math.sin(phase) if moving else .003*math.sin(phase)
    lift=.010*(1-math.cos(2*phase)) if moving else .003*math.sin(phase)
    hips=rig.pose.bones['Hips']
    mat=rest['Hips'].copy();mat.translation=Vector((.0034+sway,.170-.055*pulse+.025*hit,.310+lift-.028*pulse-.025*hit))
    hips.matrix=mat;bpy.context.view_layer.update()
    rotate_world('Hips',(1,0,0),78+2*pulse-2*hit)
    rotate_world('Hips',(0,1,0),1.7*math.sin(phase) if moving else .7*math.sin(phase))
    for n,share in (('Spine',.25),('Spine1',.35),('Spine2',.40)):
        rotate_world(n,(1,0,0),(3+3*pulse)*share)
        rotate_world(n,(0,0,1),(-2.5*math.sin(phase) if moving else 0)*share)
    rotate_world('Neck',(1,0,0),-24-8*pulse-3*hit)
    rotate_world('Head',(1,0,0),-43+11*pulse-7*hit)
    rotate_world('Head',(0,0,1),2*math.sin(phase+.2) if moving else .6*math.sin(phase))
    for s,p,off in ((1,'Left',0),(-1,'Right',.5)):
        u=(frame/end+off)%1.0 if moving else off
        if u<.6:
            travel=-.580+.3072*u/.6
            hand_lift=0
        else:
            v=(u-.6)/.4
            travel=curve(v,[(0,-.2728),(.22,-.270),(.72,-.540),(1,-.580)])
            hand_lift=.102*math.sin(math.pi*v)**1.1
        if not moving:travel=-.43+(.02 if s<0 else 0)
        wrist=Vector((s*(.290+.012*math.cos(phase)),travel-.045*pulse,.085+hand_lift))
        place_arm(p,wrist,Vector((0,-1,-.025)),.55,pole_direction=(s*(.025 if p=='Left' else .12),.13,-.43),wrist_roll=s*8,hand_correction=72,finger_curl=-.04)
        # The surviving leg drags in a low, nearly extended posture. The pole
        # points laterally so the knee keeps clearance instead of bending below
        # the ground. The arm-driven crawl remains valid with either leg absent.
        grounded_trailing_foot(p,(s*.195,.993+(.012*math.sin(phase+off*math.tau) if moving else 0)),82,(s*.56,.53,.24),True)


def transition_to_crawl(frame,end):
    t=frame/end
    # Intermediate crouch first: the palms reach toward support while the
    # pelvis lowers. Blending fixed-length local bone transforms cannot stretch
    # either arm. Final pose is exactly the start of the prone idle.
    ready_pose();a={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
    reset_pose()
    body((0,.06,-.265),-3,0,35,0,0,4,1,1)
    place_foot('Left',(.03,-.13,0));place_foot('Right',(-.03,.10,0))
    place_arm('Left',Vector((.28,-.49,.67)),Vector((0,-1,-.4)),.5,hand_correction=45)
    place_arm('Right',Vector((-.28,-.42,.77)),Vector((0,-1,-.4)),.5,hand_correction=45)
    b={bone.name:bone.matrix_basis.copy() for bone in rig.pose.bones}
    reset_pose();crawl_body(0,120,'crawl_idle')
    c={bone.name:bone.matrix_basis.copy() for bone in rig.pose.bones}
    if t<.38:blend_pose(a,b,smooth(t/.38))
    else:blend_pose(b,c,smooth((t-.38)/.62))
    # Rotational blending alone swings the boots through the floor. Re-solve
    # the actual foot targets at every frame, dragging their contact point back
    # as the pelvis turns into the prone orientation.
    u=smooth(clamp((t-.05)/.73))
    for s,p in ((1,'Left'),(-1,'Right')):
        start=Vector((rest[p+'Foot'].translation.x+s*.005,.000373 if s==1 else .130373))
        end_xy=Vector((s*.195,.993))
        xy=start.lerp(end_xy,u)
        pole=Vector((s*.18,-.64,.43)).lerp(Vector((s*.56,.53,.24)),u)
        grounded_trailing_foot(p,xy,82*u,pole,True)


def blend_pose(a,b,w):
    for pb in rig.pose.bones:
        la,qa,sa=a[pb.name].decompose();lb,qb,sb=b[pb.name].decompose()
        pb.matrix_basis=Matrix.LocRotScale(la.lerp(lb,w),qa.slerp(qb,w),Vector((1,1,1)))
    bpy.context.view_layer.update()


def jump_elevation(frame):
    return max(0,.5*9.8*((frame-21)/60)*((44-frame)/60)) if 21<frame<44 else 0


def jump_pose(frame,end):
    crouch=curve(frame,[(0,0),(8,.30),(16,1),(19,.95),(23,0),(40,0),(45,.78),(49,.90),(57,.25),(66,.04),(72,0)])
    air=curve(frame,[(0,0),(21,0),(27,1),(34,1),(42,.15),(44,0),(72,0)])
    height=jump_elevation(frame)
    body((0,-.025*crouch,-.06-.150*crouch+height+.024*air),-3+2*air,1.5*air,
         15+9*crouch-8*air,-3*air,1*air,4,2+5*air,-2+6*air)
    for s,p in ((1,'Left'),(-1,'Right')):
        place_foot(p,(s*.005,-.06 if s==1 else .07,0),3*air,height+.024*air)
    right=RIGHT_READY+Vector((-.01,.105,-.120))*crouch+Vector((-.01,-.075,.120))*air
    left=LEFT_READY+Vector((.02,.095,-.080))*crouch+Vector((.01,-.115,.175))*air
    place_arm('Right',right+Vector((0,0,height)),Vector((0,-1,.1)),.65,wrist_roll=-4)
    place_arm('Left',left+Vector((0,0,height)),Vector((0,-1,.1)),.65,wrist_roll=4)


def ladder_pose(frame,end):
    phase=math.tau*frame/end
    body((.006*math.sin(phase),-.060,.020+.007*math.sin(2*phase)),
         1.8*math.sin(phase),1.3*math.sin(phase),11,-2.5*math.sin(phase),0,1,22,22)
    rotate_world('Head',(1,0,0),-5)
    for s,p,off in ((1,'Left',0),(-1,'Right',.5)):
        u=(frame/end+off)%1.0
        if u<.6:
            hz=1.8-.6*u
            hz_lift=0.0
            hy=-.400
        else:
            v=(u-.6)/.4
            hz=curve(v,[(0,1.44),(.14,1.435),(.76,1.80),(1,1.80)])
            hz_lift=.035*math.sin(math.pi*v)
            hy=-.400+.075*math.sin(math.pi*v)
        place_arm(p,Vector((s*.24,hy,hz+hz_lift)),Vector((0,-1,.32)),.9,
                  pole_direction=(s*(-.050 if p=='Left' else .075),.065,-.38),wrist_roll=s*5,hand_correction=22)
        # Feet move on the same stagger as the hands and plant on real rungs.
        if u<.425:
            fz=.30-.6*u
            fy=-.315
        else:
            v=(u-.425)/.575
            fz=curve(v,[(0,.045),(.16,.047),(.75,.30),(1,.30)])+.035*math.sin(math.pi*v)
            fy=-.315+.065*math.sin(math.pi*v)
        # Rungs contact the sole near the toe, rather than the ankle center.
        ankle=rest[p+'Foot'].translation+Vector((s*.014,fy-.060373,fz+.018))
        solved=solve_knee(p,ankle,Vector((s*.27,-.43,.55)),.004)
        fm=rest[p+'Foot'].copy();fm.translation=solved
        rig.pose.bones[p+'Foot'].matrix=fm
        bpy.context.view_layer.update()


def pose(kind,frame,end):
    reset_pose()
    if kind in ('bite','left','right','both'):standing_attack(kind,frame,end)
    elif kind in ('crawl','crawl_idle','crawl_bite','crawl_hit'):crawl_body(frame,end,kind)
    elif kind=='to_crawl':transition_to_crawl(frame,end)
    elif kind=='jump':jump_pose(frame,end)
    elif kind=='ladder':ladder_pose(frame,end)
    if kind in ('bite','left','right','both','jump') and frame in (0,end):ready_pose()
    bpy.context.view_layer.update()


def add_mouth_shape():
    """Articulate the existing lower face while retaining the neutral surface."""
    head=bpy.data.objects['Z_Head']
    # The existing mouth already has three authored lip rings and a closed
    # interior patch. Keep its exterior vertices and polygons unchanged. Move
    # the 30 interior triangles to the back of an 18 mm cavity; the added wall
    # ring uses64triangles, and dental fronts use32. Total remains14992.
    interior=bpy.data.materials.new('Zombie.Mouth.Interior');interior.use_nodes=True
    bs=interior.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.008,.0015,.001,1);bs.inputs['Roughness'].default_value=.7
    teeth=bpy.data.materials.new('Zombie.Mouth.Teeth');teeth.use_nodes=True
    bs=teeth.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.55,.48,.32,1);bs.inputs['Roughness'].default_value=.36
    head.data.materials.append(interior);interior_index=len(head.data.materials)-1
    head.data.materials.append(teeth);teeth_index=len(head.data.materials)-1
    for poly in head.data.polygons:
        if all(2833<=i<=2864 for i in poly.vertices):poly.material_index=interior_index
    original_vertex_count=len(head.data.vertices)
    bm=bmesh.new();bm.from_mesh(head.data);bm.verts.ensure_lookup_table();deform=bm.verts.layers.deform.verify()
    head_group=head.vertex_groups['Head'].index
    front_ring=[bm.verts[i] for i in range(2833,2865)]
    cavity_ring=[bm.verts.new(v.co+Vector((0,.018,0))) for v in front_ring]
    for old,new in zip(front_ring,cavity_ring):
        for group,weight in old[deform].items():new[deform][group]=weight
    old_inner=[f for f in bm.faces if all(2833<=v.index<=2864 for v in f.verts)]
    old_inner_polys=[[v.index-2833 for v in f.verts] for f in old_inner]
    bmesh.ops.delete(bm,geom=old_inner,context='FACES_ONLY')
    for ids in old_inner_polys:
        face=bm.faces.new(tuple(cavity_ring[i] for i in ids));face.material_index=interior_index
    for i in range(32):
        j=(i+1)%32
        face=bm.faces.new((front_ring[i],front_ring[j],cavity_ring[j],cavity_ring[i]));face.material_index=interior_index
    upper_points=sorted((v.co.x,v.co.y,v.co.z) for v in front_ring[:17])
    def lip_surface(x):
        for a,b in zip(upper_points,upper_points[1:]):
            if a[0]<=x<=b[0]:
                t=(x-a[0])/(b[0]-a[0]);return a[1]*(1-t)+b[1]*t,a[2]*(1-t)+b[2]*t
        return -.112,1.610
    lower_teeth=[]
    for lower in (False,True):
        for index in range(8):
            x=(index-3.5)*.0054;width=.0046
            lip_y,lip_z=lip_surface(x)
            y=lip_y-.00045
            top=lip_z+(-.0014 if lower else .0020)
            bottom=top-(.0047 if lower else .0065)
            coords=[(x-width/2,y,bottom),(x+width/2,y,bottom),(x+width/2,y,top),(x-width/2,y,top)]
            verts=[bm.verts.new(c) for c in coords]
            for v in verts:v[deform][head_group]=1.0
            face=bm.faces.new((verts[0],verts[1],verts[2],verts[3]));face.material_index=teeth_index
            if lower:lower_teeth.extend(verts)
    bm.verts.index_update();lower_teeth_indices=[v.index for v in lower_teeth]
    cavity_indices=[v.index for v in cavity_ring]
    bm.to_mesh(head.data);bm.free();head.data.update()
    if not head.data.shape_keys:head.shape_key_add(name='Basis')
    shape=head.shape_key_add(name='BiteOpen')
    pivot=Vector((0,.018,1.648))
    rot=Quaternion((1,0,0),math.radians(12))
    inv=head.matrix_world.inverted()
    mouth_indices={i for p in head.data.polygons if head.data.materials[p.material_index].name=='Zombie.Mouth.Authored.PBR' for i in p.vertices}
    changed=0
    for v in head.data.vertices:
        p=head.matrix_world@v.co
        # Fade well before the neck cut, nose, eyes, and ears. The lip opening
        # peaks at the lower lip and flows continuously into the chin/mandible.
        front=smooth((.035-p.y)/.115)
        side=smooth((.086-abs(p.x))/.031)
        neck=smooth((p.z-1.559)/.035)
        below=smooth((1.614-p.z)/.012)
        w=front*side*neck*below
        # Explicit authored lip ring membership keeps the upper lip and
        # philtrum stationary; a purely height-based mask stretches the face.
        if (2769<=v.index<=2785 or 2801<=v.index<=2817 or 2833<=v.index<=2849):w=0
        if (2786<=v.index<=2800 or 2818<=v.index<=2832 or 2850<=v.index<=2864):w=smooth((.0263-abs(p.x))/.012)
        if v.index>=original_vertex_count:w=0.0
        if v.index in lower_teeth_indices:w=1.0
        if w>0:
            q=p.lerp(pivot+rot@(p-pivot),w)
            shape.data[v.index].co=inv@q;changed+=1
    for index,front_index in zip(cavity_indices,range(2833,2865)):
        shape.data[index].co=shape.data[front_index].co+Vector((0,.018,0))
    shape.value=0
    return head,changed


def action_insert(name,samples):
    action=bpy.data.actions.new(name)
    action.use_fake_user=True
    rig.animation_data.action=action
    for f,sample in enumerate(samples):
        for bone in rig.pose.bones:
            bone.rotation_mode='QUATERNION'
            bone.location,bone.rotation_quaternion,bone.scale=sample[bone.name]
            for channel in ('location','rotation_quaternion','scale'):
                bone.keyframe_insert(channel,frame=f,group=bone.name)
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag=strip.channelbag(slot)
                if bag:
                    for fc in bag.fcurves:
                        for key in fc.keyframe_points:key.interpolation='LINEAR'
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new();track.name=name
    track.strips.new(name,0,action);track.mute=True
    return action


def add_bend_shapes():
    """Knee crease and trouser drape; neutral surfaces and shared rims stay fixed.

    Knee flexion folds soft tissue and trouser fabric at the back of the joint.
    Body relief is restricted to the rear crease. Front trouser fabric receives
    a small outward allowance at flexion, retaining the kneecap and limb volume.
    Vertex weights, topology, and coordinates coincident with cut caps remain.
    """
    owners={}
    for obj in bpy.data.objects:
        if obj.type=='MESH' and obj.name.startswith('Z_'):
            for v in obj.data.vertices:
                owners.setdefault(tuple(round(x,6) for x in v.co),set()).add(obj.name)
    result={}
    for name in ('Z_Thigh_L','Z_Thigh_R','Z_Shin_L','Z_Shin_R'):
        obj=bpy.data.objects[name]
        obj.shape_key_add(name='Basis');key=obj.shape_key_add(name='BendRelief')
        materials=[set() for _ in obj.data.vertices]
        for poly in obj.data.polygons:
            m=obj.data.materials[poly.material_index].name
            for index in poly.vertices:materials[index].add(m)
        changed=[];protected=0
        knee=rest[('Left' if name.endswith('_L') else 'Right')+'Leg'].translation.z
        for v in obj.data.vertices:
            p=v.co;shared=len(owners[tuple(round(x,6) for x in p)])>1
            if shared:protected+=1;continue
            rear=smooth((p.y-.025)/.05)
            cloth=materials[v.index] and all('Zombie.Cloth.' in m for m in materials[v.index])
            skin=materials[v.index]=={'Zombie.Body.PBR'}
            if not (cloth or skin):continue
            if name.startswith('Z_Shin_'):
                crease=smooth((p.z-.375)/.07)*smooth((knee-p.z)/.027)
                amount=(.036 if skin else .020)*rear*crease
            else:
                crease=smooth((p.z-knee)/.040)*(1-smooth((p.z-.585)/.080))
                amount=(.040 if skin else .023)*rear*crease
            delta=Vector((0,-amount,0))
            if cloth:
                front=smooth((.008-p.y)/.065)
                if name.startswith('Z_Shin_'):
                    front_band=smooth((p.z-.37)/.07)*smooth((knee-p.z)/.030)
                    delta.y-=.016*front*front_band
                else:
                    front_band=smooth((p.z-knee)/.012)*(1-smooth((p.z-.58)/.08))
                    delta.y-=.017*front*front_band
                    outer=smooth((abs(p.x)-.16)/.045)*smooth((p.z-.59)/.10)*(1-smooth((p.z-.84)/.12))
                    delta.x+=(1 if p.x>0 else -1)*.006*outer
            if delta.length>1e-6:
                key.data[v.index].co+=delta
                changed.append({'vertex':v.index,'rear_crease_relief_m':amount,'delta_m':list(delta),'materials':sorted(materials[v.index])})
        key.value=0.0
        result[name]={'action_prefix':'Bend.'+name+'.','shape_keys':['BendRelief'],'changed_vertices':len(changed),
                      'shared_vertices_protected':protected,'maximum_rear_crease_relief_m':max((r['rear_crease_relief_m'] for r in changed),default=0),
                      'changes':changed}
    return result


def knee_relief_value(prefix):
    a=rig.pose.bones[prefix+'UpLeg'].head;b=rig.pose.bones[prefix+'Leg'].head;c=rig.pose.bones[prefix+'Foot'].head
    degrees=math.degrees((b-a).angle(c-b))
    return smooth((degrees-45)/40)


def add_slam_shape():
    """A local pose corrective for cloth drape and the soft underarm crease.

    The shoulder panels receive a little lateral room during the two-hand slam.
    A submillimeter folded skin edge receives a smooth, localized contour repair.
    Neither the neutral mesh nor its skin weights or shared cut rims are edited.
    """
    obj=bpy.data.objects['Z_Torso']
    obj.shape_key_add(name='Basis');key=obj.shape_key_add(name='SlamDrape')
    materials=[set() for _ in obj.data.vertices]
    for poly in obj.data.polygons:
        for index in poly.vertices:materials[index].add(obj.data.materials[poly.material_index].name)
    shared=set()
    coordinates={tuple(round(x,6) for x in v.co) for v in obj.data.vertices}
    for other in bpy.data.objects:
        if other!=obj and other.type=='MESH' and other.name.startswith('Z_'):
            shared.update(coordinates & {tuple(round(x,6) for x in v.co) for v in other.data.vertices})
    # The evaluated crease shows one 0.72 mm edge inversion at the early slam.
    # Unfold it along the surrounding surface normal, then map that small pose
    # displacement back through the vertex's actual linear skinning Jacobian.
    pose('both',37,96)
    ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh()
    b=[ev.matrix_world@mesh.vertices[i].co for i in (1326,136,1499)]
    outward=(b[1]-b[0]).cross(b[2]-b[0]).normalized()
    ev.to_mesh_clear()
    vertex=obj.data.vertices[1475]
    jacobian=Matrix(((0,0,0),(0,0,0),(0,0,0)))
    for group in vertex.groups:
        bone=obj.vertex_groups[group.group].name
        if bone in rest:jacobian+=(rig.pose.bones[bone].matrix@rest[bone].inverted()).to_3x3()*group.weight
    crease_delta=jacobian.inverted()@(-outward*.0018)
    crease_center=vertex.co.copy();collar_center=Vector((-.148865819,-.017618403,1.501822472))
    # Form the collar allowance along its posed outward surface direction,
    # rather than stretching the rest mesh along an arbitrary global axis.
    pose('both',42,96)
    ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh()
    skin=[ev.matrix_world@mesh.vertices[i].co for i in (660,661,662)]
    cloth=ev.matrix_world@mesh.vertices[1050].co
    normal=(skin[1]-skin[0]).cross(skin[2]-skin[0]).normalized()
    clearance=(cloth-skin[0]).dot(normal)
    ev.to_mesh_clear()
    jacobian=Matrix(((0,0,0),(0,0,0),(0,0,0)))
    for group in obj.data.vertices[1050].groups:
        bone=obj.vertex_groups[group.group].name
        if bone in rest:jacobian+=(rig.pose.bones[bone].matrix@rest[bone].inverted()).to_3x3()*group.weight
    collar_delta=jacobian.inverted()@(normal*(.0025-clearance))
    changed=[]
    for v in obj.data.vertices:
        if tuple(round(x,6) for x in v.co) in shared:continue
        delta=Vector((0,0,0))
        if materials[v.index] and all('Zombie.Cloth.' in m for m in materials[v.index]):
            d=v.co-collar_center
            w=math.exp(-((d.x/.034)**2+(d.y/.045)**2+(d.z/.036)**2))
            delta+=collar_delta*w
        elif materials[v.index]=={'Zombie.Body.PBR'}:
            w=1-smooth((v.co-crease_center).length/.012)
            delta+=crease_delta*w
        if delta.length>1e-6:
            key.data[v.index].co+=delta
            changed.append({'vertex':v.index,'delta_m':list(delta),'materials':sorted(materials[v.index])})
    key.value=0.0
    return obj,{'action_prefix':'Slam.Z_Torso.','shape_keys':['SlamDrape'],'changed_vertices':len(changed),
                'maximum_bind_displacement_m':max((Vector(r['delta_m']).length for r in changed),default=0),
                'underarm_pose_displacement_m':.0018,'shared_cut_vertices_unchanged':True,'changes':changed}


def slam_drape_value(kind,frame,end):
    return curve(frame,[(0,0),(29,0),(35,1),(49,1),(58,0),(96,0)]) if kind=='both' else 0.0


def add_left_drape_shape():
    """Give the front collar one millimeter of local folding allowance.

    The left strike raises the clavicle while the neck stays aimed at its target.
    Ten cloth vertices need a small downward allowance to retain the collar face
    area through that motion. Bone paths, skin, neutral vertices and cut rims stay
    untouched; the key is zero in all other clips.
    """
    obj=bpy.data.objects['Z_Torso'];key=obj.shape_key_add(name='LeftDrape')
    materials=[set() for _ in obj.data.vertices]
    for poly in obj.data.polygons:
        for index in poly.vertices:materials[index].add(obj.data.materials[poly.material_index].name)
    coordinates={tuple(round(x,6) for x in v.co) for v in obj.data.vertices};shared=set()
    for other in bpy.data.objects:
        if other!=obj and other.type=='MESH' and other.name.startswith('Z_'):
            shared.update(coordinates & {tuple(round(x,6) for x in v.co) for v in other.data.vertices})
    center=obj.data.vertices[388].co.copy();changed=[]
    for vertex in obj.data.vertices:
        if tuple(round(x,6) for x in vertex.co) in shared:continue
        if not materials[vertex.index] or not all(x.startswith('Zombie.Cloth.') for x in materials[vertex.index]):continue
        weight=1-smooth((vertex.co-center).length/.025)
        delta=Vector((0,0,-.001*weight))
        if delta.length>1e-9:
            key.data[vertex.index].co+=delta
            changed.append({'vertex':vertex.index,'delta_m':list(delta)})
    key.value=0.0
    return {'shape_key':'LeftDrape','changed_vertices':len(changed),'maximum_bind_displacement_m':.001,
            'influence_radius_m':.025,'shared_cut_vertices_unchanged':True,'changes':changed}


def left_drape_value(kind,frame,end):
    return curve(frame,[(0,0),(24,0),(29,1),(48,1),(58,0),(78,0)]) if kind=='left' else 0.0


def insert_bend_action(obj,name,values,shape_name='BendRelief',action_prefix=None,additional_values=None):
    keys=obj.data.shape_keys;keys.animation_data_create()
    action=bpy.data.actions.new((action_prefix or 'Bend.'+obj.name+'.')+name);action.use_fake_user=True
    keys.animation_data.action=action
    channels={shape_name:values};channels.update(additional_values or {})
    for name_of_shape,shape_values in channels.items():
        for frame,value in enumerate(shape_values):
            keys.key_blocks[name_of_shape].value=value
            keys.key_blocks[name_of_shape].keyframe_insert('value',frame=frame,group=name_of_shape)
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag=strip.channelbag(slot)
                if bag:
                    for fc in bag.fcurves:
                        for key in fc.keyframe_points:key.interpolation='LINEAR'
    keys.animation_data.action=None
    tr=keys.animation_data.nla_tracks.new();tr.name=name;tr.strips.new(name,0,action);tr.mute=True


def jaw_value(kind,frame,end):
    if kind=='bite':return curve(frame,[(0,0),(9,.05),(18,.35),(27,1),(32,1),(36,.08),(42,.12),(50,.0),(81,0)])
    if kind=='crawl_bite':return curve(frame,[(0,0),(8,.08),(20,1),(26,1),(30,.05),(34,.15),(40,0),(72,0)])
    return 0.0


def insert_jaw_action(head,name,kind,end):
    keys=head.data.shape_keys
    keys.animation_data_create()
    action=bpy.data.actions.new('Jaw.'+name);action.use_fake_user=True
    keys.animation_data.action=action
    for f in range(end+1):
        keys.key_blocks['BiteOpen'].value=jaw_value(kind,f,end)
        keys.key_blocks['BiteOpen'].keyframe_insert('value',frame=f,group='Mouth')
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag=strip.channelbag(slot)
                if bag:
                    for fc in bag.fcurves:
                        for key in fc.keyframe_points:key.interpolation='LINEAR'
    keys.animation_data.action=None
    tr=keys.animation_data.nla_tracks.new();tr.name=name
    tr.strips.new(name,0,action);tr.mute=True


def export_glb(destination):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.data.objects:
        if obj==rig or (obj.type=='MESH' and obj.name.startswith('Z_')):
            obj.hide_set(False);obj.hide_render=False;obj.hide_viewport=False;obj.select_set(True)
    bpy.context.view_layer.objects.active=rig
    rig.animation_data.action=None
    for tr in rig.animation_data.nla_tracks:tr.mute=False
    for obj in bpy.data.objects:
        if obj.type=='MESH' and obj.name.startswith('Z_') and obj.data.shape_keys:
            keys=obj.data.shape_keys;keys.animation_data.action=None
            for tr in keys.animation_data.nla_tracks:tr.mute=False
            for key in keys.key_blocks:
                if key.name!='Basis':key.value=0.0
    reset_pose()
    bpy.ops.export_scene.gltf(filepath=str(destination),export_format='GLB',use_selection=True,
        export_animations=True,export_animation_mode='NLA_TRACKS',export_frame_range=False,
        export_force_sampling=True,export_anim_single_armature=True,export_skins=True,
        export_all_influences=False,export_def_bones=False,export_morph=True,
        export_morph_normal=True,export_extras=True,export_yup=True,
        export_materials='EXPORT',export_image_format='AUTO',export_cameras=False,export_lights=False)


report={'input_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'author_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'base_action_digests':BASE_DIGESTS,
        'bone_count':len(rig.data.bones),'actions':{},'notes':['Numeric sweep measures bone geometry; visual contact and fabric checks are separate.']}
head,mouth_vertices=add_mouth_shape()
bend_shapes=add_bend_shapes()
torso,slam_shape=add_slam_shape()
left_shape=add_left_drape_shape()
report['bend_correctives']=bend_shapes
report['slam_corrective']=slam_shape
report['left_collar_corrective']=left_shape
report['mouth_shape_changed_vertices']=mouth_vertices
for name,end,kind in NEW_CLIPS:
    samples=[];scales=0.0;elbow_min=180.;elbow_max=0.;bone_error=0.;leg_error=0.;knee_min=180.;knee_max=0.;finite=True
    bend_samples={'Left':[],'Right':[]}
    for f in range(end+1):
        pose(kind,f,end)
        for prefix in ('Left','Right'):bend_samples[prefix].append(knee_relief_value(prefix))
        sample={}
        for bone in rig.pose.bones:
            q=bone.rotation_quaternion.copy() if bone.rotation_mode=='QUATERNION' else bone.rotation_euler.to_quaternion()
            if samples and q.dot(samples[-1][bone.name][1])<0:q.negate()
            sample[bone.name]=(bone.location.copy(),q,bone.scale.copy())
            scales=max(scales,max(abs(s-1) for s in bone.scale))
            finite=finite and all(math.isfinite(x) for row in bone.matrix for x in row)
        for p in ('Left','Right'):
            a=rig.pose.bones[p+'Arm'].head;b=rig.pose.bones[p+'ForeArm'].head;c=rig.pose.bones[p+'Hand'].head
            angle=math.degrees((b-a).angle(c-b));elbow_min=min(elbow_min,angle);elbow_max=max(elbow_max,angle)
            bone_error=max(bone_error,abs((b-a).length-length[p+'Arm']),abs((c-b).length-length[p+'ForeArm']))
            a=rig.pose.bones[p+'UpLeg'].head;b=rig.pose.bones[p+'Leg'].head;c=rig.pose.bones[p+'Foot'].head
            angle=math.degrees((b-a).angle(c-b));knee_min=min(knee_min,angle);knee_max=max(knee_max,angle)
            leg_error=max(leg_error,abs((b-a).length-length[p+'UpLeg']),abs((c-b).length-length[p+'Leg']))
        samples.append(sample)
    action_insert(name,samples)
    insert_jaw_action(head,name,kind,end)
    for obj_name in bend_shapes:
        insert_bend_action(bpy.data.objects[obj_name],name,bend_samples['Left' if obj_name.endswith('_L') else 'Right'])
    insert_bend_action(torso,name,[slam_drape_value(kind,f,end) for f in range(end+1)],'SlamDrape',slam_shape['action_prefix'],
                       {'LeftDrape':[left_drape_value(kind,f,end) for f in range(end+1)]})
    report['actions'][name]={'frames_inclusive':end+1,'finite_transforms':finite,
        'maximum_local_scale_error':scales,'maximum_arm_segment_length_error_m':bone_error,
        'elbow_flexion_degrees':[elbow_min,elbow_max],'maximum_leg_segment_length_error_m':leg_error,
        'knee_flexion_degrees':[knee_min,knee_max]}
    if not finite or scales>1e-4 or bone_error>1e-4 or leg_error>1e-4:raise RuntimeError('Invalid skeleton pose: '+name)
    print('AUTHORED',name,end+1,'arm error',round(bone_error,8),'elbows',round(elbow_min,2),round(elbow_max,2),flush=True)
for name,end in [('Zombie_Idle',180),('Zombie_Walk',84),('Zombie_Attack',96),('Zombie_Hit',36)]:
    insert_jaw_action(head,name,'none',end)
    for obj_name in bend_shapes:insert_bend_action(bpy.data.objects[obj_name],name,[0.0]*(end+1))
    insert_bend_action(torso,name,[0.0]*(end+1),'SlamDrape',slam_shape['action_prefix'],{'LeftDrape':[0.0]*(end+1)})
    if fcurve_digest(bpy.data.actions[name])!=BASE_DIGESTS[name]:raise RuntimeError('Preserved base action changed: '+name)
report['base_actions_preserved_exactly']=True
mesh_counts={}
for obj in bpy.data.objects:
    if obj.type=='MESH' and obj.name.startswith('Z_'):
        obj.data.calc_loop_triangles();mesh_counts[obj.name]=len(obj.data.loop_triangles)
report['triangles_including_caps']=sum(mesh_counts.values())
if report['triangles_including_caps']>=15000 or len(rig.data.bones)!=59:raise RuntimeError('Asset budget or skeleton count changed')
contract=json.loads((ROOT/'assets/Zombie.r4.contract.json').read_text())
behavior=json.loads((ROOT/'assets/Zombie.r4.behavior.json').read_text())
for name,row in behavior['actions'].items():contract['animations'][name]=row
contract['model']='Zombie.r4.glb';contract['behavior_expansion']=1
contract['mesh_triangles']=mesh_counts;contract['triangles_including_hidden_caps']=sum(mesh_counts.values())
contract['mouth_articulation']={'shape_key':'BiteOpen','bone_count_unchanged':59,'maximum_jaw_open_degrees':12,'changed_vertices':mouth_vertices,'interior_teeth_added_triangles':96,'cavity_depth_m':.018}
behavior['status']='authored'
behavior['ladder']['initial_foot_rung_heights_m']={'left':.3,'right':0.0}
behavior['ladder'].update({'rung_height_m':.036,'rung_depth_m':.040,'hand_stance_fraction':.6,'foot_stance_fraction':.425,'foot_clearance_above_rung_top_m':.004,
  'initial_foot_support':{'left':'planted','right':'recovering from the ground rung'},'rung_heights_are':'Rung centerlines; soles rest18mm above them plus4mm clearance.'})
behavior['mouth']['max_open_degrees']=12
behavior['morph_actions']={'Z_Head':{'action_prefix':'Jaw.','shape_keys':['BiteOpen']}}
for obj_name,row in bend_shapes.items():behavior['morph_actions'][obj_name]={k:row[k] for k in ('action_prefix','shape_keys')}
behavior['morph_actions']['Z_Torso']={'action_prefix':slam_shape['action_prefix'],'shape_keys':['SlamDrape','LeftDrape']}
behavior['slam_corrective']={'shape_key':'SlamDrape','active_only_in':'Zombie_Attack_Both','neutral_geometry_unchanged':True,
  'skin_weights_unchanged':True,'shared_cut_and_cap_vertices_unchanged':True,
  'description':'Local collar drape allowance and a small soft underarm crease correction during the two-hand slam; zero in every other clip.'}
behavior['left_collar_corrective']={'shape_key':'LeftDrape','active_only_in':'Zombie_Attack_Left','neutral_geometry_unchanged':True,
  'skin_weights_unchanged':True,'shared_cut_and_cap_vertices_unchanged':True,'maximum_bind_displacement_m':.001,
  'description':'One millimeter of downward allowance over ten front-collar cloth vertices preserves the fold during the left clavicle lift; zero in every other clip.'}
behavior['knee_corrective']={'shape_key':'BendRelief','active_only_in_new_actions':True,'neutral_geometry_unchanged':True,
  'skin_weights_unchanged':True,'shared_cut_and_cap_vertices_unchanged':True,'front_kneecap_and_body_shafts_unchanged':True,
  'description':'Local rear-knee fold relief and outward trouser allowance during deep flexion. Smoother crease formation preserves the neutral leg and garment shape and maintains body volume.'}
behavior['contact_regions']={'mouth':{'mesh_name':'Z_Head','bind_min_godot_m':[-.027,1.597,.098],'bind_max_godot_m':[.027,1.624,.122],
    'description':'Authored lip and dental surfaces in mesh bind-local coordinates. Filter before skinning, then include current BiteOpen deformation and bone transform.'}}
for tr in rig.animation_data.nla_tracks:tr.mute=True
for obj in bpy.data.objects:
    if obj.type=='MESH' and obj.name.startswith('Z_') and obj.data.shape_keys:
        keys=obj.data.shape_keys;keys.animation_data.action=None
        for tr in keys.animation_data.nla_tracks:tr.mute=True
        for key in keys.key_blocks:
            if key.name!='Basis':key.value=0.0
rig.animation_data.action=bpy.data.actions['Zombie_Idle'];rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_start=0;scene.frame_end=180;scene.frame_set(0)
for obj in bpy.data.objects:
    if obj.name.startswith('Z_Cap_'):obj.hide_set(True);obj.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source/Zombie.r4.blend'))
export_glb(ROOT/'assets/Zombie.r4.glb')
report['output_blend_sha256']=hashlib.sha256((ROOT/'source/Zombie.r4.blend').read_bytes()).hexdigest()
report['output_glb_sha256']=hashlib.sha256((ROOT/'assets/Zombie.r4.glb').read_bytes()).hexdigest()
behavior['model_sha256']=report['output_glb_sha256'];behavior['source_blend_sha256']=report['output_blend_sha256']
contract['source_sha256']=report['output_blend_sha256']
contract['source_blend_sha256']=report['output_blend_sha256']
contract['model_sha256']=report['output_glb_sha256']
contract['base_source_blend_sha256']=report['input_sha256']
contract['behavior_manifest']='Zombie.r4.behavior.json'
contract['morph_actions']=behavior['morph_actions']
contract['knee_corrective']=behavior['knee_corrective']
contract['slam_corrective']=behavior['slam_corrective']
contract['left_collar_corrective']=behavior['left_collar_corrective']
(ROOT/'assets/Zombie.r4.contract.json').write_text(json.dumps(contract,indent=2)+'\n')
(ROOT/'assets/Zombie.r4.behavior.json').write_text(json.dumps(behavior,indent=2)+'\n')
(ROOT/'source/behavior_authoring_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('R4_BEHAVIORS_EXPORTED',json.dumps({'model':report['output_glb_sha256'],'blend':report['output_blend_sha256'],'triangles':report['triangles_including_caps']}),flush=True)


