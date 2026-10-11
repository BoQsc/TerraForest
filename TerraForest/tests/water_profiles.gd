# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var costs:Array=[]
var field:=PackedFloat32Array()
func check(ok:bool,label:String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func lake(fill:float,seed:=Vector3(4.5,2.5,8.5)):
    var result=ClassDB.instantiate("NativeLakeVolume")
    result.configure(Vector3.ZERO,Vector3i(16,8,16),1,fill,seed)
    check(result.bake_density(field)==1,"sampled terrain volume bakes")
    return result
func compile(volume):
    var graph=ClassDB.instantiate("NativeWaterTopology");graph.begin(volume,Vector3i.ZERO,Vector3i(16,8,16))
    while graph.statistics().status==0:graph.advance(256)
    var basins=ClassDB.instantiate("NativeWaterBasins");basins.begin(graph.graph())
    while basins.statistics().status==0:basins.advance(2048)
    check(basins.hierarchy().settling_compatible,"terrain hierarchy is closed and solver-compatible")
    return [graph,basins]
func capacity(volume)->int:
    var task=ClassDB.instantiate("NativeWaterCapacity");task.begin(volume)
    while task.statistics().status==0:task.step(2048)
    return task.statistics().amount_ml
func profiles(pair:Array,levels:PackedInt64Array,budget:=256):
    var task=ClassDB.instantiate("NativeWaterProfiles")
    check(task.begin(pair[0],pair[1],levels),"profile compilation begins")
    var before:Dictionary=task.statistics()
    check(not task.profiles().ok and not task.advance(0).ok and task.statistics()==before,"partial profiles and invalid work budgets cannot publish")
    var calls:=0;var peak:=0;var bounded:=true
    while task.statistics().status==0 and calls<400000:
        var start:=Time.get_ticks_usec();var state:Dictionary=task.advance(budget)
        peak=maxi(peak,Time.get_ticks_usec()-start);calls+=1
        bounded=bounded and state.work_units>0 and state.work_units<=budget
    check(task.statistics().status==1 and bounded,"profile compiler completes within operation budgets")
    check(task.advance(budget).work_units==0,"finished profiles perform no additional work")
    costs.append({"calls":calls,"budget":budget,"max_call_us":peak,"statistics":task.statistics()})
    return task
func rejected(pair:Array,levels:PackedInt64Array)->bool:
    var task=ClassDB.instantiate("NativeWaterProfiles")
    if not task.begin(pair[0],pair[1],levels):return true
    while task.statistics().status==0:task.advance(2048)
    return task.statistics().status==-2 and not task.profiles().ok
func finish(solver,initial:int,adding:bool)->bool:
    var ok:=true
    while solver.statistics().busy:
        var state:Dictionary=solver.advance(1)
        ok=ok and (state.total_ml+state.pending_ml==initial+state.requested_ml if adding else state.total_ml+state.moved_ml==initial)
    return ok
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    for z in 17:
        for y in 9:
            for x in 17:
                var d:float=y-(1+maxf(0,2-absf(x-8)*2))
                if x==0 or x==16 or z==0 or z==16:d=-10
                field.append(d)
    var volume=lake(5)
    var pair:Array=compile(volume)
    var levels:=PackedInt64Array([0,1000,2000,3000,4000,5000])
    var task=profiles(pair,levels);var data:Dictionary=task.profiles()
    if not data.ok:quit(1);return
    var rows:Array=data.profiles_ml
    check(rows.size()==2,"ridge has two actual terrain storage curves")
    check(absi(rows[0][-1]+rows[1][-1]-capacity(volume))<=1,"partitioned full capacity matches independent whole-volume integration to one millilitre")
    var hierarchy:Dictionary=pair[1].hierarchy()
    var left_id:int=(4+16*(2+8*8))*6;var right_id:int=(11+16*(2+8*8))*6
    var left:int=hierarchy.owners[hierarchy.ids.find(left_id)];var right:int=hierarchy.owners[hierarchy.ids.find(right_id)]
    check(left!=right,"target points map to separate below-sill bodies")
    check(absi(rows[left][2]-capacity(lake(2,Vector3(4.5,1.5,8.5))))<=1,"left below-sill profile equals separately flooded terrain capacity")
    check(absi(rows[right][2]-capacity(lake(2,Vector3(11.5,1.5,8.5))))<=1,"right below-sill profile equals separately flooded terrain capacity")
    check(profiles(pair,levels,1).profiles()==data,"one-operation scheduling preserves exact terrain capacity curves")
    var mutation:Dictionary=task.profiles();mutation.profiles_ml[0][1]=-1
    check(task.profiles()==data,"caller cannot mutate retained native capacity curves")
    var solver=ClassDB.instantiate("NativeWaterSettling")
    check(solver.configure(data.levels_mm,data.profiles_ml,data.merges),"actual terrain profiles configure native settling")
    var at_four:int=rows[0][4]+rows[1][4]
    check(solver.begin_add(left,at_four) and finish(solver,0,true),"finite pour conserves total plus pending quantity during every terrain-basin spill step")
    check(absf(solver.inspect(left).level_mm-4000)<.001 and absf(solver.inspect(right).level_mm-4000)<.001,"sufficient pour merges both actual terrain basins at four metres")
    var removal:int=at_four-rows[0][3]-rows[1][3]+1000000
    check(solver.begin_remove(left,removal) and finish(solver,at_four,false),"withdrawal conserves retained plus removed water every step")
    check(solver.inspect(left).level_mm<3000 and absf(solver.inspect(right).level_mm-3000)<.001,"withdrawal splits actual terrain basins and retains water behind the sill")
    check(solver.advance(1).work_events==0,"settled terrain water has no further solver work")
    var exact:int=capacity(lake(2.51,Vector3(4.5,1.5,8.5)))
    var interpolated:float=rows[left][2]*.49+rows[left][3]*.51
    var error:float=absf(interpolated-exact)
    check(error<=data.max_leaf_interpolation_error_bound_ml,"off-anchor geometry deviation stays inside declared conservative interpolation bound")
    # Coarse anchors expose substantial volume-to-height error; do not hide it behind a permissive bound.
    var fine_levels:=PackedInt64Array()
    for h in range(0,5001,20):fine_levels.append(h)
    var fine:Dictionary=profiles(pair,fine_levels).profiles()
    var exact_fine:int=exact
    var fine_row:PackedInt64Array=fine.profiles_ml[left]
    var fine_error:float=absf((fine_row[125]+fine_row[126])*.5-exact_fine)
    check(error>1000000 and fine_error<10000 and fine_error<error/100,"two-centimetre anchors sharply reduce measured off-anchor capacity error")
    check(fine.max_level_step_mm==20,"fine profile declares its twenty-millimetre interpolation interval")
    check(rejected(pair,PackedInt64Array([0,2000,4000,5000])),"missing sill anchor cannot silently interpolate spill capacity")
    check(rejected(pair,PackedInt64Array([1000,2000,3000,4000,5000])),"initial anchor above lowest exact air floor rejected")
    check(rejected(pair,PackedInt64Array([0,2000,3000,6000])),"capacity above source ceiling rejected")
    var fake_graph:Dictionary=pair[0].graph();fake_graph.edges[2]+=1
    var fake=ClassDB.instantiate("NativeWaterBasins");fake.begin(fake_graph)
    while fake.statistics().status==0:fake.advance(2048)
    check(rejected([pair[0],fake],levels),"hierarchy from mismatched opening data rejected")
    # A shaft connects a lower cave without removing its solid roof.
    field.clear()
    for z in 17:
        for y in 9:
            for x in 17:
                var pocket:float=minf(2.5-absf(x-4),minf(1.5-absf(y-2),2.5-absf(z-8)))
                var d:float=minf(maxf(maxf(y-4.5,pocket),minf(.75-absf(x-6),.75-absf(z-8))),y-.5)
                if x==0 or x==16 or z==0 or z==16:d=-10
                field.append(d)
    var cave=lake(6.5,Vector3(4.5,5.5,8.5));var cave_pair:Array=compile(cave)
    var cave_levels:Array=[0,1000,2000,3000,4000,5000,6000,6500]
    var cave_merges:PackedInt32Array=cave_pair[1].hierarchy().merges
    for i in range(2,cave_merges.size(),4):
        if not cave_levels.has(cave_merges[i]):cave_levels.append(cave_merges[i])
    cave_levels.sort()
    var cave_data:Dictionary=profiles(cave_pair,PackedInt64Array(cave_levels)).profiles()
    var total:=0
    for row:PackedInt64Array in cave_data.profiles_ml:total+=row[-1]
    check(absi(total-capacity(cave))<=ceili(cave_data.total_anchor_rounding_bound_ml+.5),"stacked cave profiles count three-dimensional voids without counting solid roof")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_profiles.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"costs":costs,"off_anchor_error_ml":error,"fine_off_anchor_error_ml":fine_error,"declared_error_bound_ml":data.max_leaf_interpolation_error_bound_ml,"scope":"Terrain-derived regional storage and finite settling; no world runtime, edit remapping, bucket/save integration or performance qualification."},"  "));file.close()
    print("WATER_PROFILES failures=",failures);quit(1 if failures else 0)
