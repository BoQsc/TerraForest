# SPDX-License-Identifier: 0BSD
extends Node3D
const Tokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
var terrain: Node3D
var camera: Camera3D
var structures: Node3D
var water: Node3D
var seed: int=1703
var seed_source: Callable
var picker: RefCounted
var native: RefCounted
var removed: RefCounted
var batches: Array[Node3D]=[]
var resident: Dictionary={}
var _wanted: Dictionary={}
var _requests: Dictionary={}
var _pending: Dictionary={}
var _dirty: Dictionary={}
var _last_cell:=Vector2i(-999,-999)
var rejected_batches:=0
var _support_job: Dictionary={}
var _exclusion_revision:=0

func prepare(persistence: RefCounted) -> bool:
	for addon in ["vegetation_runtime","structures"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,addon])
	native=ClassDB.instantiate("NativeGroundCover")
	picker=ClassDB.instantiate("NativeGroundCoverPicker")
	removed=ClassDB.instantiate("NativeGroundCoverState")
	return persistence.register_component("ground_cover_edits_v1",removed.capture_storage_snapshot,_restore,removed,removed.capture_storage_snapshot())

func _restore(data: PackedByteArray) -> bool:
	if not removed.restore_storage_snapshot(data): return false
	reset()
	return true

func _ready() -> void:
	if native==null or terrain==null or camera==null:
		push_error("Ground cover requires prepared persistence, terrain and camera")
		set_process(false);return
	for species in range(3):
		var batch: Node3D=ClassDB.instantiate("NativeStaticBatch")
		add_child(batch)
		if not batch.configure_asset("ground_cover/%d/v1"%species,_mesh(species)) or not batch.configure_render_streaming(true,[112.0,96.0,80.0][species],128,200000,2,8192):
			push_error("Ground cover renderer initialization failed");set_process(false);return
		batches.append(batch)
	terrain.surface_batch_ready.connect(_surface_ready)
	terrain.density_batch_ready.connect(_density_ready)
	terrain.region_changed.connect(_terrain_changed)
	terrain.reload_started.connect(reset)
	if structures!=null: structures.vegetation_changed.connect(_exclusion_changed)
	if water!=null: water.exclusion_changed.connect(_exclusion_changed)

