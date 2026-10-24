# SPDX-License-Identifier: 0BSD
extends RefCounted
# Resource creation only, once per shape. No particle/vertex work in GDScript.
static func fragment_mesh(shape:String)->Mesh:
	if shape=="spark":
		var ribbon:=QuadMesh.new();ribbon.size=Vector2.ONE
		var material:=ShaderMaterial.new();material.shader=preload("res://addons/impact_effects/grounded_spark.gdshader");ribbon.material=material
		return ribbon
	var material:=ShaderMaterial.new();material.shader=preload("res://addons/impact_effects/grounded_fragments.gdshader")
	# Reuse the already imported mineral texture; no new full-size material set.
	material.set_shader_parameter("grain",preload("res://addons/world_ecosystem/art/boulder_granite_v1.png"))
	if shape=="wood":
		var splinter:=BoxMesh.new();splinter.material=material;return splinter
	var mesh:ArrayMesh=load("res://addons/impact_effects/art/"+("soil_clod" if shape=="soil" else "stone_chip")+".obj").duplicate()
	mesh.surface_set_material(0,material)
	return mesh

static func dust_mesh()->QuadMesh:
	var mesh:=QuadMesh.new();mesh.size=Vector2.ONE
	var material:=ShaderMaterial.new();material.shader=preload("res://addons/impact_effects/grounded_dust.gdshader")
	material.set_shader_parameter("noise_map",preload("res://addons/impact_effects/art/dust_noise.tres"))
	mesh.material=material;return mesh
