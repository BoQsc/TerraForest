# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var costs:Array=[]
func check(ok:bool,label:String):
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func graph(floors:Array,edges:Array)->Dictionary:
    var ids:=PackedInt32Array()
    for i in floors.size():ids.append(i)
    return {"ids":ids,"floors_mm":PackedInt32Array(floors),"edges":PackedInt32Array(edges)}
func reduce(g:Dictionary,budget:=512):
    var task=ClassDB.instantiate("NativeWaterBasins")
    check(task.begin(g),"regional hierarchy begins")
    var before:Dictionary=task.statistics()
    check(not task.hierarchy().ok and not task.advance(0).ok and task.statistics()==before,"partial results and invalid budget do not publish or mutate")
    var bounded:=true;var calls:=0;var peak:=0
    while task.statistics().status==0 and calls<300000:
        var start:=Time.get_ticks_usec();var state:Dictionary=task.advance(budget)
        peak=maxi(peak,Time.get_ticks_usec()-start);calls+=1
        bounded=bounded and state.work_units>0 and state.work_units<=budget
    check(bounded and task.statistics().status==1,"hierarchy completes within operation budgets")
    check(task.advance(budget).work_units==0,"completed hierarchy performs zero further work")
    costs.append({"budget":budget,"calls":calls,"max_call_us":peak,"statistics":task.statistics()})
    return task
func connected_graph(g:Dictionary,a:int,b:int,h:int)->bool:
    if g.floors_mm[a]>=h or g.floors_mm[b]>=h:return false
    var seen:Dictionary={a:true};var queue:Array=[a];var cursor:=0
    while cursor<queue.size():
        var n:int=queue[cursor];cursor+=1
        if n==b:return true
        for i in range(0,g.edges.size(),3):
            if g.edges[i+2]>=h:continue
            var other:int=-1
            if g.edges[i]==n:other=g.edges[i+1]
            elif g.edges[i+1]==n:other=g.edges[i]
            if other>=0 and not seen.has(other):seen[other]=true;queue.append(other)
    return false
func connected_tree(t:Dictionary,a:int,b:int,h:int)->bool:
    var groups:Array=[]
    for i in t.leaf_floors_mm.size():groups.append({i:true})
    for i in range(0,t.merges.size(),4):
        var members:Dictionary=groups[t.merges[i]].duplicate()
        members.merge(groups[t.merges[i+1]]);groups.append(members)
        if t.merges[i+2]<h and members.has(t.owners[a]) and members.has(t.owners[b]):return true
    return t.owners[a]==t.owners[b]
func terrain_graph(ridge:bool)->Dictionary:
    var volume=ClassDB.instantiate("NativeLakeVolume")
    check(volume.configure(Vector3.ZERO,Vector3i(16,8,16),1,5,Vector3(4.5,2.5,8.5)),"terrain volume configured")
    var field:=PackedFloat32Array()
    for z in 17:
        for y in 9:
            for x in 17:
                var d:float=y-(1+maxf(0,2-absf(x-8)*2) if ridge else 1)
                if x==0 or x==16 or z==0 or z==16:d=-10
                field.append(d)
    check(volume.bake_density(field)==1,"terrain fixture bakes")
    var topology=ClassDB.instantiate("NativeWaterTopology")
    check(topology.begin(volume,Vector3i.ZERO,Vector3i(16,8,16)),"terrain topology begins")
    while topology.statistics().status==0:topology.advance(256)
    return topology.graph()
func rejected(g:Dictionary)->bool:
    var task=ClassDB.instantiate("NativeWaterBasins")
    if not task.begin(g):return true
    while task.statistics().status==0:task.advance(2048)
    return task.statistics().status==-2 and not task.hierarchy().ok
