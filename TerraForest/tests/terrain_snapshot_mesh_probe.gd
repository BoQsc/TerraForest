extends SceneTree
var checks: Array[Dictionary]=[]
var creation_ms: Array[float]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	if not ClassDB.class_exists("TerrainCore"): quit(1);return
	for size in [16,32]:
		var native=ClassDB.instantiate("TerrainCore")
		check(native.experimental_snapshot_submit(960,960,size,1,0),"surface request admitted")
		var rows: Array=[];var deadline:=Time.get_ticks_msec()+5000
		while rows.is_empty() and Time.get_ticks_msec()<deadline:
			rows=native.experimental_snapshot_poll();await process_frame
		check(rows.size()==1,"surface packet received")
		if rows.is_empty(): native.experimental_snapshot_stop();continue
		var packet: Dictionary=rows[0]
		var encoded: PackedByteArray=native.experimental_snapshot_encode(packet,960,960,size)
		check(encoded.size()>=36 and encoded.decode_u32(0)==0x324d5254 and encoded.decode_u32(32)==packet.indices.size()/4,"stream packet includes exact collision triangle count")
		var begin:=Time.get_ticks_usec();var mesh: ArrayMesh=native.experimental_snapshot_create_mesh(packet);creation_ms.append((Time.get_ticks_usec()-begin)/1000.0)
		check(mesh!=null and mesh.get_surface_count()==1,"native adapter creates one render surface")
		if mesh!=null:
			var arrays: Array=mesh.surface_get_arrays(0)
			var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var valid: bool=positions.size()*12==packet.positions.size() and normals.size()==positions.size() and indices.size()*4==packet.indices.size()
			for i in range(positions.size()):
				var p:=Vector3(packet.positions.decode_float(i*12),packet.positions.decode_float(i*12+4),packet.positions.decode_float(i*12+8))
				var n:=Vector3(packet.normals.decode_float(i*12),packet.normals.decode_float(i*12+4),packet.normals.decode_float(i*12+8))
				valid=valid and positions[i].distance_to(p)<0.001 and normals[i].dot(n)>0.999
			for i in range(indices.size()): valid=valid and indices[i]==packet.indices.decode_u32(i*4)
			check(valid,"engine mesh preserves positions normals and indices")
		for fault in ["missing_normals","bad_index","nan_position","zero_normal","foreign_owner","stale_revision","stale_epoch"]:
			var bad: Dictionary=packet.duplicate(true)
			if fault=="missing_normals": bad.erase("normals")
			elif fault=="bad_index": bad.indices.encode_u32(0,0xffffffff)
			elif fault=="nan_position": bad.positions.encode_float(0,NAN)
			elif fault=="zero_normal":
				for offset in [0,4,8]: bad.normals.encode_float(offset,0.0)
			elif fault=="foreign_owner": bad.source_id+=1
			elif fault=="stale_revision": bad.validated_revision+=1
			elif fault=="stale_epoch": bad.epoch+=1
			check(native.experimental_snapshot_create_mesh(bad)==null,"reject "+fault)
			check(native.experimental_snapshot_encode(bad,960,960,size).is_empty(),"stream conversion rejects "+fault)
		var reset:=PackedByteArray();reset.resize(8);reset.encode_u32(0,6);reset.encode_u32(4,1703);native.execute(reset)
		check(native.experimental_snapshot_create_mesh(packet)==null,"actual reset rejects retained old packet")
		check(native.experimental_snapshot_encode(packet,960,960,size).is_empty(),"stream conversion rejects actual reset")
		native.experimental_snapshot_stop();native=null;mesh=null
	await test_brick_publication()
	await test_excavation_publication()
	var failures:=0
	for row: Dictionary in checks:
		if not row.passed: failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/command.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"creation_ms":creation_ms},"  "));file.close()
	quit(0 if failures==0 else 1)

func capture_brick(native, bottom: int, top: int) -> Dictionary:
	var codec=load("res://addons/volumetric_terrain/mesh_codec.gd")
	var revision: int=native.execute(codec.command(0)).decode_u32(12)
	if not native.experimental_snapshot_submit_brick(960,960,32,bottom,revision,bottom,top): return {}
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		var rows: Array=native.experimental_snapshot_poll()
		if not rows.is_empty(): return native.experimental_snapshot_encode_brick(rows[0],960,960,32)
		await process_frame
	return {}

func prepare_brick(envelope: Dictionary) -> MeshInstance3D:
	if envelope.is_empty(): return null
	var codec=load("res://addons/volumetric_terrain/mesh_codec.gd")
	var data: Dictionary=codec.decode_mesh(envelope.packet)
	if data.has("error"): return null
	var valid:=true
	for p: Vector3 in data.arrays[Mesh.ARRAY_VERTEX]:
		valid=valid and p.y>=envelope.origin.y and p.y<=envelope.origin.y+envelope.extent.y
	check(valid,"bounded render vertices include no blocks outside owned height")
	var pieces=ClassDB.instantiate("NativeTerrainCollision")
	var recipe: Dictionary=pieces.prepare(data.faces,256)
	if not recipe.ok: return null
	var node:=MeshInstance3D.new();node.visible=false
	if not data.arrays[Mesh.ARRAY_INDEX].is_empty():
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data.arrays);node.mesh=mesh
	var body:=StaticBody3D.new();body.collision_layer=0;body.collision_mask=0;node.add_child(body)
	for piece in recipe.pieces:
		var shape:=CollisionShape3D.new();shape.shape=piece.resolve({}).shape;body.add_child(shape)
	root.add_child(node)
	return node

