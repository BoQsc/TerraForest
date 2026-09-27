extends SceneTree
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Tools = preload("res://addons/structures/structure_tools.gd")
var checks: Array[Dictionary] = []
var failures: int = 0
var timings: Array[Dictionary] = []
const CENTER = Vector3(336,180,1328)

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"pass":ok})
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func stamp(shape: int, half: Vector3, turn: int = 0, steps: int = 1) -> RefCounted:
	var result: RefCounted = ClassDB.instantiate("NativeTerrainStamp")
	check(result.configure(shape,CENTER,half,turn,steps),"native shape %d configuration" % shape)
	return result
func density(world: RefCounted, point: Vector3) -> float:
	return world.execute(Codec.point_command(point)).decode_float(16)

func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	check(ClassDB.class_exists("NativeTerrainStamp"),"native primitive kernel registered")
	var validator: RefCounted = ClassDB.instantiate("NativeTerrainStamp")
	check(not validator.configure(9,CENTER,Vector3.ONE,0,1),"unknown shape rejected")
	check(not validator.configure(1,Vector3.INF,Vector3.ONE,0,1),"nonfinite center rejected")
	check(not validator.configure(1,CENTER,Vector3(NAN,1,1),0,1),"nonfinite size rejected")
	check(not validator.configure(0,CENTER,Vector3(2,3,2),0,1),"sphere requires equal radii")
	check(not validator.configure(2,CENTER,Vector3(2,3,3),0,1),"cylinder requires circular cross section")
	check(not validator.configure(1,CENTER,Vector3.ONE,4,1),"unsupported rotation rejected")
	check(not validator.configure(4,CENTER,Vector3.ONE,0,8),"subvoxel stair rise and run rejected")
	check(not validator.configure(4,Vector3(100,100,100),Vector3(32,32,32),0,16),"excessive lattice work rejected before allocation")
	check(not validator.configure(1,Vector3(1,3,1),Vector3.ONE,0,1),"stamp cannot cross world or bedrock boundary")
	var sphere: RefCounted = stamp(0,Vector3(4,4,4))
	check(sphere.distance(CENTER)==-4 and sphere.distance(CENTER+Vector3(4,0,0))==0 and sphere.distance(CENTER+Vector3(5,0,0))==1,"sphere distances match analytic reference")
	check(not sphere.configure(1,CENTER,Vector3.ONE,0,1),"configured primitive is immutable")
	check(sphere.packet(true,0).is_empty() and sphere.packet(true,4).is_empty(),"invalid material cannot create command")
	check(is_inf(sphere.distance(Vector3.INF)),"nonfinite distance query returns exterior")
	var box: RefCounted = stamp(1,Vector3(2,3,4),1)
	check(box.distance(CENTER+Vector3(3,0,0))<0 and box.distance(CENTER+Vector3(0,0,3))>0,"quarter turn swaps asymmetric box axes")
	var cylinder: RefCounted = stamp(2,Vector3(3,5,3))
	check(cylinder.distance(CENTER+Vector3(2,4,0))<0 and cylinder.distance(CENTER+Vector3(3,0,3))>0 and cylinder.distance(CENTER+Vector3(0,6,0))>0,"cylinder sides and cap have correct signed distances")
	for turn in range(4):
		var slope: RefCounted = stamp(3,Vector3(4,4,6),turn)
		var high: Vector3 = Vector3(0,0,4).rotated(Vector3.UP,turn*PI/2).round()
		check(slope.distance(CENTER+high+Vector3.UP)<0 and slope.distance(CENTER-high+Vector3.UP)>0,"slope orientation %d preserves rising direction" % turn)
	var stairs: RefCounted = stamp(4,Vector3(4,4,8),0,4)
	check(stairs.distance(CENTER+Vector3(0,2,6))<0 and stairs.distance(CENTER+Vector3(0,2,-6))>0 and stairs.distance(CENTER+Vector3(0,-3,0))<0,"stairs preserve risers without internal zero-distance seams")
	var core: RefCounted = ClassDB.instantiate("TerrainCore")
	var before: PackedByteArray = core.execute(Codec.command(4))
	var packet: PackedByteArray = sphere.packet(true,1)
	var malformed: Array[PackedByteArray] = [packet.slice(0,51),packet+PackedByteArray([0])]
	for entry: Vector2i in [Vector2i(4,2),Vector2i(8,9),Vector2i(36,4),Vector2i(40,32),Vector2i(44,2),Vector2i(48,4)]:
		var bad: PackedByteArray = packet.duplicate()
		bad.encode_u32(entry.x,entry.y)
		malformed.append(bad)
	var invalid_float: PackedByteArray = packet.duplicate()
	invalid_float.encode_float(12,NAN)
	malformed.append(invalid_float)
	var rejected: bool = true
	for bad: PackedByteArray in malformed:
		rejected = not validator.inspect(bad)["valid"] and not Codec.reply_ok(core.execute(bad)) and rejected
	check(rejected and core.execute(Codec.command(4))==before,"all malformed packet schemas sizes enums and coordinates reject without terrain mutation")
	for preset in Tools.PRESETS:
		core.execute(Codec.command(6,[1703]))
		var command: PackedByteArray = preset.packet(CENTER,1,true,2)
		var started: int = Time.get_ticks_usec()
		var reply: PackedByteArray = core.execute(command)
		timings.append({"shape":preset.title,"stamp_ms":(Time.get_ticks_usec()-started)/1000.0})
		check(Codec.reply_ok(reply) and reply.decode_u32(16)>0,"%s writes native density lattice" % preset.title)
		var interior: Vector3 = CENTER+Vector3(0,-2,0)
		check(density(core,interior)<0 and density(core,CENTER+Vector3(20,0,0))>0,"%s has solid interior and unchanged exterior" % preset.title)
		var again: PackedByteArray = core.execute(command)
		check(Codec.reply_ok(again) and again.decode_u32(16)==0 and again.decode_u32(12)==reply.decode_u32(12),"%s repeated stamp is idempotent" % preset.title)
		var saved: PackedByteArray = core.execute(Codec.command(4)).slice(12)
		var restored: RefCounted = ClassDB.instantiate("TerrainCore")
		var load_packet: PackedByteArray = Codec.command(5)+saved
		check(Codec.reply_ok(restored.execute(load_packet)) and restored.execute(Codec.command(4)).slice(12)==saved,"%s survives unchanged terrain snapshot format" % preset.title)
		var encoded: PackedByteArray = core.execute(Codec.command(1,[320,1312,32,1]))
		var mesh: Dictionary = Codec.decode_mesh(encoded.slice(16))
		var elevated_faces: int = 0
		for point: Vector3 in mesh.get("faces",PackedVector3Array()):
			if point.y>160: elevated_faces += 1
		check(Codec.reply_ok(encoded) and not mesh.has("error") and elevated_faces>0,"%s produces native render and collision geometry at stamp altitude" % preset.title)
		check(Codec.reply_ok(core.execute(preset.packet(CENTER,1,false,2))) and density(core,interior)>0,"%s subtracts through same native edit path" % preset.title)
	DirAccess.make_dir_recursive_absolute("res://reports")
	var output := FileAccess.open("res://reports/structures.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"timings":timings,"scope":"Native construction stamps; not persistent prefab instances or city streaming"},"  "))
	output.close()
	quit(0 if failures==0 else 1)
