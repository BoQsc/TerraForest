# SPDX-License-Identifier: 0BSD
extends SceneTree
const Forest=preload("res://addons/vegetation/forest.gd")
var failed:=false
func check(value: bool,label: String) -> void:
	print("PASS " if value else "FAIL ",label)
	failed=failed or not value
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var candidate=Forest.new()
	var oracle=Forest.new()
	root.add_child(candidate);root.add_child(oracle)
	var meshes: Array[ArrayMesh]=[]
	for i in range(5): meshes.append(ArrayMesh.new())
	var transforms: Array[Transform3D]=[]
	var ids:=PackedInt64Array()
	for i in range(4096):
		ids.append(i+1)
		transforms.append(Transform3D(Basis.IDENTITY,Vector3((i%64)*4,0,(i/64)*4)))
	var eye:=Vector3(128,20,128)
	for forest in [candidate,oracle]:
		forest.setup(meshes,448)
		check(forest.upsert_chunk("initial",ids,transforms),"4096 roots admitted")
		forest.tick(eye,800,0,true)
	var additions: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(150,0,150))]
	for forest in [candidate,oracle]: forest.upsert_chunk("addition",PackedInt64Array([5000]),additions)
	oracle.changed=true
	candidate.tick(eye,800,1);oracle.tick(eye,800,1)
	check(candidate.state_sha256()==oracle.state_sha256(),"local insertion matches complete decision recalculation")
	check(candidate.rows_this_tick<32 and oracle.rows_this_tick>=4096,"one insertion does not rescan resident forest")
	for step in range(40):
		if step==3:
			for forest in [candidate,oracle]: forest.remove_root(5000)
		if step==4:
			additions[0].origin=Vector3(200,0,30)
			for forest in [candidate,oracle]: forest.upsert_chunk("addition",PackedInt64Array([5000]),additions)
		if step==6:
			additions[0].basis=Basis.IDENTITY.scaled(Vector3.ONE*3)
			for forest in [candidate,oracle]: forest.upsert_chunk("addition",PackedInt64Array([5000]),additions)
		if step==9:
			for forest in [candidate,oracle]: forest.remove_chunk("addition")
		eye+=Vector3(8,0,step%3-1)
		oracle.changed=true
		candidate.tick(eye,800,1.05+step*.05);oracle.tick(eye,800,1.05+step*.05)
		check(candidate.state_sha256()==oracle.state_sha256(),"membership, ID reuse, scale, travel and fades %d"%step)
	candidate.free();oracle.free()
	quit(1 if failed else 0)
