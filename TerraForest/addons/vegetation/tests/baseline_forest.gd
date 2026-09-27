extends Node3D
## Standalone cell renderer. One stable tier per tree; overlap only while a timed transition is active.
const CELL: float=128.0
const HEIGHT: float=18.4712715
const CENTER: Vector3=Vector3(0,9.23563575,0)
var transition_seconds: float=0.28
var membership_guard_m: float=2.0
var meshes: Array[ArrayMesh]=[]
var cells: Dictionary={}
var roots: Dictionary={}
var owners: Dictionary={}
var moving: Dictionary={}
var dirty: Dictionary={}
var previous_neighborhood: Dictionary={}
var last_eye: Vector3=Vector3(1e20,1e20,1e20)
var last_projection: float=-1.0
var changed: bool=true
var reference: bool=false
var trees_enabled: bool=true
var shadows_enabled: bool=true
var far_distance: float=2200.0
var shadow_reach: float=190.0
var max_scale: float=1.0
var stats: Dictionary={"trees":0,"selection_jobs":0,"tested_rows":0,"uploaded_bytes":0,"uploads":0,"source":0,"middle":0,"far":0,"shadow_source":0,"shadow_proxy":0,"transitions":0,"selection_us":0,"update_us":0}

func setup(shared: Array[ArrayMesh],draw_range: float)->void:
	meshes=shared;far_distance=draw_range

func _key(pos: Vector3)->Vector2i:
	return Vector2i(floori(pos.x/CELL),floori(pos.z/CELL))

func _ensure(key: Vector2i)->Dictionary:
	if not cells.has(key):cells[key]={"origin":Vector3(key.x*CELL,0,key.y*CELL),"rows":{},"nodes":[null,null,null,null,null],"capacity":0}
	return cells[key]

func upsert_chunk(chunk: String,ids: PackedInt64Array,transforms: Array[Transform3D])->bool:
	if ids.size()!=transforms.size():return false
	var seen: Dictionary={}
	for i in range(ids.size()):
		var id: int=ids[i];var t: Transform3D=transforms[i];var sc: float=t.basis.x.length()
		if seen.has(id) or (roots.has(id) and str(roots[id]["owner"])!=chunk):return false
		if not t.origin.is_finite() or not t.basis.is_finite() or sc<0.05 or sc>10.0:return false
		if absf(t.basis.y.length()-sc)>0.001 or absf(t.basis.z.length()-sc)>0.001 or t.basis.determinant()<=0:return false
		if absf(t.basis.x.dot(t.basis.y))>0.001*sc*sc or absf(t.basis.x.dot(t.basis.z))>0.001*sc*sc or absf(t.basis.y.dot(t.basis.z))>0.001*sc*sc:return false
		seen[id]=true
	remove_chunk(chunk)
	owners[chunk]=ids
	for i in range(ids.size()):
		var t: Transform3D=transforms[i];var sc: float=t.basis.x.length();var key: Vector2i=_key(t.origin)
		var row: Dictionary={"id":ids[i],"owner":chunk,"key":key,"t":t,"center":t*CENTER,"scale":sc,"lod":2,"next":-1,"shadow":-1,"shadow_next":-2,"time":0.0,"shadow_time":0.0,"seed":float(posmod(ids[i]*48271,2147483647))/2147483647.0}
		roots[ids[i]]=row;_ensure(key)["rows"][ids[i]]=row;dirty[key]=true;max_scale=maxf(max_scale,sc)
	stats["trees"]=roots.size();changed=true
	return true

func remove_root(id: int)->void:
	if not roots.has(id):return
	var row: Dictionary=roots[id];var key: Vector2i=row["key"]
	cells[key]["rows"].erase(id);roots.erase(id);moving.erase(id);dirty[key]=true;changed=true;stats["trees"]=roots.size()

func remove_chunk(chunk: String)->void:
	if not owners.has(chunk):return
	for id in owners[chunk]:remove_root(id)
	owners.erase(chunk)

func remove_roots_in_sphere(p: Vector3,radius: float)->int:
	var count: int=0
	var min_key: Vector2i=_key(p-Vector3(radius,0,radius));var max_key: Vector2i=_key(p+Vector3(radius,0,radius))
	for z in range(min_key.y,max_key.y+1):
		for x in range(min_key.x,max_key.x+1):
			var key: Vector2i=Vector2i(x,z)
			if not cells.has(key):continue
			for id in cells[key]["rows"].keys():
				if (roots[id]["t"] as Transform3D).origin.distance_to(p)<=radius:remove_root(id);count+=1
	return count

