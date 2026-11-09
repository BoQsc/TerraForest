# SPDX-License-Identifier: CC0-1.0
"""Independent, narrow eligibility audit of the supplied R11 hand-weight patch.

This checks source positions/bones, rather than trusting a patch row's claimed
region. The one reviewed proximal seam exception is explicitly limited to
vertex 741 and the original weights of its immediate neighbor 742.
Revision 3's palm and proximal-web bounds remain fixed. Revision 4 additionally
permits exactly seven source-topology-bound Middle finger ownership rows while
requiring complete recovery of both earlier row sets. Revision 5 additionally
permits exactly four left Middle ownership rows, independently checks their
source component, adjacency and interpolation, and recursively validates the
exact recovered revision 4 with every earlier check unchanged.
"""
import copy
import hashlib
import json
import math
from mathutils import Matrix, Vector

SOURCE_GLB_SHA256 = "0dc8fdbcfac451f61b6eee5c914b1e79f5ec450f5e98e4c896e8b46370bf35c8"
FAMILIES = ("Index", "Middle", "Ring", "Pinky", "Thumb")
FROZEN_V2_ROWS_SHA256 = "4e29ea49e1409107ccef77edf9e6b6d1d35011afab37d5adf16a09f095cb47a9"
FROZEN_V2_PATCH_SHA256 = "42b1a15fd864d1f43b691630e41ccf192e6db4894acdb70fb7dec9730f60ab0c"
FROZEN_V3_ROWS_SHA256 = "a715fae23e52364faf8ff32683c9bdc7325404f41559cbb5d1f35eea2b85ab0f"
FROZEN_V3_PATCH_SHA256 = "1908ffec446331c66cbb8c43b19c7dc34931e79844d01770d75043724e945e4f"
DISTAL_MIDDLE_SOURCE_POLYGONS_SHA256 = "ae9393e153c46617b3efbd205217f915924630c256a57dc8bdd56ab63ce37845"
FROZEN_V4_ROWS_SHA256 = "62679ff9e126059fded01b82650ad607360903a61fcd02898277c12b5ec513e0"
FROZEN_V4_PATCH_SHA256 = "7f7165d208ced4a8d4259b990d6ffcc8503ba3170f6e382e9dc2654565e68ab3"
LEFT_DISTAL_SOURCE_POLYGONS_SHA256 = "f0542c5e6c36db066263f98329536f2fa8321d6f1dcd0d08a161bb1a4973933b"
LEFT_DISTAL_METHOD_SUFFIX = " Three topology-reviewed left Middle shaft/pad vertices retain Middle-chain ownership; proximal web vertex 4597 blends the Middle and previous Ring chains equally."
LEFT_MIDDLE_RING_WEB = {"vertex": 4597, "middle_chain_fraction": .5, "previous_ring_chain_fraction": .5}
LEFT_DISTAL_REVIEW = {
    4578: {
        "local": [-.021405616775155067, .18070338666439056, -.028819061815738678],
        "neighbors": [4573, 4575, 4580, 4634, 4637, 4638],
        "middle_source_mass": .9402103275060654,
        "proportions": {"LeftHandMiddle2": .38920789322327076, "LeftHandMiddle3": .6107921067767292},
    },
    4597: {
        "local": [-.020433487370610237, .1526469737291336, -.011217691004276276],
        "neighbors": [4579, 4581, 4603, 4604, 4633, 4636],
        "middle_source_mass": .4847325086593628,
        "proportions": {"LeftHandMiddle1": .22825445305906872, "LeftHandMiddle2": .2717455469409313,
                        "LeftHandRing1": .09492115582555788, "LeftHandRing2": .4050788441744421},
    },
    4633: {
        "local": [-.021365443244576454, .1641080379486084, -.015726901590824127],
        "neighbors": [4579, 4597, 4598, 4604, 4634, 4635],
        "middle_source_mass": .5796910546487197,
        "proportions": {"LeftHandMiddle2": 1.0},
    },
    4637: {
        "local": [-.026102187111973763, .19869442284107208, -.0329650416970253],
        "neighbors": [4513, 4576, 4577, 4578, 4580, 4584, 4634],
        "middle_source_mass": .6998341586440802,
        "proportions": {"LeftHandMiddle3": 1.0},
    },
}
PALM_LIMITS = {
    "minimum_original_same_hand_weight_sum": 0.5,
    "hand_rest_local_x_range_metres": [-.052, .052],
    "hand_rest_local_y_range_metres": [.025, .110],
    "hand_rest_local_z_range_metres": [-.035, .030],
    "excluded_preserved_vertices": [741, 742],
    "must_be_outside_original_finger_chain_capsule": True,
    "thumb_web_lateral_blend_range_metres": [.020, .045],
    "thumb_web_distal_taper_range_metres": [.085, .110],
    "nonthumb_chain_distance_blend_range_metres": [.018, .034],
    "previous_records_preserved_except_reviewed_web_vertices": [444, 479],
}
WEB_REVIEW = {
    444: {
        "local_bounds": [(-.01037, -.01034), (.12882, .12885), (-.00784, -.00781)],
        "neighbors": [138, 139, 150, 220, 221, 442, 443, 445, 577],
        "proportions": {"RightHandIndex1": .125, "RightHandMiddle1": .875},
    },
    479: {
        "local_bounds": [(-.00958, -.00955), (.13650, .13654), (-.00033, -.00030)],
        "neighbors": [10, 20, 21, 22, 137, 145, 146, 151, 228, 229, 245, 442, 443, 445, 446, 481, 482, 483, 577],
        "proportions": {"RightHand": .025, "RightHandIndex1": .073125, "RightHandMiddle1": .901875},
    },
}
# These seven connected source vertices lie on the Middle finger's middle /
# distal surface. The original R11 skin assigns a majority of each vertex's
# mass to Middle, although the nearby Ring rest chain won the generic nearest-
# chain test. This explicit exception cannot expand to other vertices. The
# original neighbor lists and hand-rest-local coordinates are fixed review
# evidence; the target interpolation is also recomputed independently below.
DISTAL_MIDDLE_REVIEW = {
    3: {
        "local": [.025052795186638832, .18025510013103485, -.016177037730813026],
        "neighbors": [2, 9, 102, 118, 125],
        "proportions": {"RightHandMiddle2": .9159630107634998, "RightHandMiddle3": .08403698923650013},
    },
    9: {
        "local": [.02769666351377964, .19452805817127228, -.024616923183202744],
        "neighbors": [3, 102, 104, 105, 118, 121, 123],
        "proportions": {"RightHandMiddle3": 1.0},
    },
    109: {
        "local": [.021608592942357063, .1621963381767273, -.01600003056228161],
        "neighbors": [2, 110, 111, 112, 113, 125, 126, 154],
        "proportions": {"RightHandMiddle2": 1.0},
    },
    118: {
        "local": [.022896939888596535, .17851948738098145, -.023940186947584152],
        "neighbors": [3, 9, 110, 121, 125, 126, 127, 157],
        "proportions": {"RightHandMiddle2": .791823211767262, "RightHandMiddle3": .20817678823273802},
    },
    121: {
        "local": [.02369820512831211, .18950404226779938, -.03012690134346485],
        "neighbors": [9, 118, 123, 128, 157],
        "proportions": {"RightHandMiddle3": 1.0},
    },
    123: {
        "local": [.028805041685700417, .20230665802955627, -.030761318281292915],
        "neighbors": [9, 105, 121, 122, 128],
        "proportions": {"RightHandMiddle3": 1.0},
    },
    125: {
        "local": [.023705529049038887, .17200371623039246, -.016839731484651566],
        "neighbors": [2, 3, 109, 110, 118],
        "proportions": {"RightHandMiddle2": 1.0},
    },
}


