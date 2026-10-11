// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3i.hpp>
namespace terraforest {
// Immutable raw density snapshot including an explicit one-cell sampling border.
class NativeWaterField : public godot::RefCounted {
    friend class NativeWaterRegions;
    friend class NativeWaterNetwork;
    friend class NativeWaterRemapPlan;
    GDCLASS(NativeWaterField,godot::RefCounted)
    friend class NativeWaterTopology;
    godot::PackedFloat32Array density;
    godot::Vector3i origin,cells;
    int spacing=1;
    int64_t world=0,revision=0,ceiling=0,epoch=0;
    int status=-1,sampled=0;
    uint64_t core_id=0;
    bool metadata(int64_t id,int64_t rev,const godot::Vector3i &start,const godot::Vector3i &size,int64_t scale,int64_t top);
protected:
    static void _bind_methods();
public:
    bool configure(int64_t world_id,int64_t geometry_revision,const godot::Vector3i &grid_origin,const godot::Vector3i &size,int64_t cell_spacing,int64_t ceiling_mm,const godot::PackedFloat32Array &samples);
    bool begin_terrain(int64_t world_id,int64_t geometry_revision,int64_t cancel_epoch,const godot::Vector3i &grid_origin,const godot::Vector3i &size,int64_t cell_spacing,int64_t ceiling_mm);
    int sample_terrain(godot::Object *core,int64_t node_budget);
    godot::Dictionary statistics() const;
};
}
