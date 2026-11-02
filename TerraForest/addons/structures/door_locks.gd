# SPDX-License-Identifier: 0BSD
extends RefCounted

const PICK_ITEM:=213
const CAPACITY:=4096
signal changed
var store:RefCounted

func _init()->void:
	var catalog:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	catalog.register_item(PICK_ITEM,999)
	store=ClassDB.instantiate("NativeContainerStore")
	if not store.configure(catalog,CAPACITY,16,PICK_ITEM):store=null

func seed(identity:int,health:int,world_seed:int)->bool:
	if not store.seed_lock(identity,health,world_seed&0x7fffffffffffffff):return false
	changed.emit();return true

func attempt(identity:int,inventory:RefCounted)->Dictionary:
	var result:Dictionary=store.attempt_unlock(identity,inventory,inventory.snapshot().revision,store.lock_state(identity).store_revision)
	if result.ok:changed.emit()
	return result

func damage(identity:int,amount:int)->Dictionary:
	var result:Dictionary=store.damage_lock(identity,amount,store.lock_state(identity).store_revision)
	if result.ok:changed.emit()
	return result

func forget(identity:int)->void:
	if store.is_locked(identity):damage(identity,store.lock_state(identity).remaining)

func capture_storage_snapshot()->PackedByteArray:return store.capture_storage_snapshot()

func validate_snapshot(bytes:PackedByteArray)->bool:
	return store.validate_snapshot(bytes) and bytes.decode_u64(8)==0

func restore_storage_snapshot(bytes:PackedByteArray)->bool:
	if not validate_snapshot(bytes) or not store.restore_storage_snapshot(bytes):return false
	changed.emit();return true

static func empty_patch(ids:PackedInt64Array)->PackedByteArray:
	var owner=load("res://addons/structures/door_locks.gd").new()
	return preload("res://addons/world_runtime/location_capture.gd").patch(owner.store,"container",[ids])

static func validate_lock_patch(bytes:PackedByteArray)->bool:
	var owner=load("res://addons/structures/door_locks.gd").new()
	var token:Dictionary=owner.store.container_patch_state()
	var result:Dictionary=owner.store.restore_container_patch(bytes,token.revision,token.owner)
	return result.ok and owner.validate_snapshot(owner.capture_storage_snapshot())
