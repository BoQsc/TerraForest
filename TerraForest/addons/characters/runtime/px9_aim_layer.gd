# SPDX-License-Identifier: 0BSD
extends RefCounted
## Aim and recoil share a phase but have independent weights. Sampling resources
## directly never restarts the action clock or repeats its gameplay events.
var weight := 0.0
var clips: Dictionary = {}
func prepare(clock: Node) -> void:
    clips.clear(); weight = 0.0
    var pairs := {"idle":"aim_idle", "idle_empty":"aim_idle_empty", "walk":"aim_idle", "run":"aim_idle", "jump":"aim_idle", "walk_empty":"aim_idle_empty", "run_empty":"aim_idle_empty", "jump_empty":"aim_idle_empty", "fire":"aim_fire", "fire_last":"aim_fire_last"}
    for hip: String in pairs:
        var aimed: String = pairs[hip]
        var rows: Array = []
        for source: Array in [[clock.human_player, clock._human_names], [clock.item_player, clock._item_names]]:
            var player: AnimationPlayer = source[0]
            var names: Dictionary = source[1]
            var a: Animation = player.get_animation(names[hip])
            var b: Animation = player.get_animation(names[aimed])
            var base: Node = player.get_node(player.root_node)
            for track in a.get_track_count():
                var path := a.track_get_path(track)
                var kind := a.track_get_type(track)
                if path.get_subname_count() != 1 or kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]: continue
                var other := b.find_track(path, kind)
                if other < 0: continue
                var skeleton := base.get_node_or_null(NodePath(String(path).get_slice(":", 0))) as Skeleton3D
                if skeleton == null: continue
                var bone := skeleton.find_bone(path.get_subname(0))
                if bone >= 0: rows.append([skeleton, bone, kind, a, track, b, other])
        clips[hip] = rows
        # Aimed idle is shared by the movement variants; keep its idle pairing.
        if hip in ["idle", "idle_empty", "fire", "fire_last"]: clips[aimed] = rows

func advance(delta: float, aiming: bool, clock: Node) -> void:
    weight = move_toward(weight, 1.0 if aiming else 0.0, delta / .16)
    if not clips.has(clock.current_action): return # Equip/reload/inspect own their poses.
    var phase: float = clock.time_seconds / maxf(.001, clock.duration_seconds())
    var blend := smoothstep(0.0, 1.0, weight)
    for row: Array in clips[clock.current_action]:
        var skeleton: Skeleton3D = row[0]
        var bone: int = row[1]
        var a: Animation = row[3]; var b: Animation = row[5]
        var ta: float = phase * a.length; var tb: float = phase * b.length
        match row[2]:
            Animation.TYPE_POSITION_3D:
                skeleton.set_bone_pose_position(bone, a.position_track_interpolate(row[4], ta).lerp(b.position_track_interpolate(row[6], tb), blend))
            Animation.TYPE_ROTATION_3D:
                skeleton.set_bone_pose_rotation(bone, a.rotation_track_interpolate(row[4], ta).slerp(b.rotation_track_interpolate(row[6], tb), blend))
            Animation.TYPE_SCALE_3D:
                skeleton.set_bone_pose_scale(bone, a.scale_track_interpolate(row[4], ta).lerp(b.scale_track_interpolate(row[6], tb), blend))
