// SPDX-License-Identifier: 0BSD
#pragma once
#include "region_mesher.hpp"

namespace terraforest::experimental {
// Geometry-only dependency on the inclusive sample box visited by World::edit.
// Cell ownership is half-open, but boundary samples are shared by both owners.
// Invalid bounds conservatively invalidate; callers must separately track LOD,
// shading, materials and collision publication dependencies.
static bool edit_intersects_region_samples(int x,int z,int size,V3 lo,V3 hi,int positive_halo){
 if(!valid_region(x,z,size,MeshLimits{}))return true;
 if(!std::isfinite(lo.x)||!std::isfinite(lo.y)||!std::isfinite(lo.z)||
    !std::isfinite(hi.x)||!std::isfinite(hi.y)||!std::isfinite(hi.z)||
    lo.x>hi.x||lo.y>hi.y||lo.z>hi.z)return true;
 return std::floor(lo.x)<=x+size+positive_halo&&std::floor(hi.x)>=x&&
        std::floor(lo.z)<=z+size+positive_halo&&std::floor(hi.z)>=z&&
        std::floor(lo.y)<=256&&std::floor(hi.y)>=0;
}
static bool edit_affects_region(int x,int z,int size,V3 lo,V3 hi){
 return edit_intersects_region_samples(x,z,size,lo,hi,0);
}
// Canonical trilinear normals at positive boundaries read the next cell.
static bool edit_affects_region_normals(int x,int z,int size,V3 lo,V3 hi){
 return edit_intersects_region_samples(x,z,size,lo,hi,1);
}
} // namespace terraforest::experimental