func rebase(delta: Vector3)->void:
	# Rebuild affected bins only on an explicit origin shift; do not change stable IDs.
	var entries: Array=[]
	for chunk in owners:
		var ids: PackedInt64Array=PackedInt64Array();var ts: Array[Transform3D]=[]
		for id in owners[chunk]:
			if roots.has(id):
				var t: Transform3D=roots[id]["t"];t.origin-=delta;ids.append(id);ts.append(t)
		entries.append([chunk,ids,ts])
	for e in entries:upsert_chunk(e[0],e[1],e[2])
	last_eye=Vector3(1e20,1e20,1e20);changed=true

func profile(value: bool)->void:
	if reference==value:return
	reference=value
	for row in roots.values():
		row["lod"]=2;row["next"]=-1;row["shadow"]=-1;row["shadow_next"]=-2;dirty[row["key"]]=true
	moving.clear();previous_neighborhood.clear();changed=true;last_projection=-1

func visibility(trees: bool,shadows: bool)->void:
	trees_enabled=trees;shadows_enabled=shadows
	for cell in cells.values():
		for k in range(5):
			var node: MultiMeshInstance3D=cell["nodes"][k]
			if node!=null:node.visible=trees_enabled and (k<3 or shadows_enabled)

static func desired_lod(px: float,current: int,is_reference: bool)->int:
	if is_reference:
		if current==0:return 0 if px>=75.0 else 1
		return 0 if px>95.0 else 1
	if current==0:
		if px>=180.0:return 0
		return 2 if px<70.0 else 1
	if current==1:
		if px>220.0:return 0
		return 2 if px<70.0 else 1
	if px>220.0:return 0
	return 1 if px>90.0 else 2

func _choose(eye: Vector3,projection: float,t: float,instant: bool)->void:
	var started: int=Time.get_ticks_usec()
	var radius: float=maxf(shadow_reach+30.0,HEIGHT*max_scale*projection/70.0)+membership_guard_m+6.0
	var lo: Vector2i=_key(eye-Vector3(radius,0,radius));var hi: Vector2i=_key(eye+Vector3(radius,0,radius))
	var current: Dictionary={}
	for z in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var key: Vector2i=Vector2i(x,z)
			if cells.has(key):current[key]=true
	var visit: Dictionary=current.duplicate()
	for k in previous_neighborhood:visit[k]=true
	var tested: int=0
	for key in visit:
		if not cells.has(key):continue
		for row in cells[key]["rows"].values():
			tested+=1
			var dist: float=eye.distance_to(row["center"])
			var px: float=HEIGHT*float(row["scale"])*projection/maxf(dist,0.1)
			var want: int=desired_lod(px,int(row["lod"]),reference)
			# Outside the resident neighborhood only the inexpensive distant tier survives.
			if not current.has(key):want=1 if reference else 2
			if int(row["next"])==-1 and want!=int(row["lod"]):
				if instant:row["lod"]=want
				else:row["next"]=want;row["time"]=t;moving[row["id"]]=true
				dirty[key]=true
			var droot: float=eye.distance_to((row["t"] as Transform3D).origin)
			var swant: int=4 if dist<shadow_reach+20.0*float(row["scale"]) else -1
			var band: float=58.0 if reference else 32.0
			if droot<(band+3.0 if int(row["shadow"])==3 else band-3.0):swant=3
			if int(row["shadow_next"])==-2 and swant!=int(row["shadow"]):
				if instant:row["shadow"]=swant
				else:row["shadow_next"]=swant;row["shadow_time"]=t;moving[row["id"]]=true
				dirty[key]=true
	previous_neighborhood=current;last_eye=eye;last_projection=projection;changed=false
	stats["selection_jobs"]=int(stats["selection_jobs"])+1;stats["tested_rows"]=tested;stats["selection_us"]=Time.get_ticks_usec()-started

func _batch(cell: Dictionary,kind: int,count: int,bounds: AABB)->MultiMeshInstance3D:
	var n: MultiMeshInstance3D=cell["nodes"][kind]
	if n==null:
		n=MultiMeshInstance3D.new();n.name="Tier"+str(kind);n.position=cell["origin"];n.multimesh=MultiMesh.new();n.multimesh.transform_format=MultiMesh.TRANSFORM_3D;n.multimesh.use_custom_data=true;n.multimesh.mesh=meshes[kind]
		n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind<3 else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;n.ignore_occlusion_culling=kind>=3;add_child(n);cell["nodes"][kind]=n
		n.visibility_range_end=far_distance+bounds.size.length()
	if n.multimesh.instance_count!=count:n.multimesh.instance_count=count
	n.multimesh.custom_aabb=bounds;n.visible=trees_enabled and (kind<3 or shadows_enabled)
	return n

