# SPDX-License-Identifier: CC0-1.0
"""First-person motion design, in Human R11's Blender metre coordinate space."""
import math
from mathutils import Matrix, Quaternion, Vector

FPS = 60


def rigid(columns, origin):
    result = Matrix(columns).transposed().to_4x4()
    result.translation = Vector(origin)
    return result


# Anatomical palms fit around the existing pistol; no source bone/rest edits.
RIGHT_HAND_IN_ITEM = Matrix(((0.18005681037902832, -0.10395585000514984, 0.9781476259231567, 0.047514673322439194), (0.5, 0.8660253882408142, 0.0, -0.16687151789665222), (-0.8471006751060486, 0.48907381296157837, 0.20791170001029968, -0.06487691402435303), (0.0, 0.0, 0.0, 1.0)))
LEFT_SUPPORT_IN_ITEM = Matrix(((-.2113091309,.4531538935,-.8660254038,-.0955525935),
                               (-.3659981508,.7848855672,.5,-.1201036200),
                               (.9063077870,.4226182617,0,-.0898765624),(0,0,0,1)))
LEFT_MAGAZINE_IN_ITEM = Matrix(((0,0,-1,-.037),(-.9063077870,.4226182617,0,-.13587657),
                                (.4226182617,.9063077870,0,-.17872095),(0,0,0,1)))

# The palm rolls -12 degrees about the Middle MCP and moves +6 mm in item X.
# Measured pad/cap clearance determines the shared three-finger wrap.
RIGHT_GRIP = {'Index': (-21.835033606737852, -6.514067295007408, -0.4242557375691831), 'Middle': (10, 70, 12.5), 'Ring': (25, 80, 5), 'Pinky': (25, 55, 20), 'Thumb': (8, 18, 10)}
RIGHT_GRIP_SPLAY = {'Middle': -17.5, 'Ring': -22.5, 'Pinky': -17.5}
RIGHT_INDEX_TRIGGER = (-28.873482224081723, 27.576209973920353, 58.56606597699832)
RIGHT_INDEX_SPLAY = {'indexed': -6.59261095189504, 'trigger': -20.75075874873146}
RIGHT_INDEX_WAYPOINT = (-35, 10.531071339456473, 29.070905119714567, -13.67168485031325)
# Keep the resting thumb high along the upper frame. The lower exterior route
# cleared the weapon but stretched the thenar web; this reviewed route preserves
# that clearance while keeping the thumb base continuous with the palm.
RIGHT_THUMB_HOLD = ((-0.6442614793777466, 0.2570604681968689, 0.720310389995575), (-0.621638834476471, 0.6614918112754822, 0.41951605677604675), (-0.5380082726478577, 0.7518506646156311, 0.38113999366760254))
RIGHT_THUMB_MAGAZINE = ((-0.9665349125862122, 0.05019093304872513, 0.25157731771469116), (-0.4964365065097809, 0.8273941874504089, 0.2626207768917084), (-0.15631058812141418, 0.9749283790588379, -0.15837183594703674))
RIGHT_THUMB_SLIDE_TOUCH = ((-0.6442614793777466, 0.2570604681968689, 0.720310389995575), (-0.621638834476471, 0.6614918112754822, 0.41951605677604675), (-0.5380082726478577, 0.7518506646156311, 0.38113999366760254))
RIGHT_THUMB_SLIDE_PRESS = ((-0.7343705892562866, 0.2036290019750595, 0.6474836468696594), (-0.5905128717422485, 0.666788637638092, 0.45462891459465027), (-0.432950496673584, 0.7138884663581848, 0.5503790378570557))
LEFT_GRIP = {'Index': (54, 58, 26), 'Middle': (56, 62, 30), 'Ring': (60, 64, 30),
             'Pinky': (64, 66, 32), 'Thumb': (8, 18, 10)}


def right_index_pose(mix):
    """Lift the index away from the frame before curling into the guard.

    The midpoint controls only the pose path; existing action timing remains.
    """
    mix = max(0.0, min(1.0, mix))
    start = (*RIGHT_GRIP['Index'], RIGHT_INDEX_SPLAY['indexed'])
    end = (*RIGHT_INDEX_TRIGGER, RIGHT_INDEX_SPLAY['trigger'])
    values = tuple(a + (b-a)*mix + 4*mix*(1-mix)*(w-(a+b)/2)
                   for a, b, w in zip(start, end, RIGHT_INDEX_WAYPOINT))
    return values[:3], values[3]


