// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/vector3.hpp>
#include <cmath>

namespace terraforest {
// Expansion art uses image +V for downward drainage. One repeat is one metre
// projected onto the building grid: integer cell/chunk boundaries retain phase.
// Legacy materials retain their existing UVs. Call before rotating modular parts
// so roof courses follow the part through all 24 mounting orientations.
inline void building_uv(godot::Vector3 point,godot::Vector3 normal,int finish,float &u,float &v) {
    finish&=15;
    if(finish<4)return;
    if(std::abs(normal.y)<.01f)v=-point.y;
    if(finish<8||finish>10||normal.y<.01f)return;
    if(std::abs(normal.x)>.01f) {u=point.z;v=normal.x<0?-point.x:point.x;}
    else if(std::abs(normal.z)>.01f) {u=point.x;v=normal.z<0?-point.z:point.z;}
}
}
