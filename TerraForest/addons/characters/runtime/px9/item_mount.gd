# SPDX-License-Identifier: CC0-1.0
# An item keeps its own skeleton. This helper changes only its parent transform.
extends RefCounted

const Definition = preload("item_definition.gd")

static func attach(skeleton: Skeleton3D, item: Node3D, mount: Dictionary) -> BoneAttachment3D:
	var bone_name := String(mount["bone"])
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		push_error("Item mount bone does not exist: " + bone_name)
		return null
	var placement := Definition.transform(mount["transform"])
	var space := String(mount["space"])
	if space == "human_rest":
		placement = skeleton.get_bone_global_rest(index).affine_inverse() * placement
	elif space != "hand_local":
		push_error("Unknown item placement space: " + space)
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "ItemMount"
	skeleton.add_child(attachment)
	attachment.bone_name = bone_name
	attachment.bone_idx = index
	if item.get_parent() != null:
		item.reparent(attachment, false)
	else:
		attachment.add_child(item)
	# The exported item is canonical; this assignment is absolute, not additive.
	# For a rest-space wrapper, pass its documented transform with human_rest.
	item.transform = placement
	synchronize(attachment)
	return attachment

static func synchronize(attachment: BoneAttachment3D) -> void:
	# Make manual seeks/equip immediately coherent, including the first frame.
	# Native deferred skeleton updates otherwise initialize a new attachment later.
	if attachment == null:
		return
	var skeleton := attachment.get_skeleton()
	if skeleton != null:
		skeleton.force_update_all_bone_transforms()
		attachment.on_skeleton_update()

static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := find_skeleton(child)
		if found != null:
			return found
	return null

static func find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := find_player(child)
		if found != null:
			return found
	return null
