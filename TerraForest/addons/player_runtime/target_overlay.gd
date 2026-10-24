# SPDX-License-Identifier: 0BSD
extends MeshInstance3D
# Optional, advisory only. Gameplay repeats its own native pick at contact.
var game:Node
var enabled:=false
var timer:=0.0
func _ready()->void:
	var lines:=ImmediateMesh.new();lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for axis in 3:
		for a in [0.0,1.0]:
			for b in [0.0,1.0]:
				var point:=Vector3.ZERO;point[(axis+1)%3]=a;point[(axis+2)%3]=b
				lines.surface_add_vertex(point);point[axis]=1;lines.surface_add_vertex(point)
	lines.surface_end();mesh=lines
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color("6cf2c2")
	material_override=material;cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;hide()
	var config:=ConfigFile.new()
	if config.load("user://interaction_display.cfg")==OK:enabled=config.get_value("display","target_overlay",false)==true
func set_enabled(value:bool)->void:
	enabled=value;timer=0
	var config:=ConfigFile.new();config.set_value("display","target_overlay",value);config.save("user://interaction_display.cfg")
func _process(delta:float)->void:
	if not enabled or not game._model_edit_available() or game.session_menu.visible_ui() or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		hide();return
	timer-=delta
	if timer>0:return
	timer=.1
	var start:Vector3=game.camera.global_position
	var hit:Dictionary=game.structures.blocks.raycast_scene(start,start-game.camera.global_basis.z*3.5,0xFFFFFFFF,[game.player.get_rid()])
	if hit.is_empty():hide();return
	global_position=Vector3(hit.cell) if hit.has("cell") else (hit.position-hit.normal*.02).floor()
	show()
