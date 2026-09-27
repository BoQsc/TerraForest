# SPDX-License-Identifier: 0BSD
# Per-live-patch cache only. No global growing registry; no simplified colliders.
extends RefCounted

static func digest(faces: PackedVector3Array) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(faces.to_byte_array()) != OK:
		return ""
	return context.finish().hex_encode()

static func prepare(faces: PackedVector3Array, previous: Dictionary, current: Dictionary) -> Dictionary:
	var token: String = digest(faces)
	var shape: ConcavePolygonShape3D = null
	if token != "":
		shape = previous.get(token) as ConcavePolygonShape3D
	# Check exact face values as well as the digest. Reused shapes are IMMUTABLE:
	# never call set_faces on a shape still used by an old visible/collision batch.
	var reused: bool = shape != null and shape.backface_collision and shape.get_faces() == faces
	if not reused:
		shape = ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
	if token != "":
		current[token] = shape
	return {"shape": shape, "reused": reused}
