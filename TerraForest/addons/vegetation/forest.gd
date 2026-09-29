extends Node3D
## Standalone cell renderer. One stable tier per tree; overlap only while a timed transition is active.
const CELL: float=128.0
const HEIGHT: float=18.4712715
const CENTER: Vector3=Vector3(0,9.23563575,0)
var transition_seconds: float=0.28
var membership_guard_m: float=2.0
var meshes: Array[ArrayMesh]=[]
# Profiling is disabled in RUN. Native setter duration is a subset of flush time,
# not a GPU driver transfer measurement and never added to it again.
var profiling_enabled: bool=false
var phase_us: PackedInt64Array=PackedInt64Array([0,0,0,0,0,0])
var api_us_this_tick: int=0
var rows_this_tick: int=0

var cells: Dictionary={}
var roots: Dictionary={}
var owners: Dictionary={}
var moving: Dictionary={}
var dirty: Dictionary={}
var dirty_rows: Dictionary={}
var rebuild_cells: Dictionary={}
var previous_neighborhood: Dictionary={}
# Decision certificates expire in cumulative camera-travel metres. Each certificate
# is the minimum distance to any sphere that can change this root's LOD/shadow state.
# Triangle inequality makes early expiration conservative; no sampling is delayed.
var _travel: float=0.0
var _event_serial: int=0
var _popped_valid: bool=false
var _heap_distance: Array[float]=[]
var _heap_id: Array[int]=[]
var _heap_token: Array[int]=[]
var _due_tokens: Dictionary={}
var _due_distances: Dictionary={}
var _invalid_decisions: Dictionary={}

var last_eye: Vector3=Vector3(1e20,1e20,1e20)
var last_projection: float=-1.0
var changed: bool=true
var reference: bool=false
var trees_enabled: bool=true
var shadows_enabled: bool=true
var far_distance: float=2200.0
var shadow_reach: float=190.0
var max_scale: float=1.0
var stats: Dictionary={"trees":0,"selection_jobs":0,"tested_rows":0,"uploaded_bytes":0,"uploads":0,"source":0,"middle":0,"far":0,"shadow_source":0,"shadow_proxy":0,"transitions":0,"selection_us":0,"update_us":0,"transition_followups":0,"flushed_tiers":0,"row_writes":0,"custom_writes":0,"full_rebuilds":0,"selection_checked":0,"selection_skipped_cells":0,"flush_us":0}

func setup(shared: Array[ArrayMesh],draw_range: float)->void:
	meshes=shared;far_distance=draw_range

func _key(pos: Vector3)->Vector2i:
	return Vector2i(floori(pos.x/CELL),floori(pos.z/CELL))

func _ensure(key: Vector2i)->Dictionary:
	if not cells.has(key):cells[key]={"origin":Vector3(key.x*CELL,0,key.y*CELL),"rows":{},"nodes":[null,null,null,null,null],"capacity":0,"rows_cache":[],"cache_invalid":true,"bounds":AABB(),"tier_uploads":[0,0,0,0,0],"slots":[{},{},{},{},{}],"slot_ids":[[],[],[],[],[]],"packets":[{},{},{},{},{}]}
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
	# Keep unchanged rows and their ongoing LOD/shadow transitions intact.
	for old_id in owners.get(chunk,PackedInt64Array()):
		if not seen.has(old_id):remove_root(old_id)
	owners[chunk]=ids
	for i in range(ids.size()):
		var t: Transform3D=transforms[i]
		if roots.has(ids[i]) and roots[ids[i]]["t"]==t:continue
		if roots.has(ids[i]):remove_root(ids[i])
		var sc: float=t.basis.x.length();var key: Vector2i=_key(t.origin)
		var row: Dictionary={"id":ids[i],"owner":chunk,"key":key,"t":t,"center":t*CENTER,"scale":sc,"lod":2,"next":-1,"shadow":-1,"shadow_next":-2,"time":0.0,"shadow_time":0.0,"seed":float(posmod(ids[i]*48271,2147483647))/2147483647.0}
		var local_t: Transform3D=t;local_t.origin-=_ensure(key)["origin"];row["local_t"]=local_t
		if audit_enabled:_audit_pending[ids[i]]=true
		roots[ids[i]]=row;_ensure(key)["rows"][ids[i]]=row;_invalidate_cell(key);max_scale=maxf(max_scale,sc)
	stats["trees"]=roots.size();changed=true
	return true

