# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var costs: Array=[]
func check(ok: bool,label: String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func fresh():return ClassDB.instantiate("NativeWaterSettling")
func pair(spill:=2):
    var flow=fresh()
    check(flow.configure(PackedInt64Array([0,1000,2000,3000,4000]),[PackedInt64Array([0,1000000,2000000,3000000,4000000]),PackedInt64Array([0,1000000,2000000,3000000,4000000])],PackedInt32Array([0,1,spill*1000,0])),"two supplied-profile basins configured")
    return flow
func finish(flow,budget:int,adding:bool,initial:int,amount:int):
    var bounded:=true;var conserved:=true;var calls:=0;var max_us:=0
    while flow.statistics().busy and calls<100000:
        var start:=Time.get_ticks_usec();var state: Dictionary=flow.advance(budget);max_us=maxi(max_us,Time.get_ticks_usec()-start)
        bounded=bounded and state.work_events>0 and state.work_events<=budget
        conserved=conserved and (state.total_ml+state.pending_ml==initial+amount if adding else state.total_ml+state.moved_ml==initial)
        calls+=1
    check(bounded and not flow.statistics().busy,"settling finishes within per-call event budget")
    check(conserved,"every published progress step preserves exact quantity")
    costs.append({"budget":budget,"calls":calls,"events":flow.statistics().events,"max_call_us":max_us,"nodes":flow.statistics().nodes,"profile_bytes":flow.statistics().profile_bytes})
func add(flow,leaf:int,amount:int,budget:=1):
    var initial: int=flow.statistics().total_ml
    check(flow.begin_add(leaf,amount),"finite input admitted")
    finish(flow,budget,true,initial,amount)
func remove(flow,leaf:int,amount:int,budget:=1):
    var initial: int=flow.statistics().total_ml
    check(flow.begin_remove(leaf,amount),"withdrawal admitted")
    finish(flow,budget,false,initial,amount)
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var a=pair()
    add(a,0,1000000)
    check(a.inspect(0).level_mm==1000 and a.inspect(1).component_amount_ml==0,"dry raised sill prevents teleporting into neighbor")
    add(a,0,2000000)
    check(a.inspect(0).level_mm==2000 and a.inspect(1).level_mm==1000,"overflow fills neighbor while donor stays at sill")
    add(a,0,2000000)
    check(a.inspect(0).level_mm==2500 and a.inspect(1).level_mm==2500,"both filled basins merge at equal level")
    remove(a,0,1500000)
    check(a.inspect(0).level_mm==1500 and a.inspect(1).level_mm==2000,"withdrawal splits at sill and preserves disconnected remainder")
    var connected=pair(1)
    add(connected,0,3000000,2)
    check(connected.inspect(0).level_mm==1500 and connected.inspect(1).level_mm==1500,"submerged connection produces shared equilibrium level")
    var off_grid=fresh()
    check(off_grid.configure(PackedInt64Array([0,1000,2000,3000]),[PackedInt64Array([0,1000000,2000000,3000000]),PackedInt64Array([0,1000000,2000000,3000000])],PackedInt32Array([0,1,1500,0])),"spill elevation may lie between storage profile anchors")
    add(off_grid,0,2000000)
    check(off_grid.inspect(0).level_mm==1500 and off_grid.inspect(1).level_mm==500,"interpolated spill elevation preserves held and transferred quantities")
    var b=pair()
    add(b,0,5000000,256);remove(b,0,1500000,256)
    check(b.inspect(0)==a.inspect(0) and b.inspect(1)==a.inspect(1),"different event budgets yield identical final distribution")
    var nested=fresh()
    var profiles: Array=[]
    for i in 4:profiles.append(PackedInt64Array([0,1000000,2000000,3000000,4000000,5000000,6000000]))
    check(nested.configure(PackedInt64Array([0,1000,2000,3000,4000,5000,6000]),profiles,PackedInt32Array([0,1,1000,0,2,3,1000,2,4,5,3000,0])),"nested hierarchy configured")
    add(nested,0,5000000)
    check(nested.inspect(0).level_mm==2500 and nested.inspect(2).component_amount_ml==0,"nested dry sill keeps other branch dry")
    add(nested,0,3000000)
    check(nested.inspect(0).level_mm==3000 and nested.inspect(2).level_mm==1000,"nested spill reaches selected receiving branch")
    add(nested,0,8000000)
    check(nested.inspect(0).level_mm==4000 and nested.inspect(3).level_mm==4000,"nested merge shares aggregate storage profile")
    remove(nested,3,6000000)
    check(nested.inspect(0).level_mm==3000 and nested.inspect(3).level_mm==2000,"nested withdrawal splits correct branch")
    var tiny=fresh()
    var tiny_profiles: Array=[]
    for i in 4:tiny_profiles.append(PackedInt64Array([0,1]))
    check(tiny.configure(PackedInt64Array([0,1000]),tiny_profiles,PackedInt32Array([0,1,500,0,2,3,500,2,4,5,500,0])),"equal-elevation nested connections admit millilitre quantization")
    add(tiny,0,3)
    check(tiny.inspect(0).level_mm==750 and tiny.inspect(3).level_mm==750,"tiny nested merged quantities preserve exact volume")
    var full=pair()
    add(full,0,20000000)
    check(full.statistics().total_ml==8000000 and full.statistics().pending_ml==12000000,"outside capacity remains explicit unaccepted water")
    var before: Dictionary=full.statistics()
    check(full.advance(10).work_events==0 and full.statistics()==before,"settled bodies do zero solver work")
    check(not full.begin_add(-1,10) and not full.begin_add(0,-1) and not full.advance(0).ok and full.statistics()==before,"invalid commands preserve state")
    var invalid=fresh()
    check(not invalid.configure(PackedInt64Array([0,1]),[PackedInt64Array([0,1]),PackedInt64Array([0,1])],PackedInt32Array([0,0,1,0])) and not invalid.statistics().ready,"invalid topology rejects without partial configuration")
    # Unequal-area tanks: independent direct arithmetic reference, no tree walk.
    var unequal=fresh()
    check(unequal.configure(PackedInt64Array([0,1000,2000,3000,4000]),[PackedInt64Array([0,1000000,2000000,3000000,4000000]),PackedInt64Array([0,2000000,4000000,6000000,8000000])],PackedInt32Array([0,1,2000,0])),"unequal basin storage profiles configured")
    var water: Array[float]=[0.0,0.0];var cap: Array[float]=[2000000.0,4000000.0]
    var rng=RandomNumberGenerator.new();rng.seed=1703
    var exact:=true
    for i in 2000:
        var side=rng.randi_range(0,1);var amount=rng.randi_range(1,8000)*1000
        var adding=rng.randi_range(0,1)==1;var remainder: float=amount
        var previous: float=water[0]+water[1]
        if adding:
            if previous<=6000000.0:
                var part: float=minf(remainder,cap[side]-water[side]);water[side]+=part;remainder-=part
                part=minf(remainder,cap[1-side]-water[1-side]);water[1-side]+=part;remainder-=part
            if remainder>0:
                var part: float=minf(remainder,12000000.0-water[0]-water[1]);remainder-=part
                var total: float=water[0]+water[1]+part;water[0]=total/3.0;water[1]=total*2.0/3.0
            exact=exact and unequal.begin_add(side,amount)
        else:
            if previous>6000000.0:
                var part: float=minf(remainder,previous-6000000.0);remainder-=part
                water[0]=(previous-part)/3.0;water[1]=(previous-part)*2.0/3.0
            if remainder>0:
                var part: float=minf(remainder,water[side]);water[side]-=part;remainder-=part
            exact=exact and unequal.begin_remove(side,amount)
        var guard:=0
        while unequal.statistics().busy and guard<100:
            var budget=rng.randi_range(1,5);var progress: Dictionary=unequal.advance(budget)
            exact=exact and progress.work_events<=budget and (progress.total_ml+progress.pending_ml==roundi(previous)+amount if adding else progress.total_ml+progress.moved_ml==roundi(previous))
            guard+=1
        exact=exact and not unequal.statistics().busy and unequal.statistics().pending_ml==roundi(remainder) and unequal.statistics().total_ml==roundi(water[0]+water[1])
        exact=exact and absf(unequal.inspect(0).level_mm-water[0]/1000.0)<.00001 and absf(unequal.inspect(1).level_mm-water[1]/2000.0)<.00001
    check(exact,"2000 unequal-basin scoop/pour commands match independent arithmetic oracle")
    var large=fresh();profiles=[];var levels:=PackedInt64Array();var profile:=PackedInt64Array()
    for i in 15:levels.append(i*1000);profile.append(i*1000000)
    for i in 4096:profiles.append(profile)
    var layer: Array[int]=[];var entries: Array[int]=[]
    for i in 4096:layer.append(i);entries.append(i)
    var merges:=PackedInt32Array();var next_id:=4096;var height:=1
    while layer.size()>1:
        var next: Array[int]=[]
        for i in range(0,layer.size(),2):
            merges.append_array(PackedInt32Array([layer[i],layer[i+1],height*1000,entries[layer[i]]]))
            entries.append(entries[layer[i]]);next.append(next_id);next_id+=1
        layer=next;height+=1
    check(large.configure(levels,profiles,merges),"4096 storage leaves and 8191 hierarchy nodes configured")
    add(large,0,4096*13000000,32)
    check(large.inspect(0).level_mm==13000 and large.inspect(4095).level_mm==13000,"large hierarchy settles at expected conserved level")
    check(large.advance(2048).work_events==0,"large settled hierarchy performs no further events")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var f=FileAccess.open("res://reports/water_settling.json",FileAccess.WRITE)
    f.store_string(JSON.stringify({"checks":checks,"failures":failures,"costs":costs,"scope":"Native hierarchy equilibrium on supplied storage profiles; terrain hierarchy compilation, active transient flow, migration and bucket gameplay not integrated."},"  "));f.close()
    print("WATER_SETTLING failures=",failures);quit(1 if failures else 0)
