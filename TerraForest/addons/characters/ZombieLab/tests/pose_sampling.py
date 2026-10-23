"""Select the rig and every synchronized morph for read-only Blender probes."""
import bpy
import json
from pathlib import Path

_contract_path = Path(__file__).resolve().parents[1] / 'assets/Zombie.r4.behavior.json'
_mapping = json.loads(_contract_path.read_text()).get('morph_actions', {}) if _contract_path.exists() else {}


def select_pose_action(rig, action):
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    for obj in bpy.data.objects:
        if obj.type != 'MESH' or not obj.data.shape_keys:
            continue
        keys = obj.data.shape_keys
        keys.animation_data_create()
        for track in keys.animation_data.nla_tracks:
            track.mute = True
        keys.animation_data.action = None
        for block in keys.key_blocks:
            if block.name != 'Basis':
                block.value = 0.0
        prefix = _mapping.get(obj.name, {}).get('action_prefix', 'Jaw.' if obj.name == 'Z_Head' else '')
        matching = bpy.data.actions.get(prefix + action.name) if prefix else None
        if matching is not None:
            keys.animation_data.action = matching
            if matching.slots:
                keys.animation_data.action_slot = matching.slots[0]
