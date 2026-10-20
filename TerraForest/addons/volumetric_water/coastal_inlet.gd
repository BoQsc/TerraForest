# SPDX-License-Identifier: 0BSD
extends RefCounted
# First editable coastal stretch. Ocean beyond the world boundary is presentation
# only; it must not be advertised as a streamed, navigable volumetric ocean.
const LEVEL=40.0
const ARRIVAL=Vector3(39,43,1008)
static func prepare(lakes:Node3D)->int:
 return lakes.add_lake(Vector3(0,36,968),Vector3i(48,8,80),1.0,LEVEL,Vector3(8,39,1008))
static func horizon(material:ShaderMaterial)->MeshInstance3D:
 var node:=MeshInstance3D.new()
 var plane:=PlaneMesh.new();plane.size=Vector2(8000,12000)
 node.mesh=plane;node.position=Vector3(-4000,LEVEL,1000)
 var distant:ShaderMaterial=material.duplicate()
 distant.set_shader_parameter("ocean_horizon",true)
 node.material_override=distant
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 node.name="OceanHorizon"
 return node
