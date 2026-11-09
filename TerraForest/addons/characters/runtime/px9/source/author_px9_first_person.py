# SPDX-License-Identifier: CC0-1.0
"""Author a portable Human R11 + PX9 first-person animation set using Blender."""
from pathlib import Path
import json
import copy
import math
import sys
import argparse
import hashlib
import struct
import shutil
import bpy
from mathutils import Matrix, Vector, Quaternion

HERE = Path(__file__).resolve().parent
BASE = HERE.parents[1]
sys.path.insert(0, str(HERE))
from human_arm_solver import HumanArmSolver
from export_action_subset import armature_action_subset
from human_hand_weights import apply_hand_patch
import px9_motion as motion

HUMAN = (HERE / 'Human.px9_eclipse.blend' if (HERE / 'Human.px9_eclipse.blend').exists()
         else HERE / 'handoff/TerraForest_PlayerModel_HumanR11/01_Model/Human.r11.blend')
WEAPON = BASE / 'deliverables/PX9_Eclipse_Skeleton_20K_CC0/source/PX9_Eclipse_Skeleton.blend'
OUT = (HERE.parent if (HERE / 'Human.px9_eclipse.blend').exists()
       else BASE / 'deliverables/PX9_Eclipse_FirstPerson_CC0')
PARTS = ['Frame','Slide','Barrel','MuzzleHousing','GuideRod','Magazine','MagazineBase','Trigger',
         'GripPanel_Left','GripPanel_Right','Takedown','SlideStop','MagazineRelease','FramePins',
         'FrontSight','RearSight','EjectedCase']


def setup(source=None):
    bpy.ops.wm.open_mainfile(filepath=str(source or HUMAN), load_ui=False)
    scene = bpy.context.scene
    human = bpy.data.objects['Human_Rig']
    for action in list(bpy.data.actions):
        if action.name.startswith(('FP_PX9_ECLIPSE_','PX9_FP__')):
            bpy.data.actions.remove(action)
    originals = list(bpy.data.actions)
    for action in originals:
        action.use_fake_user = True
    human.animation_data.action = bpy.data.actions['Idle']
    human.animation_data.use_nla = False
    scene.frame_set(1)
    bpy.context.view_layer.update()
    solver = HumanArmSolver(human)
    for obj in list(bpy.data.objects):
        if obj.animation_data:
            obj.animation_data.action = None
            obj.animation_data.use_nla = False
        if obj.type == 'MESH' and obj.data.shape_keys:
            keys = obj.data.shape_keys
            if keys.animation_data:
                keys.animation_data.action = None
                keys.animation_data.use_nla = False
            for key in keys.key_blocks:
                if key.name != 'Basis':
                    key.value = 0
        if obj.type == 'MESH':
            obj.hide_render = obj.name != 'Human_Body'
    if bpy.data.objects.get('WeaponSkeleton') is None:
        collection = bpy.data.collections.new('PX9 — separate weapon rig')
        scene.collection.children.link(collection)
        with bpy.data.libraries.load(str(WEAPON), link=False) as (src, dst):
            dst.objects = [name for name in ['WeaponSkeleton'] + PARTS if name in src.objects]
        for obj in dst.objects:
            collection.objects.link(obj)
    item = bpy.data.objects['WeaponSkeleton']
    for name in PARTS:
        bpy.data.objects[name].hide_render=False
        bpy.data.objects[name].hide_set(False)
    for constraint in list(item.constraints):
        if constraint.name.startswith('Preview — RightHand mount'):
            item.constraints.remove(constraint)
    item.animation_data.action = None
    item.animation_data.use_nla = False
    for bone in item.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.matrix_basis = Matrix.Identity(4)
        if bone.name == 'ejected_case':
            bone.scale = (.0001,) * 3
    item.matrix_world = motion.RIGHT_HAND_IN_ITEM.inverted()
    attachment = item.constraints.new('CHILD_OF')
    attachment.name = 'Preview — RightHand mount'
    attachment.target = human
    attachment.subtarget = 'RightHand'
    attachment.inverse_matrix = Matrix.Identity(4)
    scene.render.fps = 60
    scene.frame_start = 0
    scene.frame_end = 120
    original_body=bpy.data.objects['Human_Body']
    existing=bpy.data.objects.get('Human_FP_Hands')
    if existing:
        bpy.data.objects.remove(existing,do_unlink=True)
    variant=original_body.copy();variant.data=original_body.data.copy()
    variant.name='Human_FP_Hands';variant.data.name='Human_FP_Hands_Mesh'
    scene.collection.objects.link(variant)
    patch=json.loads((HERE/'hand_weight_patch.json').read_text())
    apply_hand_patch(variant,human,patch)
    variant.hide_render=False;variant.hide_set(False)
    original_body.hide_render=True;original_body.hide_set(True)
    return scene, human, item, solver, attachment


