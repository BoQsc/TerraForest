// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_network.hpp"
#include "water_field.hpp"
#include "water_basins.hpp"
#include <set>
namespace terraforest {
// Terrain-worker coordinator. The main thread reads it only after slice completion.
class NativeWaterRuntime : public godot::RefCounted {
    GDCLASS(NativeWaterRuntime,godot::RefCounted)
    godot::Vector3 origin,seed;godot::Vector3i cells,first,last,coordinate;
    int scale=1,stage=0,index=0,status=-1;int64_t ceiling=0,revision=-1,epoch=-1;
    godot::PackedByteArray saved;godot::String error;
    godot::Ref<NativeWaterRegions> registry;godot::Ref<NativeWaterField> field;
    godot::Ref<NativeWaterTopology> graph;godot::Ref<NativeWaterBasins> basin;
    godot::Ref<NativeWaterProfiles> profile;godot::Ref<NativeWaterNetwork> network;
    std::vector<godot::Ref<NativeWaterTopology>> graphs;
    std::vector<godot::Ref<NativeWaterBasins>> basins;godot::Array profiles;
    struct BoundaryPiece {godot::Vector3i origin;godot::PackedInt32Array ids,owners,ports;int offset=0;};
    std::vector<BoundaryPiece> boundaries;std::map<std::array<int,3>,int> boundary_index;
    std::map<std::pair<int,int>,int> openings;int boundary_cursor=0,leaf_offset=0;
    std::vector<int> parents,unresolved;int seed_root=-1,filter_phase=0,filter_cursor=0;
    std::vector<godot::Ref<NativeWaterTopology>> kept_graphs;
    std::vector<godot::Ref<NativeWaterBasins>> kept_basins;
    int root(int a){while(parents[a]!=a){parents[a]=parents[parents[a]];a=parents[a];}return a;}
    void connect(int a,int b){a=root(a);b=root(b);if(a!=b)parents[b]=a;}
    std::set<int64_t> anchors;godot::PackedInt64Array levels;
    int64_t step(godot::Object *,int64_t,int64_t,int64_t);
    void fail(const char *text){status=-2;error=text;}
protected: static void _bind_methods();
public:
    bool configure(const godot::Vector3 &origin,const godot::Vector3i &cells,double spacing,double level,const godot::Vector3 &seed,const godot::PackedByteArray &state);
    int64_t sample_terrain(godot::Object *core,int64_t budget,int64_t revision,int64_t epoch);
    godot::Ref<NativeWaterNetwork> get_network() const{return status==1?network:godot::Ref<NativeWaterNetwork>();}
    godot::Dictionary statistics() const;
};
}
