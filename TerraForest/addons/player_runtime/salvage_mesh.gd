# SPDX-License-Identifier: 0BSD
extends RefCounted
## Original simple salvage silhouettes, built once for batched world drops.
static func mesh(item:int)->ArrayMesh:
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var color:Color={224:Color("889699"),225:Color("a8956a"),226:Color("bc794b"),227:Color("9aa8aa")}[item]
	for index in (2 if item==226 else 3):
		var piece:PrimitiveMesh
		var pose:=Transform3D.IDENTITY
		if item==226:
			var ring:=TorusMesh.new();ring.inner_radius=.08;ring.outer_radius=.12;ring.rings=12;ring.ring_segments=6;piece=ring
			pose.origin=Vector3(index*.04,.025+index*.025,0)
		elif item==227:
			var bolt:=CylinderMesh.new();bolt.top_radius=.018;bolt.bottom_radius=.018;bolt.height=.18;bolt.radial_segments=6;piece=bolt
			pose=Transform3D(Basis(Vector3.RIGHT,PI/2).rotated(Vector3.UP,index*.6),Vector3(index*.04-.04,.025,0))
		else:
			var sheet:=BoxMesh.new();sheet.size=Vector3(.24,.015,.13) if item==224 else Vector3(.18,.012,.16);piece=sheet
			pose=Transform3D(Basis(Vector3.UP,index*.4),Vector3(.02*index,.018+index*.017,0))
		tool.append_from(piece,0,pose)
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.8;material.metallic=0 if item==225 else .45
	tool.set_material(material)
	return tool.commit()