func activate_brick(node: MeshInstance3D, active: bool) -> void:
	node.visible=active
	(node.get_child(0) as StaticBody3D).collision_layer=1 if active else 0

func brick_ray(from: Vector3, to: Vector3) -> Dictionary:
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))

func test_brick_publication() -> void:
	var codec=load("res://addons/volumetric_terrain/mesh_codec.gd")
	var native=ClassDB.instantiate("TerrainCore")
	for y in [64,223,224]: native.execute(codec.command(3,[969,y,969,1]))
	var old: Array[MeshInstance3D]=[]
	for bottom in [192,224]:
		var envelope: Dictionary=await capture_brick(native,bottom,bottom+32)
		check(not envelope.is_empty() and envelope.origin==Vector3i(960,bottom,960) and envelope.extent==Vector3i(32,32,32),"brick envelope retains explicit 3D ownership")
		var node: MeshInstance3D=prepare_brick(envelope)
		if node==null:
			check(false,"brick render and collision preparation")
			for previous in old: previous.free()
			native.experimental_snapshot_stop();return
		old.append(node);activate_brick(node,true)
	await physics_frame;await physics_frame
	var from:=Vector3(968.5,223.5,969.5);var to:=Vector3(970.5,223.5,969.5)
	check(not brick_ray(from,to).is_empty(),"published lower brick has matching collision")
	native.execute(codec.command(3,[969,223,969,0]))
	var next: Array[MeshInstance3D]=[]
	for bottom in [192,224]:
		var envelope: Dictionary=await capture_brick(native,bottom,bottom+32)
		var node: MeshInstance3D=prepare_brick(envelope)
		if node==null:
			check(false,"replacement brick preparation")
			for previous in old+next: previous.free()
			native.experimental_snapshot_stop();return
		next.append(node)
		await physics_frame
		check(not brick_ray(from,to).is_empty(),"old collision survives incomplete replacement preparation")
	for node in old: activate_brick(node,false)
	for node in next: activate_brick(node,true)
	await physics_frame;await physics_frame
	check(brick_ray(from,to).is_empty(),"published removal clears lower brick collision")
	var hit:=brick_ray(Vector3(969.5,223.5,969.5),Vector3(969.5,224.5,969.5))
	check(not hit.is_empty() and absf(hit.position.y-224.0)<0.001,"neighbor replacement exposes matching face at vertical boundary")
	for node in old+next: node.free()
	native.experimental_snapshot_stop()

func test_excavation_publication() -> void:
	var codec=load("res://addons/volumetric_terrain/mesh_codec.gd")
	var native=ClassDB.instantiate("TerrainCore")
	var old: Array[MeshInstance3D]=[]
	for bottom in [0,32]:
		var node: MeshInstance3D=prepare_brick(await capture_brick(native,bottom,bottom+32))
		if node==null:
			check(false,"excavation control preparation")
			for previous in old: previous.free()
			native.experimental_snapshot_stop();return
		old.append(node);activate_brick(node,true)
	await physics_frame;await physics_frame
	var center:=Vector3(969,32,969)
	check(brick_ray(center+Vector3(0,0.5,0.25),center+Vector3(4,0.5,0.25)).is_empty(),"solid underground control has no internal cavity wall")
	var reply: PackedByteArray=native.execute(codec.brush(center,center,2.5,0,false,1))
	check(codec.reply_ok(reply),"real density excavation crosses vertical brick boundary")
	var next: Array[MeshInstance3D]=[]
	for bottom in [0,32]:
		var node: MeshInstance3D=prepare_brick(await capture_brick(native,bottom,bottom+32))
		if node==null:
			check(false,"excavated brick preparation")
			for previous in old+next: previous.free()
			native.experimental_snapshot_stop();return
		next.append(node)
		await physics_frame
		check(brick_ray(center+Vector3(0,0.5,0.25),center+Vector3(4,0.5,0.25)).is_empty(),"incomplete excavation does not publish new collision early")
	for node in old: activate_brick(node,false)
	for node in next: activate_brick(node,true)
	await physics_frame;await physics_frame
	for dy in [-0.5,0.5]:
		var hit:=brick_ray(center+Vector3(0,dy,0.25),center+Vector3(4,dy,0.25))
		check(not hit.is_empty() and hit.position.x>970.0 and hit.position.x<972.5,"excavated collision matches cavity on each side of Y join")
	for node in old+next: node.free()
	native.experimental_snapshot_stop()
