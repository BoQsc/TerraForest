#pragma once
#include <godot_cpp/variant/color.hpp>
namespace terraforest {
inline godot::Color block_map_material(int material){
 // Legacy map symbols are unchanged; E2 colors use measured albedo means.
 const godot::Color colors[]={godot::Color(.44,.29,.23),godot::Color(.43,.33,.22),godot::Color(.58,.57,.54),godot::Color(.39,.43,.46),godot::Color(.304501,.235809,.194853),godot::Color(.455406,.407571,.351048),godot::Color(.397449,.372995,.335766),godot::Color(.319066,.265830,.203727),godot::Color(.279438,.277947,.272065),godot::Color(.333831,.326665,.316796),godot::Color(.321923,.251761,.195179),godot::Color(.451460,.428322,.399508)};
 return colors[material>=0&&material<12?material:0];
}
}
