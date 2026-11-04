# SPDX-License-Identifier: 0BSD
extends SceneTree
const Pickups=preload("res://addons/world_runtime/material_pickups.gd")
const Persistence=preload("res://addons/world_runtime/world_persistence.gd")
var checks:=0
var failures:=0
class TerrainFixture extends Node:
	var prepared_snapshot_components:Dictionary={}
	var snapshot_restore_ok:=true
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func bounds(node:Node3D)->AABB:
	var result:=AABB();var first:=true
	for child in node.find_children("*","MeshInstance3D",true,false):
		var box:AABB=node.global_transform.affine_inverse()*child.global_transform*child.mesh.get_aabb()
		result=box if first else result.merge(box);first=false
	return result
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:="res://reports/original_size_drops/source"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size-evidence="):output=arg.trim_prefix("--size-evidence=")
	var scene:=Node3D.new();root.add_child(scene)
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(30,.2,30);shape.shape=box;floor_body.add_child(shape)
	var floor_mesh:=MeshInstance3D.new();var plane:=BoxMesh.new();plane.size=box.size
	var material:=StandardMaterial3D.new();material.albedo_color=Color("45524c");plane.material=material;floor_mesh.mesh=plane;floor_body.add_child(floor_mesh);scene.add_child(floor_body);floor_body.position.y=-.1
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("182a28");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;scene.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);scene.add_child(sun)
	var provider:=Persistence.new();var full:=Pickups.new();scene.add_child(full)
	check(full.prepare(provider) and full.configure_physics(RID(),false) and full.full_size_enabled,"original-size item drops default enabled")
	var compact:=Pickups.new();scene.add_child(compact);compact.prepare(Persistence.new());compact.set_full_size_enabled(false)
	var view=preload("res://addons/player_runtime/tool_view.gd").new();scene.add_child(view)
	for item:int in [1,2,3,4,5,6]:
		var source_size:=Vector3.ZERO
		if item in [1,2]:
			view.human.equip(item);var extent:=AABB();var first:=true
			for mesh:MeshInstance3D in view.human.meshes:
				if not String(mesh.name).to_lower().replace("_",".").begins_with("equipment.") or not mesh.visible:continue
				var b:AABB=mesh.global_transform*mesh.mesh.get_aabb();extent=b if first else extent.merge(b);first=false
			source_size=extent.size
		elif item==4:source_size=bounds(view.tools[4]).size
		else:
			var source:Node3D=view.human.EQUIPMENT[item].instantiate();view.add_child(source);source_size=bounds(source).size;source.free()
		var mesh:Mesh=full.renderers[item].multimesh.mesh
		var factor:float=full.size_layouts[item].scale
		check((mesh.get_aabb().size*factor).distance_to(source_size)<.0001,"item %d uses its authored held-model dimensions: %s"%[item,source_size])
		check(full.collision_half(item).y>=source_size.y*.5 and full.collision_half(item).x>=source_size.x*.5,"item %d physics box encloses the full-size geometry"%item)
		check(compact.size_layouts[item].scale==1.0 and compact.visual_offset(item)==Vector3.ZERO,"item %d compact option retains original small representation"%item)
	view.hide()
	for index in 3:
		var item:int=[1,2,5][index]
		var at:=Vector3((index-1)*1.5,.17,-.8)
		full.spawn(item,at);compact.spawn(item,Vector3(at.x,.17,1))
		for mode in 2:
			var label:=Label3D.new();label.text=["Pickaxe","Hatchet","Shovel"][index]+(" · Authored size" if mode==0 else " · Compact 35 cm");label.font_size=24;label.pixel_size=.002;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.position=Vector3(at.x,.04,-1.2 if mode==0 else 1.45);scene.add_child(label)
	full.update_view(0,Vector3.ZERO,true);compact.update_view(0,Vector3.ZERO,true)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var transform:Transform3D=full.renderers[1].multimesh.get_instance_transform(0)
		check(absf(transform.basis.x.length()-full.size_layouts[1].scale)<.00001 and transform.origin.distance_to(Vector3(-1.5,.17,-.8)+full.visual_offset(1))<.00001,"native instance transform scales geometry and lifts it without scaling world positions")
	var inventory:RefCounted=preload("res://addons/player_runtime/item_catalog.gd").create_inventory()
	inventory.grant(1,1,0);inventory.wear_tool(0,7,inventory.snapshot().revision)
	var expected:Dictionary=inventory.snapshot().slots[0]
	var result:=full.drop_stack(inventory,0,inventory.snapshot().revision,Vector3(3,2,-2),1,true,Vector3(.4,.1,0))
	check(result.ok,"full-size worn pickaxe enters the existing physical transaction")
	var handle:int=full.stores[1].resolve_identity(result.id)
	for i in 150:
		full.step_physics(1.0/60,true,func(_bounds:AABB):return true);await physics_frame
	var landed:Vector3=full.stores[1].get_position(handle)
	var visual_bottom:float=landed.y+full.visual_offset(1).y-full.renderers[1].multimesh.mesh.get_aabb().size.y*full.size_layouts[1].scale*.5
	check(absf(landed.y-.17)<.04 and visual_bottom>-.01 and visual_bottom<.04,"full-size physics and rendered tool settle above the actual floor")
	var canonical:Vector3=landed
	full.physics_settings_path="user://original_size_%d.cfg"%OS.get_process_id();full.persist_physics_settings=true
	full.set_full_size_enabled(false)
	check(full.stores[1].get_position(handle).distance_to(canonical)<.00001 and full.size_layouts[1].scale==1,"changing size keeps the canonical pickup position and identity")
	var fixture:=TerrainFixture.new();scene.add_child(fixture);provider._terrain=fixture
	var sections:Dictionary=provider._capture().sections
	var reopened:=Pickups.new();scene.add_child(reopened);reopened.physics_settings_path=full.physics_settings_path
	var restored:=Persistence.new()
	check(reopened.prepare(restored) and reopened.configure_physics(RID(),true) and not reopened.full_size_enabled,"fresh session loads the saved compact preference")
	restored._terrain=fixture;restored._restore(sections,1)
	var identity:int=result.id;var new_handle:int=reopened.stores[1].resolve_identity(identity)
	check(new_handle>0 and reopened.stores[1].get_position(new_handle).distance_to(canonical)<.00001,"save/reload preserves drop coordinates while size remains a global preference")
	reopened.set_full_size_enabled(true)
	var target:Vector3=reopened.stores[1].get_position(new_handle)+reopened.visual_offset(1)
	var aimed:=reopened.aimed(target-Vector3.FORWARD,target+Vector3.FORWARD,func(_p:Vector3):return true)
	check(aimed.ok and aimed.item==1,"aimed pickup follows the larger visible tool center")
	check(reopened.collect_near(target,inventory,func(_p:Vector3):return true).ok and inventory.snapshot().slots[0]==expected,"recovery after resizing and reload preserves exact tool wear")
	DirAccess.remove_absolute(full.physics_settings_path)
	reopened.free()
	var sink:RefCounted=preload("res://addons/player_runtime/item_catalog.gd").create_inventory()
	full.collect_near(full.stores[1].get_position(handle)+full.visual_offset(1),sink,func(_p:Vector3):return true)
	full.set_full_size_enabled(true);full.update_view(0,Vector3.ZERO,true)
	if DisplayServer.get_name()!="headless":
		var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4.2;scene.add_child(camera);camera.position=Vector3(3,4.5,7);camera.look_at(Vector3(0,.35,0));camera.make_current()
		for i in 5:await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(output)
		check(root.get_texture().get_image().save_png(output.path_join("comparison.png"))==OK,"authored-size and compact comparison saves")
	scene.free();await process_frame
	print("ORIGINAL_SIZE_DROPS checks=",checks," failures=",failures);quit(1 if failures else 0)
