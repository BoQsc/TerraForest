extends RefCounted
const Candidate=preload("res://addons/vegetation/forest.gd")
const Reference=preload("res://addons/vegetation/reference_rc2/forest.gd")

func storage_ok(f)->bool:
	var totals: Array[int]=[0,0,0,0,0]
	for cell in f.cells.values():
		for kind in range(5):
			var members: Array=cell["slot_ids"][kind]
			var slots: Dictionary=cell["slots"][kind]
			var packets: Dictionary=cell["packets"][kind]
			var node: MultiMeshInstance3D=cell["nodes"][kind]
			if members.size()!=slots.size() or members.size()!=packets.size():return false
			if node!=null and node.multimesh.visible_instance_count!=members.size():return false
			if node==null and not members.is_empty():return false
			for i in range(members.size()):
				var id: int=members[i]
				if slots.get(id,-1)!=i or not f.roots.has(id):return false
				var row: Dictionary=f.roots[id]
				if not Candidate._has_tier(row,kind):return false
				var p: Vector4=packets[id]
				if not p.is_equal_approx(f._packet(row,kind)):return false
				# The headless dummy renderer returns identity/default values for these
				# getters. Actual storage readback is checked by rendered smoke instead.
				if RenderingServer.get_video_adapter_name()!="":
					if not node.multimesh.get_instance_transform(i).is_equal_approx(row["local_t"]):print("BAD TRANSFORM ",kind," ",i," ",node.multimesh.get_instance_transform(i)," expected ",row["local_t"]);return false
					var c: Color=node.multimesh.get_instance_custom_data(i)
					if not Vector4(c.r,c.g,c.b,c.a).is_equal_approx(p):print("BAD PACKET ",kind," ",i," ",c," expected ",p);return false
			totals[kind]+=members.size()
	for kind in range(5):
		if totals[kind]!=int(f.stats[Candidate.COUNT_KEYS[kind]]):return false
	return true

