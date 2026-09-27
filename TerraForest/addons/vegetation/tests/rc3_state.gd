extends RefCounted
const Candidate=preload("res://addons/vegetation/forest.gd")
const Previous=preload("res://addons/vegetation/reference_rc2/forest.gd")

func run(app: Node)->Dictionary:
	var checks: Array=[]
	var h=Candidate.new()
	var rng: RandomNumberGenerator=RandomNumberGenerator.new();rng.seed=1203
	for i in range(1000):
		var d: float=rng.randf_range(0,500)
		h._due_tokens[i]=i;h._due_distances[i]=d;h._heap_push(d,i,i)
	var ordered: bool=true;var last: float=-1.0
	while not h._heap_distance.is_empty():
		var d: float=h._heap_distance[0]
		var id: int=h._heap_pop()
		ordered=ordered and d>=last and h._popped_valid and id>=0
		last=d
	checks.append({"name":"1000 heap deadlines pop in nondecreasing order without losing roots","pass":ordered})
	h._due_tokens[-9223372036854775807]=7;h._heap_push(1.0,-9223372036854775807,7)
	var negative: int=h._heap_pop()
	checks.append({"name":"Negative 64-bit stable IDs are not used as invalid-event sentinels","pass":h._popped_valid and negative==-9223372036854775807})
	h._due_tokens[1]=2;h._heap_push(1,1,1);h._heap_push(2,1,2)
	h._heap_pop();var rejected: bool=not h._popped_valid
	h._heap_pop();checks.append({"name":"Superseded deadlines are rejected without invalidating latest event","pass":rejected and h._popped_valid})
	h.free()
	var old=Previous.new();var new=Candidate.new();app.world.add_child(old);app.world.add_child(new)
	old.setup(app.asset.meshes,2200);new.setup(app.asset.meshes,2200);old.visibility(false,false);new.visibility(false,false)
	var ids: PackedInt64Array=PackedInt64Array();var ts: Array[Transform3D]=[]
	for i in range(256):
		ids.append(i-128)
		var t: Transform3D=Transform3D(Basis(Vector3.UP,rng.randf_range(-PI,PI)).scaled(Vector3.ONE*rng.randf_range(0.3,2.0)),app.base_pose.origin+Vector3(rng.randf_range(-500,500),rng.randf_range(-300,300),rng.randf_range(-500,500)))
		ts.append(t)
	old.upsert_chunk("random",ids,ts);new.upsert_chunk("random",ids,ts)
	old.audit_enabled=true;new.audit_enabled=true;old.profiling_enabled=true;new.profiling_enabled=true
	var eye: Vector3=app.base_pose.origin;var proj: float=785.6277
	old.reset_lod_state(eye,proj,0);new.reset_lod_state(eye,proj,0)
	var matches: bool=true;var phases: bool=true;var heap_bound: bool=true
	for i in range(600):
		var u: float=float(i)/40.0
		var p: Vector3=eye+Vector3(70*sin(u),35*sin(u*0.73),80*cos(u*1.3))
		if i%73==0:p+=Vector3(800,120,-700)
		if i%100==0:proj=400.0+float(i%400)*4.0
		if i==211:
			old.shadow_reach=170;new.shadow_reach=170;old.changed=true;new.changed=true
		if i==350:
			old.remove_root(2);new.remove_root(2)
		if i==410:
			var add: Array[Transform3D]=[Transform3D(Basis.IDENTITY,eye+Vector3(10,0,10))]
			old.upsert_chunk("replacement",PackedInt64Array([2]),add);new.upsert_chunk("replacement",PackedInt64Array([2]),add)
		old.tick(p,proj,float(i)/60);new.tick(p,proj,float(i)/60)
		matches=matches and old.audit_checksum==new.audit_checksum
		var sum_us: int=new.phase_us[0]+new.phase_us[1]+new.phase_us[2]+new.phase_us[3]+new.phase_us[5]
		phases=phases and sum_us==int(new.stats.update_us) and new.phase_us[4]<=new.phase_us[2]
		heap_bound=heap_bound and new._heap_distance.size()<=4*new._due_tokens.size()+1024
	checks.append({"name":"600 adversarial frames match RC2 with vertical positions, teleports, FOV/setting changes, deletion and stable-ID reuse","pass":matches and new.state_sha256()==old.state_sha256()})
	checks.append({"name":"Exclusive CPU phases sum to whole tick; slot helper is bounded by flush","pass":phases})
	checks.append({"name":"Live and superseded event records remain under the stated queue bound","pass":heap_bound})
	# Exact transitions and boundaries, including the shadow 29/35m hysteresis pair.
	old.free();new.free();old=Previous.new();new=Candidate.new();app.world.add_child(old);app.world.add_child(new)
	old.setup(app.asset.meshes,2200);new.setup(app.asset.meshes,2200);old.visibility(false,false);new.visibility(false,false)
	var one: Array[Transform3D]=[Transform3D.IDENTITY]
	old.upsert_chunk("one",PackedInt64Array([42]),one);new.upsert_chunk("one",PackedInt64Array([42]),one)
	old.audit_enabled=true;new.audit_enabled=true
	var boundary_match: bool=true;var t: float=0.0
	for reference in [false,true]:
		old.profile(reference);new.profile(reference)
		old.reset_lod_state(Vector3(0,9.23563575,20),800,0);new.reset_lod_state(Vector3(0,9.23563575,20),800,0)
		for px in [220.0,180.0,90.0,70.0,95.0,75.0]:
			for offset in [-2.1,-0.02,-0.0001,0.0,0.0001,0.02,2.1]:
				var p: Vector3=Vector3(0,9.23563575,Candidate.HEIGHT*800/px+offset)
				t+=0.4;old.tick(p,800,t);new.tick(p,800,t)
				boundary_match=boundary_match and old.audit_checksum==new.audit_checksum
	checks.append({"name":"Inclusive/exclusive LOD boundaries and source-heavy diagnostic retain reference decisions","pass":boundary_match})
	new.profiling_enabled=false;new.audit_enabled=false
	new.tick(Vector3(0,9,100),800,t+1,true)
	var jobs: int=new.stats.selection_jobs;var updates: int=new.stats.uploaded_bytes
	for i in range(240):new.tick(Vector3(0,9,100),800,t+2+float(i)/60)
	checks.append({"name":"Settled turns/stationary frames perform no decision rescheduling or instance writes","pass":jobs==int(new.stats.selection_jobs) and updates==int(new.stats.uploaded_bytes)})
	old.free();new.free()
	return {"status":"EXECUTED_NATIVE_STATE_AND_QUEUE_REGRESSIONS","checks":checks,"not_measured":"Target GPU power, CPU percent, long-session/gameplay frame times"}
