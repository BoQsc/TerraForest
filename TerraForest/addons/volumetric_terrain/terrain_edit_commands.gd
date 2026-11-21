# SPDX-License-Identifier: 0BSD
extends RefCounted
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")

static func execute(core:RefCounted,commands:Array,revision_before:int,include_surface_owners:bool=false)->Dictionary:
	var reply:=PackedByteArray()
	var changed:Array[bool]=[]
	var removed_samples:=PackedInt64Array();removed_samples.resize(16)
	var footprints:Array[PackedByteArray]=[]
	var surface_owners:Array[PackedByteArray]=[]
	var excavation_only:=true
	var capture_writes:=core.has_method("execute_edit_with_writes")
	for command:PackedByteArray in commands:
		if include_surface_owners and (command.size()!=44 or command.decode_u32(0)!=2 or command.decode_u32(36)!=0):excavation_only=false
		var writes:=PackedByteArray()
		var owners:=PackedByteArray()
		if capture_writes and command.size()>=4 and command.decode_u32(0) in [2,3,28,38,41]:
			var receipt:Dictionary=core.execute_edit_with_writes(command,true) if include_surface_owners else core.execute_edit_with_writes(command)
			reply=receipt.get("reply",PackedByteArray())
			writes=receipt.get("writes",PackedByteArray())
			if include_surface_owners:owners=receipt.get("surface_owners",PackedByteArray())
		else:
			reply=core.execute(command)
		footprints.append(writes)
		if include_surface_owners:surface_owners.append(owners)
		var removed:=Codec.excavation_samples(reply)
		for material in range(16):removed_samples[material]+=removed[material]
		var revision_after:int
		if writes.size()>=12:
			revision_after=writes.decode_u32(8)
		else:
			var stats:PackedByteArray=core.execute(Codec.command(0))
			revision_after=stats.decode_u32(12)
		changed.append(revision_after!=revision_before);revision_before=revision_after
		if not Codec.reply_ok(reply):removed_samples.fill(0);break
	if not excavation_only:surface_owners.clear()
	return {"reply":reply,"changed":changed,"removed":removed_samples,"writes":footprints,"surface_owners":surface_owners}
