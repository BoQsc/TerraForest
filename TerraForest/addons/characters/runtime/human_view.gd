# SPDX-License-Identifier: 0BSD
extends Node3D
## Camera-local presentation. The existing native motor remains the player owner.
signal swing_contact(identity:int)
signal swing_finished(identity:int,cancelled:bool)
const MODEL = preload("res://addons/characters/runtime/assets/Human.r11.glb")
const PLACEMENT = preload("res://addons/characters/runtime/assets/Human.placement.res")
const UNARMED = preload("res://addons/characters/runtime/assets/Human.unarmed.res")
const UNARMED_BODY = preload("res://addons/characters/runtime/assets/Human.unarmed_body.res")
const PICKAXE_DIAGONAL = preload("res://addons/characters/runtime/assets/Human.pickaxe_diagonal.res")
const PICKAXE_PULLBACK = preload("res://addons/characters/runtime/assets/Human.pickaxe_side_pullback.res")
const PICKAXE_FRESH = preload("res://addons/characters/runtime/assets/Human.pickaxe_fresh.res")
const PICKAXE_LOCOMOTION = preload("res://addons/characters/runtime/assets/Human.pickaxe_locomotion.res")
const HAMMER = preload("res://addons/characters/runtime/assets/Human.hammer.res")
const SHOVEL = preload("res://addons/characters/runtime/assets/Human.shovel.res")
const BUCKET = preload("res://addons/characters/runtime/assets/Human.bucket.res")
const BUCKET_MODEL = preload("res://addons/volumetric_water/bucket_model.gd")
const EQUIPMENT = {3:preload("res://addons/characters/runtime/assets/Hammer.glb"),5:preload("res://addons/characters/runtime/assets/Shovel.glb")}
const AUTHORED_TOOLS = [0,1,2,3,5,401]
const HIDDEN_SURFACE = preload("res://addons/characters/runtime/hidden_surface.gdshader")
var model: Node3D
var animation_player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var body_mesh: MeshInstance3D
var original_body_mesh: Mesh
var unarmed_body_mesh: ArrayMesh
var clips: Dictionary = {}
var current := 0
var active_clip := ""
var action_remaining := 0.0
var placement_active := false
var swing_identity:=0
var swing_clip:=""
var contact_seconds:=0.0
var contact_sent:=false
# Contact poses in the authored clips (seconds on the animation timeline).
const CONTACTS={"FP_Unarmed_Punch":28.0/60.0,"FP_Pickaxe_Fresh_Swing":50.0/60.0,"FP_Pickaxe_SidePullback_Swing":32.0/60.0,"FP_Pickaxe_Diagonal_Swing":32.0/60.0,"FP_Pickaxe_Swing":41.0/60.0,"FP_Axe_Swing":34.0/60.0,"FP_Hammer_Swing":28.0/60.0,"FP_Shovel_Swing":34.0/60.0,"FP_Place_Relaxed":13.0/30.0}
var body: CharacterBody3D
var third_person:=false
var bucket_fill:=0.0
var bucket_previous_fill:=0.0
var bucket_display_fill:=0.0
var bucket_water:MeshInstance3D
var face_surfaces:Array=[]
var face_meshes:Dictionary={}
@export var diagonal_pickaxe := true
@export_enum("fresh", "pullback", "diagonal") var pickaxe_swing := "fresh"

