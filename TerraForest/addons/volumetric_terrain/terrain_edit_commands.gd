# SPDX-License-Identifier: 0BSD
extends RefCounted
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")

static func execute(core:RefCounted,commands:Array,revision_before:int)->Dictionary:
	var reply:=PackedByteArray()
	var changed:Array[bool]=[]
	var removed_samples:=PackedInt64Array();removed_samples.resize(16)
	for command:PackedByteArray in commands:
		reply=core.execute(command)
		var removed:=Codec.excavation_samples(reply)
		for material in range(16):removed_samples[material]+=removed[material]
		var stats:PackedByteArray=core.execute(Codec.command(0))
		var revision_after:int=stats.decode_u32(12)
		changed.append(revision_after!=revision_before);revision_before=revision_after
		if not Codec.reply_ok(reply):removed_samples.fill(0);break
	return {"reply":reply,"changed":changed,"removed":removed_samples}
