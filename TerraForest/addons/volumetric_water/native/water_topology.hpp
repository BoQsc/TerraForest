// SPDX-License-Identifier: 0BSD
#pragma once
#include "lake_volume.hpp"
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
namespace terraforest {
// Immutable regional air graph below the source's ceiling. Not a liquid state.
class NativeWaterTopology : public godot::RefCounted {
    GDCLASS(NativeWaterTopology,godot::RefCounted)
    friend class NativeWaterProfiles;
    godot::Ref<NativeLakeVolume> source;
    godot::Vector3i first,extent;
    godot::PackedInt32Array ids,floors,edges;
    uint32_t cursor=0,count=0,node_count=0,edge_count=0,portals=0;
    int status=-1;
protected:
    static void _bind_methods();
public:
    bool begin(const godot::Ref<NativeLakeVolume> &volume,const godot::Vector3i &first_cell,const godot::Vector3i &cells);
    godot::Dictionary advance(int64_t cell_budget);
    godot::Dictionary statistics() const;
    godot::Dictionary graph() const;
};
}
