# SPDX-License-Identifier: 0BSD
extends "res://tools/preview_pickaxe_fresh.gd"
const OUTPUT="res://reports/item_use_v2"
const CANDIDATE="res://addons/characters/authoring/Human.item_use_v2.res"
var item_library:AnimationLibrary
var hand_samples:Array
var mount_heights:Dictionary={}
var floor_triangles:Dictionary={}
func setup(kind:String)->Dictionary:
	var data:=panel(kind);data.view.equip(0)
	data.view.animation_player.add_animation_library("item_review",item_library)
	for name in item_library.get_animation_list():data.view.clips[String(name)]="item_review/"+String(name)
	for child in data.viewport.get_children():
		if child is Label:child.queue_free()
	for child in data.camera.get_parent().get_children():
		if child is MeshInstance3D and not child.mesh is PlaneMesh:child.queue_free()
	var skeleton:Skeleton3D=data.view.model.find_children("*","Skeleton3D",true,false)[0]
	var attachment:=BoneAttachment3D.new();attachment.bone_name="RightHand";skeleton.add_child(attachment)
	var prop:=MeshInstance3D.new();prop.layers=1<<19;prop.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;attachment.add_child(prop)
	data.prop=prop;data.skeleton=skeleton;data.attachment=attachment
	return data
func item_mesh(index:int)->Mesh:
	if index==0:return load("res://addons/player_runtime/art/consumables/214.res")
	if index==1:return load("res://addons/player_runtime/art/consumables/218.res")
	var box:=BoxMesh.new();box.size=Vector3(.10,.08,.12);box.material=mat(Color("718e9e"));return box
func mount(data:Dictionary,mesh:Mesh)->void:
	data.prop.mesh=mesh
	data.prop.basis=Basis(Vector3.RIGHT,Vector3(0,0,-1),Vector3(0,1,0))
	data.prop.position=Vector3(0,item_library.get_meta("support_center_hand_y"),-mount_height(mesh))
func underside_triangles(mesh:Mesh)->Array:
	if floor_triangles.has(mesh):return floor_triangles[mesh]
	var triangles:Array=[]
	for surface in mesh.get_surface_count():
		var arrays:=mesh.surface_get_arrays(surface);var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in points.size():indices.append(i)
		for i in indices.size()/3:
			var a:=points[indices[i*3]];var b:=points[indices[i*3+1]];var c:=points[indices[i*3+2]]
			var v:=Vector2(b.x-a.x,b.z-a.z);var w:=Vector2(c.x-a.x,c.z-a.z);var determinant:=v.cross(w)
			if absf(determinant)<.00000001:continue
			triangles.append([a,b,c,v,w,determinant])
	floor_triangles[mesh]=triangles;return triangles
func lower_surface(mesh:Mesh,point:Vector2)->float:
	var bottom:=INF
	for triangle:Array in underside_triangles(mesh):
		var delta:=point-Vector2(triangle[0].x,triangle[0].z)
		var u:float=delta.cross(triangle[4])/triangle[5];var v:float=triangle[3].cross(delta)/triangle[5]
		if u<0 or v<0 or u+v>1:continue
		bottom=minf(bottom,triangle[0].y+u*(triangle[1].y-triangle[0].y)+v*(triangle[2].y-triangle[0].y))
	return bottom
func mount_height(mesh:Mesh)->float:
	if mount_heights.has(mesh):return mount_heights[mesh]
	var height:=-INF
	for row:Array in hand_samples:
		var point:=Vector3(float(row[0]),float(row[1]),float(row[2]))
		var bottom:=lower_surface(mesh,Vector2(point.x,point.y-float(item_library.get_meta("support_center_hand_y"))))
		if is_finite(bottom):height=maxf(height,-point.z-bottom)
	if not is_finite(height):height=-float(item_library.get_meta("support_plane_hand_z"))-mesh.get_aabb().position.y
	height+=.0007;mount_heights[mesh]=height;return height
func run()->void:
	item_library=load(CANDIDATE)
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://addons/characters/authoring/Human.item_use_v2.json"));hand_samples=source.support_samples_hand
	DirAccess.make_dir_recursive_absolute(OUTPUT+"/frames");FileAccess.open(OUTPUT+"/.gdignore",FileAccess.WRITE).store_string("")
	var front:=setup("fresh");var side:=setup("side");var close:=setup("side")
	front.viewport.size=Vector2i(960,540);side.viewport.size=Vector2i(640,300);close.viewport.size=Vector2i(640,240)
	side.camera.position=Vector3(1.15,1.60,-1.45);side.camera.fov=40;side.camera.look_at(Vector3(.1,1.37,-.28))
	close.camera.fov=42;close.camera.near=.015
	var canvas:=SubViewport.new();canvas.size=Vector2i(1600,640);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var bg:=ColorRect.new();bg.size=canvas.size;bg.color=Color("1e272d");canvas.add_child(bg)
	label(canvas,"ITEM HOLD / USE - REVISION 02",Vector2(24,12),25,Color("edc798"))
	label(canvas,"First person",Vector2(740,18),20)
	label(canvas,"Body / grip underside",Vector2(1035,18),20)
	var note:=label(canvas,"",Vector2(24,599),21)
	for entry in [[front,Vector2(0,52),Vector2(960,540)],[side,Vector2(960,52),Vector2(640,300)],[close,Vector2(960,352),Vector2(640,240)]]:
		var picture:=TextureRect.new();picture.texture=entry[0].viewport.get_texture();picture.position=entry[1];picture.size=entry[2];canvas.add_child(picture)
	var stills:=OS.get_cmdline_user_args().has("--stills")
	var frames:Array=[0,18,25,45,55,73,100,139,159,169,253,273,283] if stills else range(342)
	var last_item:=-1
	for frame:int in frames:
		var index:=mini(frame/114,2);var elapsed:float=(frame%114)/30.0
		if index!=last_item:
			var mesh:=item_mesh(index)
			for data in [front,side,close]:mount(data,mesh)
			last_item=index
		var clip:="Hold";var cursor:=elapsed-.6
		if elapsed<.6:clip="Equip";cursor=elapsed
		elif elapsed>=1.2 and elapsed<2.8:clip="Use";cursor=elapsed-1.2
		elif elapsed>=2.8:cursor=elapsed-2.8
		for data in [front,side,close]:pose(data.view,"FP_Item_"+clip,cursor)
		var skeleton:Skeleton3D=close.skeleton
		var hand:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
		var point:=hand*Vector3(0,.065,-.02)
		close.camera.position=point+hand.basis.z*.13-hand.basis.y*.23-hand.basis.x*.20
		close.camera.look_at(point)
		note.text="%s / %s / %.2f s / 1x speed / review only - no consumption or rewards"%[["Book","Bread","Neutral object"][index],clip,cursor]
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		var shot:=canvas.get_texture().get_image()
		if not stills:shot.save_png(OUTPUT+"/frames/%03d.png"%frame)
		if frame in [0,18,25,45,55,73,100,139,159,169,253,273,283]:shot.save_png(OUTPUT+"/pose_%03d.png"%frame)
		if frame%60==0:print("ITEM_USE_PREVIEW frame=",frame)
	canvas.free();front.viewport.free();side.viewport.free();close.viewport.free();quit()
