extends RefCounted

const LAYER=1<<18
const REACH=64.0
const RECEIVER_RADIUS=3.0
const LIMIT=96
var view:Camera3D
var lights:Dictionary={}
var active:=false
var mirrors:Dictionary={}
var next_refresh:=0
var last_position:=Vector3.INF
var refresh_ms:=0.0
var morph_mirrors:Array[MeshInstance3D]=[]

func set_active(value:bool)->void:
	if active==value:return
	active=value;next_refresh=0
	for mirror:Variant in mirrors.values():
		if is_instance_valid(mirror):mirror.visible=active

func refresh()->void:
	if not active or DisplayServer.get_name()=="headless":return
	var now:=Time.get_ticks_msec()
	if now<next_refresh and last_position.distance_squared_to(view.global_position)<16.0:return
	next_refresh=now+200;last_position=view.global_position
	var started:=Time.get_ticks_usec()
	var targets:PackedVector3Array=[]
	var area:=AABB(last_position-Vector3.ONE*RECEIVER_RADIUS,Vector3.ONE*RECEIVER_RADIUS*2)
	for entry:Dictionary in lights.values():
		var light:Light3D=entry.node.get_ref()
		if not is_instance_valid(light) or not light.is_visible_in_tree() or not light.shadow_enabled or not (light.shadow_caster_mask&LAYER):continue
		var target:Vector3
		if light is DirectionalLight3D:target=last_position+light.global_basis.z*REACH
		else:
			var reach:float=light.omni_range if light is OmniLight3D else light.spot_range
			if last_position.distance_to(light.global_position)>reach+RECEIVER_RADIUS:continue
			target=light.global_position
		targets.append(target);area=area.expand(target)
	area=area.grow(RECEIVER_RADIUS)
	var candidates:Array[Dictionary]=[]
	for identity in RenderingServer.instances_cull_aabb(area,view.get_world_3d().scenario):
		var source:GeometryInstance3D=instance_from_id(identity) as GeometryInstance3D
		if source==null or not (source is MeshInstance3D or source is MultiMeshInstance3D):continue
		if source.layers&((1<<18)|(1<<19)) or source.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF or not source.is_visible_in_tree():continue
		var bounds:AABB=source.global_transform*source.get_aabb()
		var influence:=bounds.grow(RECEIVER_RADIUS)
		var relevant:=false
		for target in targets:
			if influence.intersects_segment(last_position,target)!=null:relevant=true;break
		if not relevant:continue
		var closest:=last_position.clamp(bounds.position,bounds.end)
		candidates.append({"source":source,"distance":last_position.distance_squared_to(closest)})
	candidates.sort_custom(func(first:Dictionary,second:Dictionary)->bool:
		return first.distance<second.distance if first.distance!=second.distance else first.source.get_instance_id()<second.source.get_instance_id())
	var retained:={}
	morph_mirrors.clear()
	for index in mini(LIMIT,candidates.size()):
		var source:GeometryInstance3D=candidates[index].source
		var identity:=source.get_instance_id();retained[identity]=true
		var mirror:GeometryInstance3D=mirrors.get(identity)
		if not is_instance_valid(mirror):
			mirror=MeshInstance3D.new() if source is MeshInstance3D else MultiMeshInstance3D.new()
			mirror.name="FirstPersonShadowCaster";mirror.layers=LAYER
			mirror.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			source.add_child(mirror);mirrors[identity]=mirror
		if source is MeshInstance3D:
			if mirror.mesh!=source.mesh:mirror.mesh=source.mesh
			mirror.skin=source.skin
			var skeleton:=source.get_node_or_null(source.skeleton) as Skeleton3D
			if skeleton!=null:mirror.skeleton=mirror.get_path_to(skeleton)
			for surface in source.mesh.get_surface_count() if source.mesh!=null else 0:mirror.set_surface_override_material(surface,source.get_surface_override_material(surface))
			if mirror.get_blend_shape_count()>0:morph_mirrors.append(mirror)
		else:
			if mirror.multimesh!=source.multimesh:mirror.multimesh=source.multimesh
		mirror.material_override=source.material_override;mirror.material_overlay=source.material_overlay
		mirror.extra_cull_margin=source.extra_cull_margin;mirror.custom_aabb=source.custom_aabb
		mirror.visibility_range_begin=source.visibility_range_begin;mirror.visibility_range_end=source.visibility_range_end
		mirror.visibility_range_begin_margin=source.visibility_range_begin_margin;mirror.visibility_range_end_margin=source.visibility_range_end_margin
		mirror.visibility_range_fade_mode=source.visibility_range_fade_mode;mirror.lod_bias=source.lod_bias
		mirror.visible=true
	for identity:Variant in mirrors.keys():
		if retained.has(identity):continue
		if is_instance_valid(mirrors[identity]):mirrors[identity].queue_free()
		mirrors.erase(identity)
	refresh_ms=(Time.get_ticks_usec()-started)/1000.0

func sync_morphs()->void:
	if not active:return
	for mirror in morph_mirrors:
		if not is_instance_valid(mirror):continue
		var source:MeshInstance3D=mirror.get_parent()
		for shape in mini(source.get_blend_shape_count(),mirror.get_blend_shape_count()):
			var weight:=source.get_blend_shape_value(shape)
			if mirror.get_blend_shape_value(shape)!=weight:mirror.set_blend_shape_value(shape,weight)

func dispose()->void:
	for mirror:Variant in mirrors.values():
		if is_instance_valid(mirror):mirror.queue_free()
	mirrors.clear()
	morph_mirrors.clear()
