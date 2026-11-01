# SPDX-License-Identifier: 0BSD
extends RefCounted
## Approved E2 resources. Names and approval metadata are presentation only;
## the hash-reviewed cells and attachment transforms are never rewritten.
const IDS=["trader_t1","town_hall_t1","church_c1","school_s2","warehouse_w1","cottage_a2","shop_b2","shop_b1","house_c1"]
const TITLES=["Trader's house","Town hall","Church","School","Warehouse","Furnished cottage with door and windows","Village general store","Village shop B / hipped roof","Large two-storey house C1"]
static func asset(id:String)->Resource:
	var index:=IDS.find(id)
	if index<0:return null
	var source:Resource=load("res://addons/structures/prefabs/expansion_"+id+"_e2.tres")
	if source==null:return null
	var result:Resource=source.duplicate()
	result.resource_name=TITLES[index]
	result.set_meta("review_only",false)
	result.set_meta("approved_revision",id+"_e2")
	result.set_meta("approved_date","2026-11-01")
	return result
static func assets()->Array[Resource]:
	var result:Array[Resource]=[]
	for id:String in IDS:
		var approved:=asset(id)
		if approved!=null:result.append(approved)
	return result
