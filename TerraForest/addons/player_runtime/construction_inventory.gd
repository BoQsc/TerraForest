# SPDX-License-Identifier: 0BSD
extends RefCounted
# Main-thread coordinator with incremental native prefab preparation.
# Inventory debit and prepared publication are synchronous; inventory has at most 32 slots.
# prefab material totals are cached at authoring time in NativeBlockPrefab.
var gameplay := false
var busy := false
var reason := ""
var prefab_transaction: RefCounted
var pending_prefab: Dictionary={}

func place_model(history: RefCounted, collection: Node3D, inventory: RefCounted, transforms: PackedFloat32Array, protection: AABB, costs: PackedInt64Array) -> int:
	if gameplay and costs.is_empty():
		reason="This object has no gameplay recipe"
		return 0
	var created: Array[int]=[0]
	var accepted:=_apply(inventory,costs,func() -> bool:
		created[0]=history.insert(collection,transforms,protection)
		return created[0]>0)
	return created[0] if accepted else 0

func place_block(blocks: Node, inventory: RefCounted, cell: Vector3i, word: int) -> bool:
	if busy: return false
	if gameplay and word != 0 and blocks.get_cell(cell)!=0:
		reason="Clear the occupied cell before building"
		return false
	var costs:=PackedInt64Array()
	if word != 0: costs=PackedInt64Array([101+(word>>5),1])
	return _apply(inventory,costs,blocks.set_cells.bind(PackedInt32Array([cell.x,cell.y,cell.z,word])))

func _prefab_costs(asset: Resource, recipes: Dictionary) -> Dictionary:
	if prefab_transaction==null: prefab_transaction=ClassDB.instantiate("NativePrefabPlacement")
	var models: Dictionary=prefab_transaction.model_counts(asset)
	var costs:=PackedInt64Array()
	if gameplay:
		var counts: PackedInt64Array=asset.get_material_counts()
		for material in range(4):
			if counts[material]>0: costs.append_array(PackedInt64Array([101+material,counts[material]]))
		for key: String in models:
			var recipe: PackedInt64Array=recipes.get(key,PackedInt64Array())
			if recipe.is_empty() or recipe.size()%2!=0:
				reason="Attached model has no gameplay recipe";return {"ok":false}
			for i in range(0,recipe.size(),2): costs.append_array(PackedInt64Array([recipe[i],recipe[i+1]*int(models[key])]))
	return {"ok":true,"costs":costs,"attached":not models.is_empty()}

func place_prefab(blocks: Node, inventory: RefCounted, asset: Resource, cell: Vector3i, rotation: int, models: Dictionary={}, recipes: Dictionary={}, protections: Array=[]) -> bool:
	if busy or not pending_prefab.is_empty(): return false
	var recipe:=_prefab_costs(asset,recipes)
	if not recipe.ok:return false
	if not recipe.attached: return _apply(inventory,recipe.costs,blocks.place_prefab.bind(asset,cell,rotation))
	var response: Dictionary={}
	var accepted:=_apply(inventory,recipe.costs,func() -> bool:
		response.merge(prefab_transaction.place(blocks,asset,cell,rotation,models,protections),true)
		return response.get("ok",false))
	if not accepted and response.has("reason"): reason=response.reason
	return accepted

func begin_prefab(blocks: Node, inventory: RefCounted, asset: Resource, cell: Vector3i, rotation: int, models: Dictionary, recipes: Dictionary, protections: Array) -> bool:
	if busy or not pending_prefab.is_empty():return false
	var recipe:=_prefab_costs(asset,recipes)
	if not recipe.ok:return false
	var response: Dictionary=prefab_transaction.begin(blocks,asset,cell,rotation,models,protections)
	if not response.ok:reason=response.reason;return false
	pending_prefab={"inventory":inventory,"costs":recipe.costs,"gameplay":gameplay,"revision":inventory.snapshot().revision}
	reason="Preparing building...";return true

func cancel_prefab() -> bool:
	if busy:return false
	if prefab_transaction!=null and not prefab_transaction.cancel():return false
	pending_prefab={};return true

func advance_prefab(protections: Array) -> Dictionary:
	if pending_prefab.is_empty():return {"ok":false,"status":"failed","reason":"No prepared placement"}
	if gameplay!=pending_prefab.gameplay:
		cancel_prefab();return {"ok":false,"status":"failed","reason":"Construction mode changed"}
	var result: Dictionary=prefab_transaction.advance(2048,16,1000)
	if not result.ok:
		pending_prefab={};reason=result.reason;return result
	if result.status!="ready":return result
	var request:=pending_prefab
	if gameplay and request.inventory.snapshot().revision!=request.revision:
		cancel_prefab();return {"ok":false,"status":"failed","reason":"Inventory changed during preparation"}
	var response: Dictionary={}
	var accepted:=_apply(request.inventory,request.costs,func() -> bool:
		response.merge(prefab_transaction.commit(protections),true)
		return response.get("ok",false))
	pending_prefab={}
	if not accepted:
		prefab_transaction.cancel()
		if response.has("reason"):reason=response.reason
		return {"ok":false,"status":"failed","reason":reason}
	return response

func _apply(inventory: RefCounted, costs: PackedInt64Array, placement: Callable) -> bool:
	if busy: return false
	busy=true
	reason=""
	var before: Dictionary={}
	var debit_revision: int=-1
	if gameplay and not costs.is_empty():
		before=inventory.snapshot()
		var debit: Dictionary=inventory.consume_items(costs,before.revision)
		if not debit.ok:
			reason="Missing construction materials" if debit.reason=="insufficient_items" else "Inventory changed; try again"
			busy=false
			return false
		debit_revision=debit.revision
	# No await: placement rejection is atomic in NativeBlockWorld. On success its
	# change signals already observe the deducted inventory. Never overwrite a
	# concurrent/reentrant inventory mutation when rolling back a rejected edit.
	var accepted: bool=placement.call()
	if not accepted:
		reason="Placement rejected; materials returned"
		if debit_revision>=0 and not inventory.restore(before,debit_revision).ok:
			reason="Inventory changed during rejected placement; rollback failed"
			push_error(reason)
	busy=false
	return accepted
