# SPDX-License-Identifier: 0BSD
extends RefCounted
# Shared miniature vehicle pickup; fixed geometry, no live vehicle simulation.
static var cached:ArrayMesh
static func mesh()->ArrayMesh:
	if cached!=null:return cached
	cached=ArrayMesh.new()
	for part:Array in [[Vector3(.32,.14,.55),Vector3(0,0,0),Color("658867")],[Vector3(.26,.13,.27),Vector3(0,.13,-.02),Color("83a6b6")],[Vector3(.29,.035,.3),Vector3(0,.21,-.02),Color("506c52")]]:
		var box:=BoxMesh.new();box.size=part[0]
		var material:=StandardMaterial3D.new();material.albedo_color=part[2];material.roughness=.8
		var surface:=SurfaceTool.new();surface.append_from(box,0,Transform3D(Basis.IDENTITY,part[1]));surface.set_material(material);surface.commit(cached)
	for x:float in [-.17,.17]:
		for z:float in [-.18,.18]:
			var wheel:=CylinderMesh.new();wheel.top_radius=.065;wheel.bottom_radius=.065;wheel.height=.055;wheel.radial_segments=12;wheel.rings=1
			var material:=StandardMaterial3D.new();material.albedo_color=Color("252c30")
			var surface:=SurfaceTool.new();surface.append_from(wheel,0,Transform3D(Basis(Vector3.FORWARD,PI*.5),Vector3(x,-.045,z)));surface.set_material(material);surface.commit(cached)
	return cached