def transform(origin, pitch=0, roll=0, yaw=0):
    # Canonical weapon is +Y forward. Human R11 looks -Y.
    q = (Quaternion((0, 0, 1), math.radians(180 + yaw))
         @ Quaternion((1, 0, 0), math.radians(pitch))
         @ Quaternion((0, 1, 0), math.radians(roll)))
    return Matrix.LocRotScale(Vector(origin), q, Vector((1, 1, 1)))


def idle_transform():
    return transform((-.12, -.40, 1.475), pitch=2, roll=-4, yaw=5)


IDLE = (-.12, -.40, 1.475, 2, -4, 5)
AIM = (0, -.45, 1.571, 0, 0, 0)
LOW = (-.22, -.20, 1.15, -50, -12, 20)
WORK = (-.035, -.43, 1.60, 5, 25, 25)
LEFT_OPEN = {'Index': (0, 4, 3), 'Middle': (8, 12, 6), 'Ring': (12, 17, 8),
             'Pinky': (17, 23, 10), 'Thumb': (5, 9, 5)}
LEFT_MAG_GRIP = {'Index': (48, 66, 24), 'Middle': (52, 64, 28),
                 'Ring': (54, 62, 28), 'Pinky': (57, 60, 25), 'Thumb': (8, 20, 12)}
LEFT_SLIDE_GRIP = {'Index': (0, 65, 10), 'Middle': (-5, 77, 10),
                   'Ring': (0, 60, 15), 'Pinky': (-10, 20, 30), 'Thumb': (6, 12, 8)}
LEFT_RACK_OPEN = {'Index': (-25, 8, 4), 'Middle': (-25, 8, 4),
                  'Ring': (-25, 12, 5), 'Pinky': (-35, 5, 5), 'Thumb': (6, 12, 8)}
# The hand turns across the rear slide so all four fingers wrap the near
# face together. The thumb bends down along the opposite exterior instead
# of hovering forward beside a misplaced little finger. Closure remains
# independent of wrist travel and the returning slide.
LEFT_SLIDE_IN_ITEM = (Quaternion((0,0,1), math.radians(-80))
                      @ Quaternion((0,1,0), math.radians(15))).to_matrix().to_4x4()
LEFT_SLIDE_IN_ITEM.translation = Vector((-.112,-.125,.108))
# Lower the thumb metacarpal and let the two phalanges follow a soft curve.
# This reduces the pinched thumb web while keeping its pad on the far side.
LEFT_RACK_THUMB_CLOSED = ((.8,.25,-.5),(.10,.95,-.05),(-.12,.98,-.12))
LEFT_RACK_THUMB_OPEN = ((.8,.3,.15),(0,1,.12),(0,1,.08))
# The release opens from the held grasp with the thumb base below the
# fingers, retaining a rounded web instead of swinging the base inward.
# Approach and held-grasp directions remain unchanged.
LEFT_RACK_THUMB_RELEASE = ((.85,.05,-.5),(.35,.9,-.15),(.08,.97,-.22))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t*t*(3-2*t)


def curve(keys, frame):
    """Shape-preserving cubic Hermite interpolation, with zero end tangents."""
    scalar = isinstance(keys[0][1], (float, int))
    values = [[float(v)] if scalar else list(v) for _, v in keys]
    if frame <= keys[0][0]:
        result = values[0]
    elif frame >= keys[-1][0]:
        result = values[-1]
    else:
        def tangent(i, c):
            if i == 0 or i == len(keys)-1:
                return 0.0
            a = (values[i][c]-values[i-1][c])/(keys[i][0]-keys[i-1][0])
            b = (values[i+1][c]-values[i][c])/(keys[i+1][0]-keys[i][0])
            return 2*a*b/(a+b) if a*b > 0 else 0.0
        i = next(i for i in range(len(keys)-1) if keys[i][0] <= frame <= keys[i+1][0])
        dt = keys[i+1][0]-keys[i][0]
        t = (frame-keys[i][0])/dt
        result = [(2*t**3-3*t*t+1)*values[i][c] + (t**3-2*t*t+t)*dt*tangent(i,c)
                  +(-2*t**3+3*t*t)*values[i+1][c] + (t**3-t*t)*dt*tangent(i+1,c)
                  for c in range(len(values[0]))]
    return result[0] if scalar else result


