# SPDX-License-Identifier: 0BSD
extends RefCounted
# One Blender-authored PBR asset shared by inventory and native pickup rendering.
const PICKUP=preload("res://addons/volumetric_water/assets/Bucket.pickup.res")
const HELD=preload("res://addons/volumetric_water/assets/Bucket.held.res")
const BAIL=preload("res://addons/volumetric_water/assets/Bucket.bail.res")
static func mesh() -> Mesh:
 return PICKUP
