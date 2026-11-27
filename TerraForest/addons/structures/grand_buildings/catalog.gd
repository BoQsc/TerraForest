# SPDX-License-Identifier: 0BSD
extends RefCounted
## Additional construction designs. Baked cells only; authoring never runs in play.
const IDS := ["courtyard_flats", "grand_cathedral", "street_tower"]
const TITLES := ["Foundry Court · 60 flats", "Saint Brigid · Grand cathedral", "Needle Street · Residential tower"]
static func asset(index: int) -> Resource:
	if index < 0 or index >= IDS.size(): return null
	return load("res://addons/structures/grand_buildings/" + IDS[index] + ".tres")
