# SPDX-License-Identifier: 0BSD
extends RefCounted
# Main-thread, synchronous coordinator. Native inventory stages at most 32 slots;
# prefab material totals are cached at authoring time in NativeBlockPrefab.
var gameplay := false
var busy := false
var reason := ""

func place_block(blocks: Node, inventory: RefCounted, cell: Vector3i, word: int) -> bool:
	if busy: return false
	if gameplay and word != 0 and blocks.get_cell(cell)!=0:
		reason="Clear the occupied cell before building"
		return false
	var costs:=PackedInt64Array()
	if word != 0: costs=PackedInt64Array([101+(word>>5),1])
	return _apply(inventory,costs,blocks.set_cells.bind(PackedInt32Array([cell.x,cell.y,cell.z,word])))

func place_prefab(blocks: Node, inventory: RefCounted, asset: Resource, cell: Vector3i, rotation: int) -> bool:
	if busy: return false
	var costs:=PackedInt64Array()
	if gameplay:
		var counts: PackedInt64Array=asset.get_material_counts()
		for material in range(4):
			if counts[material]>0: costs.append_array(PackedInt64Array([101+material,counts[material]]))
	return _apply(inventory,costs,blocks.place_prefab.bind(asset,cell,rotation))

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
