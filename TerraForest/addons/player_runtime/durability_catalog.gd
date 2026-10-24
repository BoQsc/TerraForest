# SPDX-License-Identifier: 0BSD
extends RefCounted
# Balance definitions only. Native stores retain damage, wear and save ownership.
# Keep existing maxima stable: changing one needs an explicit saved-damage policy.
const WORLD={"terrain":30,"tree":90,"actor":100,"vehicle":300,"model":90}
# Packed block material order: brick, wood, concrete, metal. All shapes share it.
const BLOCK_MAXIMUM=[90,60,120,180]
# GroundCatalog species order: stone, fern, grass, three flowers, low bush, twigs, woody bush.
const COVER_MAXIMUM=[45,10,10,10,10,10,40,10,2]
const TOOLS={1:200,2:200,3:200,4:200,5:200}
const MODELS={
	"furniture/table/v1":{"name":"Wooden table","health":90,"material":"wood"},
	"furniture/chair/v1":{"name":"Wooden chair","health":90,"material":"wood"},
	"furniture/shelf/v1":{"name":"Wooden shelf","health":90,"material":"wood"},
	"storage/wooden_chest/v1":{"name":"Wooden chest","health":90,"material":"wood"},
	"architecture/wooden_door/v1":{"name":"Wooden door","health":90,"material":"wood"},
	"architecture/wooden_window/v1":{"name":"Wooden window","health":90,"material":"wood"},
	"architecture/wooden_ladder/v1":{"name":"Wooden ladder","health":90,"material":"wood"},
	"architecture/wooden_fence/v1":{"name":"Wooden fence","health":90,"material":"wood"},
	"architecture/metal_beam/v1":{"name":"Metal beam","health":90,"material":"other"},
	"architecture/doorway/v1":{"name":"Doorway","health":90,"material":"other"},
	"architecture/metal_guardrail/v1":{"name":"Metal guardrail","health":90,"material":"other"},
	"architecture/metal_stairrail/v1":{"name":"Metal stair rail","health":90,"material":"other"},
	# Paving has no independent hit collider; its supporting terrain receives hits.
	"architecture/concrete_paving/v1":{"name":"Concrete paving","health":90,"material":"other"}
}

static func model_profile(asset:String)->Dictionary:
	if MODELS.has(asset):return MODELS[asset]
	# Preserve the existing policy for modded model keys.
	return {"name":"Object","health":WORLD.model,"material":"wood" if "wood" in asset or "furniture" in asset or "storage" in asset else "other"}
