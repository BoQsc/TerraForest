# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var costs:Array=[]
func check(ok:bool,label:String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func graph(x:int,rev:=0,world:=7,change:=false,top:=10000,y_region:=0,z_region:=0,solid:=false):
    var origin:=Vector3i(x*16-1,y_region*16-1,z_region*16-1);var density:=PackedFloat32Array()
    for z in 19:
        for y in 19:
            for xx in 19:
                density.append(-1 if solid else float(origin.y+y-1)*(2 if change else 1))
    var field=ClassDB.instantiate("NativeWaterField")
    field.configure(world,rev,origin,Vector3i(18,18,18),1,top,density)
    var g=ClassDB.instantiate("NativeWaterTopology");g.begin_field(field,Vector3i.ONE,Vector3i(16,16,16))
    while g.statistics().status==0:g.advance(128)
    return g
func finish(r,budget:=128)->bool:
    var bounded:=true;var calls:=0;var peak:=0
    while r.statistics().busy and calls<20000:
        var start:=Time.get_ticks_usec();var s:Dictionary=r.advance(budget)
        peak=maxi(peak,Time.get_ticks_usec()-start);calls+=1
        bounded=bounded and s.ok and s.work_units>0 and s.work_units<=budget
    costs.append({"budget":budget,"calls":calls,"max_call_us":peak,"statistics":r.statistics()})
    return bounded and not r.statistics().busy
func shared_port(g)->int:
    var ports:PackedInt32Array=g.graph().world_ports
    for i in range(0,ports.size(),9):
        if ports[i]==15 and ports[i+4]==16 and ports[i+1]>2:return i/9
    return -1
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var left=graph(0);var right=graph(1);var port:=shared_port(left)
    check(port>=0,"fixture locates an actual shared boundary face")
    var r=ClassDB.instantiate("NativeWaterRegions")
    check(r.configure(7,1),"world registry configures")
    var lt:Dictionary=r.reserve_region(Vector3i.ZERO,0,0,0)
    var rt:Dictionary=r.reserve_region(Vector3i(1,0,0),0,0,0)
    check(lt.ok and rt.ok and lt.generation!=rt.generation,"region reservations receive distinct monotonic tickets")
    var before:Dictionary=r.statistics()
    check(not r.advance(0).ok and r.statistics()==before,"invalid budget preserves registry state")
    check(r.begin_publish(left,lt.generation) and finish(r),"first region publishes under bounded work")
    check(r.inspect_port(Vector3i.ZERO,lt.generation,port).reason=="stale_neighbour","reserved but unpublished neighbour blocks exchange eligibility")
    check(r.begin_publish(right,rt.generation),"neighbour publication begins")
    r.advance(1)
    check(not r.inspect_port(Vector3i.ZERO,lt.generation,port).connected,"partial neighbour publication cannot authorize exchange")
    check(finish(r,1),"one-operation publication completes")
    var link:Dictionary=r.inspect_port(Vector3i.ZERO,lt.generation,port)
    check(link.connected and link.neighbour==Vector3i(1,0,0) and link.neighbour_generation==rt.generation,"reciprocal ready geometry authorizes exact neighbour generation")
    check(r.advance(128).work_units==0,"idle registry performs zero background work")
    var next:Dictionary=r.reserve_region(Vector3i(1,0,0),1,0,rt.generation)
    check(next.ok and not r.inspect_port(Vector3i.ZERO,lt.generation,port).connected,"invalidation immediately disables old boundary links")
    check(not r.begin_publish(right,rt.generation) and not r.begin_publish(right,next.generation),"old ticket and old geometry cannot satisfy replacement reservation")
    var changed=graph(1,1,7,true)
    check(r.begin_publish(changed,next.generation) and finish(r),"new revision replaces old endpoint records")
    var mismatch:Dictionary=r.inspect_port(Vector3i.ZERO,lt.generation,port)
    check(mismatch.reason=="geometry_mismatch","matching opening elevation does not conceal different face samples")
    var newer:Dictionary=r.reserve_region(Vector3i(1,0,0),2,0,next.generation)
    var restored=graph(1,2)
    check(r.begin_publish(restored,newer.generation),"replacement can start after geometry mismatch")
    while r.statistics().endpoints>left.statistics().portals:r.advance(1)
    r.advance(32)
    check(r.statistics().busy and r.statistics().endpoints>left.statistics().portals,"cancellation fixture reaches partially inserted new endpoints")
    var cancelled:Dictionary=r.reserve_region(Vector3i(1,0,0),3,0,newer.generation)
    check(cancelled.ok and not r.statistics().busy and not r.inspect_port(Vector3i.ZERO,lt.generation,port).connected,"invalidation cancels partially published replacement without exposing its links")
    check(not r.begin_publish(restored,newer.generation),"cancelled completion cannot reactivate previous ticket")
    var latest=graph(1,3)
    check(r.begin_publish(latest,cancelled.generation) and finish(r),"cancelled endpoint debris is retired before the next publication")
    check(r.inspect_port(Vector3i.ZERO,lt.generation,port).connected and r.statistics().endpoints==left.statistics().portals+right.statistics().portals,"replacement restores matching links without leaking endpoint records")
    check(not r.reserve_region(Vector3i(1,0,0),2,0,cancelled.generation).ok,"older revision cannot reserve a current region")
    var foreign=ClassDB.instantiate("NativeWaterRegions");foreign.configure(7,1)
    var ft:Dictionary=foreign.reserve_region(Vector3i(1,0,0),3,0,0)
    check(not foreign.begin_publish(graph(1,3,8),ft.generation),"foreign world cannot satisfy an otherwise matching unpublished reservation")
    check(not r.begin_release(Vector3i(1,0,0),newer.generation),"stale generation cannot unload current owner")
    check(r.begin_release(Vector3i(1,0,0),cancelled.generation),"current owner can begin retirement")
    check(not r.inspect_port(Vector3i.ZERO,lt.generation,port).connected and finish(r),"retirement disables links immediately and completes incrementally")
    check(r.statistics().endpoints==left.statistics().portals and r.statistics().regions==1,"retirement preserves neighbour records and frees region slot")
    var reload:Dictionary=r.reserve_region(Vector3i(1,0,0),3,0,0)
    check(reload.ok and reload.generation>cancelled.generation and not r.begin_publish(latest,cancelled.generation),"unload/reload cannot reuse an old generation ticket")
    check(r.begin_publish(latest,reload.generation) and finish(r) and r.inspect_port(Vector3i.ZERO,lt.generation,port).connected,"reloaded region reconnects through its new ticket")
    var ceiling:Dictionary=r.reserve_region(Vector3i(1,0,0),4,0,reload.generation)
    check(r.begin_publish(graph(1,4,7,false,11000),ceiling.generation) and finish(r),"different ceiling snapshot can be published for explicit compatibility evaluation")
    check(r.inspect_port(Vector3i.ZERO,lt.generation,port).reason=="ceiling_mismatch","different water compilation ceilings cannot silently exchange")
    var sealed:Dictionary=r.reserve_region(Vector3i(1,0,0),5,0,ceiling.generation)
    check(r.begin_publish(graph(1,5,7,false,10000,0,0,true),sealed.generation) and finish(r),"solid neighbour snapshot publishes without boundary openings")
    check(r.inspect_port(Vector3i.ZERO,lt.generation,port).reason=="unmatched_face","ready neighbour with no reciprocal opening is distinct from an unloaded neighbour")
    var stacked=ClassDB.instantiate("NativeWaterRegions");stacked.configure(7,1)
    var low=graph(0,0,7,false,32000);var high=graph(0,0,7,false,32000,1)
    var low_ticket:Dictionary=stacked.reserve_region(Vector3i.ZERO,0,0,0)
    var high_ticket:Dictionary=stacked.reserve_region(Vector3i(0,1,0),0,0,0)
    check(stacked.begin_publish(low,low_ticket.generation) and finish(stacked) and stacked.begin_publish(high,high_ticket.generation) and finish(stacked),"vertically stacked regions compile and publish under one shared ceiling above lower region")
    var vertical_connections:=0;var vertical_ports:PackedInt32Array=low.graph().world_ports
    for i in range(0,vertical_ports.size(),9):
        if vertical_ports[i+1]==15 and vertical_ports[i+5]==16 and stacked.inspect_port(Vector3i.ZERO,low_ticket.generation,i/9).connected:vertical_connections+=1
    check(vertical_connections==512,"all vertical shared faces connect with reciprocal geometry samples")
    var full=ClassDB.instantiate("NativeWaterRegions");full.configure(7,1)
    var admitted:=true
    for x in 64:admitted=admitted and full.reserve_region(Vector3i(x,0,0),0,0,0).ok
    check(admitted and not full.reserve_region(Vector3i(64,0,0),0,0,0).ok,"active region capacity rejects further reservations instead of growing unbounded")
    var pressure=ClassDB.instantiate("NativeWaterRegions");pressure.configure(7,1)
    var rejected_graph=null;var rejected_ticket:=0;var first_ticket:=0;var pressure_stable:=false
    for x in 32:
        var current=graph(x,0,7,false,32000)
        var ticket:Dictionary=pressure.reserve_region(Vector3i(x,0,0),0,0,0)
        if x==0:first_ticket=ticket.generation
        var prior:Dictionary=pressure.statistics()
        if not pressure.begin_publish(current,ticket.generation):
            pressure_stable=pressure.statistics()==prior and prior.endpoints<=65536
            rejected_graph=current;rejected_ticket=ticket.generation
            break
        if not finish(pressure,512):pressure_stable=false;break
    check(pressure_stable and rejected_graph!=null,"endpoint quota rejects overflow atomically under many actual region graphs")
    check(pressure.begin_release(Vector3i.ZERO,first_ticket) and finish(pressure,512) and pressure.begin_publish(rejected_graph,rejected_ticket) and finish(pressure,512),"retirement frees endpoint capacity and rejected publication can retry")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_regions.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"costs":costs,"scope":"Active region ownership and reciprocal boundary eligibility. Does not transfer liquid or integrate world runtime."},"  "));file.close()
    print("WATER_REGIONS failures=",failures);quit(1 if failures else 0)
