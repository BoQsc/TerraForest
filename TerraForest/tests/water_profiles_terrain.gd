# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var core=ClassDB.instantiate("TerrainCore")
    var sample:PackedByteArray=core.execute(Codec.point_command(Vector3(800,50,1310)))
    var center=Vector3(800,floorf(sample.decode_float(12)),1310)
    var ok:bool=Codec.reply_ok(core.execute(Codec.brush(center,center,4,0,false,1)))
    var revision:int=core.execute(Codec.command(0)).decode_u32(12)
    var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
    var lake=ClassDB.instantiate("NativeLakeVolume")
    ok=ok and lake.configure(center-Vector3(8,8,8),Vector3i(16,12,16),1,center.y-2,center-Vector3(0,3,0))
    var status:=0
    while status==0:status=lake.sample_terrain(core,512,revision,epoch)
    ok=ok and status==1
    var topology=ClassDB.instantiate("NativeWaterTopology")
    ok=ok and topology.begin(lake,Vector3i.ZERO,Vector3i(16,12,16))
    while topology.statistics().status==0:topology.advance(256)
    var basins=ClassDB.instantiate("NativeWaterBasins")
    ok=ok and basins.begin(topology.graph())
    while basins.statistics().status==0:basins.advance(512)
    var hierarchy:Dictionary=basins.hierarchy()
    ok=ok and hierarchy.ok and hierarchy.settling_compatible
    var levels:Array=[]
    for h in range(roundi((center.y-8)*1000),roundi((center.y-2)*1000)+1,100):levels.append(h)
    for i in range(2,hierarchy.merges.size(),4):
        if not levels.has(hierarchy.merges[i]):levels.append(hierarchy.merges[i])
    levels.sort()
    var profiles=ClassDB.instantiate("NativeWaterProfiles")
    ok=ok and profiles.begin(topology,basins,PackedInt64Array(levels))
    var calls:=0;var peak:=0
    while profiles.statistics().status==0:
        var start:=Time.get_ticks_usec();var step:Dictionary=profiles.advance(256)
        peak=maxi(peak,Time.get_ticks_usec()-start);calls+=1;ok=ok and step.work_units<=256
    var data:Dictionary=profiles.profiles();ok=ok and data.ok
    var measure=ClassDB.instantiate("NativeWaterCapacity");measure.begin(lake)
    while measure.statistics().status==0:measure.step(2048)
    var total:=0
    for row:PackedInt64Array in data.profiles_ml:total+=row[-1]
    ok=ok and absi(total-measure.statistics().amount_ml)<=ceili(data.total_anchor_rounding_bound_ml+.5)
    var solver=ClassDB.instantiate("NativeWaterSettling")
    ok=ok and solver.configure(data.levels_mm,data.profiles_ml,data.merges) and solver.begin_add(0,total)
    while solver.statistics().busy:
        var state:Dictionary=solver.advance(1);ok=ok and state.total_ml+state.pending_ml==total
    ok=ok and solver.begin_remove(0,1000)
    while solver.statistics().busy:
        var state:Dictionary=solver.advance(1);ok=ok and state.total_ml+state.moved_ml==total
    ok=ok and solver.statistics().moved_ml==1000 and solver.statistics().total_ml==total-1000
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_profiles_terrain.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"failures":0 if ok else 1,"capacity_ml":total,"retained_ml":solver.statistics().total_ml,"profiles":profiles.statistics(),"basins":basins.statistics(),"profile_calls":calls,"max_profile_call_us":peak,"scope":"Actual native terrain excavation, capacity compilation and conserved finite pour/withdrawal. Not item or saved-world integration."},"  "));file.close()
    print("WATER_PROFILES_TERRAIN failures=",0 if ok else 1);quit(0 if ok else 1)
