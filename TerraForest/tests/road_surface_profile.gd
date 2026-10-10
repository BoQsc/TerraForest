# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703,4]))
	var authored:=true
	var curved: bool="--curved" in OS.get_cmdline_user_args()
	var coefficients:=PackedFloat64Array()
	for i in 4:coefficients.append_array(PackedFloat64Array([0,0.256,-4+0.512*i,85.96295-4*i+0.256*i*i]))
	if curved:
		var a:=Vector3(576,coefficients[3],1310);var b:=Vector3(592,coefficients[7],1310)
		var valid:=Codec.curved_road_bed(a,b,4,4,16,coefficients,0)
		var before: Dictionary=core.geometry_cache_key(576,1296,64,1)
		for defect in 3:
			var invalid:=valid.duplicate()
			if defect==0:invalid.encode_float(56,NAN)
			elif defect==1:invalid.encode_u32(48,65)
			else:invalid.encode_float(56+7*4,100)
			authored=not Codec.reply_ok(core.execute(invalid)) and authored
		authored=core.geometry_cache_key(576,1296,64,1)==before and authored
	for i in 4:
		var a:=Vector3(576+i*16,85.96295-i*4,1310)
		var b:=a+Vector3(16,-4,0)
		if curved:
			a.y=coefficients[i*4+3];b.y=a.y+coefficients[i*4+1]+coefficients[i*4+2]
		var packet:=Codec.curved_road_bed(a,b,4,4,16,coefficients,i) if curved else Codec.road_bed(a,b,4,4,16)
		authored=Codec.reply_ok(core.execute(packet)) and authored
	var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
	var faces:=PackedVector3Array()
	for x in [576,592,608,624]:
		for z in [1296,1312]:
			for y in [32,64,96]:
				var mesh: Dictionary=Codec.decode_mesh(core.build_owned_region(x,z,16,1,y,y+32,epoch))
				if mesh.has("error"):push_error(str(mesh));quit(1);return
				faces.append_array(mesh.faces)
	var body:=StaticBody3D.new();body.collision_layer=1
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
	var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision);root.add_child(body)
	await physics_frame;await physics_frame
	var rows: Array=[];var missing:=0;var max_error:=0.0;var max_angle:=0.0;var max_step_error:=0.0
	var previous:=NAN
	var expected_normal:=Vector3(0.25,1,0).normalized()
	for i in 385:
		var x:=584.0+i*0.125;var expected:=85.96295-(x-576)*0.25
		if curved:
			expected+=0.001*(x-576)*(x-576)
			expected_normal=Vector3(0.25-0.002*(x-576),1,0).normalized()
		var ray:=PhysicsRayQueryParameters3D.create(Vector3(x,expected+2,1310),Vector3(x,expected-2,1310),1)
		var hit:=root.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():missing+=1;continue
		var height: float=hit.position.y;var angle: float=rad_to_deg(hit.normal.angle_to(expected_normal))
		max_error=maxf(max_error,absf(height-expected));max_angle=maxf(max_angle,angle)
		if is_finite(previous):max_step_error=maxf(max_step_error,absf(height-previous+0.03125-(0.001*((x-576)*(x-576)-(x-576-0.125)*(x-576-0.125)) if curved else 0.0)))
		previous=height
		rows.append({"x":x,"height":height,"expected":expected,"normal":hit.normal,"angle_degrees":angle})
	var passed:=authored and missing==0 and max_error<=0.03 and max_angle<=2 and max_step_error<=0.02
	var result:={"curved":curved,"passed":passed,"failures":0 if passed else 1,"authored":authored,"missing":missing,"max_height_error":max_error,"max_normal_error_degrees":max_angle,"max_step_error":max_step_error,"samples":rows,"scope":"Native generator-4 graded road collision, 25% constant grade across four joined sections; 0.125 m ray spacing. No vehicle suspension."}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/road_surface_profile.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("ROAD_SURFACE_PROFILE ",passed," height_error=",max_error," normal_error=",max_angle," step_error=",max_step_error," missing=",missing)
	body.free();quit(0 if passed else 1)
