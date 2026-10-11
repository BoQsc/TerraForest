# SPDX-License-Identifier: 0BSD
# Retained appearance baseline from 6213d78, test use only.
extends RefCounted
static func build(species: int) -> Mesh:
	var material:=StandardMaterial3D.new()
	material.albedo_color=[Color("777975"),Color("557538"),Color("677e3e")][species]
	material.roughness=1.0
	if species==0:
		var rock:=SphereMesh.new()
		rock.radius=0.3;rock.height=0.35;rock.radial_segments=8;rock.rings=3;rock.material=material
		return rock
	# Opaque crossed tapered blades; no alpha overdraw or per-blade physics.
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	for blade in range(5 if species==2 else 7):
		var angle:=blade*2.399963
		var direction:=Vector3(cos(angle),0,sin(angle))
		var side:=Vector3(-direction.z,0,direction.x)*(0.045 if species==2 else 0.13)
		var base:=direction*0.1
		var top:=direction*(0.24 if species==2 else 0.38)+Vector3.UP*(0.4 if species==2 else 0.7)
		var normal: Vector3=(top-base+side).cross(side*2).normalized()
		vertices.append_array(PackedVector3Array([base-side,top,base+side]))
		normals.append_array(PackedVector3Array([normal,normal,normal]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,material)
	return mesh

