// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <map>
#include <queue>
#include <tuple>
#include <vector>

namespace terraforest {
// Disposable, local walking route. This deliberately does not promise stairs,
// jumping, crowd avoidance, arbitrary distance, or multi-storey connectivity.
class ActorRoute {
    struct Node {godot::Vector3 p; int x,z,parent; double g; bool closed=false;};
    struct Entry {double f; int index; bool operator<(const Entry &b) const {return f>b.f || (f==b.f && index>b.index);}};
    std::vector<Node> nodes_;
    std::map<std::tuple<int,int,int>,int> lookup_;
    std::priority_queue<Entry> open_;
    std::vector<godot::Vector3> path_;
    size_t waypoint_=0;
    int expanding_=-1, neighbour_=0;
    bool limited_=false, unknown_=false;
    godot::Vector3 origin_,goal_,expected_;
    godot::AABB bounds_;
    bool has_bounds_=false;
    double retry_=0, stuck_=0;
    int stalls_=0;
    void start(const godot::Vector3 &position,const godot::Vector3 &goal);
    void include(const godot::AABB &bounds);
    bool edge(godot::PhysicsDirectSpaceState3D *space,const godot::Vector3 &from,
        godot::Vector3 &to,const godot::Callable &readiness,const godot::Callable &admission,
        const godot::Ref<godot::PhysicsRayQueryParameters3D> &ray,
        const godot::Ref<godot::PhysicsShapeQueryParameters3D> &shape);
public:
    enum State {IDLE,PLANNING,FOLLOWING,ARRIVED,BLOCKED,UNAVAILABLE,SEARCH_LIMIT};
    State state=IDLE;
    int expansions=0;
    void invalidate(){state=IDLE;}
    void invalidate(const godot::AABB &bounds){if(!has_bounds_ || bounds.size==godot::Vector3() || bounds_.intersects(bounds))invalidate();}
    void prepare(const godot::Vector3 &position,const godot::Vector3 &goal,double delta);
    // Exactly one candidate edge per call (at most four physics queries).
    void step(godot::PhysicsDirectSpaceState3D *space,const godot::Callable &readiness,
        const godot::Callable &admission,const godot::Ref<godot::PhysicsRayQueryParameters3D> &ray,
        const godot::Ref<godot::PhysicsShapeQueryParameters3D> &shape);
    godot::Vector3 target(const godot::Vector3 &position);
    void moved(const godot::Vector3 &position,double delta);
    godot::Dictionary status() const;
};
}
