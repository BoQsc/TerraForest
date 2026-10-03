# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func density(x: float,y: float,z: float,divide: bool) -> float:
	var d:=y-(2.0+((x-16)*(x-16)+(z-16)*(z-16))/20.0)
	if divide: d=minf(d,absf(x-16)-1.0)
	return d
func run_case(divide: bool) -> void:
	var lake: RefCounted=ClassDB.instantiate("NativeLakeVolume")
	check(lake.configure(Vector3.ZERO,Vector3i(32,12,32),1.0,8.0,Vector3(12,6,16)),"shoreline volume configured")
	var field:=PackedFloat32Array()
	for z in 33:
		for y in 13:
			for x in 33: field.append(density(x,y,z,divide))
	check(lake.bake_density(field)==1,"curved basin bakes")
	var arrays: Array=lake.smooth_surface_arrays()
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var fractional:=false
	var valid:=indices.size()%3==0 and not indices.is_empty()
	var area:=0.0
	for i in range(0,indices.size(),3):
		var a:=vertices[indices[i]];var b:=vertices[indices[i+1]];var c:=vertices[indices[i+2]]
		var cross: Vector3=(b-a).cross(c-a)
		valid=valid and cross.y < -0.000001
		area+=absf(cross.y)*0.5
		# For this concave quadratic air field, linear clipped triangles must lie
		# inside the analytic free surface. Check vertices and interior points.
		for p: Vector3 in [a,b,c,(a+b+c)/3.0,(a+b)/2.0,(b+c)/2.0,(c+a)/2.0]:
			valid=valid and absf(p.y-8)<0.0001 and density(p.x,p.y,p.z,divide)>=-0.0001
			if divide: valid=valid and p.x<=15.0001
	for i in vertices.size():
		var p:=vertices[i]
		fractional=fractional or absf(p.x-roundf(p.x))>0.001 or absf(p.z-roundf(p.z))>0.001
		valid=valid and normals[i]==Vector3.UP and uv[i]==Vector2(p.x,p.z)
	check(valid,"clipped triangles preserve winding, height, UVs and solid exclusion")
	check(fractional,"curved shore has sub-cell contour vertices")
	check(area>130 if divide else area>350,"surface reaches the physical shoreline rather than the conservative voxel inset")
	check(arrays==lake.smooth_surface_arrays() and lake.statistics().builder_bytes==0,"surface is cached and 3D scratch is released")
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array()
	check(not lake.smooth_surface_arrays()[Mesh.ARRAY_VERTEX].is_empty(),"caller cannot mutate published surface channels")
	if divide: check(not lake.contains(Vector3(20,6,16)),"disconnected neighboring basin remains dry")
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
	run_case(false);run_case(true)
	var narrow: RefCounted=ClassDB.instantiate("NativeLakeVolume")
	narrow.configure(Vector3.ZERO,Vector3i(8,6,8),1.0,3.5,Vector3(2.5,2.5,2.5))
	var field:=PackedFloat32Array()
	for z in 9:
		for y in 7:
			for x in 9:
				var solid:=x==0 or x==8 or z==0 or z==8 or y==0
				if x==3 and z==0 and y in [3,4]: solid=false
				field.append(-1.0 if solid else 1.0)
	check(narrow.bake_density(field)==1,"conservative volume excludes sub-cell boundary opening")
	check(narrow.smooth_surface_arrays()==narrow.surface_arrays(),"surface reaching volume boundary falls back without drawing a leak")
	quit(1 if failures else 0)
