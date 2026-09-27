extends RefCounted
const Candidate=preload("res://addons/vegetation/forest.gd")
const Reference=preload("res://addons/vegetation/reference_rc3/forest.gd")

func _add(checks: Array,name: String,value: bool)->void:
	checks.append({"name":name,"pass":value})

func _buffer(count: int)->PackedFloat32Array:
	var data: PackedFloat32Array=PackedFloat32Array();data.resize(count*16)
	for i in range(count):
		Candidate._write(data,i,Transform3D(Basis.IDENTITY,Vector3(i*2,3,-4)),Vector4(0.25,float(i),-1,0.28))
	return data

func run(app: Node)->Dictionary:
	var checks: Array=[];var f=Candidate.new();app.world.add_child(f);f.setup(app.asset.meshes,2200)
	var mm: MultiMesh=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_custom_data=true
	mm.custom_aabb=AABB(Vector3(-20,-20,-20),Vector3(40,40,40))
	f._allocate_editable(mm,0)
	_add(checks,"Zero capacity never primes an invalid slot",int(f.stats.get("instance_cache_primes",0))==0)
	f._allocate_editable(mm,3)
	_add(checks,"Fresh editable allocation is hidden and primed once",mm.instance_count==3 and mm.visible_instance_count==0 and int(f.stats.instance_cache_primes)==1)
	mm.buffer=_buffer(3);mm.visible_instance_count=3
	mm.set_instance_custom_data(1,Color(0.5,7,1,0.28))
	var actual_storage: bool=RenderingServer.get_video_adapter_name()!=""
	if actual_storage:
		_add(checks,"First sparse edit preserves uploaded transform and other rows",mm.get_instance_transform(1).origin.is_equal_approx(Vector3(2,3,-4)) and mm.get_instance_custom_data(0).g==0 and mm.get_instance_custom_data(2).g==2 and mm.get_instance_custom_data(1).g==7)
	f._allocate_editable(mm,3)
	_add(checks,"Unchanged capacity neither re-primes nor hides live rows",int(f.stats.instance_cache_primes)==1 and mm.visible_instance_count==3)
	mm.buffer=_buffer(3)
	if actual_storage:_add(checks,"Same-capacity bulk rewrite replaces cache rather than retaining stale edits",mm.get_instance_custom_data(1).g==1)
	f._allocate_editable(mm,9)
	_add(checks,"Growth creates a new hidden prepared allocation",mm.instance_count==9 and mm.visible_instance_count==0 and int(f.stats.instance_cache_primes)==2)
	mm.buffer=_buffer(9);mm.visible_instance_count=9
	mm.set_instance_custom_data(8,Color(0.5,9,1,0.28))
	if actual_storage:_add(checks,"Grown allocation accepts a sparse edit in its new tail",mm.get_instance_transform(8).origin.is_equal_approx(Vector3(16,3,-4)) and mm.get_instance_custom_data(8).g==9)
	f._allocate_editable(mm,2)
	_add(checks,"Shrink also re-prepares and hides storage",mm.instance_count==2 and mm.visible_instance_count==0 and int(f.stats.instance_cache_primes)==3)
	mm.buffer=_buffer(2);mm.visible_instance_count=2
	f._allocate_editable(mm,0);f._allocate_editable(mm,0)
	_add(checks,"Zero resize clears live cache payload estimate without priming",mm.instance_count==0 and int(f.stats.instance_cache_live_payload_bytes)==0 and int(f.stats.instance_cache_primes)==3)
	f._allocate_editable(mm,4);mm.buffer=_buffer(4);mm.visible_instance_count=4
	mm.set_instance_custom_data(3,Color(0.2,5,1,0.28))
	_add(checks,"Reallocation after zero receives its own preparation",int(f.stats.instance_cache_primes)==4)
	if actual_storage:_add(checks,"Reallocated sparse record is coherent",mm.get_instance_custom_data(3).g==5)
	f._allocate_editable(mm,0);mm=null
	var ts: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3.ZERO),Transform3D(Basis.IDENTITY,Vector3(8,0,0))]
	f.upsert_chunk("unit",PackedInt64Array([701,702]),ts);f.tick(Vector3(0,9,20),800,0,true)
	var initial_primes: int=int(f.stats.instance_cache_primes)
	_add(checks,"Live tree batches pass through editable allocation helper",initial_primes>4 and int(f.stats.source)==2)
	f.tick(Vector3(0,9,550),800,1,true)
	var key: Vector2i=Vector2i.ZERO;var source_node: MultiMeshInstance3D=f.cells[key].nodes[0]
	_add(checks,"Hidden source tier remains allocated for later reuse",source_node!=null and source_node.multimesh.visible_instance_count==0)
	var extra: Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(12,0,0))]
	f.upsert_chunk("addition",PackedInt64Array([703]),extra);f.tick(Vector3(0,9,550),800,2,true)
	_add(checks,"World growth prepares previously empty tiers too",source_node.multimesh.instance_count==3 and source_node.multimesh.visible_instance_count==0 and int(f.stats.instance_cache_primes)>initial_primes)
	f.tick(Vector3(0,9,20),800,3);f.tick(Vector3(0,9,20),800,3.4)
	var checker=load("res://addons/vegetation/tests/rc2_state.gd").new()
	_add(checks,"First reactivation after growth preserves dense slots and packets",int(f.stats.source)==3 and checker.storage_ok(f))
	var calls: int=int(f.stats.instance_cache_primes)
	f.reset_lod_state(Vector3(0,9,20),800,0)
	_add(checks,"Canonical reset at unchanged capacity does not repeat cache preparation",int(f.stats.instance_cache_primes)==calls)
	f.remove_root(702);f.tick(Vector3(0,9,20),800,5,true)
	_add(checks,"Removal shrinks storage and leaves valid remaining instances",not f.roots.has(702) and checker.storage_ok(f))
	f.rebase(Vector3(130,0,0));f.tick(Vector3(-130,9,20),800,6,true)
	_add(checks,"Rebased batches are prepared and coherent",checker.storage_ok(f))
	f.remove_chunk("unit");f.remove_chunk("addition");f.tick(Vector3.ZERO,800,7,true)
	_add(checks,"Unloading releases live cache-payload accounting",f.cells.is_empty() and int(f.stats.instance_cache_live_payload_bytes)==0)
	# This is first-use readiness through the same helper, not a warm traversal.
	f.upsert_chunk("new_region",PackedInt64Array([99001]),[Transform3D(Basis.IDENTITY,Vector3(500,0,500))]);f.tick(Vector3(500,9,520),800,8,true)
	_add(checks,"New region after unload obtains prepared batches",f.roots.size()==1 and int(f.stats.instance_cache_live_payload_bytes)>0 and checker.storage_ok(f))
	var result: Dictionary={"scope":"Native storage/state checks. CPU cache readiness follows initialization order; no claim of target-GPU timings or driver trace.","actual_storage_getters":actual_storage,"checks":checks,"stats":f.stats.duplicate(true)}
	f.free();return result
