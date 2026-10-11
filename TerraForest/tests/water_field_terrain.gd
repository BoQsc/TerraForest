# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func revision(core)->int:return core.execute(Codec.command(0)).decode_u32(12)
func epoch(core)->int:return core.execute(Codec.command(13)).decode_u32(12)
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var core=ClassDB.instantiate("TerrainCore")
    var sample:PackedByteArray=core.execute(Codec.point_command(Vector3(800,50,1310)))
    var center:=Vector3(800,floorf(sample.decode_float(12)),1310)
    var origin:=Vector3i(center)-Vector3i(9,9,9)
    var f=ClassDB.instantiate("NativeWaterField")
    check(f.begin_terrain(9,revision(core),epoch(core),origin,Vector3i(18,18,18),1,roundi((center.y+8)*1000)),"native raw sampler starts on open outdoor terrain")
    var invalid=ClassDB.instantiate("NativeWaterTopology")
    check(not invalid.begin_field(f,Vector3i.ONE,Vector3i(16,16,16)),"partially sampled terrain cannot enter graph compiler")
    var before:Dictionary=f.statistics()
    check(f.sample_terrain(core,0)==-1 and f.statistics()==before,"invalid sample budget leaves builder unchanged")
    var peak:=0;var calls:=0;var bounded:=true
    while f.statistics().status==0:
        var previous:int=f.statistics().sampled_nodes;var start:=Time.get_ticks_usec()
        f.sample_terrain(core,256);peak=maxi(peak,Time.get_ticks_usec()-start);calls+=1
        bounded=bounded and f.statistics().sampled_nodes-previous<=256
    check(f.statistics().ready and bounded,"native terrain sampling completes within node budgets")
    var graph=ClassDB.instantiate("NativeWaterTopology");graph.begin_field(f,Vector3i.ONE,Vector3i(16,16,16))
    while graph.statistics().status==0:graph.advance(128)
    check(graph.graph().ok and graph.statistics().portals>0,"real outdoor terrain preserves open outgoing boundaries")
    var pending=ClassDB.instantiate("NativeWaterField")
    pending.begin_terrain(9,revision(core),epoch(core),origin,Vector3i(18,18,18),1,roundi((center.y+8)*1000))
    pending.sample_terrain(core,32)
    check(Codec.reply_ok(core.execute(Codec.brush(center,center,4,0,false,1))),"terrain excavation changes source while sampling is incomplete")
    check(pending.sample_terrain(core,32)==-4 and not pending.statistics().ready,"edit cancels partial density instead of mixing terrain revisions")
    check(not invalid.begin_field(pending,Vector3i.ONE,Vector3i(16,16,16)),"cancelled mixed-revision source cannot publish topology")
    var identity=ClassDB.instantiate("NativeWaterField")
    identity.begin_terrain(9,revision(core),epoch(core),origin,Vector3i(18,18,18),1,roundi((center.y+8)*1000));identity.sample_terrain(core,1)
    var another=ClassDB.instantiate("TerrainCore")
    check(identity.sample_terrain(another,1)==-4,"sampler cannot switch terrain owners between slices")
    var newest=ClassDB.instantiate("NativeWaterField")
    check(newest.begin_terrain(9,revision(core),epoch(core),origin,Vector3i(18,18,18),1,roundi((center.y+8)*1000)),"fresh snapshot accepts edited native terrain revision")
    while newest.statistics().status==0:newest.sample_terrain(core,512)
    check(newest.statistics().ready and newest.statistics().revision!=f.statistics().revision,"new immutable snapshot completes while previous snapshot remains unchanged")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_field_terrain.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"sample_calls":calls,"max_sample_call_us":peak,"field":f.statistics(),"graph":graph.statistics(),"scope":"Native open-terrain sampling and snapshot cancellation; no water quantity remapping or runtime exchange."},"  "));file.close()
    print("WATER_FIELD_TERRAIN failures=",failures);quit(1 if failures else 0)
