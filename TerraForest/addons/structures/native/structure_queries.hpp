#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <memory>
namespace terraforest {
class NativeBlockWorld;
class NativeRegionWorldArchive;
struct StructureExclusionCache;
class NativeStructureQueries : public godot::RefCounted {
    GDCLASS(NativeStructureQueries,godot::RefCounted)
    std::unique_ptr<StructureExclusionCache> exclusion;
protected:
    static void _bind_methods();
public:
    NativeStructureQueries();
    ~NativeStructureQueries();
    void configure_archive(const godot::Ref<NativeRegionWorldArchive> &archive,const godot::PackedByteArray &checkpoint);
    void clear_exclusion_cache();
    godot::Dictionary exclusion_stats() const;
    godot::Dictionary capture_models(NativeBlockWorld *blocks,const godot::Array &models,godot::Vector3i origin,godot::Vector3i size) const;
    bool is_collision_region_ready(NativeBlockWorld *blocks,const godot::Array &models,const godot::AABB &bounds) const;
    godot::PackedByteArray overlap_mask(NativeBlockWorld *blocks,const godot::Array &models,const godot::TypedArray<godot::Transform3D> &transforms,const godot::AABB &bounds);
};
}