def _smoothstep(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def _independent_finger_distribution(hand, family, arc, chain):
    """Independent evaluation of the declared adjacent-phalanx interpolation."""
    lengths = [(end - start).length for start, end in chain]
    names = [hand + family + str(number) for number in (1, 2, 3)]
    if arc < .014:
        fraction = _smoothstep((arc + .018) / .032)
        return {hand: 1.0 - fraction, names[0]: fraction}
    first, second = lengths[0], lengths[0] + lengths[1]
    width_a = min(.008, lengths[0] * .27, lengths[1] * .27)
    width_b = min(.007, lengths[1] * .27, lengths[2] * .27)
    if arc < first - width_a:
        return {names[0]: 1.0}
    if arc <= first + width_a:
        fraction = _smoothstep((arc - first + width_a) / (2.0 * width_a))
        return {names[0]: 1.0 - fraction, names[1]: fraction}
    if arc < second - width_b:
        return {names[1]: 1.0}
    if arc <= second + width_b:
        fraction = _smoothstep((arc - second + width_b) / (2.0 * width_b))
        return {names[1]: 1.0 - fraction, names[2]: fraction}
    return {names[2]: 1.0}


def _maximum_weight_error(left, right):
    return max((abs(left.get(name, 0.0) - right.get(name, 0.0))
                for name in set(left) | set(right)), default=0.0)


def closest_chain(point, chain):
    """Distance to finite segments, with signed extension before chain root."""
    choices = []
    offset = 0.0
    for index, (a, b) in enumerate(chain):
        direction = b - a
        length = direction.length
        parameter = (point - a).dot(direction) / direction.length_squared
        finite = min(1.0, max(0.0, parameter))
        distance = (point - (a + finite * direction)).length
        arc = offset + finite * length
        if index == 0 and parameter < 0.0:
            arc = parameter * length
        choices.append((distance, arc, index))
        offset += length
    return min(choices, key=lambda value: value[0])


def audit_hand_patch(patch, body_reference, human_reference, original_body):
    if patch.get("patch_revision") == 5:
        return _audit_revision_5(patch, body_reference, human_reference, original_body)
    issues = []
    exceptions = []
    rows = patch.get("vertices", patch.get("rows", []))
    bones = human_reference["bones"]
    positions = body_reference["positions"]
    weights = body_reference["weights"]
    eligibility = patch.get("eligibility", {})
    standard = {
        "minimum_original_same_hand_weight_sum": 0.5,
        "minimum_hand_rest_local_y_metres": 0.025,
        "maximum_nearest_finger_chain_distance_metres": 0.026,
        "minimum_chain_arc_metres": -0.018,
        "maximum_output_influences": 4,
    }
    for key, expected in standard.items():
        if eligibility.get(key) != expected:
            issues.append({"issue": "general_eligibility_rule_changed", "field": key,
                           "expected": expected, "actual": eligibility.get(key)})
    if (patch.get("source_glb_sha256") != SOURCE_GLB_SHA256
            or patch.get("source_vertex_count") != 4868
            or patch.get("source_bone_count") != 59
            or patch.get("source_mesh") != "Human_Body"):
        issues.append({"issue": "source_identity_mismatch"})
    if patch.get("changed_vertices") != len(rows):
        issues.append({"issue": "declared_row_count_mismatch"})
    revision_4 = patch.get("patch_revision") == 4
    revision_3 = patch.get("patch_revision") in (3, 4)
    if revision_3:
        expected_previous = FROZEN_V3_PATCH_SHA256 if revision_4 else FROZEN_V2_PATCH_SHA256
        if (patch.get("previous_patch_sha256") != expected_previous
                or patch.get("frozen_revision_2_rows_sha256") != FROZEN_V2_ROWS_SHA256):
            issues.append({"issue": "prior_patch_or_frozen_revision_2_provenance_mismatch"})
        frozen_rows = [row.get("frozen_revision_2_row", row) for row in rows if row.get("finger") != "Palm"]
        frozen_hash = hashlib.sha256(json.dumps(frozen_rows, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        if len(frozen_rows) != 791 or frozen_hash != FROZEN_V2_ROWS_SHA256:
            issues.append({"issue": "frozen_791_records_not_recoverable_exactly"})
        if eligibility.get("reviewed_proximal_index_middle_web_vertices") != [444, 479]:
            issues.append({"issue": "reviewed_web_vertex_declaration_changed"})
        for key, expected in PALM_LIMITS.items():
            if eligibility.get("palm_extension", {}).get(key) != expected:
                issues.append({"issue": "palm_rule_changed", "field": key,
                               "expected": expected, "actual": eligibility.get("palm_extension", {}).get(key)})
        palm_counts = {side: sum(row.get("finger") == "Palm" and row.get("side") == side for row in rows)
                       for side in ("Left", "Right")}
        if len(rows) != 1060 or palm_counts != {"Left": 143, "Right": 126}:
            issues.append({"issue": "reviewed_revision_3_row_count_changed", "palm_counts": palm_counts})
    if revision_4:
        reviewed_ids = sorted(DISTAL_MIDDLE_REVIEW)
        if (patch.get("frozen_revision_3_rows_sha256") != FROZEN_V3_ROWS_SHA256
                or eligibility.get("reviewed_distal_middle_topology_vertices") != reviewed_ids):
            issues.append({"issue": "reviewed_revision_4_provenance_or_vertex_declaration_changed"})
        recovered_v3 = [row.get("frozen_revision_3_row", row) for row in rows]
        recovered_hash = hashlib.sha256(json.dumps(recovered_v3, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        if len(recovered_v3) != 1060 or recovered_hash != FROZEN_V3_ROWS_SHA256:
            issues.append({"issue": "frozen_1060_revision_3_records_not_recoverable_exactly"})
        revised_ids = sorted(row.get("vertex") for row in rows if "frozen_revision_3_row" in row)
        if revised_ids != reviewed_ids:
            issues.append({"issue": "unreviewed_revision_4_row_change", "vertices": revised_ids})
        expected_counts = {
            "Left": {"Index": 88, "Middle": 71, "Palm": 143, "Pinky": 58, "Ring": 72, "Thumb": 87},
            "Right": {"Index": 88, "IndexMiddleWeb": 2, "Middle": 97, "Palm": 126, "Pinky": 54, "Ring": 67, "Thumb": 107},
        }
        actual_counts = {side: {} for side in ("Left", "Right")}
        for row in rows:
            side, family = row.get("side"), row.get("finger")
            if side in actual_counts and isinstance(family, str):
                actual_counts[side][family] = actual_counts[side].get(family, 0) + 1
        if patch.get("counts") != expected_counts or actual_counts != expected_counts:
            issues.append({"issue": "reviewed_revision_4_family_counts_changed"})

    to_rig = Matrix(body_reference["rig_matrix_world"]).inverted() @ Matrix(body_reference["object_matrix_world"])
    inverses = {side: Matrix(bones[side + "Hand"]["matrix_local"]).inverted() for side in ("Left", "Right")}
    chains = {side: {family: [(Vector(bones[f"{side}Hand{family}{i}"]["head_local"]),
                               Vector(bones[f"{side}Hand{family}{i}"]["tail_local"]))
                              for i in range(1, 4)] for family in FAMILIES}
              for side in ("Left", "Right")}
    declared = eligibility.get("explicit_source_boundary_weight_outliers", [])
    if declared and (len(declared) != 1 or declared[0].get("vertices") != [741]):
        issues.append({"issue": "unreviewed_exception_declaration", "declaration": declared})
    exception_spec = declared[0] if len(declared) == 1 and declared[0].get("vertices") == [741] else None
    seen = set()
    row_stats = []
    palm_stats = []
    web_stats = []
    distal_middle_stats = []
    source_neighbors = {index: set() for index in set(WEB_REVIEW) | set(DISTAL_MIDDLE_REVIEW)}
    for edge in original_body.data.edges:
        a, b = edge.vertices
        if a in source_neighbors:
            source_neighbors[a].add(b)
        if b in source_neighbors:
            source_neighbors[b].add(a)
    distal_middle_tip_triangle = any(
        len(face.vertices) == 3 and set(face.vertices) == {105, 9, 123}
        for face in original_body.data.polygons)
    distal_middle_polygons = [
        {"polygon": face.index, "vertices": list(face.vertices)}
        for face in original_body.data.polygons if any(index in DISTAL_MIDDLE_REVIEW for index in face.vertices)]
    distal_middle_topology_hash = hashlib.sha256(
        json.dumps(distal_middle_polygons, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if revision_4 and (len(distal_middle_polygons) != 27 or
                       distal_middle_topology_hash != DISTAL_MIDDLE_SOURCE_POLYGONS_SHA256):
        issues.append({"issue": "distal_middle_reviewed_27_source_polygons_changed"})
    for row in rows:
        index = row.get("vertex")
        side = row.get("side")
        if not isinstance(index, int) or not 0 <= index < len(positions) or index in seen or side not in inverses:
            issues.append({"issue": "invalid_row_identity", "vertex": index, "side": side})
            continue
        seen.add(index)
        source_weights = weights[index]
        hand = side + "Hand"
        mass = sum(weight for bone, weight in source_weights.items() if bone.startswith(hand))
        point = to_rig @ Vector(positions[index])
        local = inverses[side] @ point
        row_issues = []
        is_exception = row.get("eligibility_exception") is not None
        if row.get("finger") == "Palm":
            if not revision_3 or is_exception or index in (741, 742):
                row_issues.append("unreviewed_palm_row")
            if (mass < .5 - 1e-7 or not -.052 - 1e-7 <= local.x <= .052 + 1e-7
                    or not .025 - 1e-7 <= local.y <= .110 + 1e-7
                    or not -.035 - 1e-7 <= local.z <= .030 + 1e-7):
                row_issues.append("outside_reviewed_central_palm_bounds")
            family, (distance, arc, segment) = min(
                ((family, closest_chain(point, chain)) for family, chain in chains[side].items()),
                key=lambda item: item[1][0])
            if distance <= .026 - 1e-7 and arc >= -.018 + 1e-7:
                row_issues.append("palm_row_overlaps_standard_finger_capsule")
            if row.get("nearest_family") != family:
                row_issues.append("palm_nearest_family_mismatch")
            for key, measured in (("hand_local_y", local.y), ("nearest_chain_distance", distance),
                                  ("chain_arc_metres", arc)):
                if (not math.isfinite(float(row.get(key, float("inf"))))
                        or abs(float(row.get(key, 0.0)) - measured) > 1e-6):
                    row_issues.append("reported_palm_geometry_mismatch:" + key)
            declared_local = row.get("hand_local_position", [])
            if (len(declared_local) != 3 or any(not math.isfinite(float(value)) for value in declared_local)
                    or (Vector(declared_local) - local).length > 1e-6):
                row_issues.append("reported_palm_local_position_mismatch")
            lateral = local.x * (1 if side == "Left" else -1)
            blend_family, blend_arc = family, arc
            if lateral > .020:
                blend_family = "Thumb"
                blend_arc = closest_chain(point, chains[side]["Thumb"])[1]
                envelope = _smoothstep((lateral - .020) / .025) * (1 - _smoothstep((local.y - .085) / .025))
            else:
                envelope = 1 - _smoothstep((distance - .018) / .016)
            if row.get("blend_family") != blend_family or abs(float(row.get("blend_chain_arc_metres", float("inf"))) - blend_arc) > 1e-6:
                row_issues.append("palm_blend_branch_mismatch")
            partial = _independent_finger_distribution(hand, blend_family, blend_arc, chains[side][blend_family])
            partial = {name: value * envelope for name, value in partial.items()}
            partial[hand] = partial.get(hand, 0.0) + 1 - envelope
            total = sum(partial.values())
            partial = {name: value / total for name, value in partial.items() if value > 1e-8}
            target = {name: value for name, value in source_weights.items()
                      if not name.startswith(hand) and value > 1e-8}
            target.update({name: value * mass for name, value in partial.items() if value * mass > 1e-8})
            replacement = {part["bone"]: float(part["weight"]) for part in row["weights"]}
            error = _maximum_weight_error(target, replacement)
            if error > 2e-6:
                row_issues.append("palm_weights_do_not_match_independent_source_geometry")
            nonhand_error = max((abs(source_weights.get(name, 0.0) - replacement.get(name, 0.0))
                                for name in set(source_weights) | set(replacement) if not name.startswith(hand)), default=0.0)
            if nonhand_error > 1e-12:
                row_issues.append("palm_original_nonhand_influence_changed")
            if len(replacement) > 4 or abs(sum(replacement.values()) - 1.0) > 1e-6:
                row_issues.append("palm_output_not_normalized_within_four_influences")
            palm_stats.append({"vertex": index, "side": side, "passed": not row_issues,
                               "hand_local": list(local), "hand_mass": mass,
                               "independent_weight_error": error, "nonhand_weight_error": nonhand_error})
        elif row.get("eligibility_exception") == "source_proximal_index_middle_web":
            spec = WEB_REVIEW.get(index)
            if (not revision_3 or spec is None or side != "Right" or row.get("finger") != "IndexMiddleWeb"):
                row_issues.append("unreviewed_proximal_web_row")
            else:
                if mass < .999 or any(not low <= value <= high for value, (low, high) in zip(local, spec["local_bounds"])):
                    row_issues.append("web_source_position_or_hand_mass_changed")
                neighbors = sorted(source_neighbors[index])
                if neighbors != spec["neighbors"] or row.get("source_neighbors") != neighbors:
                    row_issues.append("web_original_mesh_adjacency_changed")
                index_distance = closest_chain(point, chains[side]["Index"])[0]
                middle_distance = closest_chain(point, chains[side]["Middle"])[0]
                if max(index_distance, middle_distance) > .014 or abs(index_distance - middle_distance) > .0011:
                    row_issues.append("web_outside_reviewed_ambiguous_proximal_roots")
                old_row = row.get("frozen_revision_2_row", {})
                if old_row.get("vertex") != index or old_row.get("finger") != "Index":
                    row_issues.append("web_frozen_revision_2_identity_mismatch")
                if row.get("same_hand_proportions") != spec["proportions"]:
                    row_issues.append("web_reviewed_proportions_changed")
                target = {name: value for name, value in source_weights.items() if not name.startswith(hand)}
                target.update({name: value * mass for name, value in spec["proportions"].items()})
                replacement = {part["bone"]: float(part["weight"]) for part in row["weights"]}
                error = _maximum_weight_error(target, replacement)
                if error > 1e-7:
                    row_issues.append("web_replacement_not_reviewed_proximal_blend")
                if len(replacement) > 4 or abs(sum(replacement.values()) - 1.0) > 1e-6:
                    row_issues.append("web_output_not_normalized_within_four_influences")
                web_stats.append({"vertex": index, "passed": not row_issues, "source_neighbors": neighbors,
                                  "hand_local": list(local), "replacement_error": error,
                                  "index_chain_distance": index_distance, "middle_chain_distance": middle_distance})
        elif row.get("eligibility_exception") == "source_distal_middle_topology":
            spec = DISTAL_MIDDLE_REVIEW.get(index)
            if (not revision_4 or spec is None or side != "Right" or row.get("finger") != "Middle"):
                row_issues.append("unreviewed_distal_middle_row")
            else:
                if (mass < .999 or (local - Vector(spec["local"])).length > 2e-6
                        or sum(value for name, value in source_weights.items()
                               if name.startswith("RightHandMiddle")) <= .5):
                    row_issues.append("distal_middle_original_position_or_family_mass_changed")
                neighbors = sorted(source_neighbors[index])
                if neighbors != spec["neighbors"] or row.get("source_neighbors") != neighbors:
                    row_issues.append("distal_middle_original_adjacency_changed")
                if not distal_middle_tip_triangle:
                    row_issues.append("distal_middle_reviewed_tip_triangle_missing")
                old_v3 = row.get("frozen_revision_3_row", {})
                old_v2 = row.get("frozen_revision_2_row", {})
                if (old_v3.get("vertex") != index or old_v3.get("side") != "Right"
                        or old_v3.get("finger") != "Ring" or old_v2 != old_v3):
                    row_issues.append("distal_middle_frozen_row_identity_mismatch")
                distance, arc, segment = closest_chain(point, chains[side]["Middle"])
                if distance > .0177 or not .0478 <= arc <= .0909 or segment not in (1, 2):
                    row_issues.append("distal_middle_outside_reviewed_own_chain_region")
                for key, measured in (("hand_local_y", local.y), ("nearest_chain_distance", distance),
                                      ("chain_arc_metres", arc)):
                    if (not math.isfinite(float(row.get(key, float("inf"))))
                            or abs(float(row.get(key, 0.0)) - measured) > 1e-6):
                        row_issues.append("distal_middle_reported_geometry_mismatch:" + key)
                partial = _independent_finger_distribution(hand, "Middle", arc, chains[side]["Middle"])
                if _maximum_weight_error(partial, spec["proportions"]) > 2e-6:
                    row_issues.append("distal_middle_independent_interpolation_changed")
                declared_proportions = row.get("same_hand_proportions", {})
                if (set(declared_proportions) != set(spec["proportions"])
                        or _maximum_weight_error(declared_proportions, spec["proportions"]) > 2e-6):
                    row_issues.append("distal_middle_reviewed_proportions_changed")
                target = {name: value for name, value in source_weights.items() if not name.startswith(hand)}
                target.update({name: value * mass for name, value in partial.items() if value * mass > 1e-8})
                replacement = {part["bone"]: float(part["weight"]) for part in row["weights"]}
                error = _maximum_weight_error(target, replacement)
                nonhand_error = max((abs(source_weights.get(name, 0.0) - replacement.get(name, 0.0))
                                    for name in set(source_weights) | set(replacement)
                                    if not name.startswith(hand)), default=0.0)
                if error > 2e-6 or nonhand_error > 1e-12:
                    row_issues.append("distal_middle_weights_do_not_match_independent_source_geometry")
                if (len(replacement) > 4 or any(not math.isfinite(value) or value < 0 for value in replacement.values())
                        or abs(sum(replacement.values()) - 1.0) > 1e-6):
                    row_issues.append("distal_middle_output_not_normalized_within_four_influences")
                distal_middle_stats.append({
                    "vertex": index, "passed": not row_issues, "source_neighbors": neighbors,
                    "hand_local": list(local), "source_middle_family_mass": sum(
                        value for name, value in source_weights.items() if name.startswith("RightHandMiddle")),
                    "middle_chain_distance": distance, "middle_chain_arc": arc,
                    "independent_weight_error": error, "nonhand_weight_error": nonhand_error,
                })
        elif is_exception:
            # These numbers are independently bound to the immutable original
            # body, not taken from arbitrary replacement thresholds in JSON.
            if (index != 741 or side != "Right" or row.get("finger") != "Thumb"
                    or row.get("eligibility_exception") != "source_boundary_thumb_weight_outlier_741"
                    or row.get("copied_same_hand_proportions_from_vertex") != 742
                    or exception_spec is None):
                row_issues.append("unreviewed_exception_row")
            else:
                for key, expected in {
                    "source_neighbor": 742,
                    "minimum_original_same_hand_weight_sum": 0.999,
                    "hand_rest_local_y_range_metres": [0.01818, 0.01820],
                    "maximum_rest_distance_to_source_neighbor_metres": 0.00155,
                }.items():
                    if exception_spec.get(key) != expected:
                        row_issues.append("exception_limit_changed:" + key)
                if mass < 0.999 or not 0.01818 <= local.y <= 0.01820:
                    row_issues.append("exception_source_region_mismatch")
                distance = (Vector(positions[index]) - Vector(positions[742])).length
                if distance > 0.00155:
                    row_issues.append("source_neighbor_too_distant")
                for key, expected in {
                    "source_hand_local_y_metres": local.y,
                    "source_forearm_weight": source_weights.get("RightForeArm", 0.0),
                    "source_thumb1_weight": source_weights.get("RightHandThumb1", 0.0),
                }.items():
                    if abs(float(exception_spec.get(key, float("inf"))) - expected) > 1e-7:
                        row_issues.append("exception_source_value_mismatch:" + key)
                expected_edges = {(640, 741), (741, 742), (640, 742)}
                listed_edges = {tuple(sorted(edge)) for edge in exception_spec.get("source_boundary_edges", [])}
                triangle_present = any(len(face.vertices) == 3 and set(face.vertices) == {640, 741, 742}
                                       for face in original_body.data.polygons)
                if listed_edges != expected_edges or not triangle_present:
                    row_issues.append("original_boundary_triangle_mismatch")
                old_nonhand = {bone: value for bone, value in source_weights.items() if not bone.startswith(hand)}
                neighbor_hand = {bone: value for bone, value in weights[742].items() if bone.startswith(hand)}
                neighbor_mass = sum(neighbor_hand.values())
                target = dict(old_nonhand)
                target.update({bone: value / neighbor_mass * (1.0 - sum(old_nonhand.values()))
                               for bone, value in neighbor_hand.items()})
                replacement = {part["bone"]: float(part["weight"]) for part in row["weights"]}
                error = max((abs(target.get(bone, 0.0) - replacement.get(bone, 0.0))
                             for bone in set(target) | set(replacement)), default=0.0)
                if error > 1e-7:
                    row_issues.append("neighbor_hand_proportions_not_preserved")
                nonhand_error = max((abs(source_weights.get(bone, 0.0) - replacement.get(bone, 0.0))
                                    for bone in set(source_weights) | set(replacement) if not bone.startswith(hand)), default=0.0)
                if nonhand_error > 1e-12:
                    row_issues.append("original_exception_nonhand_weight_changed")
                exceptions.append({"vertex": index, "passed": not row_issues,
                                   "source_hand_mass": mass, "source_hand_rest_local_y": local.y,
                                   "neighbor_vertex": 742, "source_neighbor_distance_metres": distance,
                                   "maximum_neighbor_proportion_error": error,
                                   "maximum_nonhand_weight_error": nonhand_error,
                                   "original_boundary_triangle_present": triangle_present})
        else:
            if mass < 0.5 - 1e-7 or local.y < 0.025 - 1e-7:
                row_issues.append("outside_general_distal_hand_region")
            family, (distance, arc, segment) = min(
                ((family, closest_chain(point, chain)) for family, chain in chains[side].items()),
                key=lambda item: item[1][0])
            if distance > 0.026 + 1e-7 or arc < -0.018 - 1e-7:
                row_issues.append("outside_own_finger_chain_capsule")
            if family != row.get("finger"):
                row_issues.append("claimed_finger_is_not_nearest_chain")
            for key, measured in (("hand_local_y", local.y), ("nearest_chain_distance", distance),
                                  ("chain_arc_metres", arc)):
                if not math.isfinite(float(row.get(key, float("inf")))) or abs(float(row.get(key, 0.0)) - measured) > 1e-6:
                    row_issues.append("reported_geometry_mismatch:" + key)
            row_stats.append({"vertex": index, "side": side, "hand_mass": mass,
                              "hand_rest_local_y": local.y, "chain_distance": distance, "chain_arc": arc})
        if row_issues:
            issues.append({"vertex": index, "issues": row_issues})
    if exception_spec is not None and len(exceptions) != 1:
        issues.append({"issue": "declared_exception_not_present_once"})
    if revision_3 and sorted(row["vertex"] for row in web_stats) != [444, 479]:
        issues.append({"issue": "declared_proximal_web_rows_not_present_once"})
    if revision_4 and sorted(row["vertex"] for row in distal_middle_stats) != sorted(DISTAL_MIDDLE_REVIEW):
        issues.append({"issue": "declared_distal_middle_rows_not_present_once"})
    return {
        "passed": not issues, "issues": issues, "general_vertices_checked": len(row_stats),
        "minimum_general_hand_mass": min((row["hand_mass"] for row in row_stats), default=None),
        "minimum_general_hand_local_y_metres": min((row["hand_rest_local_y"] for row in row_stats), default=None),
        "maximum_general_chain_distance_metres": max((row["chain_distance"] for row in row_stats), default=None),
        "minimum_general_chain_arc_metres": min((row["chain_arc"] for row in row_stats), default=None),
        "reviewed_exception_vertices": [row["vertex"] for row in exceptions if row["passed"]],
        "exceptions": exceptions,
        "central_palm_vertices_checked": len(palm_stats),
        "central_palm_bounds_independently_verified": all(row["passed"] for row in palm_stats),
        "central_palm_maximum_independent_weight_error": max((row["independent_weight_error"] for row in palm_stats), default=0.0),
        "central_palm_maximum_nonhand_weight_error": max((row["nonhand_weight_error"] for row in palm_stats), default=0.0),
        "central_palm_rows": palm_stats,
        "reviewed_multi_family_vertices": [row["vertex"] for row in web_stats if row["passed"]],
        "proximal_web_rows": web_stats,
        "reviewed_distal_middle_vertices": [row["vertex"] for row in distal_middle_stats if row["passed"]],
        "distal_middle_rows": distal_middle_stats,
        "distal_middle_tip_triangle_present": distal_middle_tip_triangle,
        "distal_middle_source_polygon_count": len(distal_middle_polygons),
        "distal_middle_source_polygons_sha256": distal_middle_topology_hash,
    }


def _audit_revision_5(patch, body_reference, human_reference, original_body):
    """Independent four-row review on an exactly reconstructed revision 4.

    Do not import the patch author here: fixed source observations and a
    separate interpolation implementation provide independent validation.
    No pose, mesh or skeleton is modified by this audit.
    """
    issues = []
    rows = patch.get("vertices", [])
    reviewed_ids = sorted(LEFT_DISTAL_REVIEW)
    actual_ids = sorted(row.get("vertex", -1) for row in rows if "frozen_revision_4_row" in row)
    eligibility = patch.get("eligibility", {})
    if (patch.get("previous_patch_sha256") != FROZEN_V4_PATCH_SHA256
            or patch.get("frozen_revision_4_rows_sha256") != FROZEN_V4_ROWS_SHA256
            or eligibility.get("reviewed_left_distal_middle_topology_vertices") != reviewed_ids
            or eligibility.get("reviewed_left_middle_ring_web") != LEFT_MIDDLE_RING_WEB):
        issues.append({"issue": "revision_5_provenance_or_four_vertex_declaration_changed"})
    if actual_ids != reviewed_ids:
        issues.append({"issue": "unreviewed_revision_5_rows", "vertices": actual_ids})
    recovered_rows = [copy.deepcopy(row.get("frozen_revision_4_row", row)) for row in rows]
    recovered_hash = hashlib.sha256(json.dumps(recovered_rows, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if len(recovered_rows) != 1060 or recovered_hash != FROZEN_V4_ROWS_SHA256:
        issues.append({"issue": "frozen_1060_revision_4_records_not_recoverable_exactly"})
    expected_counts = {
        "Left": {"Index": 88, "Middle": 75, "Palm": 143, "Pinky": 58, "Ring": 68, "Thumb": 87},
        "Right": {"Index": 88, "IndexMiddleWeb": 2, "Middle": 97, "Palm": 126, "Pinky": 54, "Ring": 67, "Thumb": 107},
    }
    actual_counts = {side: {} for side in ("Left", "Right")}
    for row in rows:
        side, family = row.get("side"), row.get("finger")
        if side in actual_counts and isinstance(family, str):
            actual_counts[side][family] = actual_counts[side].get(family, 0) + 1
    if patch.get("counts") != expected_counts or actual_counts != expected_counts:
        issues.append({"issue": "reviewed_revision_5_family_counts_changed"})
    if patch.get("changed_vertices") != 1060:
        issues.append({"issue": "reviewed_revision_5_row_count_changed"})

    base = copy.deepcopy(patch)
    base["vertices"] = recovered_rows
    base["patch_revision"] = 4
    base["previous_patch_sha256"] = FROZEN_V3_PATCH_SHA256
    base.pop("frozen_revision_4_rows_sha256", None)
    base["eligibility"].pop("reviewed_left_distal_middle_topology_vertices", None)
    base["eligibility"].pop("reviewed_left_middle_ring_web", None)
    if not base.get("method", "").endswith(LEFT_DISTAL_METHOD_SUFFIX):
        issues.append({"issue": "reviewed_revision_5_method_suffix_changed"})
    else:
        base["method"] = base["method"][:-len(LEFT_DISTAL_METHOD_SUFFIX)]
    # Keep original dictionary order as well as values: the complete patch
    # digest binds the byte-exact previous JSON serialization.
    base["counts"] = copy.deepcopy(patch.get("counts", {}))
    base["counts"].setdefault("Left", {})["Middle"] = 71
    base["counts"]["Left"]["Ring"] = 72
    full_recovered_hash = hashlib.sha256((json.dumps(base, indent=2) + "\n").encode()).hexdigest()
    if full_recovered_hash != FROZEN_V4_PATCH_SHA256:
        issues.append({"issue": "complete_revision_4_patch_not_recoverable_exactly"})
    inherited = audit_hand_patch(base, body_reference, human_reference, original_body)
    if not inherited["passed"]:
        issues.append({"issue": "inherited_revision_4_audit_failed", "prior_issues": inherited["issues"]})

    bones = human_reference["bones"]
    positions, weights = body_reference["positions"], body_reference["weights"]
    to_rig = Matrix(body_reference["rig_matrix_world"]).inverted() @ Matrix(body_reference["object_matrix_world"])
    inverse_hand = Matrix(bones["LeftHand"]["matrix_local"]).inverted()
    chain = [(Vector(bones[f"LeftHandMiddle{i}"]["head_local"]),
              Vector(bones[f"LeftHandMiddle{i}"]["tail_local"])) for i in (1, 2, 3)]
    ring_chain = [(Vector(bones[f"LeftHandRing{i}"]["head_local"]),
                   Vector(bones[f"LeftHandRing{i}"]["tail_local"])) for i in (1, 2, 3)]
    source_neighbors = {index: set() for index in reviewed_ids}
    eligible = {index for index, position in enumerate(positions)
                if (inverse_hand @ to_rig @ Vector(position)).y > .15
                and sum(weight for bone, weight in weights[index].items() if bone.startswith("LeftHand")) > .5}
    adjacency = {index: set() for index in eligible}
    for edge in original_body.data.edges:
        a, b = map(int, edge.vertices)
        if a in source_neighbors:
            source_neighbors[a].add(b)
        if b in source_neighbors:
            source_neighbors[b].add(a)
        if a in adjacency and b in adjacency:
            adjacency[a].add(b)
            adjacency[b].add(a)
    component = {4637} if 4637 in adjacency else set()
    queue = list(component)
    while queue:
        for neighbor in adjacency[queue.pop()]:
            if neighbor not in component:
                component.add(neighbor)
                queue.append(neighbor)
    if len(component) != 47 or not set(reviewed_ids).issubset(component):
        issues.append({"issue": "left_middle_topology_separated_component_changed", "component_size": len(component)})
    polygons = [{"polygon": face.index, "vertices": list(face.vertices)}
                for face in original_body.data.polygons if any(index in LEFT_DISTAL_REVIEW for index in face.vertices)]
    topology_hash = hashlib.sha256(json.dumps(polygons, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if len(polygons) != 21 or topology_hash != LEFT_DISTAL_SOURCE_POLYGONS_SHA256:
        issues.append({"issue": "left_middle_reviewed_21_source_polygons_changed"})
    row_map = {row.get("vertex"): row for row in rows}
    reviewed_rows = []
    for index, spec in LEFT_DISTAL_REVIEW.items():
        row = row_map.get(index, {})
        row_issues = []
        source_weights = weights[index]
        mass = sum(value for name, value in source_weights.items() if name.startswith("LeftHand"))
        middle_mass = sum(value for name, value in source_weights.items() if name.startswith("LeftHandMiddle"))
        point = to_rig @ Vector(positions[index])
        local = inverse_hand @ point
        if (row.get("side") != "Left" or row.get("finger") != "Middle"
                or row.get("eligibility_exception") != "source_left_distal_middle_topology"):
            row_issues.append("unreviewed_left_middle_row_identity")
        if (mass < .999 or (local - Vector(spec["local"])).length > 2e-6
                or abs(middle_mass - spec["middle_source_mass"]) > 1e-6):
            row_issues.append("left_middle_original_position_or_family_mass_changed")
        neighbors = sorted(source_neighbors[index])
        if neighbors != spec["neighbors"] or row.get("source_neighbors") != neighbors:
            row_issues.append("left_middle_original_adjacency_changed")
        old = row.get("frozen_revision_4_row", {})
        if old.get("vertex") != index or old.get("side") != "Left" or old.get("finger") != "Ring":
            row_issues.append("left_middle_frozen_revision_4_identity_mismatch")
        distance, arc, segment = closest_chain(point, chain)
        if distance > .016 or not .037 <= arc <= .0884 or segment not in (0, 1, 2):
            row_issues.append("left_middle_outside_reviewed_chain_region")
        for key, measured in (("hand_local_y", local.y), ("nearest_chain_distance", distance),
                              ("chain_arc_metres", arc)):
            if (not math.isfinite(float(row.get(key, float("inf"))))
                    or abs(float(row.get(key, 0.0)) - measured) > 1e-6):
                row_issues.append("left_middle_reported_geometry_mismatch:" + key)
        partial = _independent_finger_distribution("LeftHand", "Middle", arc, chain)
        if index == 4597:
            ring_arc = closest_chain(point, ring_chain)[1]
            ring_partial = _independent_finger_distribution("LeftHand", "Ring", ring_arc, ring_chain)
            prior_ring = {part["bone"]: float(part["weight"]) for part in old.get("weights", [])}
            if _maximum_weight_error(prior_ring, ring_partial) > 2e-6:
                row_issues.append("left_web_previous_ring_distribution_changed")
            partial = {name: .5 * value for name, value in partial.items()}
            partial.update({name: .5 * value for name, value in ring_partial.items()})
            if row.get("web_blend") != LEFT_MIDDLE_RING_WEB:
                row_issues.append("left_web_half_blend_declaration_changed")
        elif "web_blend" in row:
            row_issues.append("unreviewed_left_web_blend")
        if _maximum_weight_error(partial, spec["proportions"]) > 2e-6:
            row_issues.append("left_middle_independent_interpolation_changed")
        declared = row.get("same_hand_proportions", {})
        if set(declared) != set(spec["proportions"]) or _maximum_weight_error(declared, spec["proportions"]) > 2e-6:
            row_issues.append("left_middle_reviewed_proportions_changed")
        target = {name: value for name, value in source_weights.items() if not name.startswith("LeftHand")}
        target.update({name: value * mass for name, value in partial.items() if value * mass > 1e-8})
        replacement = {part["bone"]: float(part["weight"]) for part in row.get("weights", [])}
        error = _maximum_weight_error(target, replacement)
        nonhand_error = max((abs(source_weights.get(name, 0.0) - replacement.get(name, 0.0))
                            for name in set(source_weights) | set(replacement)
                            if not name.startswith("LeftHand")), default=0.0)
        if error > 2e-6 or nonhand_error > 1e-12:
            row_issues.append("left_middle_weights_do_not_match_independent_source_geometry")
        if (len(replacement) > 4 or any(not math.isfinite(value) or value < 0 for value in replacement.values())
                or abs(sum(replacement.values()) - 1.0) > 1e-6):
            row_issues.append("left_middle_output_not_normalized_within_four_influences")
        reviewed_rows.append({"vertex": index, "passed": not row_issues, "source_neighbors": neighbors,
                              "hand_local": list(local), "source_middle_family_mass": middle_mass,
                              "middle_chain_distance": distance, "middle_chain_arc": arc,
                              "independent_weight_error": error, "nonhand_weight_error": nonhand_error})
        if row_issues:
            issues.append({"vertex": index, "issues": row_issues})
    return {
        "passed": not issues, "issues": issues, "skin_patch_revision": 5,
        "reviewed_exception_vertices": inherited["reviewed_exception_vertices"],
        "reviewed_multi_family_vertices": inherited["reviewed_multi_family_vertices"],
        "reviewed_distal_middle_vertices": inherited["reviewed_distal_middle_vertices"],
        "reviewed_left_distal_middle_vertices": [row["vertex"] for row in reviewed_rows if row["passed"]],
        "reviewed_middle_ring_web_vertices": [row["vertex"] for row in reviewed_rows if row["passed"] and row["vertex"] == 4597],
        "left_distal_middle_rows": reviewed_rows,
        "left_distal_middle_source_polygon_count": len(polygons),
        "left_distal_middle_source_polygons_sha256": topology_hash,
        "left_middle_topology_component_vertices": sorted(component),
        "complete_recovered_revision4_sha256": full_recovered_hash,
        "inherited_revision4_audit": inherited,
        "scope": "Exactly four left Middle ownership rows plus full independent validation of recovered revision 4; geometry/rest preservation and collision clearance are separate checks.",
    }
