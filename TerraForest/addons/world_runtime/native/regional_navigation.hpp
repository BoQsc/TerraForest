// SPDX-License-Identifier: 0BSD
#pragma once
#include "actor_route.hpp"
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <array>
#include <set>
namespace terraforest {
// Derived, bounded surface graph. Its vertices retain height: coincident X/Z on
// different storeys are distinct. Cross-tile links are discovered by the same
// supported walking sweeps as local routes, including stairs and cave ramps.
class RegionalGraph {
public:
    static constexpr int NODE_LIMIT=32768;
    struct Vertex {godot::Vector3 p;int profile;std::array<int,8> edge,progress{};std::array<godot::Vector3,8> probe;
        Vertex(godot::Vector3 point,int kind):p(point),profile(kind){edge.fill(-2);}};
    std::vector<Vertex> vertices;
    std::map<std::tuple<int,int,int,int>,int> index;
    godot::PackedVector3Array requests;
    uint64_t hits=0,queries=0,revision=0;
    real_t lowest=0,highest=0;
    void clear(){vertices.clear();index.clear();requests.clear();++revision;}
    void request(const godot::Vector3 &point);
    int candidate(int from,const godot::Vector3 &origin,int profile,int direction,
        ActorRoute &validator,godot::PhysicsDirectSpaceState3D *space,
        const godot::Callable &readiness,const godot::Callable &admission,
        const godot::Ref<godot::PhysicsRayQueryParameters3D> &ray,
        const godot::Ref<godot::PhysicsShapeQueryParameters3D> &shape);
};
class RegionalRoute {
    struct Node {int vertex,parent;double g;bool closed=false;};
    struct Entry {double score;int node;bool operator<(const Entry &b)const{return score>b.score||(score==b.score&&node>b.node);}};
    std::vector<Node> nodes_;
    std::map<int,int> visited_;
    std::priority_queue<Entry> open_;
    std::vector<godot::Vector3> path_;
    godot::Vector3 start_,goal_,expected_,progress_anchor_;
    int expanding_=-1,direction_=0,profile_=0,stalls_=0;
    size_t waypoint_=0;
    double retry_=0,stuck_=0,height_weight_=2;
    bool waiting_=false;
    bool finishing_=false;
    std::vector<godot::Vector3> finish_samples_;
    godot::Vector3 position(const Node &node,const RegionalGraph &graph)const{return node.vertex<0?start_:graph.vertices[node.vertex].p;}
public:
    static constexpr int QUERY_LIMIT=16384;
    static constexpr double RADIUS=96;
    ActorRoute::State state=ActorRoute::IDLE;
    int expansions=0;
    void begin(godot::Vector3 start,godot::Vector3 goal,int profile);
    void invalidate(){state=ActorRoute::IDLE;}
    void prepare(godot::Vector3 point,godot::Vector3 goal,int profile,double delta);
    void step(RegionalGraph &graph,ActorRoute &validator,godot::PhysicsDirectSpaceState3D *space,
        const godot::Callable &readiness,const godot::Callable &admission,
        const godot::Ref<godot::PhysicsRayQueryParameters3D> &ray,
        const godot::Ref<godot::PhysicsShapeQueryParameters3D> &shape);
    godot::Vector3 target(godot::Vector3 point);
    godot::Dictionary status(const RegionalGraph &graph) const;
    godot::PackedVector3Array points()const;
};
}
