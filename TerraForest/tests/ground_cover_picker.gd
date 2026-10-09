# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func records(ids: PackedInt64Array,poses: Array[Transform3D],species: int=0) -> Array:
	var out:=[]
	for i in range(3): out.append({"ids":PackedInt64Array(),"transforms":PackedFloat32Array()})
	out[species].ids=ids
	for t in poses:
		out[species].transforms.append_array(PackedFloat32Array([t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z]))
	return out
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var picker=ClassDB.instantiate("NativeGroundCoverPicker")
	var a:=Transform3D(Basis.IDENTITY,Vector3(970,20,970))
	var b:=Transform3D(Basis.IDENTITY,Vector3(972,20,970))
	var rows:=records(PackedInt64Array([3,2]),[a,b])
	check(picker.replace_cell(Vector2i(30,30),rows),"resident interaction owner accepted")
	var hit: Dictionary=picker.pick(Vector3(967,20,970),Vector3(974,20,970))
	check(hit.hit and hit.id==3 and is_equal_approx(hit.position.x,969.6),"nearest clump wins with exact proxy intersection")
	hit=picker.pick(Vector3(974,20,970),Vector3(967,20,970))
	check(hit.hit and hit.id==2,"reverse ray selects opposite nearest clump")
	check(not picker.pick(Vector3(967,21,970),Vector3(974,21,970)).hit,"parallel ray outside bounds misses")
	check(picker.pick(Vector3(970,20,970),Vector3(971,20,970)).fraction==0.0,"ray starting inside proxy hits at zero")
	check(not picker.pick(Vector3(NAN,20,970),Vector3(974,20,970)).hit and not picker.pick(Vector3.ZERO,Vector3(9,0,0)).hit,"nonfinite and over-reach rays rejected")
	var bad:=records(PackedInt64Array([3,3]),[a,b])
	check(not picker.replace_cell(Vector2i(30,30),bad) and picker.pick(Vector3(967,20,970),Vector3(974,20,970)).id==3,"duplicate identity rejection preserves previous owner")
	check(not picker.replace_cell(Vector2i(29,30),rows),"misowned transforms rejected")
	a.basis=Basis(Vector3.UP,0.7).scaled(Vector3(3,1,0.5))
	check(picker.replace_cell(Vector2i(30,30),records(PackedInt64Array([7]),[a],2)),"rotated scaled grass proxy accepted")
	var from: Vector3=a*Vector3(-2,0.3,0)
	var to: Vector3=a*Vector3(0,0.3,0)
	hit=picker.pick(from,to)
	check(hit.hit and hit.id==7 and hit.species==2 and hit.position.is_equal_approx(a*Vector3(-0.4,0.3,0)),"inverse transform preserves exact oriented intersection")
	# Proxy protrudes into the adjacent cell; query cannot use origin cell alone.
	a=Transform3D(Basis.IDENTITY.scaled(Vector3(4,1,4)),Vector3(991.9,20,970))
	check(picker.replace_cell(Vector2i(30,30),records(PackedInt64Array([8]),[a])),"boundary proxy accepted")
	check(picker.pick(Vector3(992.5,20,968),Vector3(992.5,20,972)).hit,"cell padding finds protruding neighbour proxy")
	for z in range(27,34):
		for x in range(27,34):
			if Vector2i(x,z)==Vector2i(30,30): continue
			picker.replace_cell(Vector2i(x,z),records(PackedInt64Array([100+z*63+x]),[Transform3D(Basis.IDENTITY,Vector3(x*32+10,20,z*32+10))]))
	hit=picker.pick(Vector3(992.5,20,968),Vector3(992.5,20,972))
	check(hit.hit and hit.tested<=4 and hit.cells<=4,"query visits local cells independently of all 49 resident owners")
	check(not picker.replace_cell(Vector2i(40,40),records(PackedInt64Array([9]),[Transform3D(Basis.IDENTITY,Vector3(1290,20,1290))])),"resident interaction owner cap enforced")
	picker.remove_cell(Vector2i(30,30))
	check(not picker.pick(Vector3(992.5,20,968),Vector3(992.5,20,972)).hit,"retired render owner cannot be picked")
	var dense=ClassDB.instantiate("NativeGroundCoverPicker")
	var accepted:=true
	for z in range(27,34):
		for x in range(27,34):
			var ids:=PackedInt64Array();var poses: Array[Transform3D]=[]
			for i in range(320):
				ids.append((z*63+x)*320+i+1)
				poses.append(Transform3D(Basis.IDENTITY,Vector3(x*32+10,20,z*32+10)))
			accepted=dense.replace_cell(Vector2i(x,z),records(ids,poses)) and accepted
	check(accepted,"maximum 15680 resident interaction records accepted within owner bounds")
	hit=dense.pick(Vector3(968,20,970),Vector3(972,20,970))
	check(hit.hit and hit.tested==320 and hit.cells<=4,"dense local query tests 320 records rather than scanning all 15680")
	check(hit.id==(30*63+30)*320+1,"coincident proxy ties choose stable lowest identity")
	var many_ids:=PackedInt64Array();var many_poses: Array[Transform3D]=[]
	for i in range(321): many_ids.append(i+1);many_poses.append(Transform3D(Basis.IDENTITY,Vector3(970,20,970)))
	check(not dense.replace_cell(Vector2i(30,30),records(many_ids,many_poses)),"oversized owner rejected before replacing existing queries")
	var report:={"checks":checks,"failures":failures}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/ground_cover_picker.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report));file.close()
	print("GROUND_COVER_PICKER ",JSON.stringify(report))
	quit(1 if failures else 0)
