extends SceneTree
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Legacy = preload("res://addons/volumetric_terrain/collision_reuse.gd")
var checks := 0
var failures := 0
var timing := {}
var recipes: RefCounted

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ")+label)

func _initialize() -> void:
	if not ClassDB.class_exists("NativeTerrainCollision"):
		GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	run.call_deferred()

func worker_prepare(faces: PackedVector3Array) -> Dictionary:
	var result: Dictionary = recipes.prepare(faces,1024)
	result["worker_resolve"] = result.pieces[0].resolve({})
	return result

func summary(samples: Array[float]) -> Dictionary:
	samples.sort()
	return {"samples":samples.size(),"median_ms":samples[samples.size()/2],"p95_ms":samples[mini(samples.size()-1,int(samples.size()*0.95))],"max_ms":samples.back()}

func run() -> void:
	check(ClassDB.class_exists("NativeTerrainCollision"),"native collision recipe API registered")
	if failures: finish(); return
	recipes = ClassDB.instantiate("NativeTerrainCollision")
	var empty: Dictionary = recipes.prepare(PackedVector3Array(),1024)
	check(empty.ok and empty.pieces.is_empty(),"empty geometry needs no collision pieces")
	check(not recipes.prepare(PackedVector3Array([Vector3.ZERO]),1024).ok,"incomplete triangle rejected")
	check(not recipes.prepare(PackedVector3Array([Vector3(NAN,0,0),Vector3.ZERO,Vector3.ONE]),1024).ok,"nonfinite geometry rejected")
	check(not recipes.prepare(PackedVector3Array(),255).ok and not recipes.prepare(PackedVector3Array(),1025).ok,"piece bounds enforced")
	var uninitialized: RefCounted = ClassDB.instantiate("NativeTerrainCollisionPiece")
	check(not uninitialized.resolve({}).ok,"uninitialized public recipe cannot create a physics resource")
	var faces := PackedVector3Array()
	for i in range(2051):
		var origin := Vector3(i%47,0,i/47)
		faces.append_array(PackedVector3Array([origin,origin+Vector3.BACK,origin+Vector3.RIGHT]))
	var original := faces.duplicate()
	var worker := Thread.new()
	worker.start(worker_prepare.bind(faces))
	var prepared: Dictionary = worker.wait_to_finish()
	check(prepared.ok and prepared.pieces.size()==3,"worker prepares full pieces and final three-triangle tail")
	check(not prepared.worker_resolve.ok,"physics resolution rejected on worker thread")
	var joined := PackedVector3Array()
	for piece in prepared.pieces: joined.append_array(piece.get_faces())
	check(joined==original,"piece boundaries preserve exact face order and values")
	faces[0]=Vector3(99,99,99)
	var copy: PackedVector3Array = prepared.pieces[0].get_faces()
	copy[0]=Vector3(-99,-99,-99)
	check(prepared.pieces[0].get_faces()[0]==original[0],"input and returned face mutations cannot modify immutable recipes")
	var previous := {}
	for piece in prepared.pieces:
		var first: Dictionary = piece.resolve({})
		previous[piece.get_token()]=first.shape
		var reused: Dictionary = piece.resolve(previous)
		check(first.ok and not first.reused and reused.reused and first.shape==reused.shape,"identical geometry reuses the same live shape")
	var first_piece: RefCounted = prepared.pieces[0]
	var old_shape: ConcavePolygonShape3D = previous[first_piece.get_token()]
	old_shape.backface_collision=false
	var replaced: Dictionary = first_piece.resolve(previous)
	check(not replaced.reused and replaced.shape!=old_shape and not old_shape.backface_collision,"incorrect backface state replaced without mutating the old live shape")
	old_shape.backface_collision=true
	old_shape.set_faces(PackedVector3Array([Vector3.ZERO,Vector3.UP,Vector3.RIGHT]))
	replaced=first_piece.resolve(previous)
	check(not replaced.reused and old_shape.get_faces().size()==3,"hash-bucket collision or externally changed shape requires exact-match replacement")
	check(not first_piece.resolve({first_piece.get_token():17}).reused,"malformed cached value cannot be reused")
	benchmark()
	previous.clear()
	finish()

