extends SceneTree

var checks:=0
var failures:=0

func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
func signature(indices:PackedInt32Array,offset:int)->String:
	return "%d,%d,%d"%[indices[offset],indices[offset+1],indices[offset+2]]
func run()->void:
	var model:Node3D=load("res://addons/characters/runtime/assets/Human.r11.glb").instantiate();root.add_child(model)
	for entry in [["body","Human_Body"],["unarmed","Human_Body"],["shirt","Wardrobe_WorkShirt"]]:
		var source:ArrayMesh=load("res://addons/characters/runtime/assets/Human.unarmed_body.res") if entry[0]=="unarmed" else model.find_child(entry[1],true,false).mesh
		var expected:Dictionary={};var actual:Dictionary={}
		for surface in source.get_surface_count():
			var indices:PackedInt32Array=source.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
			for offset in range(0,indices.size(),3):
				var key:=str(surface)+":"+signature(indices,offset);expected[key]=int(expected.get(key,0))+1
		for kind in ["body","arms"]:
			var mesh:ArrayMesh=load("res://addons/characters/runtime/assets/first_person/"+entry[0]+"_"+kind+".res")
			var surfaces:PackedInt32Array=mesh.get_meta("source_surfaces")
			var shapes:PackedInt32Array=mesh.get_meta("source_blend_shapes")
			var vertices:Array=mesh.get_meta("source_vertices")
			var geometry_ok:=true;var morphs_ok:=true;var materials_external:=true
			for surface in mesh.get_surface_count():
				var original:=source.surface_get_arrays(surfaces[surface]);var split:=mesh.surface_get_arrays(surface)
				var indices:PackedInt32Array=split[Mesh.ARRAY_INDEX];var remapped:PackedInt32Array=[]
				for index in indices:remapped.append(vertices[surface][index])
				for offset in range(0,indices.size(),3):
					if remapped[offset]==remapped[offset+1] and remapped[offset]==remapped[offset+2]:continue
					var key:=str(surfaces[surface])+":"+signature(remapped,offset);actual[key]=int(actual.get(key,0))+1
				materials_external=materials_external and mesh.surface_get_material(surface)==null
				for index in vertices[surface].size():
					geometry_ok=geometry_ok and split[Mesh.ARRAY_VERTEX][index].distance_to(original[Mesh.ARRAY_VERTEX][vertices[surface][index]])<.0001
				var original_morphs:=source.surface_get_blend_shape_arrays(surfaces[surface]);var split_morphs:=mesh.surface_get_blend_shape_arrays(surface)
				for shape in shapes.size():
					morphs_ok=morphs_ok and mesh.get_blend_shape_name(shape)==source.get_blend_shape_name(shapes[shape])
					for index in range(0,vertices[surface].size(),maxi(1,vertices[surface].size()/32)):
						morphs_ok=morphs_ok and split_morphs[shape][Mesh.ARRAY_VERTEX][index].distance_to(original_morphs[shapes[shape]][Mesh.ARRAY_VERTEX][vertices[surface][index]])<.0001
			check(geometry_ok,entry[0]+" "+kind+" retains every selected vertex")
			check(morphs_ok,entry[0]+" "+kind+" retains sampled authored morphs and channel identities")
			check(materials_external,entry[0]+" "+kind+" cannot serialize headless placeholder textures")
		check(expected==actual,entry[0]+" partitions every original triangle exactly once without changing winding")
	model.free();print("FIRST_PERSON_MESHES_CHECK checks=",checks," failures=",failures);quit(1 if failures else 0)
