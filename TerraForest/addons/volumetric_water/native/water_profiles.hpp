// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_topology.hpp"
#include "water_basins.hpp"
#include "water_clip.hpp"
#include <godot_cpp/variant/packed_int64_array.hpp>
namespace terraforest {
class NativeWaterProfiles : public godot::RefCounted {
    GDCLASS(NativeWaterProfiles,godot::RefCounted)
    godot::Ref<NativeWaterTopology> topology;
    godot::Ref<NativeWaterBasins> basins;
    godot::PackedInt64Array levels;
    std::vector<double> sums,correction;
    std::vector<godot::PackedInt64Array> rows;
    std::array<water_clip::Tet,3> air;
    int air_count=0,phase=0,cursor=0,anchor=0,status=-1,leaves=0;
    int64_t work_total=0,max_interval_ml=0,max_step_mm=0;
    godot::String error;
    void unit();
    void fail(const char *why);
protected:
    static void _bind_methods();
public:
    bool begin(const godot::Ref<NativeWaterTopology> &graph,const godot::Ref<NativeWaterBasins> &hierarchy,const godot::PackedInt64Array &levels_mm);
    godot::Dictionary advance(int64_t work_budget);
    godot::Dictionary statistics() const;
    godot::Dictionary profiles() const;
};
}
