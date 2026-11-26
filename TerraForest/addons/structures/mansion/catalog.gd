# SPDX-License-Identifier: 0BSD
extends RefCounted
const PATH:="res://addons/structures/mansion/homestead_manor.tres"
static func asset() -> Resource:
	return load(PATH) if ResourceLoader.exists(PATH) else null