static func _write(buffer: PackedFloat32Array,index: int,t: Transform3D,packet: Vector4)->void:
	var o: int=index*16
	buffer[o]=t.basis.x.x;buffer[o+1]=t.basis.y.x;buffer[o+2]=t.basis.z.x;buffer[o+3]=t.origin.x
	buffer[o+4]=t.basis.x.y;buffer[o+5]=t.basis.y.y;buffer[o+6]=t.basis.z.y;buffer[o+7]=t.origin.y
	buffer[o+8]=t.basis.x.z;buffer[o+9]=t.basis.y.z;buffer[o+10]=t.basis.z.z;buffer[o+11]=t.origin.z
	buffer[o+12]=packet.x;buffer[o+13]=packet.y;buffer[o+14]=packet.z;buffer[o+15]=packet.w

func _flush()->void:
	for key in dirty:
		if not cells.has(key):continue
		var cell: Dictionary=cells[key];var rs: Array=cell["rows"].values();var n: int=rs.size()
		if n==0:
			for node in cell["nodes"]:
				if node!=null:(node as Node).queue_free()
			cells.erase(key);continue
		var first: Vector3=(rs[0]["t"] as Transform3D).origin-cell["origin"]
		var bounds: AABB=AABB(first,Vector3.ZERO)
		for row in rs:bounds=bounds.expand((row["t"] as Transform3D).origin-cell["origin"])
		bounds=bounds.grow(14.0*max_scale);bounds.size.y+=20.0*max_scale
		for kind in range(5):
			var buffer: PackedFloat32Array=PackedFloat32Array();buffer.resize(n*16);var written: int=0
			for row in rs:
				var from: int=int(row["lod"]) if kind<3 else int(row["shadow"])
				var dest: int=int(row["next"]) if kind<3 else int(row["shadow_next"])
				var transient: bool=dest>=0 if kind<3 else dest>=-1
				if kind!=from and not (transient and kind==dest):continue
				var packet: Vector4=Vector4(float(row["seed"]),0,0,transition_seconds)
				if transient:packet.y=fposmod(float(row["time"] if kind<3 else row["shadow_time"]),4096.0);packet.z=-1.0 if kind==from else 1.0
				var tr: Transform3D=row["t"];tr.origin-=cell["origin"]
				_write(buffer,written,tr,packet);written+=1
			var node: MultiMeshInstance3D=cell["nodes"][kind]
			if written==0:
				if node!=null:node.multimesh.visible_instance_count=0
				continue
			node=_batch(cell,kind,n,bounds);node.multimesh.buffer=buffer;node.multimesh.visible_instance_count=written
			stats["uploads"]=int(stats["uploads"])+1;stats["uploaded_bytes"]=int(stats["uploaded_bytes"])+buffer.size()*4
	dirty.clear()
	var counts: Array[int]=[0,0,0,0,0]
	for cell in cells.values():
		for kind in range(5):
			var node: MultiMeshInstance3D=cell["nodes"][kind]
			if node!=null:counts[kind]+=maxi(node.multimesh.visible_instance_count,0)
	for i in range(5):stats[["source","middle","far","shadow_source","shadow_proxy"][i]]=counts[i]

func tick(eye: Vector3,projection: float,t: float,instant: bool=false)->void:
	var started: int=Time.get_ticks_usec();var finished: bool=false
	for id in moving.keys():
		if not roots.has(id):moving.erase(id);continue
		var r: Dictionary=roots[id]
		if int(r["next"])>=0 and t-float(r["time"])>=transition_seconds:r["lod"]=r["next"];r["next"]=-1;dirty[r["key"]]=true;finished=true
		if int(r["shadow_next"])>=-1 and t-float(r["shadow_time"])>=transition_seconds:r["shadow"]=r["shadow_next"];r["shadow_next"]=-2;dirty[r["key"]]=true
		if int(r["next"])==-1 and int(r["shadow_next"])==-2:moving.erase(id)
	if changed or last_eye.distance_squared_to(eye)>=membership_guard_m*membership_guard_m or absf(last_projection-projection)>0.01 or finished:_choose(eye,projection,t,instant)
	if not dirty.is_empty():_flush()
	stats["transitions"]=moving.size();stats["update_us"]=Time.get_ticks_usec()-started
