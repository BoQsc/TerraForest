# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var costs:Array=[]
func check(ok:bool,label:String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func samples(origin:Vector3i,kind:int)->PackedFloat32Array:
    var result:=PackedFloat32Array()
    for z in 19:
        for y in 19:
            for x in 19:
                var p:=Vector3(origin+Vector3i(x,y,z))
                var d:float=p.y-1
                if kind==1:d=4-p.distance_to(Vector3(8,5,8))
                if kind==2:d=maxf(2-p.distance_to(Vector3(4,4,8)),2-p.distance_to(Vector3(12,4,8)))
                result.append(d)
    return result
func field(origin:Vector3i,kind:=0,rev:=1):
    var f=ClassDB.instantiate("NativeWaterField")
    check(f.configure(7,rev,origin,Vector3i(18,18,18),1,10000,samples(origin,kind)),"raw density snapshot publishes without a closed-lake seed")
    return f
func graph(f,budget:=128):
    var t=ClassDB.instantiate("NativeWaterTopology")
    check(t.begin_field(f,Vector3i.ONE,Vector3i(16,16,16)),"owned region with complete sampled border begins")
    var calls:=0;var peak:=0;var bounded:=true
    while t.statistics().status==0:
        var start:=Time.get_ticks_usec();var s:Dictionary=t.advance(budget)
        peak=maxi(peak,Time.get_ticks_usec()-start);calls+=1;bounded=bounded and s.work_cells<=budget
    check(bounded and t.graph().ok,"raw region extraction respects cell budget")
    costs.append({"calls":calls,"budget":budget,"max_call_us":peak,"statistics":t.statistics()})
    return t
func basins(t):
    var b=ClassDB.instantiate("NativeWaterBasins");b.begin(t.graph())
    while b.statistics().status==0:b.advance(2048)
    return b
func face_ports(g:Dictionary,x:int,from_left:bool)->Dictionary:
    var result:Dictionary={};var ports:PackedInt32Array=g.world_ports
    for i in range(0,ports.size(),9):
        if (ports[i]==x-1 and ports[i+4]==x) if from_left else (ports[i]==x and ports[i+4]==x-1):
            var a:Array=[];var b:Array=[]
            for j in 4:a.append(ports[i+j]);b.append(ports[i+4+j])
            var key:String=str(a if from_left else b)+str(b if from_left else a)
            result[key]=ports[i+8]
    return result
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var left_field=field(Vector3i(-1,-1,-1));var right_field=field(Vector3i(15,-1,-1))
    var left=graph(left_field);var right=graph(right_field)
    var lg:Dictionary=left.graph();var rg:Dictionary=right.graph()
    check(lg.world_id==7 and lg.revision==1 and lg.grid_origin==Vector3i(-1,-1,-1),"published graph carries explicit world, snapshot and lattice metadata")
    var lp:Dictionary=face_ports(lg,16,true);var rp:Dictionary=face_ports(rg,16,false)
    check(not lp.is_empty() and lp==rp,"independently sampled adjacent regions agree on reciprocal world-space openings")
    check(lg.world_ports.size()==left.statistics().portals*9,"every outgoing edge has a world-addressed boundary record")
    check(basins(left).hierarchy().requires_stitching,"open raw terrain cannot masquerade as a sealed basin")
    var invalid=ClassDB.instantiate("NativeWaterTopology")
    check(not invalid.begin_field(left_field,Vector3i.ZERO,Vector3i(16,16,16)) and not invalid.begin_field(left_field,Vector3i(2147483647,1,1),Vector3i.ONE),"missing border and oversized coordinates rejected safely")
    check(not invalid.begin_join([left,right]),"legacy same-source join cannot accidentally merge separate raw snapshots")
    var changed=graph(field(Vector3i(-1,-1,-1),0,2))
    check(changed.graph().revision!=lg.revision,"recompiled snapshot has a distinct revision even with unchanged geometry")
    var cavity=graph(field(Vector3i(-1,-1,-1),1));var cb=basins(cavity)
    check(cavity.statistics().portals==0 and cb.hierarchy().settling_compatible,"enclosed raw cave produces a finite closed storage component")
    var p=ClassDB.instantiate("NativeWaterProfiles")
    var levels:=PackedInt64Array([0,1000,2000,3000,4000,5000,6000,7000,8000,9000,10000])
    check(p.begin(cavity,cb,levels),"raw geometry enters existing storage compiler")
    while p.statistics().status==0:p.advance(1024)
    var data:Dictionary=p.profiles()
    check(data.ok and data.profiles_ml.size()==1 and data.profiles_ml[0][-1]>0,"raw cave compiles positive finite capacity")
    var solver=ClassDB.instantiate("NativeWaterSettling")
    check(solver.configure(data.levels_mm,data.profiles_ml,data.merges) and solver.begin_add(0,1000000),"raw cave accepts finite water")
    while solver.statistics().busy:solver.advance(1)
    check(solver.statistics().total_ml==1000000,"raw cave retains exactly the supplied water quantity")
    var separate=basins(graph(field(Vector3i(-1,-1,-1),2))).hierarchy()
    check(separate.roots.size()==2,"raw input preserves both disconnected caves without seed-based exclusion")
    var density:=samples(Vector3i(-1,-1,-1),1);var copy=ClassDB.instantiate("NativeWaterField")
    copy.configure(7,1,Vector3i(-1,-1,-1),Vector3i(18,18,18),1,10000,density);density.fill(-1)
    check(graph(copy).graph()==cavity.graph(),"caller mutation cannot alter published density snapshot")
    var bad=ClassDB.instantiate("NativeWaterField");density[0]=NAN
    check(not bad.configure(7,1,Vector3i(-1,-1,-1),Vector3i(18,18,18),1,10000,density),"nonfinite density rejected")
    check(not copy.configure(7,2,Vector3i(-1,-1,-1),Vector3i(18,18,18),1,10000,samples(Vector3i(-1,-1,-1),0)),"published density cannot be overwritten")
    check(graph(left_field,1).graph()==lg,"raw graph and boundary records are scheduler-independent")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_field.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"costs":costs,"matched_face_ports":lp.size(),"scope":"Raw immutable density admission and world-addressed openings; ownership exchange and world fluid runtime remain open."},"  "));file.close()
    print("WATER_FIELD failures=",failures);quit(1 if failures else 0)
