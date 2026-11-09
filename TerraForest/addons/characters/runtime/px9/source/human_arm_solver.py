# SPDX-License-Identifier: CC0-1.0
"""Constraint-free arm posing for the unchanged Human R11 skeleton.

Call in Blender. Transforms/targets are in Human_Rig armature space.
No rest bones, mesh data, root motion or animation actions are modified here.
The caller owns action creation, per-frame sampling and key insertion.
"""
import math
import bpy
from mathutils import Matrix, Quaternion, Vector


FINGER_FLEX = {
    # Degrees about each phalanx's local -X, proximal to distal.
    # These are starting poses; fit them to the actual item in the caller.
    'relaxed': {'Index': (16, 24, 12), 'Middle': (20, 28, 14),
                'Ring': (24, 32, 16), 'Pinky': (28, 36, 18), 'Thumb': (10, 18, 10)},
    'grip': {'Index': (46, 58, 32), 'Middle': (46, 58, 32),
             'Ring': (48, 60, 34), 'Pinky': (50, 60, 34), 'Thumb': (8, 22, 14)},
    'index_extended': {'Index': (4, 10, 6), 'Middle': (46, 58, 32),
                       'Ring': (48, 60, 34), 'Pinky': (50, 60, 34), 'Thumb': (8, 22, 14)},
    'magazine': {'Index': (42, 60, 28), 'Middle': (46, 64, 32),
                 'Ring': (50, 64, 32), 'Pinky': (54, 64, 32), 'Thumb': (8, 25, 18)},
    'open': {'Index': (5, 8, 4), 'Middle': (7, 10, 5),
             'Ring': (10, 13, 6), 'Pinky': (13, 16, 8), 'Thumb': (6, 9, 5)},
}


def _unit_project(vector, normal, fallback):
    value = vector - normal * vector.dot(normal)
    if value.length_squared < 1e-10:
        value = fallback - normal * fallback.dot(normal)
    if value.length_squared < 1e-10:
        fallback = Vector((0, 0, 1)) if abs(normal.z) < .9 else Vector((1, 0, 0))
        value = fallback - normal * fallback.dot(normal)
    return value.normalized()


def bone_transform(head, direction, across):
    """Rigid matrix with local Y along a bone and local X across its width."""
    y = Vector(direction).normalized()
    x = _unit_project(Vector(across), y, Vector((1, 0, 0)))
    z = x.cross(y).normalized()
    return Matrix.LocRotScale(Vector(head), Matrix((x, y, z)).transposed().to_quaternion(), Vector((1, 1, 1)))