def pose_matrix(values):
    return transform(values[:3], pitch=values[3], roll=values[4], yaw=values[5])


def mix_matrix(a, b, weight):
    weight = max(0.0, min(1.0, weight))
    return Matrix.LocRotScale(a.translation.lerp(b.translation, weight),
                             a.to_quaternion().slerp(b.to_quaternion(), weight),
                             Vector((1, 1, 1)))


def blend_fingers(a, b, t):
    return {name: tuple(x+(y-x)*t for x,y in zip(a[name],b[name])) for name in a}


def loose_left():
    result = LEFT_SUPPORT_IN_ITEM.copy()
    result = idle_transform() @ result
    result.translation = Vector((.24, -.22, 1.285))
    return result


def arm_pole(side, wrist_matrix, forearm_length, neutral_mix=.15):
    """Favor a relaxed wrist while keeping the elbow on its anatomical side."""
    hand_y = wrist_matrix.to_quaternion() @ Vector((0,1,0))
    neutral = Vector(((-1 if side=='Right' else 1)*.38,-.08,1.22))
    return (wrist_matrix.translation-hand_y*forearm_length).lerp(neutral,neutral_mix)


def rack_clearance(frame):
    """Smooth exterior approach/withdrawal; contact frames retain zero offset."""
    if 5 < frame < 22:
        t = (frame-5)/17
        travel = LEFT_SLIDE_IN_ITEM.translation-LEFT_SUPPORT_IN_ITEM.translation
    elif 40 < frame < 60:
        t = (frame-40)/20
        travel = LEFT_SUPPORT_IN_ITEM.translation-(LEFT_SLIDE_IN_ITEM.translation+Vector((0,-.034,0)))
    else:
        return Vector((0,0,0))
    bell = math.sin(math.pi*t)**2
    # The asymmetric component eases vertical departure and arrival. The
    # extra 8 mm exterior arc clears the longer fingertips between authored
    # keys while retaining the shared, ordinary finger-opening schedule.
    return (Vector((-.098,-.045,0))*bell
            + travel*((3/(math.pi*math.pi))*bell*(2*t-1)))


