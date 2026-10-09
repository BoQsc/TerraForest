# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func shadows(batch: Node,enabled: bool) -> bool:
	if batch.get_child_count()==0: return false
	for child in batch.get_children():
		if child.cast_shadow!=(GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF): return false
	return true
func ticks() -> void:
	for i in range(4): await process_frame
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
	check(batch.configure_asset("shadow/test/v1",BoxMesh.new()) and batch.configure_render_streaming(true,96,32,65536,4,8192),"native renderer configured")
	var poses: Array[Transform3D]=[Transform3D.IDENTITY]
	check(batch.upsert_transforms(PackedInt64Array([1]),poses),"initial instance accepted")
	await ticks()
	check(shadows(batch,true),"existing model default still casts shadows")
	var original: PackedByteArray=batch.capture_snapshot()
	batch.set_casts_shadows(false)
	check(shadows(batch,false) and batch.capture_snapshot()==original,"policy changes existing draw pages without modifying placements")
	poses=[Transform3D(Basis.IDENTITY,Vector3(40,0,0))]
	check(batch.upsert_transforms(PackedInt64Array([2]),poses),"second spatial group accepted")
	await ticks()
	check(batch.get_child_count()==2 and shadows(batch,false),"newly streamed pages inherit disabled casting")
	batch.set_casts_shadows(true)
	check(shadows(batch,true),"policy can restore casting on all live pages")
	batch.free()
	var result:={"checks":checks,"failures":failures}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/static_shadow_policy.json",FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
	print("STATIC_SHADOW_POLICY ",JSON.stringify(result))
	quit(1 if failures else 0)