def rewrite_glb(path, transform_doc):
    """Edit only JSON metadata/node wrappers; preserve the GLB binary payload."""
    blob=path.read_bytes()
    magic,version,total=struct.unpack_from('<4sII',blob)
    assert magic==b'glTF' and version==2 and total==len(blob)
    offset=12; chunks=[]; document=None
    while offset<len(blob):
        length,kind=struct.unpack_from('<II',blob,offset);offset+=8
        payload=blob[offset:offset+length];offset+=length
        if kind==0x4E4F534A: document=json.loads(payload)
        else: chunks.append((kind,payload))
    transform_doc(document)
    payload=json.dumps(document,ensure_ascii=False,separators=(',',':')).encode('utf-8')
    payload+=b' '*((-len(payload))%4)
    parts=[struct.pack('<II',len(payload),0x4E4F534A)+payload]
    parts.extend(struct.pack('<II',len(payload),kind)+payload for kind,payload in chunks)
    result=b''.join(parts)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,len(result)+12)+result)


def canonicalize_export_quaternions(path):
    """Keep sampled rotation keys in one hemisphere after the native exporter.

    Blender's sampled matrix decomposition may select equivalent quaternion
    signs anew. Only rotation animation float values change here; geometry,
    skin weights, inverse binds and embedded images stay byte-identical.
    """
    blob=path.read_bytes();offset=12;chunks=[];document=None;binary=None
    while offset<len(blob):
        length,kind=struct.unpack_from('<II',blob,offset);offset+=8
        payload=blob[offset:offset+length];offset+=length
        if kind==0x4E4F534A:document=json.loads(payload)
        elif kind==0x004E4942:binary=bytearray(payload)
        else:chunks.append((kind,payload))
    done=set();flipped=0
    for animation in document.get('animations',[]):
        for channel in animation['channels']:
            if channel['target']['path']!='rotation':continue
            sampler=animation['samplers'][channel['sampler']]
            assert sampler.get('interpolation','LINEAR') in ('LINEAR','STEP')
            index=sampler['output']
            if index in done:continue
            done.add(index);acc=document['accessors'][index]
            assert acc['componentType']==5126 and acc['type']=='VEC4' and not acc.get('sparse')
            view=document['bufferViews'][acc['bufferView']]
            stride=view.get('byteStride',16)
            start=view.get('byteOffset',0)+acc.get('byteOffset',0)
            previous=None;minimum=[float('inf')]*4;maximum=[-float('inf')]*4
            for key in range(acc['count']):
                at=start+key*stride;q=struct.unpack_from('<4f',binary,at)
                if previous is not None and sum(a*b for a,b in zip(previous,q))<0:
                    q=tuple(-v for v in q);struct.pack_into('<4f',binary,at,*q);flipped+=1
                previous=q
                minimum=[min(a,b) for a,b in zip(minimum,q)]
                maximum=[max(a,b) for a,b in zip(maximum,q)]
            if 'min' in acc:acc['min']=minimum
            if 'max' in acc:acc['max']=maximum
    data=json.dumps(document,ensure_ascii=False,separators=(',',':')).encode('utf-8')
    data+=b' '*((-len(data))%4)
    payload=struct.pack('<II',len(data),0x4E4F534A)+data
    payload+=struct.pack('<II',len(binary),0x004E4942)+binary
    payload+=b''.join(struct.pack('<II',len(data),kind)+data for kind,data in chunks)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,12+len(payload))+payload)
    return {'rotation_accessors':len(done),'equivalent_keys_flipped':flipped}