func benchmark() -> void:
	# Real terrain mesh from the native core, also works in clean release projects.
	var core: RefCounted = ClassDB.instantiate("TerrainCore")
	var response: PackedByteArray = core.execute(Codec.command(1,[960,1312,32,1,0]))
	check(Codec.reply_ok(response),"native terrain collision fixture generated")
	if not Codec.reply_ok(response): return
	var decoded: Dictionary = Codec.decode_mesh(response.slice(16))
	check(not decoded.has("error") and not decoded.faces.is_empty(),"real terrain fixture contains collision faces")
	if decoded.has("error") or decoded.faces.is_empty(): return
	var faces: PackedVector3Array = decoded.faces
	timing["scope"]="Headless real-terrain CPU calls, excludes simulation and node attachment; no frame-rate guarantee."
	timing["triangles"]=faces.size()/3
	for size in [256,512,1024]:
		var cook: Array[float] = []
		var prepare: Array[float] = []
		var reuse: Array[float] = []
		var legacy_reuse: Array[float] = []
		var total_cook: Array[float] = []
		for iteration in range(12):
			var baked: Dictionary = recipes.prepare(faces,size)
			prepare.append(baked.prepare_ms)
			var previous := {}
			var total := 0.0
			for piece in baked.pieces:
				var resolved: Dictionary = piece.resolve({})
				cook.append(resolved.cook_ms)
				total+=float(resolved.cook_ms)
				previous[piece.get_token()]=resolved.shape
			total_cook.append(total)
			var begin := Time.get_ticks_usec()
			for piece in baked.pieces: piece.resolve(previous)
			reuse.append(float(Time.get_ticks_usec()-begin)/1000.0)
			var old_cache := {}
			for at in range(0,faces.size(),size*3):
				Legacy.prepare(faces.slice(at,mini(at+size*3,faces.size())),{},old_cache)
			begin=Time.get_ticks_usec()
			for at in range(0,faces.size(),size*3):
				Legacy.prepare(faces.slice(at,mini(at+size*3,faces.size())),old_cache,{})
			legacy_reuse.append(float(Time.get_ticks_usec()-begin)/1000.0)
		timing[str(size)]={"pieces":int(ceil(float(faces.size())/(size*3))),"prepare_worker":summary(prepare),"cook_piece":summary(cook),"cook_tile":summary(total_cook),"reuse_tile":summary(reuse),"legacy_reuse_tile":summary(legacy_reuse)}
	if "--profile-attachment" in OS.get_cmdline_user_args():benchmark_attachment(faces)
	print("COLLISION_TIMING ",JSON.stringify(timing))

func attachment_case(pieces:Array,previous:Dictionary,enter_first:bool)->Dictionary:
	# Original diagnostic: resource setup is not the engine's first live-body cook.
	var body:=StaticBody3D.new();body.collision_layer=0;body.collision_mask=0
	var enter_ms:=0.0
	if enter_first:
		var began:=Time.get_ticks_usec();root.add_child(body);enter_ms=(Time.get_ticks_usec()-began)/1000.0
	var setup_ms:=0.0;var attach_ms:=0.0;var largest_unit_ms:=enter_ms;var reused:=0
	var cache:Dictionary={}
	for piece:RefCounted in pieces:
		var began:=Time.get_ticks_usec()
		var resolved:Dictionary=piece.resolve(previous)
		var setup:float=(Time.get_ticks_usec()-began)/1000.0
		setup_ms+=setup;reused+=int(resolved.reused)
		began=Time.get_ticks_usec()
		var node:=CollisionShape3D.new();node.shape=resolved.shape;body.add_child(node)
		var attached:float=(Time.get_ticks_usec()-began)/1000.0
		attach_ms+=attached;largest_unit_ms=maxf(largest_unit_ms,setup+attached)
		cache[resolved.token]=resolved.shape
	if not enter_first:
		var began:=Time.get_ticks_usec();root.add_child(body);enter_ms=(Time.get_ticks_usec()-began)/1000.0
		largest_unit_ms=maxf(largest_unit_ms,enter_ms)
	check(body.get_shape_owners().size()==pieces.size() and PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"attachment diagnostic publishes every piece into a real physics space")
	check(reused==(pieces.size() if not previous.is_empty() else 0),"attachment diagnostic distinguishes newly created from live-reused shapes")
	return {"body":body,"cache":cache,"setup_ms":setup_ms,"attach_ms":attach_ms,"enter_ms":enter_ms,"total_ms":setup_ms+attach_ms+enter_ms,"largest_unit_ms":largest_unit_ms}

func benchmark_attachment(faces:PackedVector3Array)->void:
	var result:Dictionary={"engine":ProjectSettings.get_setting("physics/3d/physics_engine","DEFAULT"),"scope":"Headless real-terrain static-body publication, layer/mask zero as in preparation. Timed resource setup, per-piece attachment and body entry; excludes simulation, rendering and retirement. Deferred entry includes its final indivisible publication. No production policy change."}
	for size:int in [256,512,1024]:
		var samples:Dictionary={"cold_live":{},"reused_live":{},"cold_deferred":{}}
		for iteration:int in 6:
			var pieces:Array=recipes.prepare(faces,size).pieces
			var reconstructed:=PackedVector3Array()
			for piece:RefCounted in pieces:reconstructed.append_array(piece.get_faces())
			check(reconstructed==faces,"attachment partition preserves every collision triangle in order")
			var cold:Dictionary=attachment_case(pieces,{},true)
			var reused:Dictionary=attachment_case(pieces,cold.cache,true)
			var deferred:Dictionary=attachment_case(pieces,{},false)
			var cases:Dictionary={"cold_live":cold,"reused_live":reused,"cold_deferred":deferred}
			for label:String in cases:
				for metric:String in ["setup_ms","attach_ms","enter_ms","total_ms","largest_unit_ms"]:
					if not samples[label].has(metric):samples[label][metric]=[] as Array[float]
					samples[label][metric].append(float(cases[label][metric]))
			cold.body.free();reused.body.free();deferred.body.free()
		for label:String in samples:
			for metric:String in samples[label]:samples[label][metric]=summary(samples[label][metric])
		result[str(size)]={"pieces":int(ceil(float(faces.size())/(size*3))),"cases":samples}
	timing["attachment"]=result

func finish() -> void:
	recipes=null
	DirAccess.make_dir_recursive_absolute("res://reports")
	var result := {"checks":checks,"failures":failures,"timing":timing}
	var file := FileAccess.open("res://reports/terrain_collision.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("TERRAIN_COLLISION_RESULT ",JSON.stringify(result))
	quit(1 if failures else 0)
