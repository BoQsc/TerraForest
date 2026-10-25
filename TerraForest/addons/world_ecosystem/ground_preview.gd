# SPDX-License-Identifier: 0BSD
# One bounded advisory marker; checks run only while the tool is active, at 10 Hz.
extends MeshInstance3D
var remaining:=0.0
var result: Dictionary={}
var ghost:=MeshInstance3D.new()
func _ready() -> void:
	var lines:=PackedVector3Array()
	var corners: Array[Vector3]=[Vector3(-0.4,0,-0.4),Vector3(0.4,0,-0.4),Vector3(0.4,0,0.4),Vector3(-0.4,0,0.4)]
	for i in range(4):
		lines.append(corners[i]);lines.append(corners[(i+1)%4])
		lines.append(corners[i]+Vector3.UP*0.8);lines.append(corners[(i+1)%4]+Vector3.UP*0.8)
		lines.append(corners[i]);lines.append(corners[i]+Vector3.UP*0.8)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=lines
	var wire:=ArrayMesh.new();wire.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays);mesh=wire
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("edc66a");material_override=material
	material.no_depth_test=true
	var tint:=StandardMaterial3D.new();tint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;tint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;tint.cull_mode=BaseMaterial3D.CULL_DISABLED
	ghost.material_override=tint;ghost.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(ghost)
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hide()
func update(game: Node,delta: float) -> void:
	if not game.ground_mode or not game._model_edit_available(true) or game.session_menu.visible_ui() or game.player_hud.inventory_open or game.world_vehicle.driving or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		hide();remaining=0.0;result={};game.player_hud.show_ground_feedback("");return
	remaining-=delta
	if remaining>0: return
	remaining=.05
	var start: Vector3=game.camera.global_position
	var end: Vector3=start-game.camera.global_basis.z*(3.5 if game.construction_inventory.gameplay else 8.0)
	result=game.ground_interaction.placement_probe(game.ground_species,start,end,game.player_hud.inventory,game.construction_inventory.gameplay)
	visible=result.has("pose")
	if visible:
		global_transform=result.pose
		var tint:=Color("83d9ba") if result.ok else Color("e5c273") if result.reason=="Ground cover updating" else Color("ec876e")
		material_override.albedo_color=tint;tint.a=.32;ghost.material_override.albedo_color=tint
		if game.ground_species<game.ground_cover.preview_meshes.size():ghost.mesh=game.ground_cover.preview_meshes[game.ground_species]
	game.player_hud.show_ground_feedback(result.reason)