def select_objects(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.hide_set(False);obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]


def export_rig(path,rig,meshes,actions,materials):
    select_objects([rig]+meshes)
    with armature_action_subset(rig,actions):
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
            export_materials=materials,export_animations=True,export_animation_mode='ACTIONS',
            export_anim_single_armature=False,export_frame_range=False,export_force_sampling=True,
            export_frame_step=1,export_anim_slide_to_zero=True,export_optimize_animation_size=False,
            export_skins=True,export_morph=False,export_yup=True,export_rest_position_armature=True,
            export_cameras=False,export_lights=False,export_extras=True)


def save_definition(definition,human,out):
    convert=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
    local=motion.RIGHT_HAND_IN_ITEM.inverted()@convert.inverted()
    rest=convert@human.data.bones['RightHand'].matrix_local@motion.RIGHT_HAND_IN_ITEM.inverted()@convert.inverted()
    def packed(matrix):
        return {'basis_columns':[[matrix[row][column] for row in range(3)] for column in range(3)],
                'origin':list(matrix.translation)}
    definition['mount']['transform']=packed(local)
    definition['mount']['note']='Canonical item. Joint-local axes retain Blender bone axes; the glTF item basis conversion is included once in this measured hand-local transform.'
    definition['mount']['rest_space_transform']=packed(rest)
    definition['source_mount']={'right_hand_in_item_blender':[list(row) for row in motion.RIGHT_HAND_IN_ITEM],
                                'rest_space_matrix_godot':[list(row) for row in rest]}
    definition['camera']['fov_degrees']=60
    definition['human']['reset_blend_shape_prefixes']=['TP_Grip_','FP_']
    definition['human']['hand_weight_patch']='Human.px9_eclipse.hand_weights.json'
    definition['human']['mesh_overrides']=[{'mesh':'Human_Body','resource':'Human.px9_eclipse.body.res'}]
    (out/'item_px9.json').write_text(json.dumps(definition,indent=2)+'\n')
    # Keep the alternate wrapper route synchronized when the per-item grip
    # station changes. Its embedded GLB already supplies the rest placement.
    rest_definition=copy.deepcopy(definition)
    rest_definition['files']['canonical_item_scene']=definition['files']['item_scene']
    rest_definition['files']['item_scene']=definition['files']['rest_space_item_scene']
    rest_definition['mount']['space']='human_rest'
    rest_definition['mount']['transform']={'basis_columns':[[1,0,0],[0,1,0],[0,0,1]],'origin':[0,0,0]}
    rest_definition['mount']['note']='The GLB already contains PX9_Eclipse_RestSpace with the final measured rest placement. Apply only the inverse RightHand global rest on this imported scene root; the embedded child supplies the placement once.'
    rest_definition['description']='Alternative definition for the embedded rest-space item. Same paired human/item clips, events, upper-body layer and optional hand mesh. The canonical item_px9.json remains the default.'
    (out/'item_px9_rest_space.json').write_text(json.dumps(rest_definition,indent=2)+'\n')
    return rest


def write_preview_helper(definition):
    table={clip['label']:{'human':clip['human_action'],'weapon':clip['weapon_action'],
                          'frame_end':clip['frame_end']} for clip in definition['actions']}
    text=bpy.data.texts.get('PX9_Clip_Table.json') or bpy.data.texts.new('PX9_Clip_Table.json')
    text.clear();text.write(json.dumps(table,indent=2))
    helper=bpy.data.texts.get('Preview_FirstPerson.py') or bpy.data.texts.new('Preview_FirstPerson.py')
    helper.clear();helper.write('''# CC0-1.0 — change CLIP below, then Run Script; Space plays both rigs.
import bpy, json
CLIP = "Inspect"
table = json.loads(bpy.data.texts['PX9_Clip_Table.json'].as_string())
entry = table[CLIP]
for name, key in [('Human_Rig', 'human'), ('WeaponSkeleton', 'weapon')]:
    rig = bpy.data.objects[name]
    rig.animation_data_create()
    rig.animation_data.use_nla = False
    rig.animation_data.action = bpy.data.actions[entry[key]]
bpy.context.scene.render.fps = 60
bpy.context.scene.frame_start = 0
bpy.context.scene.frame_end = entry['frame_end']
bpy.context.scene.frame_set(0)
print('Selected', CLIP, 'frames 0 through', entry['frame_end'])
''')


