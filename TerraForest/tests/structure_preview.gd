# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var blocks: Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks)
	blocks.set_collision_radius(0)
	check(blocks.preview_mesh(0,0)==null and blocks.preview_mesh(1,4)==null,"preview rejects invalid shape and rotation")
	for shape in range(1,7):
		for rotation in range(4):
			var before: PackedByteArray=blocks.capture_snapshot()
			var preview: Mesh=blocks.preview_mesh(shape,rotation)
			var same: bool=preview!=null and preview==blocks.preview_mesh(shape,rotation) and blocks.capture_snapshot()==before
			blocks.set_cells(PackedInt32Array([0,0,0,shape+(rotation<<3)]));blocks.flush_bakes()
			var actual: Mesh
			for child in blocks.get_children():
				if child is MeshInstance3D: actual=child.mesh
			if preview==null or actual==null:
				same=false
			else:
				var p: Array=preview.surface_get_arrays(0)
				var a: Array=actual.surface_get_arrays(0)
				for field in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_INDEX]: same=same and p[field]==a[field]
			check(same,"shape %d rotation %d preview matches placed geometry, is cached and does not edit world"%[shape,rotation])
	blocks.free();quit(1 if failures else 0)
