#pragma once
#include <godot_cpp/variant/color.hpp>
namespace terraforest {
inline godot::Color block_map_material(int material){
 const godot::Color colors[]={godot::Color(.44,.29,.23),godot::Color(.43,.33,.22),godot::Color(.58,.57,.54),godot::Color(.39,.43,.46)};
 return colors[material&3];
}
}