func _mesh(species: int) -> Mesh:
	var material:=StandardMaterial3D.new()
	material.albedo_color=[Color("777975"),Color("557538"),Color("677e3e")][species]
	material.roughness=1.0
	if species==0:
		var rock:=SphereMesh.new()
		rock.radius=0.3;rock.height=0.35;rock.radial_segments=8;rock.rings=3;rock.material=material
		return rock
	# Opaque crossed tapered blades; no alpha overdraw or per-blade physics.
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	for blade in range(5 if species==2 else 7):
		var angle:=blade*2.399963
		var direction:=Vector3(cos(angle),0,sin(angle))
		var side:=Vector3(-direction.z,0,direction.x)*(0.045 if species==2 else 0.13)
		var base:=direction*0.1
		var top:=direction*(0.24 if species==2 else 0.38)+Vector3.UP*(0.4 if species==2 else 0.7)
		var normal: Vector3=(top-base+side).cross(side*2).normalized()
		vertices.append_array(PackedVector3Array([base-side,top,base+side]))
		normals.append_array(PackedVector3Array([normal,normal,normal]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,material)
	return mesh

func reset() -> void:
	for key in resident: _retire(key)
	resident.clear();_wanted.clear();_dirty.clear();_pending.clear();_requests.clear();_support_job.clear()
	_last_cell=Vector2i(-999,-999)

func _retire(key: Vector2i) -> void:
	picker.remove_cell(key)
	for species in range(3):
		batches[species].remove_instances(resident[key][species].ids)

func _process(_delta: float) -> void:
	if not terrain.world_ready or terrain.stopping: return
	if seed_source.is_valid(): seed=seed_source.call()
	if not removed.bind_world(seed,1):
		push_error("Ground-cover save belongs to a different generation profile")
		set_process(false);return
	for batch in batches: batch.set_render_focus(camera.global_position)
	var center:=Vector2i(floori(camera.global_position.x/32.0),floori(camera.global_position.z/32.0))
	if center!=_last_cell:
		_last_cell=center;_wanted.clear()
		for key in native.wanted(center): _wanted[key]=true
		for key in resident.keys():
			if not _wanted.has(key):
				_retire(key);resident.erase(key);_dirty.erase(key)
	if terrain.pending_edit or _requests.size()>=1: return
	if not _support_job.is_empty():
		if not _support_job.waiting:
			_support_job.waiting=terrain.request_density_batch(_support_job.points,_support_job.token)
		return
	for key in _wanted:
		if (resident.has(key) and not _dirty.has(key)) or _pending.has(key): continue
		var data: Dictionary=native.candidates(key,seed)
		var token:=Tokens.allocate()
		if terrain.request_surface_batch(data.points,token):
			data.key=key;_requests[token]=data;_pending[key]=token
		break

func _surface_ready(token: int,points: PackedVector3Array,normals: PackedVector3Array,epoch: int,revision: int) -> void:
	if not _requests.has(token): return
	var request: Dictionary=_requests[token];_requests.erase(token);_pending.erase(request.key)
	if not _wanted.has(request.key) or epoch!=terrain.epoch or revision!=terrain.published_revision or terrain.pending_edit: return
	var placed: Dictionary=native.place(request.ids,points,normals)
	if not placed.ok: rejected_batches+=1;return
	var mask: PackedByteArray=removed.mask(placed.ids)
	var structure_mask:=PackedByteArray();var water_mask:=PackedByteArray()
	if structures!=null: structure_mask=structures.overlap_mask(placed.transforms,AABB(Vector3(-0.4,0,-0.4),Vector3(0.8,0.8,0.8)))
	if water!=null: water_mask=water.placement_mask(placed.transforms)
	if (structures!=null and structure_mask.size()!=mask.size()) or (water!=null and water_mask.size()!=mask.size()):
		rejected_batches+=1;return
	# Only this bounded 64-candidate owner is combined in scene glue.
	for i in range(mask.size()):
		if (structures!=null and structure_mask[i]) or (water!=null and water_mask[i]): mask[i]=1
	var packed: Array=native.pack(placed.ids,placed.transforms,mask)
	if packed.size()!=3: rejected_batches+=1;return
	var authored_poses: Array[Transform3D]=removed.sample_transforms(request.key)
	if authored_poses.is_empty():
		_publish(request.key,packed,authored_poses,PackedByteArray());return
	_support_job={"key":request.key,"packed":packed,"poses":authored_poses,"points":removed.support_points(request.key),"token":Tokens.allocate(),"waiting":false,"epoch":epoch,"revision":revision,"density_revision":terrain.density_revision,"exclusion_revision":_exclusion_revision}
	_pending[request.key]=-1

func _density_ready(result: Dictionary) -> void:
	if _support_job.is_empty() or result.token!=_support_job.token: return
	var job:=_support_job;_support_job={};_pending.erase(job.key)
	if job.exclusion_revision!=_exclusion_revision or not _wanted.has(job.key) or result.status!="ok" or result.epoch!=terrain.epoch or job.epoch!=terrain.epoch or result.revision!=job.density_revision or terrain.density_revision!=job.density_revision or terrain.published_revision!=job.revision or terrain.pending_edit: return
	var structure_support:=PackedByteArray();structure_support.resize(job.poses.size())
	if structures!=null:
		var probes: Array[Transform3D]=[]
		for pose: Transform3D in job.poses: probes.append(Transform3D(Basis.IDENTITY,pose.origin-Vector3.UP*0.05))
		structure_support=structures.overlap_mask(probes,AABB(Vector3.ONE*-0.03,Vector3.ONE*0.06))
	var unsupported: PackedByteArray=removed.support_mask(result.values,structure_support)
	if unsupported.size()!=job.poses.size(): rejected_batches+=1;return
	_publish(job.key,job.packed,job.poses,unsupported)

func _publish(key: Vector2i,packed: Array,authored_poses: Array[Transform3D],unsupported: PackedByteArray) -> void:
	var authored_blocked:=PackedByteArray();authored_blocked.resize(authored_poses.size())
	var authored_water:=PackedByteArray();authored_water.resize(authored_poses.size())
	if structures!=null: authored_blocked=structures.overlap_mask(authored_poses,AABB(Vector3(-0.4,0,-0.4),Vector3(0.8,0.8,0.8)))
	if water!=null: authored_water=water.placement_mask(authored_poses)
	if authored_blocked.size()!=unsupported.size(): rejected_batches+=1;return
	for i in range(unsupported.size()):
		if unsupported[i]: authored_blocked[i]=1
	var authored: Array=removed.query_filtered(key,authored_blocked,authored_water)
	if authored.size()!=3: rejected_batches+=1;return
	for species in range(3):
		packed[species].ids.append_array(authored[species].ids)
		packed[species].transforms.append_array(authored[species].transforms)
	if resident.get(key,[])==packed: _dirty.erase(key);return
	var previous: Array=resident.get(key,[])
	if not picker.replace_cell(key,packed): rejected_batches+=1;return
	for species in range(3):
		if not batches[species].upsert_instances(packed[species].ids,packed[species].transforms):
			# Restore interaction and all collections if any publication fails.
			if previous.is_empty(): picker.remove_cell(key)
			else: picker.replace_cell(key,previous)
			for rollback in range(3):
				batches[rollback].remove_instances(packed[rollback].ids)
				if not previous.is_empty(): batches[rollback].upsert_instances(previous[rollback].ids,previous[rollback].transforms)
			rejected_batches+=1;return
	if not previous.is_empty():
		for species in range(3):
			var retired:=PackedInt64Array()
			for id in previous[species].ids:
				if not packed[species].ids.has(id): retired.append(id)
			batches[species].remove_instances(retired)
	resident[key]=packed;_dirty.erase(key)

func _terrain_changed(bounds: AABB,_revision: int) -> void: _exclusion_changed(bounds)
func _exclusion_changed(bounds: AABB) -> void:
	for key: Vector2i in _wanted:
		var owner:=AABB(Vector3(key.x*32,bounds.position.y,key.y*32),Vector3(32,maxf(1,bounds.size.y),32)).grow(8.0)
		if bounds.size==Vector3.ZERO or owner.intersects(bounds):
			_dirty[key]=true;_exclusion_revision+=1