def build_outputs(scene,human,item,solver,attachment,definition,human_actions,item_actions,report,out):
    out.mkdir(parents=True,exist_ok=True);(out/'source').mkdir(exist_ok=True)
    (out/'previews').mkdir(exist_ok=True);(out/'validation').mkdir(exist_ok=True)
    rest_placement=save_definition(definition,human,out)
    write_preview_helper(definition)
    human.animation_data.action=None;human.animation_data.use_nla=False
    item.animation_data.action=None;item.animation_data.use_nla=False
    export_rig(out/'Human.px9_eclipse.glb',human,[bpy.data.objects['Human_Body']],human_actions,'NONE')
    def human_metadata(doc):
        doc['asset']['copyright']='CC0-1.0; see LICENSE.txt and SOURCE_NOTES.txt.'
        for scene_data in doc.get('scenes',[]):
            scene_data['extras']={'asset_role':'Human R11 first-person animation carrier',
                'new_clip_count':len(definition['actions']),'sample_fps':60,'bone_count':59,
                'runtime_reference':'Human.r11.glb',
                'note':'Animation carrier only. Original runtime meshes, morphs and 71 clips are supplied separately.'}
    rewrite_glb(out/'Human.px9_eclipse.glb',human_metadata)
    human_cleanup=canonicalize_export_quaternions(out/'Human.px9_eclipse.glb')
    attachment.mute=True;item.matrix_world=Matrix.Identity(4)
    item.animation_data.action=None;item.animation_data.use_nla=False
    for bone in item.pose.bones:
        bone.matrix_basis=Matrix.Identity(4)
        if bone.name=='ejected_case':bone.scale=(.0001,)*3
    bpy.context.view_layer.update()
    old_actions=[bpy.data.actions['PX9_SKEL__'+name] for name in
                 ['idle','fire','fire_last_round','reload_tactical','reload_empty','rack_slide','inspect','draw','holster','disassemble','assemble']]
    export_rig(out/'PX9_Eclipse_FP.glb',item,[bpy.data.objects[name] for name in PARTS],old_actions+item_actions,'EXPORT')
    rename={clip['weapon_action']:clip['item_clip'] for clip in definition['actions']}
    rename.update({action.name:action.name[len('PX9_SKEL__'):] for action in old_actions})
    def metadata(doc):
        for anim in doc.get('animations',[]):
            if anim['name'] in rename:anim['name']=rename[anim['name']]
        doc['asset']['copyright']='CC0-1.0; see LICENSE.txt and SOURCE_NOTES.txt.'
        manifest={'new_first_person_clips':[c['item_clip'] for c in definition['actions']],
                  'sample_fps':60,'human_animation_carrier':'Human.px9_eclipse.glb',
                  'paired_clock':True,'original_weapon_clip_count':11}
        for scene_data in doc.get('scenes',[]):
            scene_data['extras']={'asset_role':'PX-9 ECLIPSE separate animated weapon',
                'triangle_count':19616,'triangle_budget':20000,'mesh_count':17,'bone_count':22,
                'first_person_animation_manifest':manifest}
        for node in doc.get('nodes',[]):
            extras=node.get('extras',{})
            if 'animation_manifest' in extras:
                extras['legacy_animation_manifest']=extras.pop('animation_manifest')
                extras['first_person_animation_manifest']=manifest
    rewrite_glb(out/'PX9_Eclipse_FP.glb',metadata)
    item_cleanup=canonicalize_export_quaternions(out/'PX9_Eclipse_FP.glb')
    rest_path=out/'PX9_Eclipse_FP_RestSpace.glb'
    shutil.copy2(out/'PX9_Eclipse_FP.glb',rest_path)
    def wrap(doc):
        scene_data=doc['scenes'][doc.get('scene',0)]
        node={'name':'PX9_Eclipse_RestSpace','children':scene_data['nodes'],
              'matrix':[rest_placement[row][col] for col in range(4) for row in range(4)]}
        scene_data['nodes']=[len(doc['nodes'])];doc['nodes'].append(node)
    rewrite_glb(rest_path,wrap)
    attachment.mute=False;item.matrix_world=motion.RIGHT_HAND_IN_ITEM.inverted()
    for rig,actions in [(human,human_actions),(item,item_actions)]:
        rig.animation_data.use_nla=False
        rig.animation_data.action=next(a for a in actions if a.get('runtime_clip')=='FP_PX9_ECLIPSE_Inspect')
    scene.frame_start=0;scene.frame_end=240;scene.frame_set(0)
    stage(scene)
    scene.camera=camera(scene,'PX9 First Person',(0,.03,1.65),(0,-1,1.65),60,near=.16)
    write_preview_helper(definition)
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_perspective='CAMERA'
                area.spaces.active.clip_start=.16
                area.spaces.active.shading.type='SOLID'
                area.spaces.active.shading.color_type='MATERIAL'
    select_objects([human])
    bpy.data.objects['Human_Body'].hide_set(True)
    bpy.data.objects['Human_Body'].hide_render=True
    bpy.data.objects['Human_FP_Hands'].hide_set(False)
    bpy.data.objects['Human_FP_Hands'].hide_render=False
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'source/Human.px9_eclipse.blend'),compress=True)
    shutil.copy2(HERE/'AUTHORED_FRAMES.json',out/'validation/AUTHORED_FRAMES.json')
    concise={k:v for k,v in report.items() if k!='clips'}
    concise['quaternion_export_cleanup']={'human':human_cleanup,'weapon':item_cleanup}
    concise['clips']=[{k:v for k,v in clip.items() if k!='description'} for clip in definition['actions']]
    concise['human_animation_sha256']=hashlib.sha256((out/'Human.px9_eclipse.glb').read_bytes()).hexdigest()
    concise['item_sha256']=hashlib.sha256((out/'PX9_Eclipse_FP.glb').read_bytes()).hexdigest()
    concise['source_sha256']=hashlib.sha256((out/'source/Human.px9_eclipse.blend').read_bytes()).hexdigest()
    (out/'validation/AUTHORING_VALIDATION.json').write_text(json.dumps(concise,indent=2)+'\n')
    print('FP_EXPORT_COMPLETE',json.dumps(concise),flush=True)


