# SPDX-License-Identifier: 0BSD
extends RefCounted
# Existing accounting checks now await the real strike/recovery instead of mouse-down.
static func strike(game:Node)->bool:
	if not game.world_attack.attack():return false
	return await finish(game)
static func finish(game:Node)->bool:
	var deadline:=Time.get_ticks_msec()+4000
	while not game.world_attack.pending.is_empty() and Time.get_ticks_msec()<deadline:await game.get_tree().process_frame
	return game.world_attack.pending.is_empty() and game.world_attack.last_hit