func remove_root(id: int)->void:
	if audit_enabled:_audit_pending[id]=true
	if not roots.has(id):return
	var row: Dictionary=roots[id];var key: Vector2i=row["key"]
	cells[key]["rows"].erase(id);roots.erase(id);moving.erase(id);_invalidate_cell(key);changed=true;stats["trees"]=roots.size()

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
		row["lod"]=2;row["next"]=-1;row["shadow"]=-1;row["shadow_next"]=-2;_mark(row["key"],31)
	moving.clear();previous_neighborhood.clear();changed=true;last_projection=-1
	for key in cells:rebuild_cells[key]=true

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

func _mark(key: Vector2i, mask: int)->void:
	dirty[key]=int(dirty.get(key,0))|mask

static func _tier_mask(a: int,b: int)->int:
	return ((1<<a) if a>=0 else 0)|((1<<b) if b>=0 else 0)

func _mark_row(row: Dictionary,mask: int)->void:
	_invalid_decisions[row["id"]]=true
	if audit_enabled:_audit_pending[row["id"]]=true
	var key: Vector2i=row["key"]
	if cells.has(key):cells[key]["certificate_valid"]=false
	_mark(key,mask)
	if not dirty_rows.has(key):dirty_rows[key]={}
	dirty_rows[key][row["id"]]=int(dirty_rows[key].get(row["id"],0))|mask

func _invalidate_cell(key: Vector2i)->void:
	rebuild_cells[key]=true
	if cells.has(key):cells[key]["cache_invalid"]=true;cells[key]["certificate_valid"]=false
	_mark(key,31)

func _members(cell: Dictionary)->Array:
	if bool(cell["cache_invalid"]):
		var rows: Array=cell["rows"].values()
		cell["rows_cache"]=rows
		if not rows.is_empty():
			var first: Vector3=(rows[0]["t"] as Transform3D).origin-cell["origin"]
			var bounds: AABB=AABB(first,Vector3.ZERO)
			for row in rows:
				bounds=bounds.expand((row["t"] as Transform3D).origin-cell["origin"])
			bounds=bounds.grow(14.0*max_scale)
			bounds.size.y+=20.0*max_scale
			cell["bounds"]=bounds
		cell["cache_invalid"]=false
	return cell["rows_cache"]

func _choose_visual(row: Dictionary,eye: Vector3,projection: float,t: float,instant: bool,nearby: bool)->void:
	if int(row["next"])!=-1:return
	var dist: float=eye.distance_to(row["center"])
	var px: float=HEIGHT*float(row["scale"])*projection/maxf(dist,0.1)
	var want: int=desired_lod(px,int(row["lod"]),reference)
	if not nearby:want=1 if reference else 2
	if want==int(row["lod"]):return
	_mark_row(row,_tier_mask(int(row["lod"]),want))
	if instant:row["lod"]=want
	else:
		row["next"]=want;row["time"]=t;moving[row["id"]]=true

func _heap_push(distance: float,id: int,token: int)->void:
	var i: int=_heap_distance.size()
	_heap_distance.append(distance);_heap_id.append(id);_heap_token.append(token)
	while i>0:
		var parent: int=(i-1)/2
		if _heap_distance[parent]<=distance:break
		_heap_distance[i]=_heap_distance[parent];_heap_id[i]=_heap_id[parent];_heap_token[i]=_heap_token[parent]
		i=parent
	_heap_distance[i]=distance;_heap_id[i]=id;_heap_token[i]=token

func _heap_pop()->int:
	var id: int=_heap_id[0]
	var token: int=_heap_token[0]
	var n: int=_heap_distance.size()-1
	var distance: float=_heap_distance[n];var last_id: int=_heap_id[n];var last_token: int=_heap_token[n]
	_heap_distance.pop_back();_heap_id.pop_back();_heap_token.pop_back()
	if n>0:
		var i: int=0
		while i*2+1<n:
			var child: int=i*2+1
			if child+1<n and _heap_distance[child+1]<_heap_distance[child]:child+=1
			if distance<=_heap_distance[child]:break
			_heap_distance[i]=_heap_distance[child];_heap_id[i]=_heap_id[child];_heap_token[i]=_heap_token[child]
			i=child
		_heap_distance[i]=distance;_heap_id[i]=last_id;_heap_token[i]=last_token
	_popped_valid=int(_due_tokens.get(id,-1))==token
	if not _popped_valid:return id
	_due_tokens.erase(id);_due_distances.erase(id)
	return id