func _ready() -> void:
	# Inverse of the source viewer's FP camera (0, 1.65, .03), facing +Z.
	position = Vector3(0, -1.65, 0.03)
	rotation.y = PI
	model = MODEL.instantiate()
	add_child(model)
	# Rigid tools share the existing weapon bones and the same skinned hands.
	var skeleton:=model.find_children("*","Skeleton3D",true,false)[0] as Skeleton3D
	for item:int in EQUIPMENT:
		var attachment:=BoneAttachment3D.new()
		attachment.bone_name="Weapon_Axe" if item==3 else "Weapon_Pickaxe"
		skeleton.add_child(attachment)
		var equipment:Node3D=EQUIPMENT[item].instantiate()
		attachment.add_child(equipment)
		# GLB mesh coordinates already include Blender's Y-up conversion. Bone
		# attachments carry that conversion too; undo the rest basis once.
		equipment.transform=skeleton.get_bone_global_rest(skeleton.find_bone(attachment.bone_name)).affine_inverse()*equipment.transform
	var bail_attachment:=BoneAttachment3D.new();bail_attachment.bone_name="Weapon_Axe";skeleton.add_child(bail_attachment)
	var bail:=MeshInstance3D.new();bail.name="Equipment_Bucket_Bail";bail.mesh=BUCKET_MODEL.BAIL;bail_attachment.add_child(bail)
	bail.transform=skeleton.get_bone_global_rest(skeleton.find_bone("Weapon_Axe")).affine_inverse()
	var bucket_attachment:=BoneAttachment3D.new();bucket_attachment.bone_name="Weapon_Pickaxe";skeleton.add_child(bucket_attachment)
	var bucket_root:=Node3D.new();bucket_attachment.add_child(bucket_root)
	bucket_root.transform=skeleton.get_bone_global_rest(skeleton.find_bone("Weapon_Pickaxe")).affine_inverse()
	var bucket:=MeshInstance3D.new();bucket.name="Equipment_Bucket";bucket.mesh=BUCKET_MODEL.HELD;bucket_root.add_child(bucket)
	bucket_water=MeshInstance3D.new();bucket_water.name="Equipment_Bucket_Water"
	var water_disk:=CylinderMesh.new();water_disk.top_radius=.135;water_disk.bottom_radius=.135;water_disk.height=.001;water_disk.radial_segments=96
	var water_material:=StandardMaterial3D.new();water_material.albedo_color=Color("284d58");water_material.roughness=.15;water_material.metallic=.15
	water_material.clearcoat_enabled=true;water_material.clearcoat=.85;water_material.clearcoat_roughness=.1
	water_disk.material=water_material;bucket_water.mesh=water_disk;bucket_root.add_child(bucket_water)
	_collect(model)
	animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_player.add_animation_library("placement", PLACEMENT)
	animation_player.add_animation_library("unarmed", UNARMED)
	animation_player.add_animation_library("pickaxe_diagonal", PICKAXE_DIAGONAL)
	animation_player.add_animation_library("pickaxe_pullback", PICKAXE_PULLBACK)
	animation_player.add_animation_library("pickaxe_fresh", PICKAXE_FRESH)
	animation_player.add_animation_library("pickaxe_locomotion", PICKAXE_LOCOMOTION)
	animation_player.add_animation_library("hammer", HAMMER)
	animation_player.add_animation_library("shovel", SHOVEL)
	animation_player.add_animation_library("bucket", BUCKET)
	for clip in animation_player.get_animation_list():
		clips[String(clip).get_slice("/", String(clip).get_slice_count("/") - 1)] = clip
	equip(current)

func _collect(node: Node) -> void:
	if node is AnimationPlayer:
		animation_player = node
	if node is MeshInstance3D:
		meshes.append(node)
		if String(node.name)=="Human_Body":
			body_mesh=node;original_body_mesh=node.mesh
			unarmed_body_mesh=UNARMED_BODY.duplicate()
			for surface in original_body_mesh.get_surface_count():
				unarmed_body_mesh.surface_set_material(surface,original_body_mesh.surface_get_material(surface))
		node.layers=1<<19 # Player presentation, independently culled near the camera.
		face_meshes[node.get_instance_id()]=node.visible
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The source body combines skin and head in one skinned mesh. Hide only
		# its head/mouth surfaces so the FP camera cannot see inside the face.
		for index in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(index)
			if material != null and ("Human.Head" in material.resource_name or "Human.Mouth" in material.resource_name):
				var hidden := ShaderMaterial.new();hidden.shader = HIDDEN_SURFACE
				node.set_surface_override_material(index, hidden)
				face_surfaces.append([node,index,hidden])
	for child in node.get_children():
		_collect(child)

func set_third_person(value:bool)->void:
	if third_person==value:return
	third_person=value
	for entry:Array in face_surfaces:entry[0].set_surface_override_material(entry[1],null if value else entry[2])
	for mesh:MeshInstance3D in meshes:mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if value else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sync_equipment()

