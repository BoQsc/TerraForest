# SPDX-License-Identifier: 0BSD
extends SceneTree
# Run with the pre-content-registry native library to regenerate real old saves.
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var directory := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture-output="): directory = argument.trim_prefix("--fixture-output=")
	if directory.is_empty(): quit(2); return
	var batch: Node3D = ClassDB.instantiate("NativeStaticBatch")
	var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
	var codec: RefCounted = ClassDB.instantiate("NativeStructuresSnapshot")
	var hinges: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	var id := "architecture/wooden_door/v1"
	if not batch.configure_asset(id, BoxMesh.new()) or not codec.configure_assets(PackedStringArray([id])): quit(1); return
	var pose := PackedFloat32Array([1,0,0,10,0,1,0,0,0,0,1,0])
	if not batch.upsert_instances(PackedInt64Array([7]),pose) or not hinges.toggle(batch,7,AABB()).ok: quit(1); return
	var models: PackedByteArray = codec.encode(blocks.capture_snapshot(),{id:batch.capture_snapshot()})
	FileAccess.open(directory.path_join("structures.bin"),FileAccess.WRITE).store_buffer(models)
	FileAccess.open(directory.path_join("hinges.bin"),FileAccess.WRITE).store_buffer(hinges.capture_storage_snapshot())
	batch.free();blocks.free()
	print("LEGACY_DOOR_CAPTURE ok")
	quit()
