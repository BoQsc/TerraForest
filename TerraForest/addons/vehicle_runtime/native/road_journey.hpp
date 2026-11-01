// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <vector>
namespace terraforest {
// Published roads are a planning graph, never authority to bypass live collision.
// This planner supplies controls only; NativeDrivingPolicy remains the sole
// chassis integrator. Walking to/from the car uses NativeActorNavigator.
class NativeRoadJourney : public godot::RefCounted {
    GDCLASS(NativeRoadJourney, godot::RefCounted)
    struct Edge {int to; double cost;};
    struct Road {godot::Vector3 a,b; double width; std::vector<double> cuts;};
    std::vector<Road> roads;
    std::vector<godot::Vector3> nodes;
    std::vector<std::vector<Edge>> edges;
    godot::PackedVector3Array path;
    int cursor=0;
    double stalled=0;
    godot::Vector3 last_position;
    bool observed=false;
    godot::String state="unavailable";
protected:
    static void _bind_methods();
public:
    godot::Dictionary configure(const godot::Array &published_roads);
    godot::Dictionary route(godot::Vector3 start,godot::Vector3 destination,double maximum_snap,godot::Vector3 heading=godot::Vector3()) const;
    bool follow(const godot::PackedVector3Array &points);
    godot::Dictionary advance(godot::Transform3D pose,godot::Vector3 velocity,double delta,bool ready,bool clear);
    godot::String get_state()const{return state;}
    godot::PackedVector3Array get_path()const{return path;}
};
}
