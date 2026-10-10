# SPDX-License-Identifier: 0BSD
# Main-thread lifecycle only; profile fitting runs natively on a worker thread.
extends Node
const Tokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
var world: Node
var phase:=""
var source: Dictionary={}
var points:=PackedVector3Array()
var fitted: Dictionary={}
var worker: Thread
var solver: RefCounted
var token:=0
var deadline:=0
var section:=0
var ticket:=-1
var revision:=0
func selection() -> Array:
	var p=world.road_palette
	return [p.has_start,p.has_finish,p.start,p.finish,p.width.value,p.depth.value,p.clearance.value,p.surface.selected,p.shoulder_width()]
func cancel(reason: String="") -> void:
	var active:=not phase.is_empty()
	phase="";source={};fitted={};points=PackedVector3Array()
	if is_instance_valid(world):
		if active:world.road_preview.clear()
		world.road_palette.build_button.disabled=false
		world.road_palette.build_button.text="Build asphalt road" if world.road_palette.material_id()==4 else "Grade stone foundation"
		if active and not reason.is_empty():world.road_palette.status.text=reason
func prepare() -> void:
	if worker!=null and worker.is_alive():return
	if worker!=null:worker.wait_to_finish();worker=null
	cancel()
	var p=world.road_palette;var terrain=world.terrain
	var length:=Vector2(p.finish.x-p.start.x,p.finish.z-p.start.z).length()
	if not p.has_start or not p.has_finish or not p.start.is_finite() or not p.finish.is_finite() or length<8 or length>128 or p.material_id()!=4 or p.clearance.value<1 or terrain.pending_edit:
		p.status.text="Smooth roads need two terrain ends, 8–128 m length, asphalt and clearance of at least 1 m.";return
	source={"selection":selection(),"epoch":terrain.epoch,"revision":terrain.density_revision}
	revision=terrain.density_revision;token=Tokens.allocate();deadline=Time.get_ticks_msec()+15000
	var count:=maxi(2,ceili(length/16))
	for i in count+1:points.append(p.start.lerp(p.finish,float(i)/count))
	phase="request";p.build_button.disabled=true;p.status.text="Sampling terrain for smooth road preview…"
func start_build() -> bool:
	if phase!="ready":return false
	if world.terrain.pending_edit or not valid_source():cancel("Road preview expired; prepare it again.");return true
	phase="building";section=0;ticket=-1
	world.road_palette.build_button.disabled=true
	world.road_palette.status.text="Building smooth road in sections. Completed sections remain if interrupted; F5 saves."
	return true
func valid_source() -> bool:
	return not source.is_empty() and selection()==source.selection and world.terrain.epoch==source.epoch and (world.terrain.density_revision==revision or (phase=="building" and ticket>=0 and world.terrain.pending_edit and world.terrain.density_revision==revision+1)) and not world.terrain.stopping
func receive(id: int,samples: PackedVector3Array,_normals: PackedVector3Array,epoch: int,_published: int) -> void:
	if phase!="sampling" or id!=token:return
	if not valid_source() or epoch!=source.epoch or samples.size()!=points.size():cancel("Terrain changed while preparing the road.");return
	points=samples;points[0].y=world.road_palette.start.y
	solver=ClassDB.instantiate("NativeRoadProfile");worker=Thread.new()
	var p=world.road_palette
	var error:=worker.start(Callable(solver,"fit").bind(points,0.25,0.008,maxf(0,p.clearance.value-1),maxf(0,minf(3,p.depth.value-1))))
	if error!=OK:worker=null;cancel("Road planner unavailable.");return
	phase="fitting"
func _process(_delta: float) -> void:
	if not is_instance_valid(world) or phase.is_empty():return
	var terrain=world.terrain;var p=world.road_palette
	if phase=="building" and ticket>=0 and not terrain.pending_edit:
		var outcome: Dictionary=terrain.last_edit_outcome
		if outcome.get("ticket",-1)!=ticket or outcome.get("epoch",-1)!=source.epoch or outcome.get("status","") not in ["published","unchanged"]:
			cancel("Road interrupted; completed sections remain. Inspect before retrying.");return
		revision+=1 if outcome.status=="published" else 0
		section+=1;ticket=-1
	if not valid_source():cancel("Road selection or terrain changed; completed sections remain.");return
	if phase in ["request","sampling"] and Time.get_ticks_msec()>deadline:cancel("Terrain sampling timed out; try again.");return
	if phase=="request":
		if terrain.request_surface_batch(points,token):phase="sampling"
	elif phase=="fitting" and not worker.is_alive():
		fitted=worker.wait_to_finish();worker=null;solver=null
		if not fitted.get("ok",false):cancel("No smooth route within these cut/fill limits. Change the endpoints or clearance.");return
		var c: PackedFloat64Array=fitted.coefficients
		for i in points.size()-1:points[i].y=c[i*4+3]
		points[-1].y=c[-4]+c[-3]+c[-2]+c[-1]
		var line:=PackedVector3Array()
		for i in points.size()-1:
			for j in 9:
				var t:=j/8.0;var point:=points[i].lerp(points[i+1],t)
				point.y=((c[i*4]*t+c[i*4+1])*t+c[i*4+2])*t+c[i*4+3];line.append(point)
		world.road_preview.update_curve(line,p.width.value)
		phase="ready";p.build_button.disabled=false;p.build_button.text="Build smooth road"
		p.status.text="Smooth preview ready · end height %.2f m. Builds in sections; no terrain undo." % points[-1].y
	elif phase=="building" and ticket<0 and not terrain.pending_edit:
		if world.loading_active or world.shutdown_requested or world.world_vehicle.driving:cancel("Road construction interrupted; completed sections remain.");return
		if section==points.size()-1:
			p.register_prepared_street({"paving_segments":1,"street_ends":PackedVector3Array([points[0],points[-1]]),"street_width":p.width.value*2},terrain.epoch)
			phase="complete";p.status.text="Smooth road completed · F5 saves terrain and entrances.";return
		var a:=points[section];var b:=points[section+1]
		var span:=Vector2(b.x-a.x,b.z-a.z).length();var pad: float=0.25*(span+p.width.value)
		var lo:=a.min(b)-Vector3(p.width.value,p.depth.value+pad,p.width.value)
		var hi:=a.max(b)+Vector3(p.width.value,p.clearance.value+pad,p.width.value)
		var error: String=world._road_protection_error(AABB(lo,hi-lo))
		if not error.is_empty():cancel(error+" Completed sections remain.");return
		if not terrain.construct_curved_road_bed(a,b,fitted.coefficients,section,p.width.value,p.depth.value,p.clearance.value):cancel("Road section rejected; completed sections remain.");return
		ticket=terrain.edit_ticket
func _exit_tree() -> void:
	if worker!=null:worker.wait_to_finish();worker=null
