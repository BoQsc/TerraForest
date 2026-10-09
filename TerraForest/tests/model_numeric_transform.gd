# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var collection=ClassDB.instantiate("NativeStaticBatch");root.add_child(collection)
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,3,2)
	collection.configure_asset("tests/numeric_model",mesh)
	var camera:=Camera3D.new();var player:=CharacterBody3D.new();var ui:=Control.new()
	root.add_child(camera);root.add_child(player);root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	camera.position=Vector3(17,10,18);camera.look_at(Vector3(10,2,0));camera.current=true
	player.position=Vector3(100,0,100)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);root.add_child(light)
	var tool=load("res://addons/structures/model_tool.gd").new();root.add_child(tool)
	var entries: Array[Dictionary]=[{"title":"Building module","mesh":mesh,"collection":collection,"scale":Vector3.ONE}]
	# Match the main-world palette's three catalog rows for layout coverage.
	for title in ["Floor module","Doorway module"]:
		entries.append({"title":title,"mesh":mesh,"collection":collection,"scale":Vector3.ONE})
	tool.configure(camera,player,entries,ui);tool.set_active(true);tool.edit_available=true
	var initial:=Transform3D(Basis.IDENTITY,Vector3(10,2,0))
	var id: int=tool.history.insert(collection,tool.records(initial,collection),tool.protection())
	check(id>0,"native placement fixture created")
	tool.picked_collection=collection;tool.picked_id=id;collection.changed.connect(tool._selected_changed)
	tool.transform_controls.show();tool.sync_numeric_transform();tool.update(0,true)
	check(tool.numeric_fields[0].value==10 and tool.numeric_fields[7].value==1,"selection populates world transform fields")
	var values: Array[float]=[12.25,3.5,-2.75,15,35,-10,1.25,0.75,2.0]
	for i in 9: tool.numeric_fields[i].value=values[i]
	tool.update(0.2,true)
	check(tool.numeric_fields[0].value==12.25,"preview refresh preserves pending numeric draft")
	var before_steps: int=tool.history.stats().undo_steps
	tool.numeric_apply.pressed.emit()
	var expected:=Transform3D(Basis.from_euler(Vector3(15,35,-10)*PI/180)*Basis.from_scale(Vector3(1.25,0.75,2)),Vector3(12.25,3.5,-2.75))
	var transformed: Transform3D=tool.selected_transform().transform
	check(transformed.is_equal_approx(expected),"apply button commits position rotation and nonuniform scale")
	check(tool.history.stats().undo_steps==before_steps+1,"numeric apply creates one native undo step")
	var encoded: PackedFloat32Array=collection.get_instance(id)
	tool.availability=func(): return false
	tool.numeric_fields[0].value=30
	check(not tool.apply_numeric_transform() and collection.get_instance(id)==encoded,"live admission rejects stale numeric apply")
	tool.update(0,true)
	check(tool.numeric_apply.disabled and not tool.numeric_fields[0].editable,"unavailable editor disables fields and apply")
	tool.availability=func(): return true
	tool.gameplay=true;tool.update(0,true)
	check(not tool.numeric_controls.visible and not tool.apply_numeric_transform() and collection.get_instance(id)==encoded,"gameplay hides and rejects numeric resizing")
	tool.gameplay=false;tool.update(0,true);tool.sync_numeric_transform()
	player.position=Vector3(30,0,0)
	for i in 9: tool.numeric_fields[i].value=[30,0.9,0,0,0,0,1,1,1][i]
	var overlapping_accepted: bool=tool.apply_numeric_transform()
	check(not overlapping_accepted and collection.get_instance(id)==encoded,"native player protection rejects overlapping transform without mutation")
	check(tool.history.stats().undo_steps==before_steps+1,"rejected transforms leave undo history unchanged")
	player.position=Vector3(100,0,100)
	check(tool.history.undo(tool.protection()) and collection.get_instance(id)==tool.records(initial,collection),"undo restores exact original record")
	check(tool.picked_id==0,"undo clears stale selection")
	check(tool.history.redo(tool.protection()) and collection.get_instance(id)==encoded,"redo restores exact numeric record")
	tool.picked_collection=collection;tool.picked_id=id;collection.changed.connect(tool._selected_changed)
	tool.transform_controls.show();tool.sync_numeric_transform();tool.update(0,true)
	await process_frame
	tool.numeric_fields[0].get_line_edit().grab_focus()
	tool.numeric_fields[0].get_line_edit().text="14.5"
	tool.numeric_apply.pressed.emit()
	check(is_equal_approx(tool.selected_transform().transform.origin.x,14.5),"apply commits text still focused in numeric field")
	tool.numeric_fields[0].get_line_edit().release_focus()
	if DisplayServer.get_name()!="headless":
		preload("res://addons/presentation/fullscreen_policy.gd").apply(root)
		for frame in 5: await process_frame
		check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1920x1080 fullscreen presentation")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/evidence/model_numeric_transform/scene.png")
	tool.free();collection.free();camera.free();player.free();ui.free();light.free();await process_frame
	print("MODEL_NUMERIC_TRANSFORM checks=",checks," failures=",failures)
	quit(1 if failures else 0)
