// SPDX-License-Identifier: 0BSD
#pragma once
#include "region_mesher.hpp"

namespace terraforest::experimental {
// Geometry-only dependency on the inclusive sample box visited by World::edit.
// Cell ownership is half-open, but boundary samples are shared by both owners.
// Invalid bounds conservatively invalidate; callers must separately track LOD,
// shading, materials and collision publication dependencies.
static bool edit_affects_region(int x,int z,int size,V3 lo,V3 hi){
 if(!valid_region(x,z,size,MeshLimits{}))return true;
 if(!std::isfinite(lo.x)||!std::isfinite(lo.y)||!std::isfinite(lo.z)||
    !std::isfinite(hi.x)||!std::isfinite(hi.y)||!std::isfinite(hi.z)||
    lo.x>hi.x||lo.y>hi.y||lo.z>hi.z)return true;
 return std::floor(lo.x)<=x+size&&std::floor(hi.x)>=x&&
        std::floor(lo.z)<=z+size&&std::floor(hi.z)>=z&&
        std::floor(lo.y)<=256&&std::floor(hi.y)>=0;
}
} // namespace terraforest::experimental
