extends SceneTree

const Packs = preload("res://addons/vehicle_runtime/vehicle_packs.gd")
const Session = preload("res://addons/vehicle_runtime/world_vehicle.gd")
const MANIFEST := "res://tests/fixtures/vehicles.module.json"
var failures := 0

class ReadyProvider extends Node:
	var focus := Vector3(1000, 50, 1000)
	var travel_velocity := Vector3.ZERO
	func is_collision_region_ready(_bounds: AABB) -> bool: return true

class Fixture extends Node3D:
	var terrain := ReadyProvider.new()
	var structures := ReadyProvider.new()
	var player := CharacterBody3D.new()
	var camera := Camera3D.new()

func check(passed: bool, label: String) -> void:
	print("PASS " if passed else "FAIL ", label)
	if not passed: failures += 1

func _initialize() -> void: run.call_deferred()

func run() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var fleet: RefCounted = ClassDB.instantiate("NativeVehicleFleet")
	var codec: RefCounted = ClassDB.instantiate("NativeVehicleStorage")
	var pose := Transform3D(Basis.IDENTITY, Vector3(1000, 50, 1000))
	var legacy: int = fleet.spawn(pose)
	var old: PackedByteArray = fleet.capture_storage_snapshot()
	check(old.size() == 88 and old.decode_u32(4) == 2, "default vehicle retains exact legacy v2 layout")
	var custom: int = fleet.spawn_module(pose.translated(Vector3(8,0,0)), "test.cart.v1", PackedByteArray([1, 77]))
	var unknown: int = fleet.spawn_module(pose.translated(Vector3(16,0,0)), "missing.pack.v3", PackedByteArray([7, 8, 9]))
	var encoded: PackedByteArray = fleet.capture_storage_snapshot()
	check(encoded.decode_u32(4) == 3 and codec.validate_fleet_snapshot(encoded), "mixed fleet uses bounded versioned binary state")
	var restored: RefCounted = ClassDB.instantiate("NativeVehicleFleet")
	check(restored.restore_storage_snapshot(encoded) and restored.capture_storage_snapshot() == encoded, "unknown provider state survives exact roundtrip")
	check(restored.get_record(unknown).kind == "missing.pack.v3" and restored.get_record(custom).state == PackedByteArray([1,77]), "identities and opaque states remain distinct")
	var invalid := encoded.duplicate(); invalid.resize(invalid.size()-1)
	check(not restored.restore_storage_snapshot(invalid) and restored.capture_storage_snapshot()==encoded, "truncated v3 rejects atomically")
	invalid=encoded.duplicate();invalid.encode_u16(88, 4097)
	check(not codec.validate_fleet_snapshot(invalid), "oversized type length rejected")
	invalid=encoded.duplicate();invalid[92]=255
	check(not codec.validate_fleet_snapshot(invalid), "non-ASCII provider identity rejected")
	var oversized:=PackedByteArray();oversized.resize(4097)
	check(fleet.spawn_module(pose,"test.bad",oversized)==0 and not fleet.set_module_state(custom,oversized), "per-vehicle payload bounded before mutation")
	check(fleet.spawn_module(pose,"../invalid")==0, "invalid provider identity rejected")
	check(fleet.query_near_kind(pose.origin,32,1,64,"test.cart.v1").ids == PackedInt64Array([custom]), "kind filtering precedes nearest-result limit")
	var page: Dictionary=fleet.read_records(0,2)
	check(not page.complete and page.records.size()==2 and fleet.read_records(page.cursor,2).records[0].identity==unknown, "bounded iteration preserves sorted identities")
	var packs=Packs.new()
	var malformed_path:="user://module_manifest_check_%d.json"%OS.get_process_id()
	for descriptor:Dictionary in [
		{"api":1,"id":123,"providers":[{"capability":"vehicle","id":"test.invalid"}]},
		{"api":true,"id":"test.invalid","providers":[{"capability":"vehicle","id":"test.invalid"}]},
		{"api":1,"id":"test.invalid","providers":[{"capability":"vehicle","id":"test.staged"},{"capability":"vehicle","id":123}]}]:
		var malformed_file:=FileAccess.open(malformed_path,FileAccess.WRITE)
		malformed_file.store_string(JSON.stringify(descriptor));malformed_file.close()
		check(not packs.registry.register_manifest(malformed_path,true).ok and packs.registry.modules.is_empty() and packs.registry.entries("vehicle").is_empty(),"malformed identity types reject atomically before provider sorting")
	DirAccess.remove_absolute(malformed_path)
	check(not packs.registry.register_manifest(MANIFEST).ok and packs.registry.modules.is_empty(), "untrusted scripts never auto-enabled")
	check(packs.registry.register_manifest(MANIFEST,true).ok, "trusted independent vehicle module registered")
	check(not packs.registry.register_manifest(MANIFEST,true).ok and packs.registry.entries("vehicle").size()==2, "duplicate module rejects without partial providers")
	check(packs.prepare(false) and packs.vehicles.size()==3, "default adapter and independent systems coexist")
	check(packs.request("test.cart.v1") and packs.request("test.cart.v2") and packs.requested.size()==1, "shared scene requests deduplicated")
	check(packs.take("test.cart.v1")==packs.take("test.cart.v2") and packs.requested.is_empty(), "every accepted scene request drained once")
	var world:=Fixture.new();root.add_child(world)
	world.add_child(world.terrain);world.add_child(world.structures);world.add_child(world.player);world.player.add_child(world.camera)
	world.player.position=pose.origin+Vector3.RIGHT*2.8
	var session:=Session.new();world.add_child(session)
	session.packs=packs;session._packs_ready=true;session.fleet=fleet;session.storage=codec;session._world=world;session.fleet_enabled=true
	session.activation=preload("res://addons/vehicle_runtime/fleet_activation.gd").new(session)
	check(session.activation.admit(world,custom,true), "independent RigidBody scene activates without DrivingCar fields")
	var body: RigidBody3D=session.activation.residents.get(custom)
	if body != null:
		check(session.adapter(body).charge==77 and session.activation.parked_views.has("test.cart.v1"), "adapter restores opaque state and creates its own prototype")
		world.player.position=body.position+Vector3.RIGHT*2.8
		check(session.enter(world,custom) and session.adapter(body).enabled and Engine.physics_ticks_per_second==60, "custom controller receives entry without Ranger physics policy")
		session.adapter(body).camera_update(body,world.camera,0.016)
		check(session.adapter(body).camera_updates==1, "per-vehicle camera implementation dispatches")
		session.adapter(body).charge=23
		var saved: PackedByteArray=session.capture_snapshot()
		check(codec.validate_fleet_snapshot(saved) and fleet.get_record(custom).state==PackedByteArray([1,23]), "save captures independent controller state")
		check(session.restore_snapshot(saved) and not session.driving and session.activation.residents.is_empty(), "reload releases input and pooled bodies")
		check(session.activation.admit(world,custom,true) and session.activation.residents[custom]==body and session.adapter(body).charge==23, "same-kind pooling restores saved custom state")
	check(not session.activation.admit(world,unknown,true) and fleet.get_record(unknown).present, "missing pack never substitutes Ranger or discards record")
	var renderer: Node3D=ClassDB.instantiate("NativeParkedVehicleRenderer");world.add_child(renderer)
	check(renderer.configure(fleet,[{"mesh":BoxMesh.new(),"transform":Transform3D.IDENTITY}],4,"test.cart.v1"), "native parked renderer accepts explicit provider")
	check(renderer.refresh(pose.origin,32,PackedInt64Array(),64).ids==PackedInt64Array([custom]), "mixed parked fleet never uses wrong mesh")
	check(fleet.get_record(legacy).kind==Packs.DEFAULT, "legacy identity remains default provider")
	world.free();packs.finish()
	print("VEHICLE_MODULES failures=", failures)
	quit(1 if failures else 0)
