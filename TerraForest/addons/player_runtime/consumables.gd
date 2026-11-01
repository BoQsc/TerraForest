# SPDX-License-Identifier: 0BSD
extends RefCounted

const ITEMS={
	214:{"name":"Field manual","food":0,"xp":25,"effect":0,"seconds":0,"text":"Survey before you strike. Exposed mineral stones mark deposits below. Keep a clear route back to daylight, and leave timber supports intact until another support carries the roof."},
	215:{"name":"Unsent letter","food":0,"xp":10,"effect":0,"seconds":0,"text":"I left provisions above the trees, where the lookout stairs meet the platform. Take only what you need. The people lying quietly in the houses are not always gone."},
	216:{"name":"Survey journal","food":0,"xp":15,"effect":2,"seconds":120,"text":"A careful worker learns from each small change: an exposed seam, a tired tool, a path that remains passable. Work deliberately. A quiet room can hold a sleeping danger."},
	217:{"name":"Tinned beans","food":35,"xp":0,"effect":1,"seconds":180,"text":"Restores 35% food. Well fed: +5% action damage for three active minutes."},
	218:{"name":"Trail bread","food":20,"xp":0,"effect":0,"seconds":0,"text":"A dense travel loaf. Restores 20% food."},
	219:{"name":"Dried berries","food":10,"xp":0,"effect":0,"seconds":0,"text":"A small ration of dried berries. Restores 10% food."}
}
const EFFECTS={1:{"name":"Well fed","damage":50,"learning":0},2:{"name":"Focused","damage":0,"learning":100}}

static func create()->RefCounted:
	var store:RefCounted=ClassDB.instantiate("NativePlayerSurvival")
	var items:=PackedInt64Array();var effects:=PackedInt64Array()
	for identity:int in ITEMS:
		var entry:Dictionary=ITEMS[identity];items.append_array(PackedInt64Array([identity,entry.food,entry.xp,entry.effect,entry.seconds]))
	for identity:int in EFFECTS:
		var entry:Dictionary=EFFECTS[identity];effects.append_array(PackedInt64Array([identity,entry.damage,entry.learning]))
	return store if store.configure(items,effects) else null

static func description(identity:int)->String:
	if not ITEMS.has(identity):return ""
	var item:Dictionary=ITEMS[identity]
	return ("Read · %d XP%s"%[item.xp," · Focused: +10% XP for two active minutes" if item.effect==2 else ""]) if item.xp>0 else item.text
