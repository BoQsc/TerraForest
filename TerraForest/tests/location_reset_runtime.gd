# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func _initialize()->void:
	for addon:String in ["player_runtime","vegetation_runtime"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,addon])
	run.call_deferred()

func run()->void:
	var inventory:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	for identity:int in [102,201,301]:inventory.register_item(identity,999)
	var corpses:RefCounted=ClassDB.instantiate("NativeCorpseStore")
	check(corpses.configure(inventory,4096,8),"corpse registry initializes")
	var bounds:=AABB(Vector3(100,80,100),Vector3.ONE*16)
	var owned:=PackedInt64Array([2501])
	check(not corpses.foreign_corpse_in_region(bounds,owned),"empty location is clear")
	var corpse:int=corpses.create_corpse(bounds.get_center(),0,1703,2501,1001)
	check(corpse>0 and not corpses.foreign_corpse_in_region(bounds,owned),"owned corpse is admissible")
	check(corpses.foreign_corpse_in_region(bounds,PackedInt64Array()),"unselected corpse is excluded")
	var before:PackedByteArray=corpses.capture_corpse_snapshot()
	for selection:PackedInt64Array in [PackedInt64Array([0]),PackedInt64Array([2501,2501])]:
		check(corpses.foreign_corpse_in_region(bounds,selection),"invalid ownership fails closed")
	check(corpses.foreign_corpse_in_region(AABB(),owned),"invalid volume fails closed")
	check(corpses.capture_corpse_snapshot()==before,"occupancy checks never mutate corpse state")
	for index in 24:corpses.create_corpse(Vector3(500+index,80,500),0,1703)
	var legacy:int=corpses.create_corpse(bounds.get_center(),0,1703)
	check(legacy>0 and corpses.foreign_corpse_in_region(bounds,owned),"dormant legacy corpse beyond twelve-body render budget blocks reset")
	var poses:=PackedFloat32Array()
	for index in 15:poses.append_array(PackedFloat32Array([1,0,0,500,0,1,0,80,0,0,1,500]))
	check(corpses.update_corpse(legacy,Vector3(500,80,500),0,0,poses) and not corpses.foreign_corpse_in_region(bounds,owned),"body wholly outside permits reset")
	poses[3]=108;poses[7]=88;poses[11]=108
	check(corpses.update_corpse(legacy,Vector3(500,80,500),0,0,poses) and corpses.foreign_corpse_in_region(bounds,owned),"limb in bounds excludes corpse even with root far outside")
	var world:=Node3D.new();root.add_child(world)
	var falls:Node3D=ClassDB.instantiate("NativeTreeFall");world.add_child(falls)
	check(falls.configure(BoxMesh.new()),"tree fall presentation initializes")
	check(falls.start(Transform3D(Basis.IDENTITY,bounds.position-Vector3(0,.2,0)),Vector3.RIGHT,.1) and falls.start(Transform3D(Basis.IDENTITY,Vector3(500,80,500)),Vector3.RIGHT,.2),"local and outside falling trees coexist")
	falls.clear_region(AABB());check(falls.count()==2,"invalid cleanup bounds leave trees alone")
	falls.clear_region(bounds);check(falls.count()==1,"root boundary compensation removes only owned falling tree")
	falls.clear_region(bounds);check(falls.count()==1,"repeated local fall cleanup is idempotent")
	var damage:RefCounted=ClassDB.instantiate("NativeWorldDurability")
	var fractures:Node3D=ClassDB.instantiate("NativeBoulderFracture");world.add_child(fractures)
	var material:=ShaderMaterial.new();material.shader=Shader.new();material.shader.code="shader_type spatial;"
	check(fractures.configure(BoxMesh.new(),material,damage),"native boulder presentation initializes")
	var rows:=PackedFloat32Array([1,0,0,108,0,1,0,88,0,0,1,108,1,0,0,500,0,1,0,80,0,0,1,500])
	check(fractures.upsert_rows(PackedInt64Array([100,200]),rows),"two boulder owners are resident")
	damage.hit("cover:100",240,80);fractures.sync_damage(100)
	damage.hit("cover:200",240,80);fractures.sync_damage(200)
	check(fractures.finish(100) and fractures.stage(100)==3 and fractures.stage(200)==1,"selected boulder reaches final transient fracture")
	var empty:RefCounted=ClassDB.instantiate("NativeWorldDurability")
	check(damage.restore_storage_snapshot(empty.capture_storage_snapshot()),"authoritative damage resets for presentation fixture")
	check(fractures.refresh_damage(PackedInt64Array([100])) and fractures.stage(100)==0 and fractures.stage(200)==1,"selected final fracture returns to whole without refreshing neighboring boulder")
	before=damage.capture_storage_snapshot()
	check(fractures.refresh_damage(PackedInt64Array([999])) and damage.capture_storage_snapshot()==before,"unloaded boulder refresh is harmless and never changes damage")
	world.free()
	await process_frame
	print("LOCATION_RESET_RUNTIME checks=",checks," failures=",failures)
	quit(1 if failures else 0)
