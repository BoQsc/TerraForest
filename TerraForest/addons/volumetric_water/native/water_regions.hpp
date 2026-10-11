// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_topology.hpp"
#include <map>
namespace terraforest {
// Serialized active-region ownership and reciprocal geometry gate. No liquid ledger.
class NativeWaterRegions : public godot::RefCounted {
    friend class NativeWaterNetwork;
    GDCLASS(NativeWaterRegions,godot::RefCounted)
    using RegionKey=std::array<int32_t,3>;
    using PortKey=std::array<int32_t,8>;
    struct Endpoint {RegionKey region{};int64_t generation=0,ceiling=0;int32_t height=0;std::array<float,3> density{};};
    struct Region {
        int64_t generation=0,revision=0,epoch=0;
        bool ready=false;
        godot::Ref<NativeWaterTopology> graph;
        std::vector<PortKey> keys;
    };
    std::map<RegionKey,Region> regions;
    std::map<PortKey,std::array<Endpoint,2>> ports;
    godot::Ref<NativeWaterTopology> incoming;
    RegionKey active{};
    int64_t world=0,next_generation=1,work_total=0;
    int spacing=1,mode=0,port_cursor=0,ready_count=0,endpoint_count=0;
    static RegionKey key(const godot::Vector3i &v);
    static PortKey port_key(const int32_t *row,int &side);
    void unready(Region &region);
    void retire_one(Region &region);
    bool publish_one(Region &region);
protected:
    static void _bind_methods();
public:
    bool configure(int64_t world_id,int64_t grid_spacing);
    godot::Dictionary reserve_region(const godot::Vector3i &coordinate,int64_t revision,int64_t epoch,int64_t expected_generation);
    bool begin_publish(const godot::Ref<NativeWaterTopology> &graph,int64_t generation);
    bool begin_release(const godot::Vector3i &coordinate,int64_t generation);
    godot::Dictionary advance(int64_t work_budget);
    godot::Dictionary inspect_port(const godot::Vector3i &coordinate,int64_t generation,int64_t port_index) const;
    godot::Dictionary statistics() const;
};
}