func _initialize():
    GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
    var flat=reduce(terrain_graph(false));var f:Dictionary=flat.hierarchy()
    check(f.leaf_floors_mm.size()==1 and f.merges.is_empty() and f.settling_compatible,"thousands of flat connected tetrahedra collapse to one basin")
    var sampled:Dictionary=terrain_graph(true)
    var ridge=reduce(sampled);var r:Dictionary=ridge.hierarchy()
    check(r.leaf_floors_mm.size()==2 and r.merges.size()==4 and r.merges[2]==3000,"sampled ridge reduces to exactly two basins joining at three metres")
    check(r.settling_compatible and r.portals.is_empty(),"closed sampled basin hierarchy is eligible for storage-profile integration")
    var tiny=reduce(sampled,1)
    check(tiny.hierarchy()==r,"one-operation scheduling preserves complete hierarchy exactly")
    var copied:Dictionary=ridge.hierarchy();copied.owners[0]=-999
    check(ridge.hierarchy()==r,"published arrays cannot mutate native ownership")
    var simple:Dictionary=graph([0,0,0,0,1000],[0,1,1000,2,3,1500,1,2,3000,1,4,1000])
    var nested=reduce(simple);var n:Dictionary=nested.hierarchy()
    check(n.leaf_floors_mm.size()==4 and n.merges.size()==12 and n.roots.size()==1,"nested basin hierarchy retains distinct lower minima")
    var matches:=true
    for h in [1,999,1000,1001,1499,1500,1501,2999,3000,3001]:
        for a in 5:
            for b in 5:
                var expected:=connected_graph(simple,a,b,h)
                var actual:bool=simple.floors_mm[a]<h and simple.floors_mm[b]<h and connected_tree(n,a,b,h)
                matches=matches and expected==actual
    check(matches,"250 independent graph flood comparisons match hierarchy around all opening heights")
    var random:=RandomNumberGenerator.new();random.seed=73421
    var random_match:=true
    for trial in 24:
        var node_floors:Array=[];var random_edges:Array=[]
        for i in 12:node_floors.append(random.randi_range(-2,3)*100)
        for a in 12:
            for b in range(a+1,12):
                if random.randf()<.25:random_edges.append_array([a,b,maxi(node_floors[a],node_floors[b])+random.randi_range(0,4)*100])
        var input:Dictionary=graph(node_floors,random_edges)
        var task=ClassDB.instantiate("NativeWaterBasins");task.begin(input)
        while task.statistics().status==0:task.advance(128)
        var tree:Dictionary=task.hierarchy()
        random_match=random_match and tree.ok
        for h in range(-199,802,100):
            for a in 12:
                for b in range(a,12):
                    var expected:=connected_graph(input,a,b,h)
                    var actual:bool=node_floors[a]<h and node_floors[b]<h and connected_tree(tree,a,b,h)
                    random_match=random_match and expected==actual
        var reversed_edges:Array=[]
        for i in range(random_edges.size()-3,-1,-3):reversed_edges.append_array(random_edges.slice(i,i+3))
        var reverse=ClassDB.instantiate("NativeWaterBasins");reverse.begin(graph(node_floors,reversed_edges))
        while reverse.statistics().status==0:reverse.advance(128)
        random_match=random_match and reverse.hierarchy()==tree
    check(random_match,"20592 independent random-graph flood comparisons and edge-order permutations preserve connectivity")
    var deep_floors:Array=[];var deep_edges:Array=[]
    for i in 70:
        deep_floors.append(0)
        if i:deep_edges.append_array([i-1,i,i*100])
    var deep=reduce(graph(deep_floors,deep_edges)).hierarchy()
    check(not deep.settling_compatible,"hierarchies deeper than solver limit are explicitly ineligible")
    var profiles:Array=[]
    for i in 4:profiles.append(PackedInt64Array([0,1000000,1500000,3000000,4000000]))
    var solver=ClassDB.instantiate("NativeWaterSettling")
    check(solver.configure(PackedInt64Array([0,1000,1500,3000,4000]),profiles,n.merges),"compiled nested entries pass native settling ownership validation")
    check(solver.begin_add(n.owners[0],5000000),"compiled hierarchy accepts finite water addition")
    while solver.statistics().busy:solver.advance(1)
    check(solver.statistics().total_ml==5000000 and solver.statistics().pending_ml==0,"terrain-independent profile handoff conserves all input water")
    var open=reduce(graph([0,0],[0,1,2000,1,99,2500]));var o:Dictionary=open.hierarchy()
    check(o.requires_stitching and not o.settling_compatible and o.portals==PackedInt32Array([1,99,2500]),"external opening survives and prevents false closed-lake publication")
    var disconnected=reduce(graph([0,0],[])).hierarchy()
    check(disconnected.roots.size()==2 and not disconnected.settling_compatible,"disconnected regions remain a forest instead of inventing a connection")
    check(rejected({"ids":PackedInt32Array([1,0]),"floors_mm":PackedInt32Array([0,0]),"edges":PackedInt32Array()}),"unordered identity rejected")
    check(rejected(graph([1000,0],[0,1,999])),"opening below air floor rejected")
    check(rejected(graph([0],[3,4,1000])),"unowned edge rejected")
    check(rejected(graph([0],[0,0,0])),"self edge rejected")
    var excess:Array=[]
    for i in 4097:excess.append(0)
    check(rejected(graph(excess,[])),"too many isolated minima fail without publishing a partial hierarchy")
    # Equal-height plateaus must not create a leaf per node even at regional maximum.
    var many:Array=[];var links:Array=[]
    for i in 24576:
        many.append(0)
        if i>0:links.append_array([i-1,i,0])
    var maximum=reduce(graph(many,links),2048).hierarchy()
    check(maximum.leaf_floors_mm.size()==1 and maximum.merges.is_empty(),"maximum regional plateau compacts to one basin")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var file=FileAccess.open("res://reports/water_basins.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"costs":costs,"scope":"Regional merge forest and ownership; real terrain storage profiles, world stitching, fluid gameplay and thermal qualification remain open."},"  "));file.close()
    print("WATER_BASINS failures=",failures);quit(1 if failures else 0)
