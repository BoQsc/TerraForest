# SPDX-License-Identifier: 0BSD
extends RefCounted
## Original procedural seated pose on the existing licensed human/garment rig.
static func create(parent:Node3D,slots:Array,driver:bool)->Node3D:
	var human:=preload("res://addons/characters/runtime/human_view.gd").new()
	parent.add_child(human);human.set_process(false);human.set_third_person(true)
	human.clothing.set_slots(slots)
	human.position=Vector3(.43 if driver else -.43,-.5,.15);human.rotation=Vector3.ZERO;human.scale=Vector3.ONE*.9
	human.animation_player.play(human.clips["Idle"]);human.animation_player.advance(0);human.animation_player.pause()
	var skeleton:Skeleton3D=human.model.find_children("*","Skeleton3D",true,false)[0]
	for bone:String in ["LeftUpLeg","RightUpLeg"]:_bend(skeleton,bone,Vector3.RIGHT,-PI*.48)
	for bone:String in ["LeftLeg","RightLeg"]:_bend(skeleton,bone,Vector3.RIGHT,PI*.48)
	skeleton.force_update_all_bone_transforms()
	var hips:Vector3=skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
	for side:String in ["Left","Right"]:
		var sign_value:float=1 if side=="Left" else -1
		var hand:Vector3=hips+Vector3(sign_value*.16,.18 if driver else .19,.33 if driver else .28)
		_arm(skeleton,side,hand,Vector3(sign_value,-.3,-.2))
	_seat_fittings(human,driver)
	return human
static func _bend(skeleton:Skeleton3D,name:String,axis:Vector3,angle:float)->void:
	var index:=skeleton.find_bone(name)
	if index<0:return
	var local_axis:Vector3=skeleton.get_bone_global_rest(index).basis.inverse()*axis
	skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index)*Quaternion(local_axis.normalized(),angle))

static func _arm(skeleton:Skeleton3D,side:String,target:Vector3,pole:Vector3)->void:
	var upper:=skeleton.find_bone(side+"Arm");var lower:=skeleton.find_bone(side+"ForeArm");var hand:=skeleton.find_bone(side+"Hand")
	if upper<0 or lower<0 or hand<0:return
	var root:Vector3=skeleton.get_bone_global_pose(upper).origin
	var elbow:Vector3=skeleton.get_bone_global_pose(lower).origin
	var wrist:Vector3=skeleton.get_bone_global_pose(hand).origin
	var a:=root.distance_to(elbow);var b:=elbow.distance_to(wrist)
	var axis:Vector3=(target-root).normalized();var distance:=clampf(root.distance_to(target),absf(a-b)+.001,a+b-.001)
	var along:float=(a*a-b*b+distance*distance)/(2*distance)
	var bend:Vector3=(pole-axis*pole.dot(axis)).normalized()
	var joint:Vector3=root+axis*along+bend*sqrt(maxf(0,a*a-along*along))
	_aim(skeleton,upper,lower,joint)
	_aim(skeleton,lower,hand,root+axis*distance)

static func _aim(skeleton:Skeleton3D,bone:int,child:int,target:Vector3)->void:
	var pose:Transform3D=skeleton.get_bone_global_pose(bone)
	var from:Vector3=(skeleton.get_bone_global_pose(child).origin-pose.origin).normalized()
	var desired:Quaternion=Quaternion(from,(target-pose.origin).normalized())*pose.basis.get_rotation_quaternion()
	var parent:=skeleton.get_bone_parent(bone)
	if parent>=0:desired=skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion().inverse()*desired
	skeleton.set_bone_pose_rotation(bone,desired);skeleton.force_update_all_bone_transforms()

static func _seat_fittings(human:Node3D,driver:bool)->void:
	# Small original cabin fittings, visual only; the chassis remains the sole
	# collider. Parent to this occupant so ordinary pooled car bodies stay clean.
	var fittings:=Node3D.new();human.add_child(fittings);fittings.transform=human.transform.affine_inverse()
	var material:=StandardMaterial3D.new();material.albedo_color=Color("20272a");material.roughness=.9
	var x:float=.43 if driver else -.43
	for item:Array in [[Vector3(.5,.12,.5),Vector3(x,.29,.13)],[Vector3(.5,.5,.12),Vector3(x,.61,-.12)]]:
		var box:=BoxMesh.new();box.size=item[0];box.material=material
		var view:=MeshInstance3D.new();view.mesh=box;fittings.add_child(view);view.position=item[1]
	if driver:
		var ring:=TorusMesh.new();ring.inner_radius=.13;ring.outer_radius=.155;ring.rings=16;ring.ring_segments=8;ring.material=material
		var wheel:=MeshInstance3D.new();wheel.mesh=ring;fittings.add_child(wheel);wheel.position=Vector3(x,.55,.437);wheel.rotation.x=PI/2
		var spoke:=BoxMesh.new();spoke.size=Vector3(.27,.025,.025);spoke.material=material
		var hub:=MeshInstance3D.new();hub.mesh=spoke;fittings.add_child(hub);hub.position=wheel.position