def evaluate(action, frame):
    """One deterministic authored sample. Events live in the companion definition."""
    data = list(IDLE)
    if action.startswith('aim_'):
        data = list(AIM)
    if action in ('idle', 'idle_empty', 'aim_idle', 'aim_idle_empty'):
        phase = 2*math.pi*frame/120
        amount = .00065 if action.startswith('aim_') else .0015
        data[0] += amount*math.sin(phase)
        data[2] += amount*.65*math.sin(2*phase)
        data[4] += (.09 if action.startswith('aim_') else .22)*math.sin(phase)
    elif action in ('walk','run'):
        phase = 2*math.pi*frame/(72 if action=='walk' else 48)
        strength = 1.0 if action=='walk' else 2.4
        data[0] += .004*strength*math.sin(phase)
        data[1] += .003*strength*math.sin(2*phase)
        data[2] -= .005*strength*(1-math.cos(2*phase))
        data[3] -= .65*strength*(1-math.cos(2*phase))
        data[4] += .7*strength*math.sin(phase)
    elif action=='jump':
        d=curve([(0,(0,0,0)),(7,(.015,-.014,-3)),(18,(-.014,.025,2)),
                 (31,(.008,.013,1)),(38,(.025,-.025,-4)),(49,(-.004,.005,.8)),(60,(0,0,0))],frame)
        data[1]+=d[0]; data[2]+=d[1]; data[3]+=d[2]
    elif action=='equip':
        data=curve([(0,LOW),(11,(-.19,-.255,1.315,-26,-11,12)),
                    (26,(-.125,-.39,1.48,3.3,-3,5)),(34,(-.12,-.402,1.479,2.6,-4,5)),(42,IDLE)],frame)
    elif action=='holster':
        data=curve([(0,IDLE),(8,(-.13,-.385,1.468,0,-6,6)),
                    (22,(-.19,-.255,1.315,-26,-11,12)),(36,LOW)],frame)
    elif action=='inspect':
        data=curve([(0,IDLE),(28,(-.045,-.42,1.56,8,-28,-18)),
                    (57,(-.035,-.42,1.575,12,-38,-35)),(88,(-.035,-.42,1.575,12,-38,-35)),
                    (120,(.025,-.43,1.57,8,24,32)),(158,(.025,-.43,1.57,8,24,32)),
                    (190,(-.055,-.42,1.55,5,-10,12)),(218,IDLE),(240,IDLE)],frame)
    elif action=='aim_in':
        data=curve([(0,IDLE),(18,AIM)],frame)
    elif action=='aim_out':
        data=curve([(0,AIM),(18,IDLE)],frame)
    elif action in ('reload','reload_empty'):
        end=168 if action=='reload' else 192
        data=curve([(0,IDLE),(20,WORK),(44,WORK),(84,(-.03,-.42,1.61,7,27,24)),
                    (112,WORK),(124,(-.037,-.427,1.603,5,25,25)),
                    (end-20,IDLE),(end,IDLE)],frame)
    elif action=='rack':
        data=curve([(0,IDLE),(18,(-.04,-.47,1.565,8,-18,-32)),
                    (35,(-.04,-.47,1.565,8,-18,-32)),(45,(-.042,-.474,1.563,7,-16,-30)),
                    (64,IDLE),(72,IDLE)],frame)

    firing=action in ('fire','fire_last','aim_fire','aim_fire_last')
    last=action in ('fire_last','aim_fire_last')
    if firing:
        r=curve([(0,(0,0,0)),(3,(0,0,0)),(4,(.003,.002,1.0)),
                 (6,(.024,.008,8.5)),(9,(.015,.004,5.5)),(13,(.004,-.001,-.7)),
                 (18,(.001,.0005,.35)),(24,(0,0,0))],frame)
        data[1]+=r[0]; data[2]+=r[1]; data[3]+=r[2]
        data[4]+=.12*r[2]
    if action=='dry_fire':
        data[3]+=curve([(0,0),(4,0),(6,.3),(10,-.15),(20,0)],frame)
    weapon=pose_matrix(data)
    left=weapon@LEFT_SUPPORT_IN_ITEM
    left_fingers=LEFT_GRIP
    left_kind='support'
    thumb_weights=(1.0,0.0,0.0)
    contact='support'
    grip_weight=1.0
    mag_delta=Matrix.Identity(4)
    slide=-.034 if action in ('idle_empty','aim_idle_empty','reload_empty') else 0.0

    if action=='equip':
        grip_weight=smooth((frame-12)/18)
        left=mix_matrix(loose_left(),left,grip_weight)
        left_fingers=blend_fingers(LEFT_OPEN,LEFT_GRIP,grip_weight)
        thumb_weights=(grip_weight,0.0,0.0)
        if grip_weight<1: contact=None; left_kind='transition'
    elif action=='holster':
        grip_weight=1-smooth((frame-2)/14)
        left=mix_matrix(loose_left(),left,grip_weight)
        left_fingers=blend_fingers(LEFT_OPEN,LEFT_GRIP,grip_weight)
        thumb_weights=(grip_weight,0.0,0.0)
        if grip_weight<1: contact=None; left_kind='transition'
    elif action=='inspect':
        grip_weight=curve([(0,1),(10,1),(30,0),(176,0),(216,1),(240,1)],frame)
        floating=loose_left()
        floating.translation=Vector((.16,-.25,1.365))
        left=mix_matrix(floating,left,grip_weight)
        left_fingers=blend_fingers(LEFT_OPEN,LEFT_GRIP,grip_weight)
        thumb_weights=(grip_weight,0.0,0.0)
        if grip_weight<1: contact=None; left_kind='transition'
    elif action in ('reload','reload_empty'):
        # The support hand owns the magazine throughout the visible exchange.
        # At the low off-screen pouch station, one magazine mesh represents
        # both outgoing and incoming magazines; frame72 is the exchange event.
        station=weapon@LEFT_MAGAZINE_IN_ITEM
        extracted=station.copy()
        extracted.translation += weapon.to_quaternion() @ Vector((0,-.024,-.108))
        pouch=station.copy()
        pouch.translation=Vector((.18,-.12,1.13))
        pouch_q=pouch.to_quaternion()
        pouch_q=(pouch_q@Vector((0,1,0))).rotation_difference(Vector((.1,-.9,-.4)).normalized())@pouch_q
        pouch=Matrix.LocRotScale(pouch.translation,pouch_q,Vector((1,1,1)))
        if frame<=24:
            hand=station
        elif frame<=46:
            hand=mix_matrix(station,extracted,smooth((frame-24)/22))
        elif frame<=64:
            hand=mix_matrix(extracted,pouch,smooth((frame-46)/18))
        elif frame<=78:
            hand=pouch
        elif frame<=98:
            hand=mix_matrix(pouch,extracted,smooth((frame-78)/20))
        elif frame<=112:
            hand=mix_matrix(extracted,station,smooth((frame-98)/14))
        else:
            hand=station
        if 24<frame<112:
            mag_delta=weapon.inverted()@hand@LEFT_MAGAZINE_IN_ITEM.inverted()
        if frame<=24:
            amount=smooth((frame-4)/20)
            left=mix_matrix(left,hand,amount)
            left_fingers=blend_fingers(LEFT_GRIP,LEFT_MAG_GRIP,amount)
            thumb_weights=(1-amount,amount,0.0)
            contact='magazine' if frame==24 else ('support' if frame<=4 else None)
            left_kind='magazine' if amount>.5 else 'support'
        elif frame<=121:
            left=hand
            left_fingers=LEFT_MAG_GRIP
            thumb_weights=(0.0,1.0,0.0)
            left_kind='magazine'; contact='magazine'
        else:
            regrip_end=152 if action=='reload_empty' else 145
            amount=smooth((frame-121)/(regrip_end-121))
            left=mix_matrix(hand,left,amount)
            left_fingers=blend_fingers(LEFT_MAG_GRIP,LEFT_GRIP,amount)
            thumb_weights=(amount,1-amount,0.0)
            left_kind='magazine' if amount<.5 else 'support'
            contact='support' if amount>=1 else None
        if action=='reload_empty':
            slide=-.034*(1-smooth((frame-145)/4))
    elif action=='rack':
        slide=-.034*curve([(0,0),(26,0),(35,1),(40,1),(44,0),(72,0)],frame)
        # After the release marker the support hand leaves the rear station;
        # it does not chase the slide forward while the fingers are releasing.
        hand_slide=slide if frame<=40 else -.034
        slide_shift=Matrix.Translation((0,hand_slide,0))
        station=weapon@slide_shift@LEFT_SLIDE_IN_ITEM
        grip_weight=curve([(0,0),(5,0),(22,1),(40,1),(60,0),(72,0)],frame)
        left=mix_matrix(left,station,grip_weight)
        # Clear the side before turning the palm over the slide. After
        # release, lift away before returning to the support position.
        clearance=rack_clearance(frame)
        left.translation += weapon.to_quaternion() @ Vector(clearance)
        if frame<=15:
            left_fingers=blend_fingers(LEFT_GRIP,LEFT_RACK_OPEN,smooth((frame-10)/5))
        elif frame<=22:
            left_fingers=blend_fingers(LEFT_RACK_OPEN,LEFT_SLIDE_GRIP,smooth((frame-18)/4))
        elif frame<=40:
            left_fingers=LEFT_SLIDE_GRIP
        elif frame<=45:
            left_fingers=blend_fingers(LEFT_SLIDE_GRIP,LEFT_RACK_OPEN,smooth((frame-40)/5))
        else:
            left_fingers=blend_fingers(LEFT_RACK_OPEN,LEFT_GRIP,smooth((frame-48)/6))
        thumb_weights=(1-grip_weight,0.0,grip_weight)
        left_kind='slide' if grip_weight>.5 else 'support'
        contact='slide' if 22<=frame<=40 else ('support' if grip_weight==0 else None)

    trigger=0.0
    if firing:
        slide=curve([(0,0),(4,0),(6,-.034),(9,-.034),(12,(-.034 if last else 0)),(24,(-.034 if last else 0))],frame)
        trigger=curve([(0,0),(3,.75),(4,1),(9,1),(16,0),(24,0)],frame)
    elif action=='dry_fire':
        trigger=curve([(0,0),(5,1),(10,1),(17,0),(20,0)],frame)
    # Index enters the trigger only during a shot/click, then returns indexed.
    index_mix=curve([(0,0),(3,1),(10,1),(20,0),(24,0)],frame) if firing else (
        curve([(0,0),(5,1),(10,1),(18,0),(20,0)],frame) if action=='dry_fire' else 0)
    right_index,index_splay=right_index_pose(index_mix)
    case_visible=firing and 6<=frame<18
    case_time=(frame-6)/60 if case_visible else 0.0
    case_position=((.020+case_time*.80, -.022-case_time*.08, .073+case_time*1.0-3.5*case_time*case_time)
                   if case_visible else (0,-.014,.070))
    return {'weapon_world':weapon,'right_world':weapon@RIGHT_HAND_IN_ITEM,
            'left_world':left,'left_fingers':left_fingers,'left_kind':left_kind,
            'left_contact':contact,'right_index':right_index,'index_splay':index_splay,
            'left_thumb_weights':thumb_weights,
            'left_slide_thumb_close':curve([(0,0),(17,0),(22,1),(40,1),(45,0),(72,0)],frame) if action=='rack' else 1.0,
            'left_slide_thumb_release':1-smooth((frame-52)/6) if action=='rack' and frame>40 else 0.0,
            'magazine_delta':mag_delta,'slide':slide,'trigger':trigger,
            'case_visible':case_visible,'case_position':case_position,'case_time':case_time,
            'torso_yaw':(-2.5 if action in ('reload','reload_empty','rack') else 0)*
                        math.sin(math.pi*min(1,frame/(168 if action=='reload' else 192 if action=='reload_empty' else 72))) if action in ('reload','reload_empty','rack') else 0}


