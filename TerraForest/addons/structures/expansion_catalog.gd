# SPDX-License-Identifier: 0BSD
extends RefCounted
const IDS=["trader_t1","town_hall_t1","church_c1","school_s2","warehouse_w1","cottage_a2","shop_b2","shop_b1","house_c1"]
static func assets()->Array[Resource]:
	var result:Array[Resource]=[]
	for id:String in IDS:
		var asset:Resource=load("res://addons/structures/prefabs/expansion_"+id+"_e2.tres")
		if asset!=null:result.append(asset.duplicate())
	return result
