# SPDX-License-Identifier: 0BSD
extends RefCounted
# One generation-time datum contract. Blocks stay on the metre lattice; all
# ground beds and access joins use the same prepared-soil height. Existing saves
# and free player block placement do not invoke this planner.
const VERSION:=1
const SURFACE_REVEAL:=0.125
static func describe(asset:Resource)->Dictionary:
	if asset==null or not asset.is_class("NativeBlockPrefab"):return {"ok":false,"reason":"Invalid building asset"}
	var offset:Variant=asset.get_meta("site_surface_offset",0)
	var band:Variant=asset.get_meta("site_sample_band",0)
	if typeof(offset)!=TYPE_INT or offset not in [0,1,5] or typeof(band)!=TYPE_INT or band!=offset:
		return {"ok":false,"reason":"Building surface and foundation sample datums disagree"}
	if offset==5 and not asset.get_meta("cellar_clearance",false):return {"ok":false,"reason":"Underground surface needs a cellar excavation plan"}
	var reveal:=SURFACE_REVEAL if offset>0 else 0.0
	if asset.has_meta("site_surface_inset") and not is_equal_approx(float(asset.get_meta("site_surface_inset")),reveal):
		return {"ok":false,"reason":"Per-building soil offsets cannot override the terrain contact standard"}
	return {"ok":true,"surface_offset":offset,"sample_band":band,"soil_inset":reveal}

static func inset(asset:Resource)->float:
	var contract:=describe(asset)
	return contract.soil_inset if contract.ok else NAN