func run(app: Node,extended: bool=false)->Dictionary:
	var checks: Array=[]
	var old=Reference.new();var new=Candidate.new()
	app.world.add_child(old);app.world.add_child(new)
	old.setup(app.asset.meshes,2200);new.setup(app.asset.meshes,2200)
	old.visibility(false,false);new.visibility(false,false)
	var ids: PackedInt64Array=PackedInt64Array();var ts: Array[Transform3D]=[]
	if extended:
		for owner in app.forest.owners:
			ids=PackedInt64Array();ts=[]
			for id in app.forest.owners[owner]:
				if app.forest.roots.has(id):ids.append(id);ts.append(app.forest.roots[id]["t"])
			old.upsert_chunk(owner,ids,ts);new.upsert_chunk(owner,ids,ts)
	else:
		var rng: RandomNumberGenerator=RandomNumberGenerator.new();rng.seed=1202
		for i in range(128):
			ids.append(i+500001)
			var basis: Basis=Basis(Vector3.UP,rng.randf_range(-PI,PI)).scaled(Vector3.ONE*rng.randf_range(0.65,1.4))
			ts.append(Transform3D(basis,app.base_pose.origin+Vector3(rng.randf_range(-350,350),rng.randf_range(-20,20),rng.randf_range(-350,350))))
		old.upsert_chunk("test",ids,ts);new.upsert_chunk("test",ids,ts)
	old.audit_enabled=true;new.audit_enabled=true
	var eye: Vector3=app.base_pose.origin;var proj: float=1001.0*0.5/tan(deg_to_rad(32.5))
	old.reset_lod_state(eye,proj,0.0);new.reset_lod_state(eye,proj,0.0)
	var initial: String=new.state_sha256()
	checks.append({"name":"Canonical reference/candidate LOD SHA256 matches","pass":initial==old.state_sha256()})
	checks.append({"name":"Initial dense-slot buffers and packets match root state","pass":storage_ok(new)})
	var n: int=1440 if extended else 180
	var hashes: bool=true;var full: bool=true;var storage: bool=true;var counts: bool=true
	var old_ms: Array=[];var new_ms: Array=[]
	var bytes0: int=int(new.stats.uploaded_bytes);var rebuild0: int=int(new.stats.full_rebuilds)
	for i in range(n):
		var u: float=float(i)/maxi(n-1,1)
		var p: Vector3=eye+app.base_pose.basis.x*(10*sin(u*TAU))-app.base_pose.basis.z*(10*sin(u*PI))
		old.tick(p,proj,float(i)/60.0);new.tick(p,proj,float(i)/60.0)
		old_ms.append(float(old.stats.update_us)/1000.0);new_ms.append(float(new.stats.update_us)/1000.0)
		if old.audit_checksum!=new.audit_checksum:hashes=false
		for field in Candidate.COUNT_KEYS:
			if old.stats[field]!=new.stats[field]:counts=false
		if i%60==0 or i==n-1:
			full=full and old.state_sha256()==new.state_sha256()
			storage=storage and storage_ok(new)
	checks.append({"name":"Every route pose has identical visual/shadow/transition state checksum","pass":hashes})
	checks.append({"name":"All route tier counts match unchanged RC2 state policy","pass":counts})
	checks.append({"name":"Full route checkpoint SHA256s match","pass":full})
	checks.append({"name":"Dense slots survive all route additions/removals/fade packets","pass":storage})
	checks.append({"name":"Camera motion performs zero full cell rebuilds","pass":int(new.stats.full_rebuilds)==rebuild0})
	var route_bytes: int=int(new.stats.uploaded_bytes)-bytes0
	var route_stats: Dictionary=new.stats.duplicate(true)
	var moved_state: String=new.state_sha256()
	old.reset_lod_state(eye,proj,0.0);new.reset_lod_state(eye,proj,0.0)
	checks.append({"name":"Reset restores identical starting LOD state after unrelated movement","pass":new.state_sha256()==initial and old.state_sha256()==initial})
	checks.append({"name":"Reset drains every visual and shadow transition","pass":old.moving.is_empty() and new.moving.is_empty()})
	var jobs: int=int(new.stats.selection_jobs);var writes: int=int(new.stats.uploaded_bytes)
	for i in range(120):new.tick(eye,proj,float(i)/60.0)
	checks.append({"name":"Settled stationary updates do not reselect or rewrite slots","pass":int(new.stats.selection_jobs)==jobs and int(new.stats.uploaded_bytes)==writes})
	# Rapid travel and projection changes must invalidate certificates immediately.
	var changes_match: bool=true
	for i in range(60):
		var p: Vector3=eye+Vector3(sin(i*1.7)*450,cos(i*0.7)*80,cos(i*1.3)*350)
		var projection: float=proj*(0.6+float(i%5)*0.25)
		old.tick(p,projection,10.0+i*0.07);new.tick(p,projection,10.0+i*0.07)
		if old.audit_checksum!=new.audit_checksum:changes_match=false
	checks.append({"name":"Teleports/FOV changes retain exact reference decisions without stale selection","pass":changes_match and old.state_sha256()==new.state_sha256()})
	checks.append({"name":"Slot buffers remain valid after teleports and overlapping transitions","pass":storage_ok(new)})
	# Grow a cell whose previously empty tier already has an allocation.
	var unit=Candidate.new();app.world.add_child(unit);unit.setup(app.asset.meshes,2200)
	var t: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3.ZERO)]
	unit.upsert_chunk("a",PackedInt64Array([900001]),t);unit.tick(Vector3(0,9,20),800,0,true)
	unit.tick(Vector3(0,9,500),800,1,true)
	var extra: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(4,0,0)),Transform3D(Basis.IDENTITY,Vector3(8,0,0))]
	unit.upsert_chunk("b",PackedInt64Array([900002,900003]),extra);unit.tick(Vector3(0,9,500),800,2,true)
	unit.tick(Vector3(0,9,20),800,3);unit.tick(Vector3(0,9,20),800,3.4)
	checks.append({"name":"Growing an empty tier preserves capacity and all new roots","pass":int(unit.stats.source)==3 and storage_ok(unit)})
	unit.remove_root(900002);unit.tick(Vector3(0,9,20),800,4,true)
	checks.append({"name":"Deleting a middle slot leaves no hole or resurrected root","pass":not unit.roots.has(900002) and int(unit.stats.source)==2 and storage_ok(unit)})
	unit.rebase(Vector3(100,20,-60));unit.tick(Vector3(-100,-11,80),800,5,true)
	checks.append({"name":"Origin rebase updates local transforms and membership caches","pass":storage_ok(unit) and (unit.roots[900001]["t"] as Transform3D).origin==Vector3(-100,-20,60)})
	unit.remove_chunk("a");unit.remove_chunk("b");unit.tick(Vector3.ZERO,800,6,true)
	checks.append({"name":"Unload clears every slot, counter and empty batch","pass":unit.cells.is_empty() and unit.roots.is_empty() and int(unit.stats.source)==0})
	var result: Dictionary={"status":"EXECUTED_NATIVE_CPU_NOT_GPU_POWER","scope":"Checks and timing on this build machine, not target-GPU performance","storage_readback_executed":RenderingServer.get_video_adapter_name()!="","roots":new.roots.size(),"frames":n,"checks":checks,"reference_update_ms":app.distribution(old_ms),"candidate_update_ms":app.distribution(new_ms),"requested_route_update_bytes":route_bytes,"route_end_stats":route_stats,"candidate_end_after_stress":new.stats.duplicate(true),"initial_sha256":initial,"moved_sha256":moved_state}
	unit.free();old.free();new.free()
	return result
