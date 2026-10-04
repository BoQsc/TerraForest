# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func sample(core: Object,p: Vector3) -> Vector2:
	var packet:=Codec.command(26,[0,0,0])
	for axis in range(3): packet.encode_float(4+axis*4,p[axis])
	var reply: PackedByteArray=core.execute(packet)
	return Vector2(reply.decode_float(16),reply.decode_u32(12))
func oracle(core: Object,center: Vector3,shape: int) -> void:
	var before: Array[Vector2]=[]
	var points:=PackedVector3Array()
	for z in range(-3,4):
		for y in range(-3,4):
			for x in range(-3,4):
				var point:=center+Vector3(x,y,z)
				points.append(point);before.append(sample(core,point))
	var reply: PackedByteArray=core.execute(Codec.brush(center,center,2,shape,false,3))
	check(Codec.reply_ok(reply) and reply.size()==116,"excavation exposes version-compatible histogram suffix")
	var expected:=PackedInt64Array();expected.resize(16)
	for i in range(points.size()):
		var after:=sample(core,points[i])
		if before[i].x<0 and after.x>=0: expected[int(before[i].y)]+=1
	check(Codec.excavation_samples(reply)==expected,"histogram matches independent before/after density and original-material oracle")
	var total:=0
	for n in expected: total+=n
	check(total>0 and total<=int(reply.decode_u32(16)),"solid removal is bounded by actual changed samples")
	if center.y<100: check(total<int(reply.decode_u32(16)),"underground edit includes band changes that must not count as removal")
	reply=core.execute(Codec.brush(center,center,2,shape,false,3))
	check(Codec.excavation_samples(reply)==PackedInt64Array([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]),"repeated excavation does not recount removed samples")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703,3]))
	var center:=Vector3(800,30,1310)
	oracle(core,center,0)
	oracle(core,center+Vector3(12,0,0),1)
	# Author two distinguishable substrates in air; removal must report the old
	# material, even when the removal brush selects a different material.
	center=Vector3(800,210,1310)
	var added: PackedByteArray=core.execute(Codec.brush(center-Vector3(1,0,0),center-Vector3(1,0,0),2,1,true,1))
	var zero:=PackedInt64Array();zero.resize(16)
	check(Codec.excavation_samples(added)==zero,"additive construction cannot produce excavation counts")
	core.execute(Codec.brush(center+Vector3(1,0,0),center+Vector3(1,0,0),2,1,true,2))
	oracle(core,center,1)
	var malformed:=Codec.brush(center,center,2,0,false,3);malformed.encode_float(28,-1)
	check(Codec.excavation_samples(core.execute(malformed))==zero,"rejected edits have no accounting")
	check(Codec.excavation_samples(added.slice(0,52))==zero,"legacy reply cannot manufacture accounting")
	check(Codec.excavation_samples(Codec.command(0))==zero,"malformed reply yields no accounting")
	print("EXCAVATION_ACCOUNTING ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
