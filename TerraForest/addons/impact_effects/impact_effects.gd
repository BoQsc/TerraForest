# SPDX-License-Identifier: 0BSD
extends Node3D
# Optional presentation adapter. Godot's native GPU particle system owns all
# particle integration; this node runs only on hits, settings and worker replies.
const POOL_LIMIT:=8
const PARTICLES:=48
const PALETTE={"metal":Color("ffae48"),"soil":Color("705039"),"stone":Color("90918c"),"brick":Color("995744"),"concrete":Color("a7a39a"),"wood":Color("a17b4e"),"asphalt":Color("444746"),"iron":Color("697473"),"copper":Color("946c4b"),"foliage":Color("687c45"),"sand":Color("bea779"),"snow":Color("dbe2e0")}
var game:Node
var enabled:=true
var breakup_enabled:=true
var settings_path:String=ProjectSettings.get_setting("terraforest/impact_effects_settings_path","user://impact_effects.cfg")
var pool:Array[GPUParticles3D]=[]
var meshes:Dictionary={}
var sample:Dictionary={}
var sample_token:=700000000
var emitted_events:=0
var dropped_events:=0
var last_event:Dictionary={}
signal settings_changed

func attach(world:Node)->void:
	game=world
	if not settings_path.is_empty():
		var config:=ConfigFile.new()
		if config.load(settings_path)==OK:
			enabled=config.get_value("effects","enabled",true)==true
			breakup_enabled=config.get_value("effects","breakup",true)==true
	game.world_attack.impact_preparing.connect(prepare_contact)
	game.world_attack.contact_effect.connect(contact)
	game.terrain.density_ray_received.connect(receive_sample)

func set_enabled(value:bool,persist:=true)->void:
	enabled=value
	if not enabled:
		sample={};sample_token+=1
		for emitter in pool:emitter.hide();emitter.emitting=false;emitter.queue_free()
		pool.clear()
	if persist:save_settings()
	settings_changed.emit()

func set_breakup_enabled(value:bool,persist:=true)->void:
	breakup_enabled=value
	if persist:save_settings()
	settings_changed.emit()

func save_settings()->void:
	if settings_path.is_empty():return
	var config:=ConfigFile.new();config.set_value("effects","enabled",enabled);config.set_value("effects","breakup",breakup_enabled);config.save(settings_path)

func prepare_contact(from:Vector3,to:Vector3)->void:
	if not enabled:return
	sample={};sample_token+=1
	# Optional bounded prefetch during windup. A late/stale result never delays
	# the contact or authorizes an edit; unknown surfaces use a small fallback.
	game.terrain.request_density_ray(from,to,sample_token,32,true)

func receive_sample(reply:Dictionary)->void:
	if enabled and reply.get("token") == sample_token and reply.get("status")=="hit" and reply.has("surface_material"):sample=reply

func material_for(target:Dictionary)->String:
	match target.get("kind",""):
		"block":return ["brick","wood","concrete","metal"][clampi(int(target.get("material_id",0)),0,3)]
		"vehicle":return "metal"
		"tree":return "wood"
		"cover":return "stone" if target.get("species",0)==0 else ("wood" if target.get("species",0) in [6,7,8] else "foliage")
		"model":
			var asset:String=target.get("asset","")
			if "metal" in asset or "floor_panel" in asset:return "metal"
			if "concrete" in asset or "doorway" in asset:return "concrete"
			return "wood" if target.get("material")=="wood" else "stone"
		"terrain":
			if not sample.is_empty() and sample.epoch==game.terrain.epoch and sample.revision==game.terrain.native_revision and sample.position.distance_squared_to(target.position)<.2025:
				var material:int=sample.surface_material
				if material!=0:return {1:"stone",2:"wood",3:"metal",4:"asphalt",8:"iron",9:"copper",10:"soil"}.get(material,"stone")
				if sample.get("surface_depth",0.0)>1.5 or target.normal.y<.65:return "stone"
				var p:Vector3=target.position
				if game.terrain.backend.world_generator>=7:
					if p.y>175 and target.normal.y>.8:return "snow"
					if game.terrain.backend.world_generator==19 and p.y<45 and minf(minf(p.x,p.z),minf(2000-p.x,2000-p.z))<150:return "sand"
					return "soil"
				return "soil" if p.x<1000 and p.z>=1000 else ("stone" if p.x<1000 else ("sand" if p.z>=1000 else "snow"))
			return "soil" if target.normal.y>.65 else "stone"
	return ""

