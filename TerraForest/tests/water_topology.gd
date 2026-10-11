# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var costs: Array=[]
var keepers: Array=[]
func check(ok: bool,label: String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func cell_id(x:int,y:int,z:int):return (x+16*(y+8*z))*6
func make_volume(kind:int):
    var volume=ClassDB.instantiate("NativeLakeVolume")
    volume.configure(Vector3.ZERO,Vector3i(16,8,16),1,5 if kind==0 else 6.5,Vector3(4.5,2.5 if kind==0 else 5.5,8.5))
    var field:=PackedFloat32Array()
    for z in 17:
        for y in 9:
            for x in 17:
                var d: float=y-(1+maxf(0,2-absf(x-8)*2))
                if kind>0:
                    var pocket:=minf(2.5-absf(x-4),minf(1.5-absf(y-2),2.5-absf(z-8)))
                    d=maxf(y-4.5,pocket)
                    if kind==2:d=maxf(d,minf(.75-absf(x-6),.75-absf(z-8)))
                    d=minf(d,y-.5)
                if x==0 or x==16 or z==0 or z==16:d=-10
                field.append(d)
    check(volume.bake_density(field)==1,"sampled three-dimensional terrain fixture bakes")
    return volume
func compile_graph(volume,first:=Vector3i.ZERO,size:=Vector3i(16,8,16),budget:=32):
    var task=ClassDB.instantiate("NativeWaterTopology")
    check(task.begin(volume,first,size),"bounded regional graph begins")
    var before: Dictionary=task.statistics()
    check(not task.graph().ok and not task.advance(0).ok and task.statistics()==before,"partial graph and invalid budgets cannot publish")
    var bounded:=true;var calls:=0;var peak:=0;var peak_bytes: int=before.buffer_bytes
    while task.statistics().status==0 and calls<5000:
        var start:=Time.get_ticks_usec();var state: Dictionary=task.advance(budget);peak=maxi(peak,Time.get_ticks_usec()-start)
        bounded=bounded and state.work_cells>0 and state.work_cells<=budget
        calls+=1
    check(bounded and task.statistics().status==1,"graph extraction respects resumable cell budget")
    check(task.advance(budget).work_cells==0,"completed graph does no further cell work")
    var graph: Dictionary=task.graph()
    costs.append({"budget":budget,"calls":calls,"max_call_us":peak,"peak_buffers":peak_bytes,"result":task.statistics()})
    keepers.append(task)
    return graph
func connections(graph: Dictionary):
    var adj: Dictionary={}
    var edges: PackedInt32Array=graph.edges
    for i in range(0,edges.size(),3):
        var a=edges[i];var b=edges[i+1];var h=edges[i+2]
        if not adj.has(a):adj[a]=[]
        if not adj.has(b):adj[b]=[]
        adj[a].append(Vector2i(b,h));adj[b].append(Vector2i(a,h))
    return adj
func reaches(adj: Dictionary,source:int,target:int,level:int):
    var visited: Dictionary={source:true};var queue: Array[int]=[source];var head:=0
    while head<queue.size():
        var node=queue[head];head+=1
        if node==target:return true
        for edge: Vector2i in adj.get(node,[]):
            if edge.y<level and not visited.has(edge.x):visited[edge.x]=true;queue.append(edge.x)
    return false
func edge_set(graph: Dictionary):
    var result: Dictionary={};var edges: PackedInt32Array=graph.edges
    for i in range(0,edges.size(),3):result["%d/%d/%d"%[edges[i],edges[i+1],edges[i+2]]]=true
    return result
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var volume=make_volume(0)
    var graph: Dictionary=compile_graph(volume)
    var adjacency: Dictionary=connections(graph)
    check(not reaches(adjacency,cell_id(4,2,8),cell_id(11,2,8),2999),"actual sampled ridge blocks cross-basin connectivity below sill")
    check(reaches(adjacency,cell_id(4,2,8),cell_id(11,2,8),3001),"actual sampled ridge connects basins above three-metre sill")
    check(compile_graph(volume,Vector3i.ZERO,Vector3i(16,8,16),1)==graph,"scheduler budgets preserve exact graph output")
    var left: Dictionary=compile_graph(volume,Vector3i.ZERO,Vector3i(8,8,16))
    var right: Dictionary=compile_graph(volume,Vector3i(8,0,0),Vector3i(8,8,16))
    var stitched: Dictionary=edge_set(left);stitched.merge(edge_set(right))
    check(stitched==edge_set(graph),"regional portals reconstruct whole-domain edge set exactly")
    var original: Dictionary=graph.duplicate(true)
    var ids: PackedInt32Array=graph.ids;ids[0]=-123
    check(keepers[0].graph()==original,"caller graph edits do not alter published native graph")
    graph=original
    var sealed=make_volume(1);var sealed_graph: Dictionary=compile_graph(sealed)
    check(not sealed_graph.ids.has(cell_id(4,1,8)) and not sealed.contains(Vector3(4.5,1.5,8.5)),"sealed lower chamber excluded while upper water remains present")
    var connected=make_volume(2);var connected_graph: Dictionary=compile_graph(connected)
    check(connected_graph.ids.has(cell_id(4,1,8)) and reaches(connections(connected_graph),cell_id(4,5,8),cell_id(4,1,8),6000),"side shaft connects stacked three-dimensional spaces")
    check(not connected.contains(Vector3(4,4,8)),"connecting shaft does not erase the solid roof")
    var invalid=ClassDB.instantiate("NativeWaterTopology")
    check(not invalid.begin(volume,Vector3i.ZERO,Vector3i(17,8,16)) and not invalid.begin(volume,Vector3i(-1,0,0),Vector3i(8,8,8)),"oversized or out-of-domain regional allocations rejected")
    var identity="topology".sha256_buffer();var restored=ClassDB.instantiate("NativeLakeVolume")
    check(restored.restore_bake(volume.capture_bake(identity),identity),"terrain-connected source cache restores")
    check(compile_graph(restored)==graph,"cache restore preserves node floors and spill portals")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_topology.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"costs":costs,"scope":"Regional tetrahedral graph from sampled 3D density. Depression hierarchy reduction and storage-profile compilation not yet implemented."},"  "));file.close()
    print("WATER_TOPOLOGY failures=",failures);quit(1 if failures else 0)