def pose_fingers(solver, item_matrix, right_index=None, left_pose=None, left_kind='support',
                 left_thumb_weights=(1,0,0), release_press=0.0, index_splay=None,
                 slide_touch=0.0, slide_press=0.0, left_slide_thumb_close=1.0,
                 left_slide_thumb_release=0.0):
    solver.finger_pose('Right', RIGHT_GRIP, index_override=right_index)
    for family, degrees in RIGHT_GRIP_SPLAY.items():
        bone=solver.rig.pose.bones['RightHand'+family+'1']
        bone.rotation_quaternion=Quaternion((0,0,1),math.radians(degrees))@bone.rotation_quaternion
    if index_splay is None:
        index_splay=RIGHT_INDEX_SPLAY['indexed']
    index_bone=solver.rig.pose.bones['RightHandIndex1']
    index_bone.rotation_quaternion=Quaternion((0,0,1),math.radians(index_splay))@index_bone.rotation_quaternion
    solver.finger_pose('Left', left_pose or LEFT_GRIP)
    rot = item_matrix.to_quaternion()
    right_dirs=[Vector(base).lerp(Vector(pressed),release_press)
                for base,pressed in zip(RIGHT_THUMB_HOLD,RIGHT_THUMB_MAGAZINE)]
    slide_dirs=[Vector(v) for v in RIGHT_THUMB_SLIDE_TOUCH]
    right_dirs=[base.lerp(touch,slide_touch) for base,touch in zip(right_dirs,slide_dirs)]
    right_dirs=[base.lerp(Vector(pressed),slide_press)
                for base,pressed in zip(right_dirs,RIGHT_THUMB_SLIDE_PRESS)]
    for joint,direction in enumerate(right_dirs,1):
        solver.orient_finger_segment('Right','Thumb',joint,rot@direction,space='ARMATURE')
    stations=[LEFT_SUPPORT_IN_ITEM,LEFT_MAGAZINE_IN_ITEM,LEFT_SLIDE_IN_ITEM]
    directions=[((.60,.50,.62),(.55,.72,.42),(.10,.98,.15)),
                ((.65,.1,.75),(.5,.1,.86),(-.35,.9,-.25)),
                LEFT_RACK_THUMB_CLOSED]
    # Rack thumb rests along the far exterior. Its open pose and finger
    # release precede hand withdrawal; neither follows the returning slide.
    slide_open=LEFT_RACK_THUMB_OPEN
    if left_slide_thumb_release>0:
        slide_open=tuple(Vector(before).lerp(Vector(released),left_slide_thumb_release)
                         for before,released in zip(slide_open,LEFT_RACK_THUMB_RELEASE))
    directions[2]=tuple(Vector(opened).lerp(Vector(closed),left_slide_thumb_close)
                        for opened,closed in zip(slide_open,directions[2]))
    total=sum(left_thumb_weights)
    if total>0:
        for joint in range(3):
            direction=Vector((0,0,0))
            for weight,station,dirs in zip(left_thumb_weights,stations,directions):
                direction+=weight*(station.to_quaternion().inverted()@Vector(dirs[joint]).normalized())
            if direction.length>1e-6:
                solver.orient_finger_segment('Left','Thumb',joint+1,direction,space='HAND',mix=total)

