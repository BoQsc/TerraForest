# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var costs:Array=[]
var LEVELS=PackedInt64Array([0,1000,2000,3000,4000,5000,6000,7000,8000,9000,10000])
func check(ok:bool,label:String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func region(x:int,kind:=0):
    var origin:=Vector3i(x*16-1,-1,-1);var density:=PackedFloat32Array()
    for z in 19:
        for y in 19:
            for xx in 19:
                var p:=Vector3(origin+Vector3i(xx,y,z))
                var floor_height:float=1+maxf(0,3-absf(p.x-16)*1.5)
                if kind==2:floor_height=maxf(floor_height,1+maxf(0,2-absf(p.x-8)*1.5))
                if kind==3:floor_height=maxf(floor_height,maxf(1+maxf(0,1-absf(p.x-6)*1.5),1+maxf(0,2-absf(p.x-11)*1.5)))
                var d:float=minf(p.y-floor_height,minf(p.x-2,minf(30-p.x,minf(p.z-2,14-p.z))))
                if kind==1:d=maxf(2-p.distance_to(Vector3(4,5,8)),2-p.distance_to(Vector3(12,5,8)))
                density.append(d)
    var field=ClassDB.instantiate("NativeWaterField");field.configure(7,0,origin,Vector3i(18,18,18),1,10000,density)
    var g=ClassDB.instantiate("NativeWaterTopology");g.begin_field(field,Vector3i.ONE,Vector3i(16,16,16))
    while g.statistics().status==0:g.advance(128)
    var b=ClassDB.instantiate("NativeWaterBasins");b.begin(g.graph())
    while b.statistics().status==0:b.advance(1024)
    var p=ClassDB.instantiate("NativeWaterProfiles")
    check(p.begin_region(g,b,LEVELS),"regional storage compilation accepts explicit open/forest topology")
    while p.statistics().status==0:p.advance(1024)
    check(p.profiles().ok,"regional storage curves compile")
    return [g,b,p]
func publish(r,coordinate:Vector3i,g)->int:
    var ticket:Dictionary=r.reserve_region(coordinate,0,0,0)
    check(ticket.ok and r.begin_publish(g,ticket.generation),"region geometry publishes under ownership ticket")
    while r.statistics().busy:r.advance(512)
    return ticket.generation
func network(r,profiles:Array,budget:=128):
    var n=ClassDB.instantiate("NativeWaterNetwork")
    check(n.begin(r,profiles),"network compilation begins with ready matching owners")
    var before:Dictionary=n.statistics()
    check(not n.advance(0).ok and n.statistics()==before,"invalid network budget preserves state")
    var calls:=0;var peak:=0;var bounded:=true
    while n.statistics().status==0 and calls<200000:
        var start:=Time.get_ticks_usec();var s:Dictionary=n.advance(budget);calls+=1;peak=maxi(peak,Time.get_ticks_usec()-start)
        bounded=bounded and s.work_units>0 and s.work_units<=budget
    check(bounded and n.statistics().status==1,"network compilation completes in bounded work units")
    costs.append({"budget":budget,"calls":calls,"max_call_us":peak,"statistics":n.statistics()})
    return n
func settle(n,initial:int,adding:bool)->bool:
    var ok:=true
    while n.statistics().water.busy:
        var s:Dictionary=n.advance_settling(1)
        if not s.ok:return false
        ok=ok and (s.total_ml+s.pending_ml==initial+s.requested_ml if adding else s.total_ml+s.moved_ml==initial)
    return ok
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var a:Array=region(0);var b:Array=region(1)
    check(a[1].hierarchy().requires_stitching and b[1].hierarchy().requires_stitching,"fixture has an actual open boundary in both independent density snapshots")
    var r=ClassDB.instantiate("NativeWaterRegions");r.configure(7,1)
    var ag:=publish(r,Vector3i.ZERO,a[0]);var bg:=publish(r,Vector3i(1,0,0),b[0])
    var n=network(r,[a[2],b[2]])
    if n.statistics().status!=1:quit(1);return
    check(n.statistics().local_leaves==2 and n.statistics().global_leaves==2 and n.statistics().water.roots==1,"real ridge remains two minima in one connected regional water body")
    var pa:Dictionary=a[2].profiles();var pb:Dictionary=b[2].profiles()
    var amount:int=pa.profiles_ml[0][5]+pb.profiles_ml[0][5]
    check(n.begin_add(Vector3i.ZERO,0,amount) and settle(n,0,true),"pour crosses validated independent region boundary with exact conservation every event")
    check(absf(n.inspect(Vector3i.ZERO,0).level_mm-5000)<.001 and absf(n.inspect(Vector3i(1,0,0),0).level_mm-5000)<.001,"both real terrain regions reach the correct five-metre equilibrium")
    var at_sill:int=pa.profiles_ml[0][4]+pb.profiles_ml[0][4]
    var take:int=amount-at_sill+1000000
    check(n.begin_remove(Vector3i.ZERO,0,take) and settle(n,amount,false),"withdrawal conserves retained and removed quantities across regional split")
    check(n.inspect(Vector3i.ZERO,0).level_mm<4000 and absf(n.inspect(Vector3i(1,0,0),0).level_mm-4000)<.001,"opposite region keeps its water behind the physical four-metre sill")
    check(n.advance_settling(128).work_events==0 and n.advance(128).work_units==0,"settled network performs no background solver or compiler work")
    var other=network(r,[b[2],a[2]],1)
    check(other.begin_add(Vector3i.ZERO,0,amount) and settle(other,0,true) and absf(other.inspect(Vector3i(1,0,0),0).level_mm-5000)<.001,"input order and one-unit compilation preserve regional equilibrium")
    var partial=ClassDB.instantiate("NativeWaterNetwork");partial.begin(r,[a[2]])
    while partial.statistics().status==0:partial.advance(128)
    check(partial.statistics().status==-2 and not partial.begin_add(Vector3i.ZERO,0,1),"omitted connected region cannot be silently treated as a sealed wall")
    var coarse:Array=[]
    var missing:=PackedInt64Array([0,1000,2000,3000,5000,6000,7000,8000,9000,10000])
    for entry:Array in [a,b]:
        var p=ClassDB.instantiate("NativeWaterProfiles");p.begin_region(entry[0],entry[1],missing)
        while p.statistics().status==0:p.advance(1024)
        coarse.append(p)
    var bad_curve=ClassDB.instantiate("NativeWaterNetwork");bad_curve.begin(r,coarse)
    while bad_curve.statistics().status==0:bad_curve.advance(128)
    check(bad_curve.statistics().status==-2,"new cross-region sill cannot silently use an interpolated storage threshold")
    var in_flight=network(r,[a[2],b[2]])
    in_flight.begin_add(Vector3i.ZERO,0,amount);in_flight.advance_settling(1)
    check(in_flight.statistics().water.busy and in_flight.statistics().water.total_ml>0 and in_flight.statistics().water.pending_ml>0,"invalidation fixture reaches a partly settled cross-region pour")
    var saved:int=n.statistics().water.total_ml
    var replacement:Dictionary=r.reserve_region(Vector3i(1,0,0),1,0,bg)
    check(replacement.ok and not n.statistics().current and not n.begin_add(Vector3i.ZERO,0,1) and not n.advance_settling(1).ok,"changed region freezes stale network operations")
    check(n.statistics().water.total_ml==saved and not n.inspect(Vector3i.ZERO,0).ok,"stale geometry retains finite quantity while refusing stale level queries")
    check(not in_flight.advance_settling(1).ok and in_flight.statistics().water.total_ml+in_flight.statistics().water.pending_ml==amount,"invalidation freezes a partly settled pour without losing either quantity portion")
    var pending=ClassDB.instantiate("NativeWaterNetwork")
    check(not pending.begin(r,[a[2],b[2]]),"stale regional profiles cannot enter a new network")
    var nested_left:Array=region(0,2);var nested_right:Array=region(1,2)
    var nr=ClassDB.instantiate("NativeWaterRegions");nr.configure(7,1)
    publish(nr,Vector3i.ZERO,nested_left[0]);publish(nr,Vector3i(1,0,0),nested_right[0])
    var nn=network(nr,[nested_left[2],nested_right[2]])
    var ng:Dictionary=nested_left[0].graph();var nh:Dictionary=nested_left[1].hierarchy()
    var west_id:int=(5+18*(3+18*9))*6;var middle_id:int=(13+18*(3+18*9))*6
    var west:int=nh.owners[ng.ids.find(west_id)];var middle:int=nh.owners[ng.ids.find(middle_id)]
    var small_pour:int=nested_right[2].profiles().profiles_ml[0][4]+1000000
    check(west!=middle and nn.begin_add(Vector3i(1,0,0),0,small_pour) and settle(nn,0,true),"nested regional spill preserves quantity")
    check(nn.inspect(Vector3i.ZERO,middle).component_amount_ml==1000000 and nn.inspect(Vector3i.ZERO,west).component_amount_ml==0,"incoming spill follows the adjacent catchment instead of teleporting over an internal dry ridge")
    var triple_left:Array=region(0,3);var triple_right:Array=region(1,3)
    var tr=ClassDB.instantiate("NativeWaterRegions");tr.configure(7,1)
    publish(tr,Vector3i.ZERO,triple_left[0]);publish(tr,Vector3i(1,0,0),triple_right[0])
    var tn=network(tr,[triple_left[2],triple_right[2]])
    var tg:Dictionary=triple_left[0].graph();var th:Dictionary=triple_left[1].hierarchy()
    var tw:int=th.owners[tg.ids.find((5+18*(3+18*9))*6)]
    var tm:int=th.owners[tg.ids.find((10+18*(3+18*9))*6)]
    var ta:int=th.owners[tg.ids.find((15+18*(3+18*9))*6)]
    var cascade:int=triple_right[2].profiles().profiles_ml[0][4]+triple_left[2].profiles().profiles_ml[ta][3]+1000000
    check(tw!=tm and tm!=ta and tn.begin_add(Vector3i(1,0,0),0,cascade) and settle(tn,0,true),"three-minimum region conserves a cascading incoming spill")
    check(tn.inspect(Vector3i.ZERO,tm).component_amount_ml==1000000 and tn.inspect(Vector3i.ZERO,tw).component_amount_ml==0,"internal merge entry follows its witnessed downhill catchment, leaving the farther basin dry")
    var caves:Array=region(0,1);var cr=ClassDB.instantiate("NativeWaterRegions");cr.configure(7,1)
    var cg:=publish(cr,Vector3i.ZERO,caves[0]);var cn=network(cr,[caves[2]])
    check(cn.statistics().water.roots==2,"disconnected raw caves remain separate solver roots")
    check(cn.begin_add(Vector3i.ZERO,0,1000000) and settle(cn,0,true) and cn.begin_add(Vector3i.ZERO,1,2000000) and settle(cn,1000000,true),"independent cave additions conserve aggregate quantity")
    check(cn.begin_remove(Vector3i.ZERO,0,2000000) and settle(cn,3000000,false),"overdraw only removes water available in the targeted cave")
    check(cn.statistics().water.total_ml==2000000 and cn.statistics().water.pending_ml==1000000 and cn.inspect(Vector3i.ZERO,1).component_amount_ml==2000000,"overdraw cannot steal quantity from disconnected cave")
    var busy=network(cr,[caves[2]])
    var compiling=ClassDB.instantiate("NativeWaterNetwork");compiling.begin(cr,[caves[2]])
    busy.begin_add(Vector3i.ZERO,0,1000000)
    cr.reserve_region(Vector3i.ZERO,1,0,cg)
    compiling.advance(1)
    check(compiling.statistics().status==-2,"generation change cancels unfinished network compilation")
    check(not busy.advance_settling(1).ok and busy.statistics().water.total_ml+busy.statistics().water.pending_ml==1000000,"invalidation preserves accepted-plus-pending accounting for an unfinished pour")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_network.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"costs":costs,"cross_region_amount_ml":amount,"scope":"Finite hydrostatic settling across a fully ready closed active set of independent terrain regions. Runtime/remapping/save and transient flow remain open."},"  "));file.close()
    print("WATER_NETWORK failures=",failures);quit(1 if failures else 0)
