// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_profiles.hpp"
#include "water_regions.hpp"
#include "water_settling.hpp"
namespace terraforest {
// Immutable compiled geometry plus finite equilibrium state for a closed active set.
class NativeWaterNetwork : public godot::RefCounted {
    GDCLASS(NativeWaterNetwork,godot::RefCounted)
    using Key=std::array<int32_t,3>;
    struct Piece {godot::Vector3i coordinate;int64_t generation=0;int offset=0;godot::Ref<NativeWaterProfiles> profiles;};
    godot::Ref<NativeWaterRegions> registry;
    godot::Ref<NativeWaterBasins> hierarchy;
    godot::Ref<NativeWaterSettling> solver;
    std::vector<Piece> pieces;
    std::map<Key,int> indices;
    godot::PackedInt32Array ids,floors,edges,mapping;
    godot::PackedInt64Array levels;
    std::vector<godot::PackedInt64Array> rows;
    int status=-1,phase=0,piece=0,cursor=0,anchor=0,local_leaves=0,edge_count=0,global_leaves=0;
    int64_t work_total=0;
    godot::String error;
    bool current() const;
    void fail(const char *why);
    void unit();
    int owner_at(const Piece &p,const int32_t *address) const;
    int target(const godot::Vector3i &coordinate,int64_t leaf) const;
protected:
    static void _bind_methods();
public:
    bool begin(const godot::Ref<NativeWaterRegions> &owners,const godot::Array &regional_profiles);
    godot::Dictionary advance(int64_t work_budget);
    bool begin_add(const godot::Vector3i &coordinate,int64_t local_leaf,int64_t amount_ml);
    bool begin_remove(const godot::Vector3i &coordinate,int64_t local_leaf,int64_t amount_ml);
    godot::Dictionary advance_settling(int64_t event_budget);
    godot::Dictionary inspect(const godot::Vector3i &coordinate,int64_t local_leaf) const;
    godot::Dictionary statistics() const;
};
}