func contact(target:Dictionary)->void:
	if not enabled or not target.has("position") or not target.has("normal"):return
	var material:=material_for(target)
	if material.is_empty():return
	burst(target.position,target.normal,material,target.get("destroyed",false) and breakup_enabled)

func burst(point:Vector3,normal:Vector3,material:String,broken:=false)->bool:
	if not enabled or not PALETTE.has(material) or not point.is_finite() or not normal.is_finite() or normal.length_squared()<.25:return false
	var emitter:GPUParticles3D
	for candidate in pool:
		if not candidate.get_meta("busy",false):emitter=candidate;break
	if emitter==null:
		if pool.size()>=POOL_LIMIT:dropped_events+=1;return false
		emitter=GPUParticles3D.new();emitter.emitting=false;emitter.one_shot=true;emitter.explosiveness=1.0;emitter.amount=PARTICLES
		emitter.local_coords=false;emitter.fixed_fps=60;emitter.interpolate=true;emitter.fract_delta=true
		emitter.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;emitter.visibility_aabb=AABB(Vector3(-3,-3,-3),Vector3(6,6,6))
		var process:=ShaderMaterial.new();process.shader=preload("res://addons/impact_effects/motion.gdshader");emitter.process_material=process
		emitter.finished.connect(func():if is_instance_valid(emitter):emitter.set_meta("busy",false);emitter.hide())
		add_child(emitter);pool.append(emitter)
	var spark:=material=="metal"
	var shape:="spark" if spark else ("wood" if material=="wood" else "oval")
	if not meshes.has(shape):
		var mesh:PrimitiveMesh
		if shape=="oval":
			var oval:=SphereMesh.new();oval.radius=.5;oval.height=1.0;oval.radial_segments=8;oval.rings=4;mesh=oval
		else:mesh=BoxMesh.new()
		var render:=ShaderMaterial.new();render.shader=preload("res://addons/impact_effects/fragments.gdshader");render.set_shader_parameter("emission_strength",2.8 if spark else 0.0)
		mesh.material=render;meshes[shape]=mesh
	emitter.draw_pass_1=meshes[shape];emitter.lifetime=.48 if spark else .95
	emitter.amount_ratio=(.85 if broken else .46) if spark else (.75 if broken else .29)
	emitter.global_position=point+normal.normalized()*.035
	var process:ShaderMaterial=emitter.process_material
	process.set_shader_parameter("spark",spark);process.set_shader_parameter("surface_normal",normal.normalized())
	process.set_shader_parameter("tint",PALETTE[material].srgb_to_linear())
	process.set_shader_parameter("piece_scale",Vector3(.0035,.0035,.055) if spark else (Vector3(.015,.018,.06) if shape=="wood" else Vector3(.042,.030,.037)))
	process.set_shader_parameter("breakup",broken)
	process.set_shader_parameter("burst_count",int(ceil(PARTICLES*emitter.amount_ratio)))
	var plane:=Vector4(0,1,0,-point.y);var floor_found:=normal.y>.65
	if floor_found:plane=Vector4(normal.x,normal.y,normal.z,-normal.dot(point))
	if is_instance_valid(game):
		var ray:=PhysicsRayQueryParameters3D.create(emitter.global_position+Vector3.UP*.12,emitter.global_position-Vector3.UP*2.5,7,[game.player.get_rid()])
		var floor_hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(ray)
		if not floor_hit.is_empty() and floor_hit.normal.y>.3:
			var n:Vector3=floor_hit.normal;plane=Vector4(n.x,n.y,n.z,-n.dot(floor_hit.position));floor_found=true
	process.set_shader_parameter("floor_plane",plane);process.set_shader_parameter("floor_enabled",floor_found)
	emitter.set_meta("busy",true);emitter.show();emitter.restart()
	emitted_events+=1;last_event={"material":material,"position":point,"normal":normal,"broken":broken,"count":int(ceil(PARTICLES*emitter.amount_ratio))}
	return true

func statistics()->Dictionary:
	var active:=0
	for emitter in pool:if emitter.get_meta("busy",false):active+=1
	return {"enabled":enabled,"pool":pool.size(),"active":active,"particle_capacity":pool.size()*PARTICLES,"emitted":emitted_events,"dropped":dropped_events}
