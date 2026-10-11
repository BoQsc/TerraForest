// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/vector3i.hpp>
namespace terraforest {
// Shared by connectivity, rendering, point queries and volume integration.
inline constexpr int lake_tets[6][4]={{0,1,3,7},{0,1,5,7},{0,2,3,7},{0,2,6,7},{0,4,5,7},{0,4,6,7}};
inline godot::Vector3i lake_corner(int c){return godot::Vector3i(c&1,(c>>1)&1,(c>>2)&1);}
}