def pose_idle(human, item, solver):
    solver.reset()
    weapon = motion.idle_transform()
    right_target=weapon@motion.RIGHT_HAND_IN_ITEM;left_target=weapon@motion.LEFT_SUPPORT_IN_ITEM
    right = solver.solve_arm('Right', right_target,
        pole=motion.arm_pole('Right',right_target,human.data.bones['RightForeArm'].length))
    left = solver.solve_arm('Left', left_target,
        pole=motion.arm_pole('Left',left_target,human.data.bones['LeftForeArm'].length))
    motion.pose_fingers(solver, weapon)
    bpy.context.view_layer.update()
    evaluated = item.evaluated_get(bpy.context.evaluated_depsgraph_get())
    error = max(abs(evaluated.matrix_world[i][j] - weapon[i][j]) for i in range(4) for j in range(4))
    print('ATTACHMENT_MATRIX_ERROR', error, flush=True)
    assert error < .00001, error
    return {'right':right, 'left':left, 'attachment_matrix_error':error,
            'weapon_matrix_blender': [list(r) for r in weapon]}


def pose_sample(scene, human, item, solver, action_id, frame):
    # Fractional evaluation is used by the hand-continuity review. Integer
    # export keys remain at their original sixty-frame-per-second times.
    whole_frame = math.floor(frame)
    scene.frame_set(whole_frame, subframe=frame-whole_frame)
    solver.reset()
    sample=motion.evaluate(action_id,frame)
    yaw=sample['torso_yaw']
    if yaw:
        for name in ('Spine1','Spine2'):
            bone=human.pose.bones[name]
            at=bone.matrix.copy()
            bone.matrix=Matrix.LocRotScale(at.translation,
                Quaternion((0,0,1),math.radians(yaw/2))@at.to_quaternion(),Vector((1,1,1)))
            bpy.context.view_layer.update()
    try:
        arms={side:solver.solve_arm(side,sample[side.lower()+'_world'],
            pole=motion.arm_pole(side,sample[side.lower()+'_world'],human.data.bones[side+'ForeArm'].length))
            for side in ('Right','Left')}
    except ValueError as error:
        raise ValueError(f'{action_id} frame{frame}: {error}; left={tuple(sample["left_world"].translation)} right={tuple(sample["right_world"].translation)}') from error
    press=motion.curve([(0,0),(18,0),(22,1),(26,0),(192,0)],frame) if action_id in ('reload','reload_empty') else 0
    slide_touch=(motion.curve([(0,0),(138,0),(143,1),(149,1),(152,0),(192,0)],frame)
                 if action_id=='reload_empty' else 0)
    slide_press=(motion.curve([(0,0),(143,0),(145,1),(146,1),(149,0),(192,0)],frame)
                 if action_id=='reload_empty' else 0)
    motion.pose_fingers(solver,sample['weapon_world'],sample['right_index'],sample['left_fingers'],
                       sample['left_kind'],sample['left_thumb_weights'],press,sample['index_splay'],
                       slide_touch,slide_press,sample['left_slide_thumb_close'],
                       left_slide_thumb_release=sample['left_slide_thumb_release'])
    for bone in item.pose.bones:
        bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    rests={bone.name:bone.matrix_local for bone in item.data.bones}
    slide=sample['slide']
    for name,delta in [('slide',(0,slide,0)),('guide_rod',(0,slide*.13,0))]:
        item.pose.bones[name].matrix=Matrix.Translation(delta)@rests[name]
    at=rests['barrel']
    item.pose.bones['barrel'].matrix=Matrix.LocRotScale(at.translation+Vector((0,slide*.13,0)),
        Quaternion((1,0,0),math.radians(-1.8*abs(slide)/.034))@at.to_quaternion(),Vector((1,1,1)))
    item.pose.bones['magazine'].matrix=sample['magazine_delta']@rests['magazine']
    at=rests['trigger']
    item.pose.bones['trigger'].matrix=Matrix.LocRotScale(at.translation,
        Quaternion((1,0,0),math.radians(-10*sample['trigger']))@at.to_quaternion(),Vector((1,1,1)))
    item.pose.bones['magazine_release'].matrix=Matrix.Translation((.0011*press,0,0))@rests['magazine_release']
    at=rests['slide_stop']
    item.pose.bones['slide_stop'].matrix=Matrix.LocRotScale(at.translation,
        Quaternion((1,0,0),math.radians(8*slide_press))@at.to_quaternion(),Vector((1,1,1)))
    case=item.pose.bones['ejected_case']; at=rests['ejected_case']
    case.matrix=Matrix.LocRotScale(Vector(sample['case_position']),
        Quaternion((0,0,1),sample['case_time']*22)@Quaternion((0,1,0),sample['case_time']*13)@at.to_quaternion(),
        Vector((1,1,1)) if sample['case_visible'] else Vector((.0001,)*3))
    bpy.context.view_layer.update()
    actual_item=item.evaluated_get(bpy.context.evaluated_depsgraph_get()).matrix_world.copy()
    desired=sample['weapon_world']
    mount_error=max(abs(actual_item[i][j]-desired[i][j]) for i in range(4) for j in range(4))
    assert mount_error<.00001,(action_id,frame,mount_error)
    return {'frame':frame,'arms':arms,'mount_matrix_error':mount_error,
            'weapon_world_blender':[list(r) for r in desired],
            'right_hand_blender':[list(r) for r in human.pose.bones['RightHand'].matrix],
            'left_hand_blender':[list(r) for r in human.pose.bones['LeftHand'].matrix],
            'left_contact':sample['left_contact'], 'slide_offset_metres':slide,
            'magazine_delta_blender':[list(r) for r in sample['magazine_delta']],
            'case_visible':sample['case_visible']}