func _clear_events()->void:
	_heap_distance.clear();_heap_id.clear();_heap_token.clear()
	_due_tokens.clear();_due_distances.clear();_invalid_decisions.clear();_travel=0.0

func _schedule(id: int,slack: float)->void:
	_event_serial+=1
	var deadline: float=_travel+maxf(0.0,slack-0.02)
	_due_tokens[id]=_event_serial;_due_distances[id]=deadline
	_heap_push(deadline,id,_event_serial)

func _evaluate_decision(row: Dictionary,eye: Vector3,projection: float,t: float,instant: bool,nearby: bool)->void:
	var id: int=row["id"]
	var scale: float=row["scale"]
	var dist: float=eye.distance_to(row["center"])
	var root_dist: float=eye.distance_to((row["t"] as Transform3D).origin)
	var size_factor: float=HEIGHT*scale*projection
	if int(row["next"])==-1:
		var want: int=desired_lod(size_factor/maxf(dist,0.1),int(row["lod"]),reference)
		if not nearby:want=1 if reference else 2
		if want!=int(row["lod"]):
			_mark_row(row,_tier_mask(int(row["lod"]),want))
			if instant:row["lod"]=want
			else:row["next"]=want;row["time"]=t;moving[id]=true
	var reach: float=shadow_reach+20.0*scale
	var band: float=58.0 if reference else 32.0
	var threshold: float=band+3.0 if int(row["shadow"])==3 else band-3.0
	var swant: int=4 if dist<reach else -1
	if root_dist<threshold:swant=3
	if int(row["shadow_next"])==-2 and swant!=int(row["shadow"]):
		_mark_row(row,_tier_mask(int(row["shadow"]),swant))
		if instant:row["shadow"]=swant
		else:row["shadow_next"]=swant;row["shadow_time"]=t;moving[id]=true
	_invalid_decisions.erase(id)
	if not nearby:
		_due_tokens.erase(id);_due_distances.erase(id)
		return
	var slack: float=0.0
	if int(row["next"])==-1 and int(row["shadow_next"])==-2:
		var tier: int=row["lod"]
		if reference:slack=absf(dist-size_factor/(75.0 if tier==0 else 95.0))
		elif tier==0:slack=absf(dist-size_factor/180.0)
		elif tier==1:slack=minf(absf(dist-size_factor/220.0),absf(dist-size_factor/70.0))
		else:slack=absf(dist-size_factor/90.0)
		slack=minf(slack,absf(dist-reach))
		slack=minf(slack,absf(root_dist-(band+3.0 if int(row["shadow"])==3 else band-3.0)))
	_schedule(id,slack)

