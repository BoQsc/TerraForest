# SPDX-License-Identifier: CC0-1.0
"""Export a named action batch without deleting other authoring actions.

Blender 4.3 native glTF ACTIONS mode reads active actions and unmuted NLA
strips. Use export_anim_single_armature=False in the export call below.
This context manager restores all original action links and strip states.
"""
from contextlib import contextmanager
import math
import bpy


@contextmanager
def armature_action_subset(rig, actions):
    """Temporarily expose only actions to the glTF ACTIONS collector.

    Example:
        with armature_action_subset(rig, new_actions):
            bpy.ops.export_scene.gltf(...,
                export_animation_mode='ACTIONS',
                export_anim_single_armature=False,
                export_force_sampling=True,
                export_morph=False,
                export_frame_range=False)

    The caller selects the intended rig and body before exporting. Each
    returned clip uses its exact Action name. Existing Actions are retained.
    """
    actions = list(actions)
    if not actions or len({a.name for a in actions}) != len(actions):
        raise ValueError('Supply one or more uniquely named actions.')
    data = rig.animation_data_create()
    active = data.action
    use_nla = data.use_nla
    blend = data.action_blend_type
    influence = data.action_influence
    old_tracks = list(data.nla_tracks)
    names = {a.name for a in actions}
    old_track_states = [(track, track.name, track.is_solo,
                         [(strip, strip.mute) for strip in track.strips]) for track in old_tracks]
    filter_states = []
    if hasattr(bpy.data.scenes[0], 'gltf_action_filter'):
        for item in bpy.data.scenes[0].gltf_action_filter:
            if item.action in actions:
                filter_states.append((item, item.keep))
                item.keep = True
    created = []
    try:
        for track, name, solo, strips in old_track_states:
            if name in names:
                track.name = '__EXPORT_PRESERVE__' + name
            track.is_solo = False
            for strip, mute in strips:
                strip.mute = True
        data.action = actions[0]
        data.action_blend_type = 'REPLACE'
        data.action_influence = 1.0
        data.use_nla = False
        for action in actions:
            track = data.nla_tracks.new()
            created.append(track)
            track.name = action.name
            if track.name != action.name:
                raise RuntimeError('Cannot reserve exact export clip name: ' + action.name)
            strip = track.strips.new(action.name, math.floor(action.frame_range[0]), action)
            strip.action_frame_start = action.frame_range[0]
            strip.action_frame_end = action.frame_range[1]
            strip.scale = 1.0
            strip.repeat = 1.0
            strip.blend_type = 'REPLACE'
            strip.extrapolation = 'NOTHING'
            strip.mute = False
        yield
    finally:
        for track in created:
            data.nla_tracks.remove(track)
        for track, name, solo, strips in old_track_states:
            track.name = name
            for strip, mute in strips:
                strip.mute = mute
            track.is_solo = solo
        data.action = active
        data.use_nla = use_nla
        data.action_blend_type = blend
        data.action_influence = influence
        for item, keep in filter_states:
            item.keep = keep
