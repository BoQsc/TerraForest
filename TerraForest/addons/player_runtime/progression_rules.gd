# SPDX-License-Identifier: 0BSD
extends RefCounted

const MINING:=1
const WOODCRAFT:=2
const MELEE:=3
const SKILLS=[
	{"id":MINING,"name":"Mining","maximum":5,"bonus":50,"detail":"+5% damage per rank when mining terrain or natural stone."},
	{"id":WOODCRAFT,"name":"Woodcraft","maximum":5,"bonus":50,"detail":"+5% damage per rank when harvesting natural trees and plants."},
	{"id":MELEE,"name":"Melee","maximum":5,"bonus":50,"detail":"+5% damage per rank against living zombies."}
]

static func create()->RefCounted:
	var store:RefCounted=ClassDB.instantiate("NativePlayerProgression")
	var definitions:=PackedInt64Array()
	for skill:Dictionary in SKILLS:definitions.append_array(PackedInt64Array([skill.id,skill.maximum,skill.bonus]))
	return store if store.configure(definitions) else null

static func crafting_xp(recipe:Dictionary)->int:
	var total:=0
	for index in range(1,recipe.costs.size(),2):total+=int(recipe.costs[index])
	return clampi(total*3,1,60)
