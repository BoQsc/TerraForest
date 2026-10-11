# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var costs:Array=[]
func check(ok:bool,label:String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func volume(height:=8):
    var v=ClassDB.instantiate("NativeLakeVolume");v.configure(Vector3.ZERO,Vector3i(16,height,16),1,5,Vector3(4.5,2.5,8.5))
    var density:=PackedFloat32Array()
    for z in 17:
        for y in range(height+1):
            for x in 17:
                density.append(-10 if x==0 or x==16 or z==0 or z==16 else y-(1+maxf(0,2-absf(x-8)*2)))
    check(v.bake_density(density)==1,"sampled ridge bakes")
    return v
func region(v,start:Vector3i,size:Vector3i):
    var t=ClassDB.instantiate("NativeWaterTopology");t.begin(v,start,size)
    while t.statistics().status==0:t.advance(256)
    return t
func joined(parts:Array,budget:=256):
    var t=ClassDB.instantiate("NativeWaterTopology")
    check(t.begin_join(parts),"disjoint same-source regions admitted")
    var before:Dictionary=t.statistics()
    check(not t.graph().ok and not t.advance(1).ok and not t.advance_join(0).ok and t.statistics()==before,"invalid API/budget cannot mutate or publish partial join")
    var bounded:=true;var calls:=0;var peak:=0;var scratch:=0
    while t.statistics().status==0 and calls<200000:
        var start:=Time.get_ticks_usec();var s:Dictionary=t.advance_join(budget)
        peak=maxi(peak,Time.get_ticks_usec()-start);scratch=maxi(scratch,s.join_scratch_bytes);calls+=1
        bounded=bounded and s.work_units>0 and s.work_units<=budget
    check(bounded and t.statistics().status==1,"join obeys resumable work budget")
    check(t.advance_join(budget).work_units==0,"completed join performs zero work")
    costs.append({"budget":budget,"calls":calls,"max_call_us":peak,"scratch_bytes":scratch,"statistics":t.statistics()})
    return t
func edges(g:Dictionary)->Dictionary:
    var result:Dictionary={}
    for i in range(0,g.edges.size(),3):result[Vector3i(g.edges[i],g.edges[i+1],g.edges[i+2])]=true
    return result
func hierarchy(t):
    var b=ClassDB.instantiate("NativeWaterBasins");b.begin(t.graph())
    while b.statistics().status==0:b.advance(2048)
    return b
func profiles(t,b)->Dictionary:
    var p=ClassDB.instantiate("NativeWaterProfiles")
    check(p.begin(t,b,PackedInt64Array([0,1000,2000,3000,4000,5000])),"joined topology feeds terrain profile compiler")
    while p.statistics().status==0:p.advance(2048)
    return p.profiles()
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var v=volume();var whole=region(v,Vector3i.ZERO,Vector3i(16,8,16))
    var a=region(v,Vector3i.ZERO,Vector3i(8,8,16));var b=region(v,Vector3i(8,0,0),Vector3i(8,8,16))
    check(a.statistics().portals>0 and b.statistics().portals>0,"separate regions expose unresolved cross-boundary openings")
    var j=joined([a,b]);var g:Dictionary=j.graph();var original:Dictionary=whole.graph()
    check(g.ids==original.ids and g.floors_mm==original.floors_mm and edges(g)==edges(original),"joined nodes and deduplicated openings equal whole-domain geometry")
    check(j.statistics().portals==0,"internal matched openings no longer counted as external ports")
    check(joined([b,a],1).graph()==g,"input order and scheduler budget preserve canonical joined graph")
    var partial=joined([a]);check(partial.statistics().portals==a.statistics().portals,"unmatched outer openings survive partial join")
    var bh=hierarchy(j);var wh=hierarchy(whole)
    check(bh.hierarchy()==wh.hierarchy(),"separately compiled regions produce identical basin ownership and spill hierarchy")
    var jp:Dictionary=profiles(j,bh);var wp:Dictionary=profiles(whole,wh)
    check(jp==wp,"joined terrain capacities and spill thresholds equal whole-domain profiles")
    var solver=ClassDB.instantiate("NativeWaterSettling")
    check(solver.configure(jp.levels_mm,jp.profiles_ml,jp.merges),"joined profiles configure finite settling")
    var quantity:int=jp.profiles_ml[0][4]+jp.profiles_ml[1][4]
    solver.begin_add(0,quantity);var conserved:=true
    while solver.statistics().busy:
        var s:Dictionary=solver.advance(1);conserved=conserved and s.total_ml+s.pending_ml==quantity
    check(conserved and absf(solver.inspect(0).level_mm-4000)<.001 and absf(solver.inspect(1).level_mm-4000)<.001,"finite pour across compiled region boundary conserves quantity and reaches common level")
    var invalid=ClassDB.instantiate("NativeWaterTopology")
    check(not invalid.begin_join([a,a]) and not invalid.begin_join([whole,a]),"overlapping source regions rejected before mutation")
    var other=volume();var changed=region(other,Vector3i(8,0,0),Vector3i(8,8,16))
    check(not invalid.begin_join([a,changed]),"separate immutable snapshots rejected even when numerical geometry matches")
    check(not invalid.begin_join([j]) and not invalid.begin_join([]),"nested and empty joins cannot bypass region bounds")
    var tall=volume(32)
    var lower=region(tall,Vector3i.ZERO,Vector3i(16,16,16));var upper=region(tall,Vector3i(0,16,0),Vector3i(16,16,16))
    check(not invalid.begin_join([lower,upper]),"total cell budget rejects oversized joined allocation")
    check(not invalid.begin_join([a,a,a,a,a,a,a,a,a]) and not invalid.begin_join([ClassDB.instantiate("NativeWaterTopology")]),"too many or unfinished pieces rejected")
    var quarters:Array=[]
    for x in [0,8]:
        for z in [0,8]:quarters.append(region(v,Vector3i(x,0,z),Vector3i(8,8,8)))
    check(joined(quarters).graph()==g,"four-way partition produces same canonical graph")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_join.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"costs":costs,"scope":"Bounded same-source regional compilation join, not independent world-region fluid exchange."},"  "));file.close()
    print("WATER_JOIN failures=",failures);quit(1 if failures else 0)