func equip(item: int, water_ml:int=-1) -> void:
	cancel_swing()
	var previous_bucket_fill:=bucket_fill
	var previous_item:=current
	bucket_fill=clampf((item-401)/10.0,0,1) if item>=401 and item<=411 else 0.0
	if item>=401 and item<=411 and water_ml>=0:bucket_fill=clampf(water_ml/1000000.0,0,1)
	bucket_previous_fill=previous_bucket_fill if previous_item==401 else bucket_fill
	if item>=401 and item<=411:item=401
	current = item
	action_remaining = 0.0
	placement_active = false
	if model == null:
		return
	_sync_equipment()
	_play(_motion_clip("Idle"))

func _sync_equipment() -> void:
	if body_mesh!=null:
		var selected:Mesh=unarmed_body_mesh if current in [0,401] else original_body_mesh
		if body_mesh.mesh!=selected:body_mesh.mesh=selected
	for mesh in meshes:
		var label := String(mesh.name).to_lower().replace("_", ".")
		if label.begins_with("equipment."):
			mesh.visible = not placement_active and ((current == 1 and label.contains("pickaxe")) or (current == 2 and label.contains("axe") and not label.contains("pickaxe")) or (current==3 and label.contains("hammer")) or (current==5 and label.contains("shovel")) or (current==401 and label.contains("bucket")))
		elif label.begins_with("hair.") or label.begins_with("brows.") or label.begins_with("eye") or label.begins_with("upper_lashes"):
			mesh.visible=third_person and face_meshes.get(mesh.get_instance_id(),false)
	_sync_bucket_water()

func _sync_bucket_water()->void:
	if bucket_water==null:return
	bucket_display_fill=bucket_fill
	# Inventory already contains the confirmed result. Only the displayed fill
	# waits for the tip/dip beat; this cannot transfer, consume or grant water.
	if current==401 and action_remaining>0 and not placement_active:
		var time:=animation_player.current_animation_position
		if active_clip=="FP_Bucket_Pour":bucket_display_fill=lerpf(bucket_previous_fill,bucket_fill,smoothstep(.60,1.00,time))
		elif active_clip=="FP_Bucket_Scoop":bucket_display_fill=lerpf(bucket_previous_fill,bucket_fill,smoothstep(1.65,1.90,time))
	bucket_water.visible=current==401 and bucket_display_fill>.001 and not placement_active
	bucket_water.position.y=lerpf(-.412,-.252,bucket_display_fill)
	var radius:=lerpf(.108,.137,bucket_display_fill)/.135
	bucket_water.scale=Vector3(radius,1,radius)

func _motion_clip(action: String) -> String:
	if current==401:return "FP_Bucket_"+action if clips.has("FP_Bucket_"+action) else "FP_Bucket_Idle"
	if current==0:
		if third_person and action in ["Walk","Run","Jump"]:return action
		return "FP_Unarmed_Punch" if action=="Swing" else "FP_Unarmed_Idle"
	if current == 1 and diagonal_pickaxe and pickaxe_swing == "fresh":
		# Movement clips share the approved hold's exact hand-to-shaft transforms.
		return "FP_Pickaxe_Fresh_" + action if clips.has("FP_Pickaxe_Fresh_" + action) else "FP_Pickaxe_Fresh_Idle"
	if current == 1 and diagonal_pickaxe and action == "Swing" and pickaxe_swing == "pullback":
		return "FP_Pickaxe_SidePullback_Swing"
	if current == 1 and diagonal_pickaxe and clips.has("FP_Pickaxe_Diagonal_" + action):
		return "FP_Pickaxe_Diagonal_" + action
	var prefix:String={1:"FP_Pickaxe_",2:"FP_Axe_",3:"FP_Hammer_",5:"FP_Shovel_"}.get(current,"")
	return prefix + action if clips.has(prefix + action) else action