func _choose(eye: Vector3,projection: float,t: float,instant: bool)->void:
	var started: int=Time.get_ticks_usec()
	var reset_events: bool=changed or instant or projection!=last_projection
	if reset_events:_clear_events()
	else:_travel+=last_eye.distance_to(eye)
	var radius: float=maxf(shadow_reach+30.0,HEIGHT*max_scale*projection/70.0)+membership_guard_m+6.0
	var lo: Vector2i=_key(eye-Vector3(radius,0,radius));var hi: Vector2i=_key(eye+Vector3(radius,0,radius))
	var current: Dictionary={}
	for z in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var key: Vector2i=Vector2i(x,z)
			if cells.has(key):current[key]=true
	var due: Dictionary={}
	# Collect before rescheduling so zero-slack/pending roots are visited once.
	var popped: int=0
	while not _heap_distance.is_empty() and _heap_distance[0]<=_travel:
		var id: int=_heap_pop();popped+=1
		if _popped_valid and roots.has(id) and current.has(roots[id]["key"]):due[id]=true
	for id in _invalid_decisions:
		if roots.has(id) and current.has(roots[id]["key"]):due[id]=true
	_invalid_decisions.clear()
	var visit: Dictionary=current.duplicate()
	for key in previous_neighborhood:visit[key]=true
	var reused: int=0
	for key in visit:
		if not cells.has(key):continue
		if reset_events or current.has(key)!=previous_neighborhood.has(key):
			for row in _members(cells[key]):due[row["id"]]=true
		else:reused+=1
	for id in due:
		var row: Dictionary=roots[id]
		_evaluate_decision(row,eye,projection,t,instant,current.has(row["key"]))
	# Bound superseded heap records; rebuild only the live event queue, not root data.
	if _heap_distance.size()>4*_due_tokens.size()+1024:
		_heap_distance.clear();_heap_id.clear();_heap_token.clear()
		for id in _due_tokens:_heap_push(_due_distances[id],id,_due_tokens[id])
	stats["selection_checked"]=int(stats["selection_checked"])+due.size()
	stats["selection_skipped_cells"]=int(stats["selection_skipped_cells"])+reused
	stats["event_pops"]=int(stats.get("event_pops",0))+popped
	stats["event_queue_records"]=_heap_distance.size()
	stats["live_certificates"]=_due_tokens.size()
	previous_neighborhood=current;last_eye=eye;last_projection=projection;changed=false
	stats["selection_jobs"]=int(stats["selection_jobs"])+1;stats["tested_rows"]=due.size();stats["selection_us"]=Time.get_ticks_usec()-started

# A bulk upload alone leaves Godot 4.7's CPU instance cache uninitialized.
# The first sparse setter can then synchronously read the GPU buffer back.
# Establish editable CPU storage on a FRESH allocation, BEFORE .buffer is set.
# This follows the same path for startup, new tiers, growth, shrink and edits.
# Visible count is zero while the temporary initialization packet is present.
func _allocate_editable(mm: MultiMesh,count: int)->void:
	var previous: int=mm.instance_count
	if previous==count:return
	mm.visible_instance_count=0
	mm.instance_count=count
	stats["instance_cache_live_payload_bytes"]=int(stats.get("instance_cache_live_payload_bytes",0))+(count-previous)*64
	stats["instance_allocation_events"]=int(stats.get("instance_allocation_events",0))+1
	if count>0:
		var start: int=Time.get_ticks_usec() if profiling_enabled else 0
		# buffer_set is false for this generation: _multimesh_make_local zero-fills
		# new CPU data instead of recovering old data through buffer_get_data.
		mm.set_instance_custom_data(0,Color(0,0,0,0))
		stats["instance_cache_primes"]=int(stats.get("instance_cache_primes",0))+1
		stats["uploaded_bytes"]=int(stats["uploaded_bytes"])+16
		stats["custom_writes"]=int(stats["custom_writes"])+1
		if profiling_enabled:stats["instance_cache_prime_us"]=int(stats.get("instance_cache_prime_us",0))+Time.get_ticks_usec()-start

func _batch(cell: Dictionary,kind: int,count: int,bounds: AABB)->MultiMeshInstance3D:
	var n: MultiMeshInstance3D=cell["nodes"][kind]
	if n==null:
		n=MultiMeshInstance3D.new();n.name="Tier"+str(kind);n.position=cell["origin"];n.multimesh=MultiMesh.new();n.multimesh.transform_format=MultiMesh.TRANSFORM_3D;n.multimesh.use_custom_data=true;n.multimesh.mesh=meshes[kind]
		n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind<3 else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;n.ignore_occlusion_culling=kind>=3;add_child(n);cell["nodes"][kind]=n
		n.visibility_range_end=far_distance+bounds.size.length()
	n.multimesh.custom_aabb=bounds
	_allocate_editable(n.multimesh,count)
	n.visible=trees_enabled and (kind<3 or shadows_enabled)
	return n

