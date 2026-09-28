#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace terraforest {
class NativeTerrainPlanner : public godot::RefCounted {
    GDCLASS(NativeTerrainPlanner,godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::Dictionary requests(godot::Vector3 focus,bool collision,const godot::Dictionary &tiles,const godot::Dictionary &split,const godot::Array &visible) const;
    godot::Dictionary coverage(const godot::Dictionary &tiles,const godot::Dictionary &split,const godot::Array &visible) const;
    godot::Dictionary eviction_candidates(const godot::Dictionary &tiles,const godot::Array &visible,const godot::Dictionary &requested) const;
};
}
