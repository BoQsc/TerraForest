// SPDX-License-Identifier: 0BSD
#pragma once
#include "lake_volume.hpp"
#include "water_field.hpp"
#include "water_density_view.hpp"
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <vector>
#include <array>
namespace terraforest {
// Immutable regional air graph below the source's ceiling. Not a liquid state.
class NativeWaterTopology : public godot::RefCounted {
    GDCLASS(NativeWaterTopology,godot::RefCounted)
    friend class NativeWaterProfiles;
    godot::Ref<NativeLakeVolume> source;
    godot::Ref<NativeWaterField> field;
    godot::PackedInt32Array world_ports;
    WaterDensityView view() const;
    godot::Vector3i first,extent;
    godot::PackedInt32Array ids,floors,edges;
    uint32_t cursor=0,count=0,node_count=0,edge_count=0,portals=0;
    int status=-1;
    bool joined=false;
    std::vector<godot::Ref<NativeWaterTopology>> pieces;
    std::vector<int> positions;
    std::vector<std::array<int32_t,3>> edge_heap;
    int join_phase=0,piece_cursor=0,edge_cursor=0;
    int64_t join_work=0;
    std::array<int32_t,3> last_edge={-1,-1,0};
protected:
    static void _bind_methods();
public:
    bool begin(const godot::Ref<NativeLakeVolume> &volume,const godot::Vector3i &first_cell,const godot::Vector3i &cells);
    bool begin_field(const godot::Ref<NativeWaterField> &density_field,const godot::Vector3i &first_cell,const godot::Vector3i &cells);
    godot::Dictionary advance(int64_t cell_budget);
    bool begin_join(const godot::Array &regions);
    godot::Dictionary advance_join(int64_t work_budget);
    godot::Dictionary statistics() const;
    godot::Dictionary graph() const;
};
}
