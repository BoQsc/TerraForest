// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>
namespace terraforest {
struct WaterDensityView {
    godot::Vector3 origin;
    godot::Vector3i size;
    double spacing=1,ceiling=0;
    const float *density=nullptr;
    const uint8_t *mask=nullptr;
    uint32_t cell(int x,int y,int z) const {return x+size.x*(y+size.y*z);}
    uint32_t node(int x,int y,int z) const {return x+(size.x+1)*(y+(size.y+1)*z);}
};
}
