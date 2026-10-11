// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_network.hpp"
#include <deque>
namespace terraforest {
// Source owns quantity until validated private settlement is atomically committed.
class NativeWaterRemapPlan : public godot::RefCounted {
    GDCLASS(NativeWaterRemapPlan,godot::RefCounted)
    struct Sum {double value=0,error=0;void add(double v){double a=v-error,n=value+a;error=(n-value)-a;value=n;}};
    struct Component {int64_t amount=0,assigned=0;Sum volume;double cumulative=0;};
    struct State {int component=-1;double level=0;};
    godot::Ref<NativeWaterNetwork> source,destination;
    godot::Ref<NativeWaterSettling> staged,previous_source,previous_destination;
    int settlement_status=-1,settlement_cursor=0,settlement_phase=0;
    int64_t settlement_work=0,unresolved_ml=0;
    uint64_t source_revision=0,destination_revision=0;
    std::vector<State> states;
    std::map<int,Component> components;
    std::map<std::pair<int,int>,Sum> overlaps;
    std::map<std::pair<int,int>,Sum>::iterator next;
    struct Displaced {int piece,index,component,slot,seed=-1;double volume;std::array<int,4> neighbours{{-1,-1,-1,-1}};};
    std::deque<Displaced> displaced;
    std::deque<int> routes,queue;
    std::vector<int> route_offsets;
    int route_cursor=0;
    Sum routed_volume;
    int neighbour_slot(const Displaced &node,int face) const;
    Sum measured_volume;
    godot::PackedInt64Array transfers;
    int status=-1,phase=0,cursor=0,piece=0;
    int64_t work_total=0,source_ml=0,mapped_ml=0,displaced_ml=0;
    godot::String error;
    bool current() const;
    void fail(const char *why);
    void unit();
    void accumulate(int component,int target,double volume);
protected:
    static void _bind_methods();
public:
    bool begin(const godot::Ref<NativeWaterNetwork> &old_water,const godot::Ref<NativeWaterNetwork> &new_geometry);
    godot::Dictionary advance(int64_t work_budget);
    godot::Dictionary statistics() const;
    godot::Dictionary plan() const;
    bool begin_settlement();
    godot::Dictionary advance_settlement(int64_t work_budget);
    bool commit();
};
}
