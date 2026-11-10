# SPDX-License-Identifier: 0BSD
extends Node3D
const Catalog=preload("res://addons/player_runtime/carried_object_catalog.gd")
const Barrel=preload("res://addons/player_runtime/combat_barrel.gd")
var game:Node
var action_input_owned:Callable
var entries:Dictionary={}
var free_placement:=false
var quarter_turns:=0
var preview:=MeshInstance3D.new()
var cells:=MultiMeshInstance3D.new()
var tint:=StandardMaterial3D.new()
var clock:=0.0
var last_item:=-1
var last_target:Dictionary={}
var clearance_shape:=BoxShape3D.new()
var clearance_query:=PhysicsShapeQueryParameters3D.new()
func prepare(host:Node)->void:
	game=host
	clearance_query.shape=clearance_shape;clearance_query.exclude=[game.player.get_rid()]
	action_input_owned=func()->bool:return Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
	for item:int in Catalog.ITEMS:
		for entry:Dictionary in game.model_tool.catalog:
			if entry.title==Catalog.TITLES[item]:entries[item]=entry;break
	entries[222]={"mesh":Barrel.mesh(),"collection":game.combat.barrels,"scale":Vector3.ONE}
	tint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;tint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	preview.material_override=tint;preview.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(preview)
	var wire:=ImmediateMesh.new();wire.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in 3:
		for a in [-.5,.5]:
			for b in [-.5,.5]:
				var start:=Vector3.ZERO;start[axis]=-.5;start[(axis+1)%3]=a;start[(axis+2)%3]=b
				var end:=start;end[axis]=.5;wire.surface_add_vertex(start);wire.surface_add_vertex(end)
	wire.surface_end()
	cells.multimesh=MultiMesh.new();cells.multimesh.transform_format=MultiMesh.TRANSFORM_3D;cells.multimesh.mesh=wire
	cells.multimesh.instance_count=64;cells.multimesh.visible_instance_count=0;cells.material_override=tint
	cells.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(cells);hide()
func active()->bool:
	return game!=null and Catalog.supports(game.equipped_tool) and game.combat.active() and not game.player_life.dead and not game.session_menu.developer and not game.world_vehicle.driving and not game.player_view.entry.blocks_actions() and action_input_owned.is_valid() and action_input_owned.call()
static func occupied_cells(bounds:AABB)->Array[Vector3i]:
	var result:Array[Vector3i]=[]
	var low:=Vector3i((bounds.position+Vector3.ONE*.5+Vector3.ONE*.00001).floor())
	var high:=Vector3i((bounds.end+Vector3.ONE*.5-Vector3.ONE*.00001).floor())
	if (high.x-low.x+1)*(high.y-low.y+1)*(high.z-low.z+1)>64:return result
	for y in range(low.y,high.y+1):
		for z in range(low.z,high.z+1):
			for x in range(low.x,high.x+1):result.append(Vector3i(x,y,z))
	return result
func target()->Dictionary:
	if not entries.has(game.equipped_tool):return {"ok":false,"reason":"Object model unavailable"}
	var entry:Dictionary=entries[game.equipped_tool]
	var start:Vector3=game.camera.global_position
	var hit:Dictionary=game.structures.blocks.raycast_scene(start,start-game.camera.global_basis.z*4,15,[game.player.get_rid()])
	if hit.is_empty():return {"ok":false,"reason":"Aim at nearby ground or a building surface"}
	var basis:=Basis(Vector3.UP,quarter_turns*PI*.5)*Basis.from_scale(entry.scale)
	var local:AABB=Transform3D(basis,Vector3.ZERO)*entry.mesh.get_aabb()
	var anchor:Vector3=hit.position
	if not free_placement:anchor.x=roundf(anchor.x);anchor.z=roundf(anchor.z)
	anchor.y-=local.position.y
	var bounds:=AABB(anchor+local.position,local.size)
	var result:Dictionary={"ok":false,"reason":"Placement area is still loading","transform":Transform3D(basis,anchor),"bounds":bounds,"entry":entry}
	if not game._placement_collision_ready(bounds):return result
	var fit:Dictionary=game.structures.blocks.placement_support(bounds,hit.position,false,false,[game.player.get_rid()])
	if not fit.ok:result.reason=fit.reason;return result
	anchor.y+=float(fit.offset_y);bounds.position.y+=float(fit.offset_y)
	result.transform=Transform3D(basis,anchor);result.bounds=bounds
	if not game._placement_collision_ready(bounds):return result
	if not game._prefab_player_clear(bounds) or game.world_vehicle.overlaps_edit(bounds):result.reason="Move clear of the placement";return result
	# Support fitting permits a small ground contact. Check the fitted volume,
	# not the original hit point; retain blocking for walls and other objects.
	# The terrain-only inset covers the fixed support stencil's edge allowance.
	for mask:int in [14,1]:
		var inset:=.04 if mask==14 else .12
		clearance_shape.size=Vector3(bounds.size.x*.96,maxf(.01,bounds.size.y-inset),bounds.size.z*.96)
		clearance_query.transform=Transform3D(Basis.IDENTITY,bounds.get_center()+Vector3.UP*inset*.5)
		clearance_query.collision_mask=mask
		if not get_world_3d().direct_space_state.intersect_shape(clearance_query,1).is_empty():
			result.reason="Object overlaps terrain or another placement";return result
	if game.equipped_tool==222 and game.combat.barrels.get_ids().size()>=256:result.reason="Barrel limit reached";return result
	result.ok=entry.collection.can_insert_instance(game.model_tool.records(result.transform,entry.collection),game.model_tool.protection())
	result.reason="" if result.ok else "Object overlaps another placement or capacity is reached"
	return result
func refresh()->void:
	if not active():hide();last_target={};return
	show()
	if last_item!=game.equipped_tool:
		last_item=game.equipped_tool;preview.mesh=entries[last_item].mesh if entries.has(last_item) else null
	last_target=target();preview.visible=last_target.has("transform");cells.multimesh.visible_instance_count=0
	if not preview.visible:return
	preview.global_transform=last_target.transform
	tint.albedo_color=Color(.25,1,.6,.48) if last_target.ok else Color(1,.25,.18,.48)
	var occupied:=occupied_cells(last_target.bounds)
	for index in occupied.size():cells.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(occupied[index])))
	cells.multimesh.visible_instance_count=occupied.size()
func place()->bool:
	if not active() or not game.combat.can_use():return false
	# Recompute admission at the click; a displayed preview is never a receipt.
	var selected:=target()
	if not selected.get("ok",false):game._show_lake_notice(selected.get("reason","Placement unavailable"));return false
	var entry:Dictionary=selected.entry
	var id:int=game.construction_inventory.place_model(game.model_tool.history,entry.collection,game.player_hud.inventory,game.model_tool.records(selected.transform,entry.collection),game.model_tool.protection(),PackedInt64Array([game.equipped_tool,1]))
	if id<=0:game._show_lake_notice("Placement changed or no carried object remains");return false
	game.terrain.changed_since_save=true;game.player_hud.refresh();clock=0;return true
func handle_input(event:InputEvent)->bool:
	if not active():return false
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if event.physical_keycode==KEY_H:
			free_placement=not free_placement;clock=0;game._show_lake_notice("Objects: free placement" if free_placement else "Objects: building-grid placement");return true
		if event.physical_keycode==KEY_R:quarter_turns=(quarter_turns+1)%4;clock=0;return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if event.pressed:place()
		return true
	return false
func _process(delta:float)->void:
	if not active():hide();return
	clock-=delta
	if clock<=0:clock=.05;refresh()
