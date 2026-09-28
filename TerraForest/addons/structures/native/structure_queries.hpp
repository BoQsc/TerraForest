#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
namespace terraforest {
class NativeBlockWorld;
class NativeStructureQueries : public godot::RefCounted {
    GDCLASS(NativeStructureQueries,godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::PackedByteArray overlap_mask(NativeBlockWorld *blocks,const godot::Array &models,const godot::TypedArray<godot::Transform3D> &transforms,const godot::AABB &bounds) const;
};
}