func _play(clip: String, once: bool = false) -> void:
	if not clips.has(clip):
		return
	if once or active_clip != clip or not animation_player.is_playing():
		animation_player.play(clips[clip], 0.10)
		active_clip = clip
	if once:
		animation_player.seek(0,true)
		action_remaining = animation_player.get_animation(clips[clip]).length

func swing_profile()->Dictionary:
	var clip:=_motion_clip("Swing")
	if animation_player==null or not clips.has(clip) or not CONTACTS.has(clip):return {}
	var duration:float=animation_player.get_animation(clips[clip]).length
	return {"clip":clip,"contact":minf(CONTACTS[clip],duration),"duration":duration}
func swing(identity:int=0) -> bool:
	if action_remaining > 0.0:
		return false
	var profile:=swing_profile()
	if profile.is_empty():return false
	swing_identity=identity;swing_clip=profile.clip;contact_seconds=profile.contact;contact_sent=false
	_play(swing_clip,true)
	return true
func cancel_swing()->void:
	if swing_clip.is_empty():return
	var identity:=swing_identity
	swing_identity=0;swing_clip="";action_remaining=0;contact_sent=false
	if animation_player!=null:_play(_motion_clip("Idle"))
	swing_finished.emit(identity,true)

func place() -> bool:
	if action_remaining > 0.0 or not is_visible_in_tree():
		return false
	placement_active = true
	_sync_equipment()
	_play("FP_Place_Relaxed", true)
	return true

func bucket_use(pouring:bool)->bool:
	if current!=401 or action_remaining>0 or not is_visible_in_tree():return false
	# Presentation follows the existing confirmed transfer; no attack/contact
	# event can grant water, change inventory or mutate terrain from this clip.
	_play("FP_Bucket_Pour" if pouring else "FP_Bucket_Scoop",true)
	_sync_bucket_water()
	return true

func _process(delta: float) -> void:
	animation_player.active = is_visible_in_tree()
	if not animation_player.active:
		cancel_swing()
		return
	if action_remaining > 0.0:
		if not swing_clip.is_empty() and animation_player.assigned_animation!=clips[swing_clip]:cancel_swing();return
		var step:=delta
		var speed:float=animation_player.get_playing_speed()
		var position:float=animation_player.current_animation_position
		# Draw the actual contact pose on the impact frame, even after a long frame.
		if not swing_clip.is_empty() and not contact_sent and speed>0 and position+step*speed>=contact_seconds:
			step=maxf(0,(contact_seconds-position)/speed)
		animation_player.advance(step)
		if not swing_clip.is_empty() and not contact_sent and animation_player.current_animation_position+0.00001>=contact_seconds:
			contact_sent=true
			swing_contact.emit(swing_identity)
		# A hit may break/equip a tool and cancel this action inside the signal.
		if action_remaining<=0:return
		var length:float=animation_player.get_animation(animation_player.assigned_animation).length
		action_remaining=maxf(0,length-animation_player.current_animation_position) if animation_player.is_playing() else 0.0
		_sync_bucket_water()
		if action_remaining > 0.0:
			return
		if not swing_clip.is_empty():
			var identity:=swing_identity;swing_identity=0;swing_clip=""
			swing_finished.emit(identity,false)
	if placement_active:
		placement_active = false
		_sync_equipment()
	var motion := "Idle"
	# Empty hands stay at rest between deliberate actions. Generic full-body
	# Walk/Run/Jump clips can raise the unarmed hand while merely moving.
	# Authored tools use their own locomotion presentation.
	if (third_person or current in [1, 2, 3, 5, 401]) and is_instance_valid(body):
		var speed := Vector2(body.velocity.x, body.velocity.z).length()
		if not body.is_on_floor() and absf(body.velocity.y) > 0.5:
			motion = "Jump"
		elif speed > 0.15:
			# Native ground speeds are 5.5 walking / 9.9 sprinting. Preserve the
			# other tools' cadence while selecting pickaxe/bucket walks correctly.
			var run_speed:=6.5 if current==401 or (current==1 and diagonal_pickaxe and pickaxe_swing=="fresh") else 5.0
			motion = "Run" if speed > run_speed else "Walk"
	_play(_motion_clip(motion))
	animation_player.advance(delta)
