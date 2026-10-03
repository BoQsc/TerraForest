# SPDX-License-Identifier: 0BSD
extends SceneTree
const Forest=preload("res://addons/vegetation/forest.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scripted=Forest.new();scripted.native_selection=null
	var native=Forest.new();root.add_child(scripted);root.add_child(native)
	if native.native_selection==null: print("FAIL native selection unavailable");quit(1);return
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().get_mesh_arrays())
	var meshes: Array[ArrayMesh]=[mesh,mesh,mesh,mesh,mesh]
	scripted.setup(meshes,2200);native.setup(meshes,2200)
	scripted.visibility(false,false);native.visibility(false,false)
	scripted.audit_enabled=true;native.audit_enabled=true
	var rng:=RandomNumberGenerator.new();rng.seed=1703
	var ids:=PackedInt64Array();var transforms: Array[Transform3D]=[]
	for i in 2000:
		ids.append(i-1000)
		transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*rng.randf_range(0.3,2)),Vector3(rng.randf_range(-400,400),rng.randf_range(-80,80),rng.randf_range(-400,400))))
	scripted.upsert_chunk("field",ids,transforms);native.upsert_chunk("field",ids,transforms)
	var matches:=true;var bounded:=true;var script_us:=0;var native_us:=0
	for frame in 180:
		var eye:=Vector3(sin(frame*0.07)*160,cos(frame*0.03)*40,cos(frame*0.04)*170)
		if frame%37==0: eye+=Vector3(700,200,-600)
		if frame==51: scripted.remove_root(-11);native.remove_root(-11)
		if frame==63:
			var replacement: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(10,0,10))]
			scripted.upsert_chunk("replacement",PackedInt64Array([-11]),replacement);native.upsert_chunk("replacement",PackedInt64Array([-11]),replacement)
		if frame in [90,140]: scripted.profile(frame==90);native.profile(frame==90)
		var projection:=500.0 if frame%41<20 else 900.0
		scripted.tick(eye,projection,frame/60.0,frame%53==0);script_us+=int(scripted.stats.selection_us)
		native.tick(eye,projection,frame/60.0,frame%53==0);native_us+=int(native.stats.selection_us)
		if scripted.audit_checksum!=native.audit_checksum:
			print("PARITY_FAILURE_FRAME ",frame);matches=false;break
		var queue: Dictionary=native.native_selection.queue_stats()
		bounded=bounded and queue.records<=4*queue.live+1024
	matches=matches and scripted.state_sha256()==native.state_sha256()
	scripted.free();native.free()
	scripted=Forest.new();scripted.native_selection=null;native=Forest.new()
	root.add_child(scripted);root.add_child(native)
	scripted.setup(meshes,2200);native.setup(meshes,2200)
	scripted.visibility(false,false);native.visibility(false,false)
	scripted.audit_enabled=true;native.audit_enabled=true
	var one: Array[Transform3D]=[Transform3D.IDENTITY]
	var extreme:=PackedInt64Array([-9223372036854775807])
	scripted.upsert_chunk("one",extreme,one);native.upsert_chunk("one",extreme,one)
	var boundaries:=true;var t:=0.0
	for reference in [false,true]:
		scripted.profile(reference);native.profile(reference)
		scripted.reset_lod_state(Vector3(0,9.23563575,20),800,t);native.reset_lod_state(Vector3(0,9.23563575,20),800,t)
		for px in [220.0,180.0,90.0,70.0,95.0,75.0]:
			for offset in [-2.1,-0.02,-0.0001,0.0,0.0001,0.02,2.1]:
				var eye:=Vector3(0,9.23563575,Forest.HEIGHT*800/px+offset)
				t+=0.4;scripted.tick(eye,800,t);native.tick(eye,800,t)
				boundaries=boundaries and scripted.state_sha256()==native.state_sha256()
	print("NATIVE_SELECTION_BOUNDARIES ",boundaries)
	matches=matches and boundaries
	print("NATIVE_SELECTION_PARITY ",{"passed":matches,"bounded":bounded,"roots":2000,"frames":180,"script_selection_us":script_us,"native_selection_us":native_us,"scope":"Same renderer and meshes; native selection versus scripted selection, no GPU performance claim."})
	scripted.free();native.free();quit(0 if matches and bounded else 1)
