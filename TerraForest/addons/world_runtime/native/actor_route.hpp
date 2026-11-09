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
// Disposable, local walking route. This deliberately supports bounded walking/stairs, but does not promise
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
    bool direct_=true;
    godot::Vector3 origin_,goal_,expected_;
    godot::AABB bounds_;
    bool has_bounds_=false;
    bool edge_unavailable_=false;
    const char *edge_failure_="none";
    godot::RID edge_obstacle_;
    double retry_=0, stuck_=0;
    int stalls_=0;
    void start(const godot::Vector3 &position,const godot::Vector3 &goal);
    void include(const godot::AABB &bounds);
    bool edge(godot::PhysicsDirectSpaceState3D *space,const godot::Vector3 &from,
        godot::Vector3 &to,const godot::Callable &readiness,const godot::Callable &admission,
        const godot::Ref<godot::PhysicsRayQueryParameters3D> &ray,
        const godot::Ref<godot::PhysicsShapeQueryParameters3D> &shape);
public:
    // Optional, synchronous planning diagnostics. Motion guards and ordinary
    // non-profiled callers leave this pointer null; no timings survive a pass.
    struct QueryProfile {
        uint64_t readiness_ns=0,support_ns=0,hazard_ns=0,clearance_ns=0;
        uint64_t edges=0,support_rays=0,water_queries=0,admission_queries=0,shape_queries=0,sweeps=0;
    };
    QueryProfile *query_profile=nullptr;
    // Exact ray answers for one navigator's static-query policy and graph
    // revision. Direct-mapped storage has fixed cost and never rounds queries.
    struct SupportCache {
        static constexpr size_t LIMIT=65536;
        struct Entry {
            godot::Vector3 from,normal;
            real_t to_y=0,height=0;
            uint64_t revision=0;
            bool hit=false;
        };
        std::vector<Entry> entries;
        uint64_t revision=1,hits=0,misses=0;
        SupportCache():entries(LIMIT){}
        size_t slot(const godot::Vector3 &from,real_t to_y)const;
    };
    SupportCache *support_cache=nullptr;
    struct ReadinessCache {
        std::map<std::tuple<int,int,int,int,int,int>,bool> regions;
        int probes=0,hits=0;
    };
    ReadinessCache *readiness_cache=nullptr;
    bool collision_ready(const godot::AABB &bounds,const godot::Callable &readiness);
    enum State {IDLE,PLANNING,FOLLOWING,ARRIVED,BLOCKED,UNAVAILABLE,SEARCH_LIMIT};
    State state=IDLE;
    double maximum_step=.30;
    double minimum_floor_normal=.85;
    godot::Callable water_depth;
    bool edge_unavailable() const {return edge_unavailable_;}
    const char *edge_failure() const {return edge_failure_;}
    godot::RID edge_obstacle() const {return edge_obstacle_;}
    int expansions=0;
    void invalidate(){state=IDLE;}
    void invalidate(const godot::AABB &bounds){if(!has_bounds_ || bounds.size==godot::Vector3() || bounds_.intersects(bounds))invalidate();}
    void prepare(const godot::Vector3 &position,const godot::Vector3 &goal,double delta);
    // Exactly one candidate edge per call (at most 75 physics queries with stair clearance).
    void step(godot::PhysicsDirectSpaceState3D *space,const godot::Callable &readiness,
        const godot::Callable &admission,const godot::Ref<godot::PhysicsRayQueryParameters3D> &ray,
        const godot::Ref<godot::PhysicsShapeQueryParameters3D> &shape);
    godot::Vector3 target(const godot::Vector3 &position);
    void moved(const godot::Vector3 &position,double delta);
    bool permits_motion(godot::PhysicsDirectSpaceState3D *space,const godot::Vector3 &from,godot::Vector3 to,
        const godot::Callable &readiness,const godot::Callable &admission,
        const godot::Ref<godot::PhysicsRayQueryParameters3D> &ray,const godot::Ref<godot::PhysicsShapeQueryParameters3D> &shape) {
        return edge(space,from,to,readiness,admission,ray,shape);
    }
    bool sample_motion(godot::PhysicsDirectSpaceState3D *space,const godot::Vector3 &from,godot::Vector3 &to,
        const godot::Callable &readiness,const godot::Callable &admission,
        const godot::Ref<godot::PhysicsRayQueryParameters3D> &ray,const godot::Ref<godot::PhysicsShapeQueryParameters3D> &shape){
        return edge(space,from,to,readiness,admission,ray,shape);
    }
    godot::Dictionary status() const;
};
}