static func _write(buffer: PackedFloat32Array,index: int,t: Transform3D,packet: Vector4)->void:
	var o: int=index*16
	buffer[o]=t.basis.x.x;buffer[o+1]=t.basis.y.x;buffer[o+2]=t.basis.z.x;buffer[o+3]=t.origin.x
	buffer[o+4]=t.basis.x.y;buffer[o+5]=t.basis.y.y;buffer[o+6]=t.basis.z.y;buffer[o+7]=t.origin.y
	buffer[o+8]=t.basis.x.z;buffer[o+9]=t.basis.y.z;buffer[o+10]=t.basis.z.z;buffer[o+11]=t.origin.z
	buffer[o+12]=packet.x;buffer[o+13]=packet.y;buffer[o+14]=packet.z;buffer[o+15]=packet.w

# A dense prefix per tier. A fade changes only custom data; root transforms are
# immutable during ordinary viewing. Removal swaps the final row into the hole.
# Edits/canonical resets rebuild affected cells, never ordinary camera movement.
const COUNT_KEYS: Array[String]=["source","middle","far","shadow_source","shadow_proxy"]

static func _has_tier(row: Dictionary,kind: int)->bool:
	if kind<3:return kind==int(row["lod"]) or kind==int(row["next"])
	return kind==int(row["shadow"]) or kind==int(row["shadow_next"])

func _packet(row: Dictionary,kind: int)->Vector4:
	var from: int=int(row["lod"]) if kind<3 else int(row["shadow"])
	var dest: int=int(row["next"]) if kind<3 else int(row["shadow_next"])
	var transient: bool=dest>=0 if kind<3 else dest>=-1
	if transient:
		return Vector4(float(row["seed"]),fposmod(float(row["time"] if kind<3 else row["shadow_time"]),4096.0),-1.0 if kind==from else 1.0,transition_seconds)
	return Vector4(float(row["seed"]),0,0,transition_seconds)

func _put(cell: Dictionary,kind: int,slot: int,id: int,packet: Vector4,transform_changed: bool)->void:
	var api_start: int=Time.get_ticks_usec() if profiling_enabled else 0
	var node: MultiMeshInstance3D=cell["nodes"][kind]
	if transform_changed:
		node.multimesh.set_instance_transform(slot,roots[id]["local_t"])
		stats["row_writes"]=int(stats["row_writes"])+1
		stats["uploaded_bytes"]=int(stats["uploaded_bytes"])+48
	node.multimesh.set_instance_custom_data(slot,Color(packet.x,packet.y,packet.z,packet.w))
	stats["custom_writes"]=int(stats["custom_writes"])+1
	stats["uploaded_bytes"]=int(stats["uploaded_bytes"])+16
	cell["packets"][kind][id]=packet
	if profiling_enabled:api_us_this_tick+=Time.get_ticks_usec()-api_start

func _rebuild(cell: Dictionary,rows: Array)->void:
	var n: int=rows.size()
	stats["full_rebuilds"]=int(stats["full_rebuilds"])+1
	for kind in range(5):
		var members: Array=[]
		var slots: Dictionary={}
		var packets: Dictionary={}
		var buffer: PackedFloat32Array=PackedFloat32Array();buffer.resize(n*16)
		for row in rows:
			if not _has_tier(row,kind):continue
			var id: int=row["id"];var index: int=members.size()
			var packet: Vector4=_packet(row,kind)
			slots[id]=index;members.append(id);packets[id]=packet
			_write(buffer,index,row["local_t"],packet)
		var node: MultiMeshInstance3D=cell["nodes"][kind]
		var old_count: int=maxi(node.multimesh.visible_instance_count,0) if node!=null else 0
		stats[COUNT_KEYS[kind]]=int(stats[COUNT_KEYS[kind]])+members.size()-old_count
		cell["slots"][kind]=slots;cell["slot_ids"][kind]=members;cell["packets"][kind]=packets
		if members.is_empty():
			if node!=null:
				_allocate_editable(node.multimesh,n);node.multimesh.visible_instance_count=0;node.multimesh.custom_aabb=cell["bounds"]
			continue
		node=_batch(cell,kind,n,cell["bounds"])
		node.multimesh.buffer=buffer;node.multimesh.visible_instance_count=members.size()
		cell["tier_uploads"][kind]+=1
		stats["uploads"]=int(stats["uploads"])+1
		stats["uploaded_bytes"]=int(stats["uploaded_bytes"])+buffer.size()*4