def sample_motion(scene,human,item,solver,definition,make_actions=False):
    report={'fps':60,'clips':{},'source_bone_count':len(human.data.bones),'item_bone_count':len(item.data.bones),
            'scope':'Every authored integer frame. Hand anchor/rig kinematics; not a complete skin collision proof.'}
    new_human=[]; new_item=[]
    for clip in definition['actions']:
        rows=[]
        values={rig.name:{b.name:[] for b in rig.pose.bones} for rig in (human,item)}
        previous={rig.name:{} for rig in (human,item)}
        for frame in range(clip['frame_end']+1):
            row=pose_sample(scene,human,item,solver,clip['id'],frame)
            rows.append(row)
            if make_actions:
                for rig in (human,item):
                    for bone in rig.pose.bones:
                        q=bone.rotation_quaternion.copy()
                        if bone.name in previous[rig.name] and previous[rig.name][bone.name].dot(q)<0:
                            q.negate()
                        previous[rig.name][bone.name]=q.copy()
                        values[rig.name][bone.name].append((*bone.location,*q,*bone.scale))
        report['clips'][clip['id']]={'frame_end':clip['frame_end'],'sample_count':len(rows),'samples':rows}
        if make_actions:
            for rig,name,output in ((human,clip['human_action'],new_human),(item,clip['weapon_action'],new_item)):
                assert bpy.data.actions.get(name) is None,name
                action=bpy.data.actions.new(name);action.use_fake_user=True
                action.use_frame_range=True;action.frame_start=0;action.frame_end=clip['frame_end']
                action['license']='CC0-1.0';action['fps']=60;action['loop']=clip['loop']
                action['runtime_clip']=clip['human_clip'];action['frame_baked']=True
                for bone,sequence in values[rig.name].items():
                    for prop,start,count in [('location',0,3),('rotation_quaternion',3,4),('scale',7,3)]:
                        for component in range(count):
                            fc=action.fcurves.new('pose.bones["'+bone+'"].'+prop,index=component,action_group=bone)
                            fc.keyframe_points.add(len(sequence))
                            flat=[]
                            for index,entry in enumerate(sequence):flat.extend((index,entry[start+component]))
                            fc.keyframe_points.foreach_set('co',flat)
                            for key in fc.keyframe_points:key.interpolation='LINEAR'
                            fc.extrapolation='CONSTANT';fc.update()
                output.append(action)
        print('FP_SAMPLED',clip['human_clip'],len(rows),flush=True)
    allrows=[r for c in report['clips'].values() for r in c['samples']]
    report['sample_count']=len(allrows)
    report['maximum_mount_matrix_error']=max(r['mount_matrix_error'] for r in allrows)
    report['maximum_wrist_error_metres']=max(a['wrist_error_metres'] for r in allrows for a in r['arms'].values())
    report['maximum_reach_fraction']=max(a['reach_fraction'] for r in allrows for a in r['arms'].values())
    report['human_rest_unchanged']=solver.rest_unchanged()
    report['passed']=report['human_rest_unchanged'] and report['maximum_wrist_error_metres']<.00001
    (HERE/'AUTHORED_FRAMES.json').write_text(json.dumps(report,separators=(',',':'))+'\n')
    return report,new_human,new_item


