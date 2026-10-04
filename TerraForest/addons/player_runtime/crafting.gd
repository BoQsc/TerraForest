# SPDX-License-Identifier: 0BSD
extends RefCounted
# Starter recipes are game rules, not physical manufacturing ratios.
# Definitions and bounded UI orchestration may be modded; slot work is native.
const RECIPES=[
	{"title":"Brick · 2 stone → 1 brick","costs":[201,2],"outputs":[101,1]},
	{"title":"Concrete · 3 stone → 1 concrete","costs":[201,3],"outputs":[103,1]},
	{"title":"Metal · 2 iron ore → 1 metal","costs":[202,2],"outputs":[104,1]},
	{"title":"Metal · 2 copper ore → 1 metal","costs":[203,2],"outputs":[104,1]}
]
static func craft(inventory: RefCounted, recipe: int, batches: int, revision: int) -> Dictionary:
	if recipe<0 or recipe>=RECIPES.size() or batches<1 or batches>1000: return {"ok":false,"reason":"invalid_recipe_or_quantity"}
	var costs:=PackedInt64Array(RECIPES[recipe].costs)
	var outputs:=PackedInt64Array(RECIPES[recipe].outputs)
	for i in range(1,costs.size(),2): costs[i]*=batches
	for i in range(1,outputs.size(),2): outputs[i]*=batches
	return inventory.exchange_items(costs,outputs,revision)
