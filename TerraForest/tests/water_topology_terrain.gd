# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var core=ClassDB.instantiate("TerrainCore")
    var sample: PackedByteArray=core.execute(Codec.point_command(Vector3(800,50,1310)))
    var center=Vector3(800,floorf(sample.decode_float(12)),1310)
    var carve: PackedByteArray=core.execute(Codec.brush(center,center,12,0,false,1))
    var ok: bool=Codec.reply_ok(carve)
    var revision: int=core.execute(Codec.command(0)).decode_u32(12)
    var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
    var lake=ClassDB.instantiate("NativeLakeVolume")
    ok=ok and lake.configure(center-Vector3(16,16,16),Vector3i(32,20,32),1,center.y-3,center-Vector3(0,6,0))
    var status:=0;var slices:=0
    while status==0 and slices<2000:
        status=lake.sample_terrain(core,512,revision,epoch);slices+=1
    ok=ok and status==1
    var task=ClassDB.instantiate("NativeWaterTopology")
    ok=ok and task.begin(lake,Vector3i(8,2,8),Vector3i(16,16,16))
    var calls:=0;var peak:=0
    while task.statistics().status==0 and calls<1000:
        var start:=Time.get_ticks_usec();var progress: Dictionary=task.advance(64);peak=maxi(peak,Time.get_ticks_usec()-start)
        ok=ok and progress.work_cells<=64;calls+=1
    var graph: Dictionary=task.graph()
    var seed_id: int=(16+32*(10+20*16))*6
    ok=ok and graph.ok and graph.ids.has(seed_id) and not graph.edges.is_empty()
    if graph.ok and graph.ids.has(seed_id):ok=ok and graph.floors_mm[graph.ids.find(seed_id)]<=roundi((center.y-6)*1000)
    var basins=ClassDB.instantiate("NativeWaterBasins")
    ok=ok and basins.begin(graph)
    var basin_calls:=0;var basin_peak:=0
    while basins.statistics().status==0 and basin_calls<10000:
        var start:=Time.get_ticks_usec();var progress:Dictionary=basins.advance(512)
        basin_peak=maxi(basin_peak,Time.get_ticks_usec()-start);basin_calls+=1
        ok=ok and progress.work_units<=512
    var hierarchy:Dictionary=basins.hierarchy()
    ok=ok and hierarchy.ok and hierarchy.owners.size()==graph.ids.size()
    ok=ok and hierarchy.requires_stitching and not hierarchy.settling_compatible
    ok=ok and hierarchy.portals.size()/3==task.statistics().portals
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_topology_terrain.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"failures":0 if ok else 1,"source":"actual native terrain density after sphere excavation","terrain_slices":slices,"graph_calls":calls,"max_graph_call_us":peak,"graph":task.statistics(),"basins":basins.statistics(),"basin_calls":basin_calls,"max_basin_call_us":basin_peak,"scope":"Headless in-memory terrain integration; not a saved-world flow test."},"  "));file.close()
    print(("PASS " if ok else "FAIL ")+"regional graph and basin forest preserve seed and outgoing ports in actual excavated native terrain")
    print("WATER_TOPOLOGY_TERRAIN failures=",0 if ok else 1);quit(0 if ok else 1)