def camera(scene, name, location, target, fov=60, near=.015):
    old=bpy.data.objects.get(name)
    if old and old.type=='CAMERA':bpy.data.objects.remove(old,do_unlink=True)
    data = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
    data.sensor_fit = 'VERTICAL'
    data.sensor_height = 24
    data.lens = 12 / math.tan(math.radians(fov/2))
    data.clip_start = near
    data.clip_end = 100
    return obj


def stage(scene):
    for obj in list(bpy.data.objects):
        if obj.type=='LIGHT' and obj.name.startswith('FP '):
            bpy.data.objects.remove(obj,do_unlink=True)
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.world = bpy.data.worlds.new('First-person neutral studio')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.115,.135,.155,1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .45
    for name, pos, power, size in [
        ('Key',(-1.4,-2.4,3.0),160,2.0),('Fill',(1.8,-1.4,2.2),100,2.0),('Rim',(-1.0,.8,2.8),200,1.6)]:
        data=bpy.data.lights.new('FP '+name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size
        obj=bpy.data.objects.new('FP '+name,data); scene.collection.objects.link(obj); obj.location=pos
        obj.rotation_euler=(Vector((0,-.35,1.45))-obj.location).to_track_quat('-Z','Y').to_euler()
    scene.view_settings.view_transform='AgX'
    scene.view_settings.look='AgX - Medium High Contrast'


def head_mask_for_render(body):
    changes=[]
    for slot in body.material_slots:
        if slot.material and any(n in slot.material.name for n in ('Human.Head','Human.Mouth')):
            old=slot.material
            mask=bpy.data.materials.new('Preview mask — '+old.name); mask.use_nodes=True
            nodes=mask.node_tree.nodes; nodes.clear()
            transparent=nodes.new('ShaderNodeBsdfTransparent'); output=nodes.new('ShaderNodeOutputMaterial')
            mask.node_tree.links.new(transparent.outputs[0],output.inputs['Surface'])
            changes.append((slot,old)); slot.material=mask
    return changes


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser=argparse.ArgumentParser()
    parser.add_argument('--check-motion',action='store_true')
    parser.add_argument('--pose-review',action='store_true')
    parser.add_argument('--build',action='store_true')
    parser.add_argument('--only')
    parser.add_argument('--source',type=Path)
    parser.add_argument('--output',type=Path,default=OUT)
    options=parser.parse_args(args)
    scene,human,item,solver,attachment=setup(options.source)
    definition=json.loads((HERE/'item_px9_draft.json').read_text())
    if options.only:
        definition['actions']=[c for c in definition['actions'] if c['id']==options.only]
    if options.check_motion or options.build:
        report,human_actions,item_actions=sample_motion(scene,human,item,solver,definition,make_actions=options.build)
        print('FP_MOTION_CHECK',json.dumps({k:v for k,v in report.items() if k!='clips'}),flush=True)
        if not options.build:return
        build_outputs(scene,human,item,solver,attachment,definition,human_actions,item_actions,report,options.output)
        return
    record=pose_idle(human,item,solver)
    stage(scene)
    views=[
      camera(scene,'First Person',(0,.03,1.65),(0,-1,1.65),60),
      camera(scene,'Grip right',(-.72,-.82,1.68),(-.10,-.32,1.46),42),
      camera(scene,'Grip left',(.65,-.74,1.63),(-.10,-.32,1.46),42)]
    study=HERE/'study'; study.mkdir(exist_ok=True)
    (study/'initial_pose.json').write_text(json.dumps(record,indent=2))
    masked=head_mask_for_render(bpy.data.objects['Human_FP_Hands'])
    if options.pose_review:
        for action,frame in [('aim_idle',0),('inspect',57),('inspect',140),('reload',24),('reload',46),
                             ('reload',72),('reload',98),('reload',112),('reload_empty',145),('fire',6),('rack',35)]:
            pose_sample(scene,human,item,solver,action,frame)
            scene.camera=views[0]
            scene.render.filepath=str(study/f'{action}_{frame:03}.png')
            bpy.ops.render.render(write_still=True)
        for slot,original in masked:slot.material=original
        return
    for index,cam in enumerate(views):
        scene.camera=cam
        scene.render.filepath=str(study/f'idle_{index}.png')
        bpy.ops.render.render(write_still=True)
    for slot,original in masked: slot.material=original
    scene.camera=views[0]
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(study/'pose_study.blend'),compress=True)
    print('FP_STUDY_COMPLETE',str(study),flush=True)


if __name__ == '__main__':
    main()