class HumanArmSolver:
    """Analytic two-bone solve, with deterministic elbow roll and hand targets.

    Initialize after selecting the desired neutral action/pose and updating
    the dependency graph. Right = negative X; forward = negative Y; up = Z.
    Parent/spine poses may be changed between reset() and solve_arm().
    """
    def __init__(self, rig):
        self.rig = rig
        self.base = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
        self.reference = {b.name: b.matrix.copy() for b in rig.pose.bones}
        self.rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
        self.parents = {b.name: b.parent.name if b.parent else None for b in rig.data.bones}
        for bone in rig.pose.bones:
            bone.rotation_mode = 'QUATERNION'

    def reset(self):
        for bone in self.rig.pose.bones:
            bone.matrix_basis = self.base[bone.name]
        bpy.context.view_layer.update()

    def orient(self, name, head, direction):
        reference = self.reference[name].to_quaternion()
        desired = Vector(direction).normalized()
        q = (reference @ Vector((0, 1, 0))).rotation_difference(desired) @ reference
        self.rig.pose.bones[name].matrix = Matrix.LocRotScale(Vector(head), q, Vector((1, 1, 1)))
        bpy.context.view_layer.update()

    def solve_arm(self, side, wrist_matrix, pole=None, shoulder_lead=0.0,
                  shoulder_direction=None, minimum_bend=.004):
        """Place shoulder/arm/forearm/hand without changing their lengths.

        wrist_matrix is the complete desired Hand bone matrix in armature
        space, so an item can stay in an exact fixed hand-local transform.
        The elbow pole is also an armature-space point. Unreachable targets
        raise ValueError rather than silently sliding the hand off an item.
        """
        if side not in ('Left', 'Right'):
            raise ValueError(side)
        sign = 1 if side == 'Left' else -1
        shoulder_name = side + 'Shoulder'
        upper_name, lower_name, hand_name = side + 'Arm', side + 'ForeArm', side + 'Hand'
        shoulder = self.rig.pose.bones[shoulder_name].head.copy()
        if shoulder_direction is None:
            shoulder_direction = Vector((sign * .14, -.035, -.015)).lerp(
                Vector((sign * .11, -.105, .005)), float(shoulder_lead))
        self.orient(shoulder_name, shoulder, shoulder_direction)
        origin = self.rig.pose.bones[upper_name].head.copy()
        wrist = wrist_matrix.translation.copy()
        delta = wrist - origin
        distance = delta.length
        a = self.rig.data.bones[upper_name].length
        b = self.rig.data.bones[lower_name].length
        if not abs(a - b) + .0001 < distance < a + b - minimum_bend:
            raise ValueError(f'{side} wrist out of reach: distance={distance:.6f}, allowed=({abs(a-b)+.0001:.6f}, {a+b-minimum_bend:.6f})')
        axis = delta / distance
        along = (a * a - b * b + distance * distance) / (2 * distance)
        if pole is None:
            pole = Vector((sign * .38, -.08, 1.08)).lerp(
                Vector((sign * .37, -.26, 1.43)), float(shoulder_lead))
        pole_direction = _unit_project(Vector(pole) - origin, axis, Vector((0, 0, -1)))
        elbow = origin + axis * along + pole_direction * math.sqrt(max(0, a*a - along*along))
        upper_axis = (elbow - origin).normalized()
        lower_axis = (wrist - elbow).normalized()
        # The ordered upper/lower axes already orient the elbow bend plane.
        # Keep that orientation even when its X component crosses zero.
        # Re-selecting a global hemisphere at every sample introduces a
        # half-turn in the upper arm (and a compensating local forearm turn)
        # while the integer wrist target can still appear correct. This
        # fixed cross-product order is continuous for the non-straight
        # reachable bends enforced above, and is independent of sample order.
        hinge = upper_axis.cross(lower_axis).normalized()
        desired_q = wrist_matrix.to_quaternion().normalized()
        width = desired_q @ Vector((1, 0, 0))
        self.rig.pose.bones[upper_name].matrix = bone_transform(origin, upper_axis, hinge)
        bpy.context.view_layer.update()
        self.rig.pose.bones[lower_name].matrix = bone_transform(elbow, lower_axis, width)
        bpy.context.view_layer.update()
        self.rig.pose.bones[hand_name].matrix = Matrix.LocRotScale(wrist, desired_q, Vector((1, 1, 1)))
        bpy.context.view_layer.update()
        hand = self.rig.pose.bones[hand_name]
        upper = self.rig.pose.bones[upper_name]
        lower = self.rig.pose.bones[lower_name]
        return {'side': side, 'reach_fraction': distance/(a+b),
                'wrist': list(wrist), 'elbow': list(elbow),
                'wrist_error_metres': (hand.head-wrist).length,
                'upper_length_error_metres': abs((upper.tail-upper.head).length-a),
                'lower_length_error_metres': abs((lower.tail-lower.head).length-b),
                'wrist_rotation_error_radians': hand.matrix.to_quaternion().rotation_difference(desired_q).angle}

    def finger_pose(self, side, pose='grip', blend_from=None, mix=1.0, index_override=None):
        """Set local hinge curls; supports authored pose dictionaries in degrees.

        Finger translations/scales remain at neutral values. Both R11 hands
        use -X for closure; the mirrored rest geometry already carries side.
        index_override=(proximal,middle,distal) supports trigger/indexing poses.
        Thumb opposition may need orient_finger_segment() after hinge curls.
        """
        target = FINGER_FLEX[pose] if isinstance(pose, str) else pose
        source = (FINGER_FLEX[blend_from] if isinstance(blend_from, str) else blend_from) or target
        t = max(0.0, min(1.0, float(mix)))
        for finger, values in target.items():
            if finger == 'Index' and index_override is not None:
                values = index_override
            for joint, (start, end) in enumerate(zip(source[finger], values), 1):
                name = f'{side}Hand{finger}{joint}'
                bone = self.rig.pose.bones[name]
                location, _, scale = self.base[name].decompose()
                bone.location = location
                bone.scale = scale
                bone.rotation_quaternion = Quaternion((1, 0, 0), -math.radians(start+(end-start)*t))
        bpy.context.view_layer.update()

    def orient_finger_segment(self, side, finger, joint, direction, space='HAND', mix=1.0):
        """Art-direct a thumb/finger segment without changing its head/length.

        direction is either a Hand-local direction or an armature-space one.
        Call proximal before distal; this follows the current posed parent.
        """
        bone = self.rig.pose.bones[f'{side}Hand{finger}{joint}']
        current = bone.matrix.copy()
        original = current.to_quaternion()
        desired_direction = Vector(direction)
        if space == 'HAND':
            desired_direction = self.rig.pose.bones[side+'Hand'].matrix.to_quaternion() @ desired_direction
        elif space != 'ARMATURE':
            raise ValueError(space)
        desired = (original @ Vector((0, 1, 0))).rotation_difference(desired_direction.normalized()) @ original
        bone.matrix = Matrix.LocRotScale(current.translation, original.slerp(desired, float(mix)), Vector((1, 1, 1)))
        bpy.context.view_layer.update()

    def rest_unchanged(self):
        return (len(self.rig.data.bones) == len(self.rest)
                and all(b.name in self.rest and b.matrix_local == self.rest[b.name]
                        and (b.parent.name if b.parent else None) == self.parents[b.name]
                        for b in self.rig.data.bones))


def continuous_quaternion(previous, current):
    """Keep adjacent baked quaternion keys in one hemisphere."""
    value = current.copy()
    if previous is not None and previous.dot(value) < 0:
        value.negate()
    return value


def hand_from_item(item_world, hand_to_item):
    """Convert desired item transform to its exact Hand bone target."""
    return item_world @ hand_to_item.inverted()
