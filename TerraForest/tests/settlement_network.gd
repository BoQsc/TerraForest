# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan=preload("res://addons/structures/site_plan.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0
class EpochNode:
    extends Node
    var epoch:=3
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1
    print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
    DirAccess.make_dir_recursive_absolute("res://reports")
    for addon in ["structures/structures","volumetric_terrain/terrain_core","world_runtime/world_runtime"]:
        GDExtensionManager.load_extension("res://addons/"+addon+".gdextension")
    if not ClassDB.class_exists("NativeBlockPrefab") or not ClassDB.class_exists("TerrainCore"):
        check(false,"native extensions load in a clean project");quit(2);return
    var cottage=load("res://addons/structures/prefabs/brick_cottage.tres")
    var tower=load("res://addons/structures/prefabs/tower_floor.tres")
    var asset=ClassDB.instantiate("NativeBlockPrefab")
    var twin=ClassDB.instantiate("NativeBlockPrefab")
    check(asset.compose_settlement([cottage,tower],2,8,3,1703,3),"compose three connected mixed streets")
    check(twin.compose_settlement([cottage,tower],2,8,3,1703,3) and twin.get_records()==asset.get_records() and twin.get_meta("street_lines")==asset.get_meta("street_lines"),"seed reproduces blocks and road geometry")
    var before: PackedInt32Array=asset.get_records()
    var roads: PackedVector3Array=asset.get_meta("street_lines")
    check(roads.size()==10 and roads[0]==roads[6] and roads[4]==roads[7] and roads[1]==roads[8] and roads[5]==roads[9],"three street ends connect exactly to both cross streets")
    check(not asset.compose_settlement([cottage],64,8,3,1703,8) and asset.get_records()==before and asset.get_meta("street_lines")==roads,"oversized generation preserves prior geometry and road metadata")
    check(not asset.compose_settlement([cottage],2,8,3,1703,9) and not asset.compose_settlement([cottage],2,7,3,1703,2),"invalid street count and width reject")
    for rotation in 4:
        var plan: Dictionary=Plan.prepare(asset,Vector3i(700,0,700),rotation,80)
        check(plan.ok and plan.street_lines.size()==10 and plan.paving_segments>=5,"rotated connected grading/paving plan "+str(rotation))
        if not plan.ok:continue
        var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,4]))
        var accepted:=true
        for segment: Dictionary in plan.segments:
            var packet:=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
            packet.resize(48);packet.encode_float(44,segment.shoulder)
            accepted=Codec.reply_ok(core.execute(packet)) and accepted
        check(accepted,"native terrain accepts all connected site sections "+str(rotation))
        var continuous:=true
        for i in range(0,plan.street_lines.size(),2):
            for step in 9:
                var point: Vector3=plan.street_lines[i].lerp(plan.street_lines[i+1],step/8.0)
                var query:=Codec.point_command(point-Vector3.UP);query.encode_u32(0,26)
                var reply: PackedByteArray=core.execute(query)
                continuous=continuous and Codec.reply_ok(reply) and reply.decode_u32(12)==4 and reply.decode_float(16)<0
                query=Codec.point_command(point+Vector3.UP);query.encode_u32(0,26);reply=core.execute(query)
                continuous=continuous and Codec.reply_ok(reply) and reply.decode_float(16)>0
        check(continuous,"connected streets and junctions have asphalt below and clearance above "+str(rotation))
    asset.set_meta("street_lines",PackedVector3Array([Vector3.ZERO,Vector3(10,0,0),Vector3.ZERO,Vector3(0,0,10)]))
    check(not Plan.prepare(asset,Vector3i(700,0,700),0,80).ok,"tampered road through a foundation rejects")
    asset.set_meta("street_lines",roads)
    var library=preload("res://addons/structures/prefab_library.gd").new()
    library.directory="user://settlement_network_%d"%Time.get_ticks_usec()
    check(library.begin_frontage_sources([cottage,tower],2,8,3,1703,"Connected town",3).ok,"authoring worker accepts connected settlement")
    var result: Dictionary={};var deadline:=Time.get_ticks_msec()+10000
    while result.is_empty() and Time.get_ticks_msec()<deadline:result=library.poll_frontage();await process_frame
    check(result.get("ok",false),"worker saves connected settlement resource")
    if result.get("ok",false):
        var restored=ResourceLoader.load(result.path,"",ResourceLoader.CACHE_MODE_IGNORE)
        check(restored.get_records()==before and restored.get_meta("street_lines")==roads and Plan.prepare(restored,Vector3i(700,0,700),0,80).ok,"saved resource retains deterministic geometry and usable road plan")
        var palette=preload("res://addons/volumetric_terrain/road_palette.gd").new();root.add_child(palette)
        var plan: Dictionary=Plan.prepare(restored,Vector3i(700,0,700),0,80)
        palette.register_prepared_street(plan,3)
        check(palette.prepared_streets.size()==5,"all settlement streets enter the saved entrance catalog")
        palette.register_prepared_street(plan,3)
        check(palette.prepared_streets.size()==5,"repeat registration does not duplicate connected streets")
        var terrain:=EpochNode.new()
        var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
        check(palette.prepare_persistence(terrain,persistence),"connected catalog registers with compound world persistence")
        var saved: PackedByteArray=palette.capture_anchors()
        palette.prepared_streets.clear();palette.prepared_street={}
        check(palette.restore_anchors(saved) and palette.prepared_streets.size()==5 and palette.capture_anchors()==saved,"all road entrances survive exact persistence round trip")
        palette.prepared_streets.clear()
        for i in 255:
            palette.prepared_streets.append({"ends":PackedVector3Array([Vector3(100+i*2,80,100),Vector3(101+i*2,80,100)]),"width":8,"epoch":3})
        palette.prepared_street=palette.prepared_streets[0];palette.selected_street=0
        saved=palette.capture_anchors()
        palette.register_prepared_street(plan,3)
        check(palette.prepared_streets.size()==255 and palette.capture_anchors()==saved,"insufficient catalog capacity rejects entire network without partial registration")
        palette.free();terrain.free();DirAccess.remove_absolute(result.path)
    library.shutdown_frontage();DirAccess.remove_absolute(library.directory)
    var file:=FileAccess.open("res://reports/settlement_network.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Native connected layout, deterministic authoring/resource restore, all four rotations, terrain asphalt/clearance samples and editor street catalog. Not a navigation graph or city-scale performance qualification."},"  "));file.close()
    print("SETTLEMENT_NETWORK checks=",checks," failures=",failures)
    quit(1 if failures else 0)