func _flush()->void:
	var start: int=Time.get_ticks_usec()
	for key in dirty:
		if not cells.has(key):continue
		var cell: Dictionary=cells[key]
		var rs: Array=_members(cell)
		if rs.is_empty():
			for kind in range(5):
				var old: MultiMeshInstance3D=cell["nodes"][kind]
				if old!=null:
					stats[COUNT_KEYS[kind]]=int(stats[COUNT_KEYS[kind]])-maxi(old.multimesh.visible_instance_count,0)
					stats["instance_cache_live_payload_bytes"]=int(stats.get("instance_cache_live_payload_bytes",0))-old.multimesh.instance_count*64
					old.queue_free()
			cells.erase(key);continue
		if rebuild_cells.has(key):
			_rebuild(cell,rs);continue
		var changes: Dictionary=dirty_rows.get(key,{})
		for kind in range(5):
			if (int(dirty[key])&(1<<kind))==0:continue
			var slots: Dictionary=cell["slots"][kind]
			var members: Array=cell["slot_ids"][kind]
			var packets: Dictionary=cell["packets"][kind]
			var old_size: int=members.size()
			var touched: bool=false
			# Remove first, so we never exceed the fixed n-root capacity.
			for id in changes:
				if (int(changes[id])&(1<<kind))==0 or not slots.has(id):continue
				if roots.has(id) and _has_tier(roots[id],kind):continue
				var index: int=slots[id];var last_id: int=members[-1]
				if index!=members.size()-1:
					members[index]=last_id;slots[last_id]=index
					_put(cell,kind,index,last_id,packets[last_id],true)
				members.pop_back();slots.erase(id);packets.erase(id);touched=true
			for id in changes:
				if (int(changes[id])&(1<<kind))==0 or not roots.has(id):continue
				var row: Dictionary=roots[id]
				if not _has_tier(row,kind):continue
				var packet: Vector4=_packet(row,kind)
				if slots.has(id):
					if packets[id]!=packet:_put(cell,kind,slots[id],id,packet,false);touched=true
				else:
					if cell["nodes"][kind]==null:_batch(cell,kind,rs.size(),cell["bounds"])
					var index: int=members.size();members.append(id);slots[id]=index
					_put(cell,kind,index,id,packet,true);touched=true
			if touched:
				var node: MultiMeshInstance3D=cell["nodes"][kind]
				if node!=null:node.multimesh.visible_instance_count=members.size()
				stats[COUNT_KEYS[kind]]=int(stats[COUNT_KEYS[kind]])+members.size()-old_size
				cell["tier_uploads"][kind]+=1
				stats["uploads"]=int(stats["uploads"])+1
				stats["flushed_tiers"]=int(stats["flushed_tiers"])+1
	dirty.clear();dirty_rows.clear();rebuild_cells.clear()
	stats["flush_us"]=Time.get_ticks_usec()-start

func tick(eye: Vector3,projection: float,t: float,instant: bool=false)->void:
	var started: int=Time.get_ticks_usec()
	api_us_this_tick=0;rows_this_tick=0
	var phase_mark: int=started
	var p_transition: int=0;var p_selection: int=0;var p_flush: int=0;var p_audit: int=0
	var checked0: int=int(stats["selection_checked"])
	var completed: Array[int]=[]
	for id in moving.keys():
		if not roots.has(id):moving.erase(id);continue
		var r: Dictionary=roots[id]
		if int(r["next"])>=0 and (instant or t-float(r["time"])>=transition_seconds):
			_mark_row(r,_tier_mask(int(r["lod"]),int(r["next"])))
			r["lod"]=r["next"];r["next"]=-1;completed.append(id)
		if int(r["shadow_next"])>=-1 and (instant or t-float(r["shadow_time"])>=transition_seconds):
			_mark_row(r,_tier_mask(int(r["shadow"]),int(r["shadow_next"])))
			r["shadow"]=r["shadow_next"];r["shadow_next"]=-2
		if int(r["next"])==-1 and int(r["shadow_next"])==-2:moving.erase(id)
	if profiling_enabled:p_transition=Time.get_ticks_usec()-phase_mark;phase_mark=Time.get_ticks_usec()
	if changed or instant or last_eye.distance_squared_to(eye)>=membership_guard_m*membership_guard_m or absf(last_projection-projection)>0.01:
		_choose(eye,projection,t,instant)
	else:
		# A completed fade only needs a follow-up decision for that tree.
		# It must not rescan every nearby tree or rewrite unrelated shadow/far tiers.
		for id in completed:
			var row: Dictionary=roots[id]
			_choose_visual(row,eye,projection,t,false,previous_neighborhood.has(row["key"]))
			stats["transition_followups"]=int(stats["transition_followups"])+1
	if profiling_enabled:p_selection=Time.get_ticks_usec()-phase_mark;phase_mark=Time.get_ticks_usec()
	if not dirty.is_empty():_flush()
	if profiling_enabled:p_flush=Time.get_ticks_usec()-phase_mark;phase_mark=Time.get_ticks_usec()
	_audit_commit()
	if profiling_enabled:p_audit=Time.get_ticks_usec()-phase_mark
	rows_this_tick=int(stats["selection_checked"])-checked0
	stats["transitions"]=moving.size();stats["update_us"]=Time.get_ticks_usec()-started
	if profiling_enabled:
		phase_us[0]=p_transition;phase_us[1]=p_selection;phase_us[2]=p_flush;phase_us[3]=p_audit;phase_us[4]=api_us_this_tick
		phase_us[5]=maxi(0,int(stats["update_us"])-p_transition-p_selection-p_flush-p_audit)

