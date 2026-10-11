# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var core=ClassDB.instantiate("TerrainCore")
    var point:PackedByteArray=core.execute(Codec.point_command(Vector3(800,50,1304)))
    var center:=Vector3(800,floorf(point.decode_float(12)/16)*16-24,1304)
    var ok:bool=Codec.reply_ok(core.execute(Codec.brush(center,center,4,0,false,1)))
    var revision:int=core.execute(Codec.command(0)).decode_u32(12)
    var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
    var base:=Vector3i(49,floori(center.y/16),81)
    var graphs:Array=[];var basins:Array=[];var levels:Array=[]
    for h in range((base.y*16-1)*1000,roundi((center.y+4)*1000)+1,1000):levels.append(h)
    var registry=ClassDB.instantiate("NativeWaterRegions");registry.configure(9,1)
    var generations:Array=[]
    var sample_calls:=0
    for x in 2:
        var coordinate:=base+Vector3i(x,0,0)
        var field=ClassDB.instantiate("NativeWaterField")
        ok=ok and field.begin_terrain(9,revision,epoch,coordinate*16-Vector3i.ONE,Vector3i(18,18,18),1,roundi((center.y+4)*1000))
        while field.statistics().status==0:field.sample_terrain(core,512);sample_calls+=1
        ok=ok and field.statistics().ready
        var g=ClassDB.instantiate("NativeWaterTopology");ok=ok and g.begin_field(field,Vector3i.ONE,Vector3i(16,16,16))
        while g.statistics().status==0:g.advance(128)
        var b=ClassDB.instantiate("NativeWaterBasins");ok=ok and b.begin(g.graph())
        while b.statistics().status==0:b.advance(1024)
        ok=ok and b.hierarchy().ok
        var ports:PackedInt32Array=g.graph().world_ports
        for i in range(8,ports.size(),9):
            if not levels.has(ports[i]):levels.append(ports[i])
        var merges:PackedInt32Array=b.hierarchy().merges
        for i in range(2,merges.size(),4):
            if not levels.has(merges[i]):levels.append(merges[i])
        var ticket:Dictionary=registry.reserve_region(coordinate,revision,epoch,0)
        ok=ok and ticket.ok and registry.begin_publish(g,ticket.generation)
        while registry.statistics().busy:registry.advance(512)
        generations.append(ticket.generation)
        graphs.append(g);basins.append(b)
    levels.sort();var profiles:Array=[];var quantity:=0
    for x in 2:
        var p=ClassDB.instantiate("NativeWaterProfiles");ok=ok and p.begin_region(graphs[x],basins[x],PackedInt64Array(levels))
        while p.statistics().status==0:p.advance(512)
        var data:Dictionary=p.profiles();ok=ok and data.ok
        for row:PackedInt64Array in data.profiles_ml:quantity+=row[levels.find(roundi(center.y*1000))]
        profiles.append(p)
    var network=ClassDB.instantiate("NativeWaterNetwork");ok=ok and network.begin(registry,profiles)
    var calls:=0;var peak:=0
    while network.statistics().status==0:
        var start:=Time.get_ticks_usec();var s:Dictionary=network.advance(128);calls+=1;peak=maxi(peak,Time.get_ticks_usec()-start);ok=ok and s.work_units<=128
    ok=ok and network.statistics().status==1
    if ok:
        ok=network.begin_add(base,0,quantity)
        while network.statistics().water.busy:
            var s:Dictionary=network.advance_settling(1);ok=ok and s.ok and s.total_ml+s.pending_ml==quantity
        ok=ok and absf(network.inspect(base,0).level_mm-center.y*1000)<.001 and absf(network.inspect(base+Vector3i(1,0,0),0).level_mm-center.y*1000)<.001
        ok=ok and network.begin_remove(base+Vector3i(1,0,0),0,1000)
        while network.statistics().water.busy:
            var s:Dictionary=network.advance_settling(1);ok=ok and s.ok and s.total_ml+s.moved_ml==quantity
        ok=ok and network.statistics().water.total_ml==quantity-1000
    var remap_result:Dictionary={}
    if ok:
        ok=Codec.reply_ok(core.execute(Codec.brush(center,center,5,0,false,1)))
        var edited_revision:int=core.execute(Codec.command(0)).decode_u32(12)
        var edited_epoch:int=core.execute(Codec.command(13)).decode_u32(12)
        var new_graphs:Array=[];var new_basins:Array=[];var new_levels:Array=[];var new_profiles:Array=[]
        for h in range((base.y*16-1)*1000,roundi((center.y+5)*1000)+1,1000):new_levels.append(h)
        for x in 2:
            var coordinate:=base+Vector3i(x,0,0)
            var field=ClassDB.instantiate("NativeWaterField")
            ok=ok and field.begin_terrain(9,edited_revision,edited_epoch,coordinate*16-Vector3i.ONE,Vector3i(18,18,18),1,roundi((center.y+5)*1000))
            while field.statistics().status==0:field.sample_terrain(core,512)
            var graph=ClassDB.instantiate("NativeWaterTopology");ok=ok and graph.begin_field(field,Vector3i.ONE,Vector3i(16,16,16))
            while graph.statistics().status==0:graph.advance(128)
            var basin=ClassDB.instantiate("NativeWaterBasins");ok=ok and basin.begin(graph.graph())
            while basin.statistics().status==0:basin.advance(1024)
            var ports:PackedInt32Array=graph.graph().world_ports
            for i in range(8,ports.size(),9):
                if not new_levels.has(ports[i]):new_levels.append(ports[i])
            var merges:PackedInt32Array=basin.hierarchy().merges
            for i in range(2,merges.size(),4):
                if not new_levels.has(merges[i]):new_levels.append(merges[i])
            var ticket:Dictionary=registry.reserve_region(coordinate,edited_revision,edited_epoch,generations[x])
            ok=ok and ticket.ok and registry.begin_publish(graph,ticket.generation)
            while registry.statistics().busy:registry.advance(512)
            new_graphs.append(graph);new_basins.append(basin)
        new_levels.sort()
        for x in 2:
            var profile=ClassDB.instantiate("NativeWaterProfiles");ok=ok and profile.begin_region(new_graphs[x],new_basins[x],PackedInt64Array(new_levels))
            while profile.statistics().status==0:profile.advance(512)
            new_profiles.append(profile)
        var replacement=ClassDB.instantiate("NativeWaterNetwork");ok=ok and replacement.begin(registry,new_profiles)
        while replacement.statistics().status==0:replacement.advance(128)
        var remapping=ClassDB.instantiate("NativeWaterRemapPlan")
        ok=ok and not network.statistics().current and remapping.begin(network,replacement)
        while remapping.statistics().status==0:remapping.advance(128)
        remap_result=remapping.plan()
        ok=ok and remap_result.ok and remap_result.mapped_ml==quantity-1000 and remap_result.displaced_ml==0
        ok=ok and network.statistics().water.total_ml==quantity-1000 and replacement.statistics().water.total_ml==0
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_network_terrain.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"failures":0 if ok else 1,"center":center,"sample_calls":sample_calls,"anchors":levels.size(),"quantity_ml":quantity,"network_calls":calls,"max_network_call_us":peak,"network":network.statistics(),"remap":remap_result,"scope":"Actual native excavation across two independently sampled owned regions, finite pour/withdrawal, then larger excavation and conserved geometric remap plan. Not a saved-world or rendered flow test."},"  "));file.close()
    print("WATER_NETWORK_TERRAIN failures=",0 if ok else 1);quit(0 if ok else 1)
