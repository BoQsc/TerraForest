# SPDX-License-Identifier: 0BSD
extends RefCounted
## Diagnostic only: exact opaque native block meshes, no proxy simplification.
## Readbacks and occluder construction happen outside measured phases.
var sources:Array[Dictionary]=[]
var occluders:Array[OccluderInstance3D]=[]
var blocks:Node3D
var viewport:Viewport
var original_enabled:=false
var invalidated:=false
var triangles:=0
var vertices:=0
var native:=false
var boulder_flags:Array[Dictionary]=[]
var camera:Camera3D
var camera_pose:Transform3D
var camera_fov:=0.0
var control_off:=false
var fractures:Node3D
func invalidate()->void:
	invalidated=true
	if is_instance_valid(viewport):viewport.use_occlusion_culling=false
func prepare(game:Node)->void:
	blocks=game.structures.blocks;viewport=game.get_viewport()
	fractures=game.ground_cover.fractures;control_off="--trace-occlusion-control-off" in OS.get_cmdline_user_args()
	camera=game.camera;camera_pose=camera.global_transform;camera_fov=camera.fov
	if "--trace-occlusion-ignore-boulders" in OS.get_cmdline_user_args():
		for node:Node in game.ground_cover.fractures.get_children():
			if node is GeometryInstance3D:
				boulder_flags.append({"node":node,"value":node.ignore_occlusion_culling});node.ignore_occlusion_culling=true
	original_enabled=viewport.use_occlusion_culling
	blocks.changed.connect(invalidate)
	native=blocks.has_method("occlusion_stats") and blocks.occlusion_stats().get("enabled",false)
	for child:Node in blocks.get_children():
		if not child is MeshInstance3D or not child.is_visible_in_tree() or not child.mesh is ArrayMesh:continue
		var mesh:ArrayMesh=child.mesh
		if native:
			var owned:=child.get_node_or_null("BlockOccluder")
			if owned==null or not owned.is_visible_in_tree():continue
			sources.append({"node":child,"mesh":mesh,"transform":child.global_transform})
			vertices+=owned.occluder.vertices.size();triangles+=owned.occluder.indices.size()/3
			continue
		var bounds:AABB=child.global_transform*child.get_aabb()
		if game.player.global_position.clamp(bounds.position,bounds.end).distance_to(game.player.global_position)>96:continue
		var points:=PackedVector3Array();var indices:=PackedInt32Array()
		for surface:int in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:continue
			var arrays:Array=mesh.surface_get_arrays(surface)
			var base:int=points.size();var incoming:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var faces:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			if faces.is_empty():
				for index:int in incoming.size():indices.append(base+index)
			else:
				for index:int in faces:indices.append(base+index)
			points.append_array(incoming)
		if indices.is_empty():continue
		var shape:=ArrayOccluder3D.new();shape.set_arrays(points,indices)
		var node:=OccluderInstance3D.new();node.occluder=shape
		blocks.add_child(node);node.transform=child.transform
		occluders.append(node);vertices+=points.size();triangles+=indices.size()/3
		sources.append({"node":child,"mesh":mesh,"transform":child.global_transform})
func unchanged()->bool:
	if invalidated:return false
	if camera.global_position.distance_to(camera_pose.origin)>.01 or not camera.global_basis.is_equal_approx(camera_pose.basis) or not is_equal_approx(camera.fov,camera_fov):return false
	for source:Dictionary in sources:
		if not is_instance_valid(source.node) or source.node.mesh!=source.mesh or source.node.global_transform!=source.transform or not source.node.is_visible_in_tree():return false
	return true
func set_enabled(enabled:bool)->void:viewport.use_occlusion_culling=enabled and not invalidated and not control_off
func boulder_state()->Array[Dictionary]:
	var rows:Array[Dictionary]=[]
	for node:Node in fractures.get_children():
		if not node is MultiMeshInstance3D:continue
		var multimesh:MultiMesh=node.multimesh
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(multimesh.buffer.to_byte_array())
		var row:Dictionary={"path":str(node.get_path()),"count":multimesh.visible_instance_count,"buffer_sha256":hash.finish().hex_encode(),"near_poses":[]}
		for index:int in mini(8,multimesh.visible_instance_count):
			var pose:=multimesh.get_instance_transform(index)
			row.near_poses.append({"basis_x":pose.basis.x,"basis_y":pose.basis.y,"basis_z":pose.basis.z,"origin":pose.origin,"custom":multimesh.get_instance_custom_data(index)})
		if node.material_override is ShaderMaterial:
			row.eye=node.material_override.get_shader_parameter("cover_eye");row.projection=node.material_override.get_shader_parameter("horizon_projection")
		rows.append(row)
	return rows
func release()->void:
	if is_instance_valid(blocks) and blocks.changed.is_connected(invalidate):blocks.changed.disconnect(invalidate)
	if is_instance_valid(viewport):viewport.use_occlusion_culling=original_enabled
	for node:OccluderInstance3D in occluders:node.free()
	for entry:Dictionary in boulder_flags:
		if is_instance_valid(entry.node):entry.node.ignore_occlusion_culling=entry.value
	boulder_flags.clear()
	occluders.clear();sources.clear()
func run(host:SceneTree,game:Node,output:String,prefix:String="occlusion")->Dictionary:
	host.label=prefix+"_preparation";prepare(game)
	var result:Dictionary={"sources":sources.size(),"triangles":triangles,"vertices":vertices,"original_enabled":original_enabled,"unchanged":true,"phases":[]}
	result.native=native
	result.camera=camera_pose;result.camera_fov=camera_fov;result.boulders_ignored=not boulder_flags.is_empty()
	result.control_off=control_off
	result.boulder_batches=[]
	for node:Node in game.ground_cover.fractures.get_children():
		if node is MultiMeshInstance3D:
			result.boulder_batches.append({"path":str(node.get_path()),"world_transform":node.global_transform,"node_bounds":node.get_aabb(),"custom_bounds":node.multimesh.custom_aabb,"mesh_bounds":node.multimesh.mesh.get_aabb(),"visible_count":node.multimesh.visible_instance_count})
	if native:result.native_before=blocks.occlusion_stats()
	for phase:String in ["off_a","on_b","on_b2","off_a2"]:
		host.label=prefix+"_warmup";set_enabled(phase.begins_with("on"))
		await host.wait_for(func():return false,2)
		host.label=prefix+"_"+phase
		await host.wait_for(func():return false,5)
		result.unchanged=result.unchanged and unchanged()
		result.phases.append({"phase":phase,"enabled":viewport.use_occlusion_culling})
		host.label=prefix+"_screenshot";await RenderingServer.frame_post_draw
		result.phases[-1].boulders=boulder_state()
		result.phases[-1].camera=viewport.get_camera_3d().get_camera_transform()
		var began:=Time.get_ticks_usec()
		viewport.get_texture().get_image().save_png(output.path_join(prefix+"_"+phase+".png"))
		result.phases[-1].screenshot_us=Time.get_ticks_usec()-began
		# Keep synchronous readback in the screenshot phase, including the next
		# observed draw interval. In particular, do not charge it to a later save.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	if native:result.native_after=blocks.occlusion_stats()
	release();result.ok=result.unchanged and result.sources>0;return result