func _reset_cell_for_audit(key: Vector2i)->void:
	rebuild_cells[key]=true
	if cells.has(key):cells[key]["certificate_valid"]=false

# Benchmark-only state auditing. Disabled in normal gameplay. Incremental checksums
# are recorded per drawn frame; full SHA-256 checkpoints run outside sampling.
var audit_enabled: bool=false
var audit_checksum: int=0
var _audit_tokens: Dictionary={}
var _audit_pending: Dictionary={}

func reset_lod_state(eye: Vector3,projection: float,t: float=0.0)->void:
	moving.clear();previous_neighborhood.clear()
	for row in roots.values():
		row["lod"]=2;row["next"]=-1;row["shadow"]=-1;row["shadow_next"]=-2
		row["time"]=0.0;row["shadow_time"]=0.0
		_mark(row["key"],31)
		_reset_cell_for_audit(row["key"])
	last_eye=Vector3(1e20,1e20,1e20);last_projection=-1.0;changed=true
	tick(eye,projection,t,true)
	if audit_enabled:_audit_rebuild()

func _audit_token(row: Dictionary)->int:
	var t: int=roundi(float(row["time"])*1000000.0) if int(row["next"])>=0 else 0
	var st: int=roundi(float(row["shadow_time"])*1000000.0) if int(row["shadow_next"])>=-1 else 0
	var v: Array=[row["id"],row["lod"],row["next"],row["shadow"],row["shadow_next"],t,st]
	var lo: int=hash(v)
	v.reverse();v.append(1202)
	return (hash(v)<<32) | lo

func _audit_rebuild()->void:
	audit_checksum=0;_audit_tokens.clear();_audit_pending.clear()
	for id in roots:
		var token: int=_audit_token(roots[id]);_audit_tokens[id]=token;audit_checksum^=token

func _audit_commit()->void:
	if not audit_enabled:return
	for id in _audit_pending:
		audit_checksum^=int(_audit_tokens.get(id,0))
		if roots.has(id):
			var token: int=_audit_token(roots[id]);_audit_tokens[id]=token;audit_checksum^=token
		else:_audit_tokens.erase(id)
	_audit_pending.clear()

func state_sha256()->String:
	var ids: Array=roots.keys();ids.sort()
	var context: HashingContext=HashingContext.new();context.start(HashingContext.HASH_SHA256)
	for id in ids:
		var row: Dictionary=roots[id]
		var v: Array=[id,row["lod"],row["next"],row["shadow"],row["shadow_next"]]
		v.append(roundi(float(row["time"])*1000000.0) if int(row["next"])>=0 else 0)
		v.append(roundi(float(row["shadow_time"])*1000000.0) if int(row["shadow_next"])>=-1 else 0)
		context.update((JSON.stringify(v)+"\n").to_utf8_buffer())
	return context.finish().hex_encode()
