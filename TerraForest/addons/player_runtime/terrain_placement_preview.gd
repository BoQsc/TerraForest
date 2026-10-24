# SPDX-License-Identifier: 0BSD
extends MeshInstance3D
# Compact target marker, not a second terrain edit or a baked-mesh prediction.
# Geometry/shader are shared; native spatial queries run only at 20 Hz while held.
const MARKER_RADIUS:=.35
var remaining:=0.0
var last_item:=-1
var result:Dictionary={}
var caption:Label
func _ready()->void:
	# Eight flat triangles, built once. Display size is independent of edit size.
	var radius:float=MARKER_RADIUS
	var vertices:=PackedVector3Array();var uvs:=PackedVector2Array()
	for x in [-1.0,1.0]:
		for y in [-1.0,1.0]:
			for z in [-1.0,1.0]:
				var a:=Vector3(x,0,0)*radius;var b:=Vector3(0,y,0)*radius;var c:=Vector3(0,0,z)*radius
				# Godot's visible faces wind clockwise when viewed from outside.
				if (b-a).cross(c-a).dot(a+b+c)>0:var swap:=b;b=c;c=swap
				vertices.append_array(PackedVector3Array([a,b,c]));uvs.append_array(PackedVector2Array([Vector2(1,0),Vector2(0,1),Vector2.ZERO]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs
	var octahedron:=ArrayMesh.new();octahedron.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);mesh=octahedron
	var shader:=ShaderMaterial.new();shader.shader=preload("res://addons/player_runtime/terrain_placement_preview.gdshader");material_override=shader
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ui:=CanvasLayer.new();ui.layer=21;add_child(ui)
	var frame:=Control.new();frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);frame.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.add_child(frame)
	caption=Label.new();caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER);caption.offset_left=-300;caption.offset_right=300;caption.offset_top=58;caption.offset_bottom=86
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size",16);caption.add_theme_constant_override("outline_size",4);caption.add_theme_color_override("font_outline_color",Color(0,0,0,.85));frame.add_child(caption)
	hide();caption.hide()
func clear()->void:
	hide();caption.hide();result={};remaining=0.0;last_item=-1
func update(game:Node,delta:float)->void:
	game.terrain_placement.update(game)
	if not game.terrain_placement.active(game):clear();return
	if last_item!=game.equipped_tool:remaining=0;last_item=game.equipped_tool
	remaining-=delta
	if remaining>0:return
	remaining=.05;result=game.terrain_placement.target(game)
	if result.is_empty():hide();caption.hide();return
	global_position=result.position
	var tint:=Color("83d9ba") if result.ok else Color("ec876e")
	if result.reason in ["Placement area is still loading","Checking terrain"]:tint=Color("e5c273")
	material_override.set_shader_parameter("tint",tint)
	caption.text=game.player_hud.RESOURCES[result.item]+" · Right mouse: place" if result.ok else ""
	caption.modulate=tint;caption.visible=result.ok;show()
