#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
namespace terraforest {
class NativeLakeCatalog : public godot::RefCounted {
    GDCLASS(NativeLakeCatalog,godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::PackedByteArray encode(const godot::Array &records, int64_t next_id=0) const;
    godot::Dictionary decode(const godot::PackedByteArray &bytes) const;
    bool validate_snapshot(const godot::PackedByteArray &bytes) const;
    godot::PackedByteArray placement_mask(const godot::Array &volumes,const godot::TypedArray<godot::Transform3D> &transforms) const;
};
}
